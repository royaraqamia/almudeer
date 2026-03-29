import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:almudeer_mobile_app/features/transfer/data/local/transfer_database.dart';
import 'package:almudeer_mobile_app/features/transfer/data/models/transfer_models.dart';
import 'enhanced_transfer_service.dart';

/// Thread-safe transfer queue with priority support
class _TransferQueue {
  final List<QueuedTransfer> _items = [];

  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  void add(QueuedTransfer transfer) {
    _items.add(transfer);
  }

  void addFirst(QueuedTransfer transfer) {
    _items.insert(0, transfer);
  }

  QueuedTransfer? removeFirst() {
    if (_items.isEmpty) return null;
    return _items.removeAt(0);
  }

  void removeWhere(bool Function(QueuedTransfer) test) {
    _items.removeWhere(test);
  }

  QueuedTransfer? firstWhere(
    bool Function(QueuedTransfer) test, {
    QueuedTransfer? Function()? orElse,
  }) {
    try {
      return _items.firstWhere(test);
    } catch (e) {
      return orElse?.call();
    }
  }

  void clear() {
    _items.clear();
  }

  List<QueuedTransfer> toList() {
    return List.unmodifiable(_items);
  }

  void insertByPriority(QueuedTransfer transfer) {
    // Insert maintaining priority order (higher priority first)
    int insertIndex = _items.length;
    for (int i = 0; i < _items.length; i++) {
      if (_items[i].priority < transfer.priority) {
        insertIndex = i;
        break;
      }
    }
    _items.insert(insertIndex, transfer);
  }
}

final Map<Object, _AsyncLock> _locks = {};

/// A simple async lock implementation
class _AsyncLock {
  Future<void>? _last;

  Future<T> synchronized<T>(FutureOr<T> Function() action) async {
    final prev = _last;
    final completer = Completer<void>();
    _last = completer.future;
    try {
      if (prev != null) await prev;
      return await action();
    } finally {
      completer.complete();
    }
  }
}

/// A synchronization helper that actually works for async code
Future<T> synchronized<T>(Object lock, FutureOr<T> Function() action) {
  final l = _locks.putIfAbsent(lock, () => _AsyncLock());
  return l.synchronized(action);
}

/// Transfer queue item with priority
class QueuedTransfer {
  final String id;
  final File file;
  final String endpointId;
  final String deviceName;
  final int priority; // Higher = more priority
  final DateTime queuedAt;
  int retryCount;
  TransferSession? session;

  QueuedTransfer({
    required this.id,
    required this.file,
    required this.endpointId,
    required this.deviceName,
    this.priority = 0,
    required this.queuedAt,
    this.retryCount = 0,
    this.session,
  });
}

/// Production-ready transfer manager with proper concurrency control
class TransferManager extends ChangeNotifier {
  static final TransferManager _instance = TransferManager._internal();
  factory TransferManager() => _instance;
  TransferManager._internal();

  // Dependencies
  final EnhancedTransferService _transferService = EnhancedTransferService();
  final TransferDatabase _database = TransferDatabase();

  // Configuration
  static const int maxConcurrentTransfers = 2; // Reduced for stability
  static const int maxRetriesPerTransfer = 5;
  static const Duration retryDelay = Duration(seconds: 5);
  static const Duration transferTimeout = Duration(minutes: 30);

  // State
  final List<TransferSession> _activeTransfers = [];
  final _TransferQueue _transferQueue = _TransferQueue();
  final Map<String, TransferSession> _completedTransfers = {};
  final Map<String, TransferSession> _failedTransfers = {};
  final _processingLock = Object();

  bool _isInitialized = false;
  bool _isProcessing = false;
  int _totalTransferredBytes = 0;
  DateTime? _lastTransferTime;

  // Statistics
  int _totalTransfers = 0;
  int _successfulTransfers = 0;
  int _failedTransferCount = 0;

  // Streams
  final _transferController = StreamController<TransferSession>.broadcast();
  final _queueController = StreamController<int>.broadcast();

  // Getters
  List<TransferSession> get activeTransfers =>
      List.unmodifiable(_activeTransfers);
  List<TransferSession> get completedTransfers =>
      List.unmodifiable(_completedTransfers.values);
  List<TransferSession> get failedTransfers =>
      List.unmodifiable(_failedTransfers.values);
  int get queueLength => _transferQueue.length;
  int get activeCount => _activeTransfers.length;
  bool get canAcceptMore => _activeTransfers.length < maxConcurrentTransfers;
  bool get hasActiveTransfers => _activeTransfers.isNotEmpty;
  bool get isQueueEmpty => _transferQueue.isEmpty;

