import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../data/local/transfer_database.dart';
import '../../data/models/transfer_models.dart';
import 'package:almudeer_mobile_app/core/services/enhanced_transfer_service.dart';
import 'package:almudeer_mobile_app/core/services/transfer_manager.dart';

/// Pending connection request from a remote device
class PendingConnectionRequest {
  final String endpointId;
  final String deviceName;
  final DateTime receivedAt;

  PendingConnectionRequest({
    required this.endpointId,
    required this.deviceName,
    required this.receivedAt,
  });
}

/// UI-facing provider for transfer operations
class TransferProvider extends ChangeNotifier with WidgetsBindingObserver {
  final TransferManager _transferManager = TransferManager();
  final EnhancedTransferService _transferService = EnhancedTransferService();
  final TransferDatabase _database = TransferDatabase();

  // State
  final List<TransferDevice> _discoveredDevices = [];
  bool _isScanning = false;
  bool _isAdvertising = false;
  String? _errorMessage;
  bool _isInitialized = false;

  // Device connection state
  TransferDevice? _selectedDevice;
  bool _isConnecting = false;

  // New state for UX improvement
  List<HardwareRequirement> _missingRequirements = [];
  String? _lastAttemptedAction; // 'scan' or 'advertise'
  String? _lastUsedDeviceName;

  // Processing state for button loading indicators
  bool _isProcessing = false;

  // Pending connection request from receiver side
  PendingConnectionRequest? _pendingConnectionRequest;
  final StreamController<PendingConnectionRequest>
  _connectionRequestController =
      StreamController<PendingConnectionRequest>.broadcast();

  // Transfer completion/failure callbacks for haptics
  void Function(TransferSession)? onTransferCompleted;
  void Function(TransferSession)? onTransferFailed;

  // Getters
  List<TransferDevice> get discoveredDevices =>
      List.unmodifiable(_discoveredDevices);
  List<TransferSession> get activeTransfers => _transferManager.activeTransfers;
  List<TransferSession> get completedTransfers =>
      _transferManager.completedTransfers;
  List<TransferSession> get failedTransfers => _transferManager.failedTransfers;
  List<TransferSession> get transferHistory =>
      [
        ..._transferManager.completedTransfers,
        ..._transferManager.failedTransfers,
      ]..sort((a, b) {
        final aTime = a.completedAt ?? a.lastActivityAt ?? DateTime(0);
        final bTime = b.completedAt ?? b.lastActivityAt ?? DateTime(0);
        return bTime.compareTo(aTime);
      });
  int get queueLength => _transferManager.queueLength;
  int get totalActiveCount =>
      _transferManager.activeCount + _transferManager.queueLength;

  bool get isScanning => _isScanning;
  bool get isAdvertising => _isAdvertising;
  bool get isConnecting => _isConnecting;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;
  TransferDevice? get selectedDevice => _selectedDevice;
  bool get isReady => _isInitialized;
  bool get hasActiveTransfers => _transferManager.hasActiveTransfers;
  List<HardwareRequirement> get missingRequirements => _missingRequirements;
  bool get hasMissingRequirements => _missingRequirements.isNotEmpty;
  bool get isProcessing => _isProcessing;
  PendingConnectionRequest? get pendingConnectionRequest =>
      _pendingConnectionRequest;
  Stream<PendingConnectionRequest> get connectionRequestStream =>
      _connectionRequestController.stream;

  // Statistics
  double get overallProgress {
    final allTransfers = _transferManager.getAllTransfers();
    if (allTransfers.isEmpty) return 0.0;

    double totalProgress = 0;
    for (final t in allTransfers) {
      totalProgress += t.progress;
    }
    return totalProgress / allTransfers.length;
  }

  Map<String, dynamic> get statistics => _transferManager.getStatistics();

  /// Initialize the provider
  Future<void> initialize() async {
    if (_isInitialized) return;

    WidgetsBinding.instance.addObserver(this);

    try {
      await _transferManager.initialize();
      await _transferService.initialize();

      // Setup callbacks
      _transferService.onDeviceDiscovered = _onDeviceDiscovered;
      _transferService.onDeviceLost = _onDeviceLost;
      _transferService.onTransferRequested = _onTransferRequested;

      // Listen to transfer updates with completion/failure detection
      _transferManager.transferStream.listen((session) {
        if (session.state == TransferState.completed) {
          onTransferCompleted?.call(session);
        } else if (session.state == TransferState.failed) {
          onTransferFailed?.call(session);
        }
        notifyListeners();
      });

      _transferManager.queueStream.listen((length) {
        notifyListeners();
      });

      _isInitialized = true;
      _clearError();
      notifyListeners();

      debugPrint('[TransferProvider] Initialized successfully');
    } catch (e) {
      _setError('ظپط´ظ„ ظپظٹ ط§ظ„طھظ‡ظٹط¦ط©: $e');
    }
  }

