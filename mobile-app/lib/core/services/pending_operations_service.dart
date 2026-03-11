import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Operation priority levels
enum OperationPriority {
  high, // approve, send - user-facing, critical
  medium, // ignore, edit - important but can wait
  low, // mark_read, delete - background tasks
}

/// Represents a pending operation to be synced when online
class PendingOperation {
  final String id;
  final String accountHash; // Hash of the license key it belongs to (REQUIRED)
  final String
  type; // 'approve', 'ignore', 'send', 'delete', 'edit', 'mark_read'
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;
  final DateTime? lastAttempt;
  final String? error;
  final OperationPriority priority;

  /// Random for jitter calculation
  static final _random = Random();

  /// P1-6 FIX: Stale threshold increased from 7 days to 30 days
  /// to support users with extended offline periods (travel, remote areas)
  static const Duration _staleThreshold = Duration(days: 30);

  PendingOperation({
    required this.id,
    String? accountHash,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
    this.lastAttempt,
    this.error,
    OperationPriority? priority,
  }) : accountHash = accountHash ?? _validateAccountHash(),
       priority = priority ?? _inferPriority(type);

  /// Validate account hash is provided
  static String _validateAccountHash() {
    throw ArgumentError('accountHash is required for multi-account isolation');
  }

  /// Infer priority from operation type
  static OperationPriority _inferPriority(String type) {
    switch (type) {
      case 'approve':
      case 'send':
        return OperationPriority.high;
      case 'ignore':
      case 'edit':
        return OperationPriority.medium;
      case 'mark_read':
      case 'delete':
      case 'delete_conversation':
      default:
        return OperationPriority.low;
    }
  }

  /// Create with retry increment
  PendingOperation incrementRetry(String? errorMessage) {
    return PendingOperation(
      id: id,
      accountHash: accountHash,
      type: type,
      payload: payload,
      createdAt: createdAt,
      retryCount: retryCount + 1,
      lastAttempt: DateTime.now(),
      error: errorMessage,
      priority: priority,
    );
  }

  /// Check if operation should be retried based on backoff with jitter
  bool get shouldRetry {
    if (retryCount >= 5) return false; // Max 5 retries
    if (lastAttempt == null) return true;

    // Exponential backoff with jitter: base + random(0, base)
    // This prevents thundering herd when many devices come online
    final baseSeconds = 1 << retryCount; // 2, 4, 8, 16, 32
    final jitterSeconds = _random.nextInt(baseSeconds + 1);
    final backoffSeconds = baseSeconds + jitterSeconds;

    final nextRetryTime = lastAttempt!.add(Duration(seconds: backoffSeconds));
    return DateTime.now().isAfter(nextRetryTime);
  }

  /// Check if operation is stale (older than 7 days)
  bool get isStale => DateTime.now().difference(createdAt) > _staleThreshold;

  /// Priority as int for sorting (lower = higher priority)
  int get priorityValue => priority.index;

  /// P1-6 FIX: Warning threshold at 25 days - notify user before cleanup
  bool get shouldWarn =>
      DateTime.now().difference(createdAt) > const Duration(days: 25);

  Map<String, dynamic> toJson() => {
    'id': id,
    'accountHash': accountHash,
    'type': type,
    'payload': payload,
    'createdAt': createdAt.toIso8601String(),
    'retryCount': retryCount,
    'lastAttempt': lastAttempt?.toIso8601String(),
    'error': error,
    'priority': priority.name,
  };

  factory PendingOperation.fromJson(Map<String, dynamic> json) {
    return PendingOperation(
      id: json['id'] as String,
      accountHash: json['accountHash'] as String?,
      type: json['type'] as String,
      payload: Map<String, dynamic>.from(json['payload'] as Map),
      createdAt: DateTime.parse(json['createdAt'] as String),
      retryCount: json['retryCount'] as int? ?? 0,
      lastAttempt: json['lastAttempt'] != null
          ? DateTime.parse(json['lastAttempt'] as String)
          : null,
      error: json['error'] as String?,
      priority: json['priority'] != null
          ? OperationPriority.values.firstWhere(
              (p) => p.name == json['priority'],
              orElse: () => OperationPriority.medium,
            )
          : null,
    );
  }
}

/// Service for managing pending operations when offline.
///
/// Features:
/// - Persist pending operations using Hive
/// - Track retry count and last attempt time
/// - Exponential backoff for retries
/// - Stream of pending operations for UI updates
class PendingOperationsService extends ChangeNotifier {
  static const String _boxName = 'pending_operations';
  static const String _encryptionKeyStorage = 'hive_encryption_key_v1';

  // SECURITY: Hardware-backed encryption
  final _secureStorage = const FlutterSecureStorage();

  Box<String>? _box;
  bool _isInitialized = false;

  /// In-memory cache of pending operations
  final List<PendingOperation> _operations = [];

  /// Get all pending operations
  List<PendingOperation> get operations => List.unmodifiable(_operations);

  /// Check if there are pending operations
  bool get hasPendingOperations => _operations.isNotEmpty;

  /// Get count of pending operations
  int get pendingCount => _operations.length;

  /// Initialize the service
  Future<void> initialize() async {
    if (_isInitialized) return;

    // SECURITY: Use hardware-backed encryption key for Hive
    final encryptionKey = await _getOrCreateEncryptionKey();

    // Note: Hive.initFlutter() is called once in main.dart before runApp
    try {
      _box = await Hive.openBox<String>(
        _boxName,
        encryptionCipher: HiveAesCipher(encryptionKey),
      );
    } catch (e) {
      // If opening fails (e.g. legacy box was unencrypted), delete and recreate
      debugPrint(
        '[PendingOperationsService] Encryption error, recreating box: $e',
      );
      await Hive.deleteBoxFromDisk(_boxName);
      _box = await Hive.openBox<String>(
        _boxName,
        encryptionCipher: HiveAesCipher(encryptionKey),
      );
    }

    // Load existing operations
    await _loadFromDisk();

    _isInitialized = true;
    debugPrint(
      '[PendingOperationsService] Initialized with ${_operations.length} encrypted pending operations',
    );
  }