  Stream<TransferSession> get transferStream => _transferController.stream;
  Stream<int> get queueStream => _queueController.stream;

  // Statistics getters
  int get totalTransfers => _totalTransfers;
  int get successfulCount => _successfulTransfers;
  int get failedCount => _failedTransferCount;
  double get successRate => _totalTransfers > 0
      ? (_successfulTransfers / _totalTransfers) * 100
      : 0.0;

  /// Initialize the manager
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _transferService.initialize();
    await _database.initialize();

    // Restore interrupted transfers
    await _restoreInterruptedTransfers();

    // Setup transfer service callbacks
    _transferService.onTransferCompleted = _onTransferCompleted;
    _transferService.onTransferFailed = _onTransferFailed;

    _isInitialized = true;
    debugPrint('[TransferManager] Initialized');
  }

  /// Queue a file for transfer
  Future<String> queueTransfer(
    File file,
    String endpointId,
    String deviceName, {
    int priority = 0,
  }) async {
    await _ensureInitialized();

    // Validate file exists
    if (!await file.exists()) {
      throw Exception('ط§ظ„ظ…ظ„ظپ ط؛ظٹط± ظ…ظˆط¬ظˆط¯: ${file.path}');
    }

    final transferId = DateTime.now().millisecondsSinceEpoch.toString();

    final queued = QueuedTransfer(
      id: transferId,
      file: file,
      endpointId: endpointId,
      deviceName: deviceName,
      priority: priority,
      queuedAt: DateTime.now(),
    );

    // Insert into queue based on priority
    _transferQueue.insertByPriority(queued);

    _queueController.add(_transferQueue.length);
    notifyListeners();

    debugPrint(
      '[TransferManager] Queued transfer: $transferId (${file.path.split('/').last})',
    );

    // Try to process queue
    _processQueue();

    return transferId;
  }

  /// Queue multiple files
  Future<List<String>> queueMultipleTransfers(
    List<File> files,
    String endpointId,
    String deviceName, {
    int basePriority = 0,
  }) async {
    final ids = <String>[];

    for (int i = 0; i < files.length; i++) {
      // Decrease priority for later files (first files transfer first)
      final priority = basePriority - i;
      final id = await queueTransfer(
        files[i],
        endpointId,
        deviceName,
        priority: priority,
      );
      ids.add(id);
    }

    return ids;
  }

  /// Cancel a specific transfer
  Future<void> cancelTransfer(String transferId) async {
    // Check active transfers
    final activeIndex = _activeTransfers.indexWhere(
      (t) => t.sessionId == transferId,
    );
    if (activeIndex >= 0) {
      await _transferService.cancelTransfer(transferId);
      final session = _activeTransfers.removeAt(activeIndex);
      _failedTransfers[transferId] = session..state = TransferState.cancelled;
      notifyListeners();
      _processQueue();
      return;
    }

    // Check queue
    final queued = _transferQueue.firstWhere(
      (q) => q.id == transferId,
      orElse: () => throw Exception('ظ„ظ… ظٹطھظ… ط§ظ„ط¹ط«ظˆط± ط¹ظ„ظ‰ ط§ظ„ظ†ظ‚ظ„'),
    );

    if (queued != null) {
      _transferQueue.removeWhere((q) => q.id == transferId);
      _queueController.add(_transferQueue.length);
      notifyListeners();
    }
  }

  /// Pause a transfer
  Future<void> pauseTransfer(String transferId) async {
    // Verify transfer exists
    _activeTransfers.firstWhere(
      (t) => t.sessionId == transferId,
      orElse: () => throw Exception('ظ„ظ… ظٹطھظ… ط§ظ„ط¹ط«ظˆط± ط¹ظ„ظ‰ ط§ظ„ظ†ظ‚ظ„'),
    );

    await _transferService.pauseTransfer(transferId);
    notifyListeners();
  }

  /// Resume a paused or failed transfer
  Future<void> resumeTransfer(String transferId) async {
    // Check failed transfers first
    if (_failedTransfers.containsKey(transferId)) {
      final session = _failedTransfers.remove(transferId)!;

      // Validate file still exists
      if (session.metadata.filePath != null) {
        final file = File(session.metadata.filePath!);
        if (!await file.exists()) {
          _failedTransfers[transferId] = session;
          throw Exception('ط§ظ„ظ…ظ„ظپ ط§ظ„ط£طµظ„ظٹ ظ„ظ… ظٹط¹ط¯ ظ…ظˆط¬ظˆط¯ط§ظ‹');
        }
      }

      // Re-queue with higher priority
      final queued = QueuedTransfer(
        id: transferId,
        file: File(session.metadata.filePath!),
        endpointId: session.deviceId,
        deviceName: session.deviceName,
        priority: 100, // High priority for resume
        queuedAt: DateTime.now(),
        retryCount: session.retryCount + 1,
        session: session,
      );

      _transferQueue.insertByPriority(queued);
      _queueController.add(_transferQueue.length);
      notifyListeners();
      _processQueue();
      return;
    }

    // Check active transfers
    final session = _activeTransfers.firstWhere(
      (t) => t.sessionId == transferId,
      orElse: () => throw Exception('ظ„ظ… ظٹطھظ… ط§ظ„ط¹ط«ظˆط± ط¹ظ„ظ‰ ط§ظ„ظ†ظ‚ظ„'),
    );

    if (session.canResume) {
      await _transferService.resumeTransfer(transferId);
      notifyListeners();
    }
  }

  /// Cancel all transfers
  Future<void> cancelAll() async {
    // Cancel active
    for (final session in _activeTransfers.toList()) {
      await cancelTransfer(session.sessionId);
    }

    // Clear queue
    _transferQueue.clear();
    _queueController.add(0);
    notifyListeners();
  }

  /// Get transfer by ID
  TransferSession? getTransfer(String transferId) {
    // Check active
    try {
      return _activeTransfers.firstWhere((t) => t.sessionId == transferId);
    } catch (_) {}

    // Check completed
    if (_completedTransfers.containsKey(transferId)) {
      return _completedTransfers[transferId];
    }

    // Check failed
    if (_failedTransfers.containsKey(transferId)) {
      return _failedTransfers[transferId];
    }

    return null;
  }

  /// Get all transfers sorted by time
  List<TransferSession> getAllTransfers() {
    final all = <TransferSession>[
      ..._activeTransfers,
      ..._completedTransfers.values,
      ..._failedTransfers.values,
    ];

    all.sort((a, b) {
      final aTime = a.startedAt ?? a.metadata.createdAt;
      final bTime = b.startedAt ?? b.metadata.createdAt;
      return bTime.compareTo(aTime);
    });

    return all;
  }

  /// Clear completed and failed transfers from memory
  void clearCompletedTransfers() {
    _completedTransfers.clear();
    _failedTransfers.clear();
    notifyListeners();
  }

  /// Cleanup old transfers from database
  Future<void> cleanupOldTransfers({int daysToKeep = 7}) async {
    await _database.cleanupOldSessions(daysToKeep: daysToKeep);
  }

  // ==================== PRIVATE METHODS ====================

  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  Future<void> _processQueue() async {
    await synchronized(_processingLock, () async {
      if (_isProcessing) return;
      if (_transferQueue.isEmpty) return;
      if (_activeTransfers.length >= maxConcurrentTransfers) return;

      _isProcessing = true;

      while (_transferQueue.isNotEmpty &&
          _activeTransfers.length < maxConcurrentTransfers) {
        final queued = _transferQueue.removeFirst();
        if (queued == null) break;

        _queueController.add(_transferQueue.length);

        await _startTransfer(queued);
      }

      _isProcessing = false;
      notifyListeners();
    });
  }

  Future<void> _startTransfer(QueuedTransfer queued) async {
    try {
      debugPrint('[TransferManager] Starting transfer: ${queued.id}');

      // Validate file still exists
      if (!await queued.file.exists()) {
        throw Exception('File no longer exists: ${queued.file.path}');
      }

      // Use existing session if resuming
      TransferSession? session = queued.session;
      String sessionId;

      if (session == null) {
        // Create new transfer
        session = await _transferService.sendFile(
          queued.endpointId,
          queued.file,
          customTransferId: queued.id,
        );
        if (session == null) {
          _handleTransferFailure(queued, 'ظپط´ظ„ ظپظٹ ط¨ط¯ط، ط§ظ„ظ†ظ‚ظ„');
          return;
        }
        sessionId = session.sessionId;
      } else {
        // Resume existing
        sessionId = queued.id;
        await _transferService.resumeTransfer(sessionId);
      }

      // Update session info if we have a session object
      // Note: session can be null when resuming existing transfers
      // ignore: unnecessary_null_comparison
      if (session != null) {
        session.deviceName = queued.deviceName;

        if (!_activeTransfers.any((t) => t.sessionId == session!.sessionId)) {
          _activeTransfers.add(session);
        }
      }

      _totalTransfers++;
      _lastTransferTime = DateTime.now();

      // Subscribe to session updates with timeout protection
      _transferService
          .getSessionStream(sessionId)
          .listen(
            (updatedSession) {
              _onSessionUpdate(updatedSession);
            },
            onError: (error) {
              _onTransferError(sessionId, error.toString());
            },
            onDone: () {
              // Stream closed - transfer ended
            },
          );

      notifyListeners();
    } catch (e) {
      debugPrint('[TransferManager] Error starting transfer: $e');
      _handleTransferFailure(queued, e.toString());
    }
  }

  void _onSessionUpdate(TransferSession session) {
    final index = _activeTransfers.indexWhere(
      (t) => t.sessionId == session.sessionId,
    );
    if (index >= 0) {
      _activeTransfers[index] = session;
      _transferController.add(session);
      notifyListeners();
    }
  }

  void _onTransferCompleted(String sessionId) {
    final index = _activeTransfers.indexWhere((t) => t.sessionId == sessionId);
    if (index >= 0) {
      final session = _activeTransfers.removeAt(index);
      session.state = TransferState.completed;
      session.completedAt = DateTime.now();

      _completedTransfers[sessionId] = session;
      _successfulTransfers++;
      _totalTransferredBytes += session.metadata.fileSize;

      debugPrint('[TransferManager] Transfer completed: $sessionId');

      notifyListeners();
      _processQueue();
    }
  }

  void _onTransferFailed(String sessionId, String error) {
    _onTransferError(sessionId, error);
  }

  void _onTransferError(String sessionId, String error) {
    final index = _activeTransfers.indexWhere((t) => t.sessionId == sessionId);
    if (index >= 0) {
      final session = _activeTransfers.removeAt(index);
      session.state = TransferState.failed;
      session.errorMessage = error;

      _failedTransfers[sessionId] = session;
      _failedTransferCount++;

      debugPrint('[TransferManager] Transfer failed: $sessionId - $error');

      notifyListeners();
      _processQueue();
    }
  }

  void _handleTransferFailure(QueuedTransfer queued, String error) {
    queued.retryCount++;

    if (queued.retryCount < maxRetriesPerTransfer) {
      // Re-queue with delay
      Future.delayed(retryDelay, () {
        _transferQueue.addFirst(queued);
        _queueController.add(_transferQueue.length);
        notifyListeners();
        _processQueue();
      });
    } else {
      // Max retries reached
      debugPrint('[TransferManager] Max retries reached for ${queued.id}');
      _failedTransferCount++;
    }
  }

  Future<void> _restoreInterruptedTransfers() async {
    try {
      final interrupted = await _database.getResumableSessions();

      for (final session in interrupted) {
        if (session.metadata.filePath != null) {
          final file = File(session.metadata.filePath!);
          if (await file.exists()) {
            final queued = QueuedTransfer(
              id: session.sessionId,
              file: file,
              endpointId: session.deviceId,
              deviceName: session.deviceName,
              priority: 50,
              queuedAt: DateTime.now(),
              retryCount: session.retryCount,
              session: session,
            );

            _transferQueue.add(queued);
            debugPrint(
              '[TransferManager] Restored interrupted transfer: ${session.sessionId}',
            );
          } else {
            // Mark as failed since file no longer exists
            await _database.updateSessionState(
              session.sessionId,
              TransferState.failed,
              errorMessage: 'ط§ظ„ظ…ظ„ظپ ط§ظ„ط£طµظ„ظٹ ظ„ظ… ظٹط¹ط¯ ظ…ظˆط¬ظˆط¯ط§ظ‹',
            );
          }
        }
      }

      if (_transferQueue.isNotEmpty) {
        _queueController.add(_transferQueue.length);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[TransferManager] Error restoring interrupted transfers: $e');
    }
  }

  /// Get transfer statistics
  Map<String, dynamic> getStatistics() {
    final activeCount = _activeTransfers.length;

    // Calculate average speed
    double totalSpeed = 0;
    int activeWithSpeed = 0;
    for (final t in _activeTransfers) {
      if (t.currentSpeed > 0) {
        totalSpeed += t.currentSpeed;
        activeWithSpeed++;
      }
    }
    final avgSpeed = activeWithSpeed > 0 ? totalSpeed / activeWithSpeed : 0;

    return {
      'activeTransfers': activeCount,
      'queuedTransfers': _transferQueue.length,
      'completedTransfers': _completedTransfers.length,
      'failedTransfers': _failedTransfers.length,
      'totalTransferredBytes': _totalTransferredBytes,
      'averageSpeed': avgSpeed,
      'successRate': successRate,
      'totalTransfers': _totalTransfers,
      'lastTransferTime': _lastTransferTime?.toIso8601String(),
    };
  }

  @override
  void dispose() {
    _transferController.close();
    _queueController.close();
    super.dispose();
  }
}