  /// Start scanning for nearby devices
  Future<bool> startScanning(String deviceName) async {
    if (!_isInitialized) {
      _setError('ط§ظ„ظ…ط²ظˆط¯ ط؛ظٹط± ظ…ظ‡ظٹط£');
      return false;
    }

    _lastAttemptedAction = 'scan';
    _lastUsedDeviceName = deviceName;
    _isProcessing = true;
    notifyListeners();

    try {
      final hasPermissions = await _transferService
          .checkAndRequestPermissions();

      _missingRequirements = await _transferService.getMissingRequirements();

      if (!hasPermissions || _missingRequirements.isNotEmpty) {
        final error = await _transferService.getHardwareErrorMessage();
        _setError(error ?? 'ظٹط±ط¬ظ‰ ظ…ظ†ط­ ط§ظ„ط£ط°ظˆظ†ط§طھ ط§ظ„ظ…ط·ظ„ظˆط¨ط©');
        _isProcessing = false;
        notifyListeners();
        return false;
      }

      final success = await _transferService.startDiscovery(deviceName);
      if (success) {
        _isScanning = true;
        _discoveredDevices.clear();
        _clearError();
        _missingRequirements.clear();
      } else {
        final error = await _transferService.getHardwareErrorMessage();
        _setError(error ?? 'ظپط´ظ„ ط¨ط¯ط، ط§ظ„ط¨ط­ط«');
      }

      _isProcessing = false;
      notifyListeners();
      return success;
    } catch (e) {
      _isProcessing = false;
      _setError('ط®ط·ط£ ظپظٹ ط¨ط¯ط، ط§ظ„ط¨ط­ط«: $e');
      notifyListeners();
      return false;
    }
  }

  /// Stop scanning
  Future<void> stopScanning() async {
    if (!_isScanning) return;

    try {
      await _transferService.stopAll();
      _isScanning = false;
      _lastAttemptedAction = null;
      notifyListeners();
    } catch (e) {
      debugPrint('[TransferProvider] Error stopping scan: $e');
    }
  }

  /// Start advertising (receive mode)
  Future<bool> startAdvertising(String deviceName) async {
    if (!_isInitialized) {
      _setError('ط§ظ„ظ…ط²ظˆط¯ ط؛ظٹط± ظ…ظ‡ظٹط£');
      return false;
    }

    _lastAttemptedAction = 'advertise';
    _lastUsedDeviceName = deviceName;
    _isProcessing = true;
    notifyListeners();

    try {
      final hasPermissions = await _transferService
          .checkAndRequestPermissions();

      _missingRequirements = await _transferService.getMissingRequirements();

      if (!hasPermissions || _missingRequirements.isNotEmpty) {
        final error = await _transferService.getHardwareErrorMessage();
        _setError(error ?? 'ظٹط±ط¬ظ‰ ظ…ظ†ط­ ط§ظ„ط£ط°ظˆظ†ط§طھ ط§ظ„ظ…ط·ظ„ظˆط¨ط©');
        _isProcessing = false;
        notifyListeners();
        return false;
      }

      final success = await _transferService.startAdvertising(deviceName);
      if (success) {
        _isAdvertising = true;
        _clearError();
        _missingRequirements.clear();
      } else {
        final error = await _transferService.getHardwareErrorMessage();
        _setError(error ?? 'ظپط´ظ„ ط¨ط¯ط، ط§ظ„ط§ط³طھظ‚ط¨ط§ظ„');
      }

      _isProcessing = false;
      notifyListeners();
      return success;
    } catch (e) {
      _isProcessing = false;
      _setError('ط®ط·ط£ ظپظٹ ط¨ط¯ط، ط§ظ„ط§ط³طھظ‚ط¨ط§ظ„: $e');
      notifyListeners();
      return false;
    }
  }

  /// Stop advertising
  Future<void> stopAdvertising() async {
    if (!_isAdvertising) return;

    try {
      await _transferService.stopAll();
      _isAdvertising = false;
      _lastAttemptedAction = null;
      notifyListeners();
    } catch (e) {
      debugPrint('[TransferProvider] Error stopping advertising: $e');
    }
  }

  /// Stop all operations
  Future<void> stopAll() async {
    await stopScanning();
    await stopAdvertising();
    await _transferManager.cancelAll();
    _discoveredDevices.clear();
    _selectedDevice = null;
    _lastAttemptedAction = null;
    notifyListeners();
  }