  /// Get or create a secure encryption key for Hive
  Future<List<int>> _getOrCreateEncryptionKey() async {
    final String? encodedKey = await _secureStorage.read(
      key: _encryptionKeyStorage,
    );

    if (encodedKey == null) {
      // Generate a new 256-bit key
      final key = Hive.generateSecureKey();
      await _secureStorage.write(
        key: _encryptionKeyStorage,
        value: base64UrlEncode(key),
      );
      return key;
    }

    return base64Url.decode(encodedKey);
  }

  /// Load operations from disk
  Future<void> _loadFromDisk() async {
    _operations.clear();

    for (final key in _box?.keys ?? []) {
      try {
        final json = _box?.get(key);
        if (json != null) {
          final data = jsonDecode(json) as Map<String, dynamic>;
          _operations.add(PendingOperation.fromJson(data));
        }
      } catch (e) {
        debugPrint(
          '[PendingOperationsService] Error loading operation $key: $e',
        );
        await _box?.delete(key);
      }
    }

    // Cleanup stale operations (older than 30 days)
    await _cleanupStaleOperations();

    // Sort by priority first, then by creation time
    _sortOperations();
  }

  /// Sort operations by priority (high first) then by creation time
  void _sortOperations() {
    _operations.sort((a, b) {
      // First by priority (lower index = higher priority)
      final priorityCompare = a.priorityValue.compareTo(b.priorityValue);
      if (priorityCompare != 0) return priorityCompare;
      // Then by creation time (older first)
      return a.createdAt.compareTo(b.createdAt);
    });
  }

  /// Remove stale operations (older than 30 days)
  /// P1-6 FIX: Added warning notification for operations approaching stale threshold
  Future<int> _cleanupStaleOperations() async {
    final staleOps = _operations.where((op) => op.isStale).toList();

    // P1-6 FIX: Warn about operations approaching stale threshold (25-30 days)
    final warningOps = _operations
        .where((op) => op.shouldWarn && !op.isStale)
        .toList();
    if (warningOps.isNotEmpty) {
      debugPrint(
        '[PendingOperationsService] WARNING: ${warningOps.length} operations approaching stale threshold. '
        'Please sync soon to avoid data loss.',
      );
      // Notification trigger removed - will be re-implemented when NotificationsProvider is restored
      // Future: Use a dedicated NotificationService to show local notification
    }

    for (final op in staleOps) {
      _operations.remove(op);
      await _box?.delete(op.id);
      debugPrint(
        '[PendingOperationsService] Cleaned stale operation: ${op.id}',
      );
    }

    if (staleOps.isNotEmpty) {
      debugPrint(
        '[PendingOperationsService] Cleaned ${staleOps.length} stale operations',
      );
    }

    return staleOps.length;
  }

  /// Add a new pending operation
  Future<void> addOperation({
    required String type,
    required Map<String, dynamic> payload,
    String? customId,
    required String
    accountHash, // P0-2 FIX: Required for multi-account isolation
  }) async {
    await _ensureInitialized();

    final operation = PendingOperation(
      id: customId ?? '${type}_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      accountHash: accountHash,
      payload: payload,
      createdAt: DateTime.now(),
    );

    _operations.add(operation);
    await _saveToDisk(operation);
    notifyListeners();

    debugPrint(
      '[PendingOperationsService] Added operation: ${operation.id} for account: $accountHash',
    );
  }

  /// Remove an operation after successful sync
  Future<void> removeOperation(String id) async {
    await _ensureInitialized();

    _operations.removeWhere((op) => op.id == id);
    await _box?.delete(id);
    notifyListeners();

    debugPrint('[PendingOperationsService] Removed operation: $id');
  }

  /// Get operations ready for retry (respecting backoff)
  List<PendingOperation> getRetryableOperations() {
    return _operations.where((op) => op.shouldRetry).toList();
  }

  /// Update operation after failed attempt
  Future<void> markRetryFailed(String id, String errorMessage) async {
    await _ensureInitialized();

    final index = _operations.indexWhere((op) => op.id == id);
    if (index == -1) return;

    final updated = _operations[index].incrementRetry(errorMessage);
    _operations[index] = updated;
    await _saveToDisk(updated);
    notifyListeners();

    debugPrint(
      '[PendingOperationsService] Marked retry failed for: $id (attempt ${updated.retryCount})',
    );
  }

  /// Get operations of a specific type
  List<PendingOperation> getOperationsByType(String type) {
    return _operations.where((op) => op.type == type).toList();
  }

  /// Check if there's a pending operation for a specific message
  bool hasPendingOperationFor(int messageId) {
    return _operations.any((op) => op.payload['messageId'] == messageId);
  }

  /// Clear all pending operations (use with caution)
  Future<void> clearAll() async {
    await _ensureInitialized();

    _operations.clear();
    await _box?.clear();
    notifyListeners();

    debugPrint('[PendingOperationsService] Cleared all operations');
  }

  /// Save operation to disk
  Future<void> _saveToDisk(PendingOperation operation) async {
    await _box?.put(operation.id, jsonEncode(operation.toJson()));
  }

  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  @override
  void dispose() {
    _box?.close();
    super.dispose();
  }
}