  /// Connect to a device with timeout
  Future<bool> connectToDevice(TransferDevice device) async {
    _isConnecting = true;
    _selectedDevice = device;
    notifyListeners();

    try {
      final success = await _transferService
          .requestConnection(
            device.deviceName,
            device.endpointId ?? device.deviceId,
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              debugPrint('[TransferProvider] Connection timed out');
              return false;
            },
          );

      if (success) {
        device.connectionCount++;
        device.lastConnectedAt = DateTime.now();
        await _database.saveDevice(device);
      } else {
        _setError(
          'ط§ظ†طھظ‡طھ ظ…ظ‡ظ„ط© ط§ظ„ط§طھطµط§ظ„. طھط£ظƒط¯ ظ…ظ† ط£ظ† ط§ظ„ط¬ظ‡ط§ط² ط§ظ„ط¢ط®ط± ظپظٹ ظˆط¶ط¹ ط§ظ„ط§ط³طھظ‚ط¨ط§ظ„',
        );
      }

      _isConnecting = false;
      notifyListeners();
      return success;
    } catch (e) {
      device.failedConnections++;
      await _database.saveDevice(device);

      _isConnecting = false;
      _setError('ظپط´ظ„ ط§ظ„ط§طھطµط§ظ„: $e');
      notifyListeners();
      return false;
    }
  }

  /// Disconnect from current device
  Future<void> disconnect() async {
    await _transferService.stopAll();
    _selectedDevice = null;
    notifyListeners();
  }

  /// Send files to connected device
  Future<List<String>> sendFiles(List<File> files, {int priority = 0}) async {
    if (_selectedDevice == null) {
      _setError('ظ„ط§ ظٹظˆط¬ط¯ ط¬ظ‡ط§ط² ظ…طھطµظ„');
      return [];
    }

    try {
      final ids = await _transferManager.queueMultipleTransfers(
        files,
        _selectedDevice!.endpointId ?? _selectedDevice!.deviceId,
        _selectedDevice!.deviceName,
        basePriority: priority,
      );

      _clearError();
      notifyListeners();
      return ids;
    } catch (e) {
      _setError('ظپط´ظ„ ظپظٹ ط¥ط¶ط§ظپط© ط§ظ„ظ…ظ„ظپط§طھ: $e');
      return [];
    }
  }

  /// Send single file
  Future<String?> sendFile(File file, {int priority = 0}) async {
    final ids = await sendFiles([file], priority: priority);
    return ids.isNotEmpty ? ids.first : null;
  }

  /// Pause a transfer
  Future<void> pauseTransfer(String transferId) async {
    try {
      await _transferManager.pauseTransfer(transferId);
      notifyListeners();
    } catch (e) {
      _setError('ظپط´ظ„ ظپظٹ ط¥ظٹظ‚ط§ظپ ط§ظ„ظ†ظ‚ظ„ ظ…ط¤ظ‚طھط§ظ‹: $e');
    }
  }

  /// Resume a transfer
  Future<void> resumeTransfer(String transferId) async {
    try {
      await _transferManager.resumeTransfer(transferId);
      notifyListeners();
    } catch (e) {
      _setError('ظپط´ظ„ ظپظٹ ط§ط³طھط¦ظ†ط§ظپ ط§ظ„ظ†ظ‚ظ„: $e');
    }
  }

  /// Retry a failed transfer
  Future<void> retryTransfer(String transferId) async {
    try {
      await _transferManager.resumeTransfer(transferId);
      notifyListeners();
    } catch (e) {
      _setError('ظپط´ظ„ ظپظٹ ط¥ط¹ط§ط¯ط© ط§ظ„ظ…ط­ط§ظˆظ„ط©: $e');
    }
  }

  /// Cancel a transfer
  Future<void> cancelTransfer(String transferId) async {
    try {
      await _transferManager.cancelTransfer(transferId);
      notifyListeners();
    } catch (e) {
      _setError('ظپط´ظ„ ظپظٹ ط¥ظ„ط؛ط§ط، ط§ظ„ظ†ظ‚ظ„: $e');
    }
  }

  /// Cancel all transfers
  Future<void> cancelAllTransfers() async {
    await _transferManager.cancelAll();
    notifyListeners();
  }

  /// Get transfer details
  TransferSession? getTransfer(String transferId) {
    return _transferManager.getTransfer(transferId);
  }

  /// Get all transfers
  List<TransferSession> getAllTransfers() {
    return _transferManager.getAllTransfers();
  }

  /// Clear completed transfers
  void clearCompleted() {
    _transferManager.clearCompletedTransfers();
    notifyListeners();
  }

  /// Trust a device
  Future<void> trustDevice(String deviceId) async {
    final device = await _database.getDevice(deviceId);
    if (device != null) {
      device.isTrusted = true;
      await _database.saveDevice(device);

      // Update in discovered list if present
      final index = _discoveredDevices.indexWhere(
        (d) => d.deviceId == deviceId,
      );
      if (index >= 0) {
        _discoveredDevices[index] = device;
        notifyListeners();
      }
    }
  }

  /// Get trusted devices
  Future<List<TransferDevice>> getTrustedDevices() async {
    return await _database.getTrustedDevices();
  }

  /// Get transfer history
  Future<List<Map<String, dynamic>>> getTransferHistory({
    int limit = 50,
  }) async {
    return await _database.getTransferHistory(limit: limit);
  }

  /// Accept incoming transfer request
  Future<void> acceptTransferRequest(String sessionId) async {
    // Implementation depends on protocol
    notifyListeners();
  }

  /// Reject incoming transfer request
  Future<void> rejectTransferRequest(String sessionId) async {
    // Implementation depends on protocol
    notifyListeners();
  }

  /// Fix a specific requirement by opening settings
  Future<void> fixRequirement(HardwareRequirement req) async {
    await _transferService.openHardwareSettings(req);
  }

  /// Accept a pending connection request from receiver side
  Future<bool> acceptPendingConnection() async {
    final request = _pendingConnectionRequest;
    if (request == null) return false;

    _pendingConnectionRequest = null;
    notifyListeners();

    final success = await _transferService.acceptConnection(request.endpointId);
    if (success) {
      _selectedDevice = TransferDevice(
        deviceId: request.endpointId,
        deviceName: request.deviceName,
        endpointId: request.endpointId,
        discoveredAt: request.receivedAt,
      );
    }
    notifyListeners();
    return success;
  }

  /// Reject a pending connection request
  Future<void> rejectPendingConnection() async {
    final request = _pendingConnectionRequest;
    if (request == null) return;

    _pendingConnectionRequest = null;
    notifyListeners();
    // Nearby connections will handle the rejection by not accepting
  }

  /// Clear transfer history
  void clearHistory() {
    _transferManager.clearCompletedTransfers();
    notifyListeners();
  }

  // ==================== LIFECYCLE HANDLERS ====================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _onAppPaused();
    }
  }

  Future<void> _onAppPaused() async {
    // Stop scanning/advertising to save battery if no active transfers
    if (!hasActiveTransfers) {
      debugPrint(
        '[TransferProvider] App paused, stopping discovery/advertising',
      );
      await stopScanning();
      await stopAdvertising();
    }
  }

  Future<void> _onAppResumed() async {
    if (!_isInitialized) return;

    // Re-check requirements
    final prevMissing = _missingRequirements.length;
    _missingRequirements = await _transferService.getMissingRequirements();

    if (_missingRequirements.isEmpty && prevMissing > 0) {
      // Requirements were fixed, try to auto-resume
      if (_lastAttemptedAction == 'scan' && _lastUsedDeviceName != null) {
        debugPrint('[TransferProvider] Auto-resuming scan');
        startScanning(_lastUsedDeviceName!);
      } else if (_lastAttemptedAction == 'advertise' &&
          _lastUsedDeviceName != null) {
        debugPrint('[TransferProvider] Auto-resuming advertising');
        startAdvertising(_lastUsedDeviceName!);
      }
    }

    notifyListeners();
  }

  // ==================== CALLBACK HANDLERS ====================

  void _onDeviceDiscovered(TransferDevice device) {
    final existingIndex = _discoveredDevices.indexWhere(
      (d) => d.deviceId == device.deviceId,
    );

    if (existingIndex >= 0) {
      _discoveredDevices[existingIndex] = device;
    } else {
      _discoveredDevices.add(device);
    }

    notifyListeners();
  }

  void _onDeviceLost(TransferDevice device) {
    _discoveredDevices.removeWhere((d) => d.deviceId == device.deviceId);
    notifyListeners();
  }

  void _onTransferRequested(String sessionId, TransferDevice device) {
    debugPrint(
      '[TransferProvider] Transfer requested from: ${device.deviceName}',
    );

    _pendingConnectionRequest = PendingConnectionRequest(
      endpointId: device.endpointId ?? device.deviceId,
      deviceName: device.deviceName,
      receivedAt: DateTime.now(),
    );
    _connectionRequestController.add(_pendingConnectionRequest!);
    notifyListeners();
  }

  // ==================== ERROR HANDLING ====================

  void _setError(String message) {
    _errorMessage = message;
    notifyListeners();

    // Auto-clear error after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (_errorMessage == message) {
        _clearError();
      }
    });
  }

  void _clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  void clearError() => _clearError();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectionRequestController.close();
    _transferManager.dispose();
    super.dispose();
  }

  /// Reset state for account switching
  void reset() {
    // Stop scanning/advertising
    if (_isScanning) {
      stopScanning();
    }
    if (_isAdvertising) {
      stopAdvertising();
    }

    // Clear discovered devices
    _discoveredDevices.clear();

    // Clear connection state
    _selectedDevice = null;
    _isConnecting = false;

    // Clear pending requests
    _pendingConnectionRequest = null;

    // Clear error state
    _errorMessage = null;

    // Clear processing state
    _isProcessing = false;

    notifyListeners();
  }
}
