import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/local/transfer_database.dart';
import '../../data/models/transfer_models.dart';
import 'background_transfer_service.dart';

/// Protocol message types for chunked transfer
enum TransferProtocol {
  handshakeRequest, // Initiate connection with device info
  handshakeResponse, // Accept/reject connection
  metadata, // Send file metadata
  metadataAck, // Acknowledge metadata (ready to receive)
  chunkRequest, // Request specific chunk (receiver -> sender)
  chunkData, // Send chunk data (metadata only, file via payload)
  chunkAck, // Acknowledge chunk receipt
  verifyRequest, // Request final verification
  verifyResponse, // Send verification result
  pause, // Pause transfer
  resume, // Resume transfer
  cancel, // Cancel transfer
  error, // Error notification
  windowUpdate, // Update send window size
}

/// Sliding window controller for flow control
class SlidingWindow {
  final int windowSize;
  final Set<int> _inFlight = {};
  final Set<int> _acknowledged = {};
  final Map<int, Completer<void>> _pendingAcks = {};

  SlidingWindow({this.windowSize = 5});

  bool get canSend => _inFlight.length < windowSize;
  int get inFlightCount => _inFlight.length;

  Future<void> sendChunk(int chunkIndex) async {
    if (_inFlight.contains(chunkIndex)) {
      throw Exception('Chunk $chunkIndex already in flight');
    }

    _inFlight.add(chunkIndex);
    _pendingAcks[chunkIndex] = Completer<void>();

    // Wait for ACK with timeout
    try {
      await _pendingAcks[chunkIndex]!.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _inFlight.remove(chunkIndex);
          _pendingAcks.remove(chunkIndex);
          throw TimeoutException('Chunk $chunkIndex ACK timeout');
        },
      );
    } catch (e) {
      _inFlight.remove(chunkIndex);
      _pendingAcks.remove(chunkIndex);
      rethrow;
    }
  }

  void acknowledge(int chunkIndex) {
    _inFlight.remove(chunkIndex);
    _acknowledged.add(chunkIndex);
    _pendingAcks[chunkIndex]?.complete();
    _pendingAcks.remove(chunkIndex);
  }

  void reset() {
    for (final completer in _pendingAcks.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Window reset'));
      }
    }
    _inFlight.clear();
    _acknowledged.clear();
    _pendingAcks.clear();
  }
}

/// Timeout exception for transfer operations
class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
  @override
  String toString() => 'TimeoutException: $message';
}

/// Production-ready enhanced file transfer service
class EnhancedTransferService {
  static final EnhancedTransferService _instance =
      EnhancedTransferService._internal();
  factory EnhancedTransferService() => _instance;
  EnhancedTransferService._internal();

  // Dependencies
  final TransferDatabase _database = TransferDatabase();
  final BackgroundTransferService _backgroundService =
      BackgroundTransferService();
  final _uuid = const Uuid();
  final _secureStorage = const FlutterSecureStorage();
  String? _cachedDeviceId; // Cache device ID to avoid repeated storage reads

  // Configuration
  static const int defaultChunkSize =
      1024 * 1024; // 1MB chunks (optimized for WiFi Direct speeds)
  static const int maxRetries = 5;
  static const int defaultWindowSize =
      20; // 20 chunks in-flight (20MB with 1MB chunks)
  static const Duration chunkTimeout = Duration(seconds: 30);
  static const Duration handshakeTimeout = Duration(seconds: 10);
  static const Duration verificationTimeout = Duration(seconds: 60);
  static const Duration connectionRetryDelay = Duration(seconds: 2);
  static const String serviceId = 'com.royaraqamia.almudeer.transfer';

  // File transfer limits
  static const int maxFileSize = 2 * 1024 * 1024 * 1024; // 2GB max file size
  static const List<String> blockedFileExtensions = [
    '.exe', '.bat', '.cmd', '.sh', '.ps1', // Executables
    '.apk', '.xapk', // Android packages (prevent malware)
    '.js', '.vbs', '.jar', // Scripts
    '.msi', '.dmg', // Installers
  ];

  // State
  final Map<String, TransferSession> _activeSessions = {};
  final Map<String, StreamController<TransferSession>> _sessionControllers = {};
  final Map<String, Timer> _sessionTimers = {};
  final Map<String, SlidingWindow> _windows = {};
  final Map<String, Completer<void>> _pendingHandshakes = {};
  final Map<String, Completer<bool>> _pendingVerifications = {};
  final Map<String, RandomAccessFile> _openFiles = {}; // Track open files
  final Map<String, List<int>> _sessionPendingChunkIndices = {};
  final Map<String, Map<int, Uint8List>> _sessionBufferedChunkData = {};
  final Map<String, Map<int, Map<String, dynamic>>>
  _sessionBufferedChunkMetadata = {};
  // Buffer for FILE payloads that arrive before metadata (race condition fix)
  final Map<String, Map<int, Uint8List>> _filePayloadBuffer = {};

  // Progress update batching (reduce database writes)
  final Map<String, int> _pendingProgressUpdates =
      {}; // sessionId -> completedChunks
  final Map<String, Timer> _progressDebounceTimers = {};
  static const int progressUpdateInterval = 10; // Update every 10 chunks
  static const Duration progressDebounceDelay = Duration(milliseconds: 500);

  // Nearby Connections
  final Strategy _strategy = Strategy.P2P_STAR;
  bool _isAdvertising = false;
  bool _isDiscovering = false;
  int? _sdkInt;

  // Callbacks
  void Function(TransferDevice device)? onDeviceDiscovered;
  void Function(TransferDevice device)? onDeviceLost;
  void Function(String sessionId, TransferDevice device)? onTransferRequested;
  void Function(String sessionId)? onTransferCompleted;
  void Function(String sessionId, String error)? onTransferFailed;

  // Streams
  Stream<TransferSession> getSessionStream(String sessionId) {
    _sessionControllers[sessionId] ??=
        StreamController<TransferSession>.broadcast();
    return _sessionControllers[sessionId]!.stream;
  }

  /// Initialize the service
  Future<void> initialize() async {
    await _database.initialize();

    // Initialize SDK version for permission checks
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      _sdkInt = androidInfo.version.sdkInt;
    }

    debugPrint('[EnhancedTransferService] Initialized (API $_sdkInt)');
  }

  // ==================== PERMISSIONS ====================

  Future<List<HardwareRequirement>> getMissingRequirements() async {
    if (!Platform.isAndroid) return [];

    if (_sdkInt == null) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      _sdkInt = androidInfo.version.sdkInt;
    }
    final sdkInt = _sdkInt!;
    final missing = <HardwareRequirement>[];

    // Check Permissions
    if (sdkInt >= 33) {
      if (!await Permission.bluetoothScan.isGranted ||
          !await Permission.bluetoothAdvertise.isGranted ||
          !await Permission.bluetoothConnect.isGranted) {
        missing.add(HardwareRequirement.bluetoothPermission);
      }
      if (!await Permission.nearbyWifiDevices.isGranted) {
        missing.add(HardwareRequirement.nearbyWifiPermission);
      }
    } else if (sdkInt >= 31) {
      if (!await Permission.bluetoothScan.isGranted ||
          !await Permission.bluetoothAdvertise.isGranted ||
          !await Permission.bluetoothConnect.isGranted) {
        missing.add(HardwareRequirement.bluetoothPermission);
      }
      if (!await Permission.location.isGranted) {
        missing.add(HardwareRequirement.locationPermission);
      }
    } else {
      if (!await Permission.bluetooth.isGranted) {
        missing.add(HardwareRequirement.bluetoothPermission);
      }
      if (!await Permission.location.isGranted) {
        missing.add(HardwareRequirement.locationPermission);
      }
    }

    // Check Hardware Services
    if (await Permission.location.serviceStatus.isDisabled) {
      missing.add(HardwareRequirement.locationService);
    }

    // Note: bluetooth service status is harder to check across all versions via permission_handler
    // but Nearby Connections usually fails if it's off.

    return missing;
  }

  Future<void> openHardwareSettings(HardwareRequirement requirement) async {
    if (!Platform.isAndroid) return;

    String action;
    switch (requirement) {
      case HardwareRequirement.locationPermission:
      case HardwareRequirement.bluetoothPermission:
      case HardwareRequirement.nearbyWifiPermission:
        await openAppSettings();
        return;
      case HardwareRequirement.locationService:
        action = 'android.settings.LOCATION_SOURCE_SETTINGS';
        break;
      case HardwareRequirement.bluetoothService:
        action = 'android.settings.BLUETOOTH_SETTINGS';
        break;
    }

    try {
      final intent = AndroidIntent(action: action);
      await intent.launch();
    } catch (e) {
      debugPrint(
        '[EnhancedTransferService] Failed to launch intent $action: $e',
      );
      // Fallback: Open app settings if specific setting fails
      await openAppSettings();
    }
  }

  Future<bool> checkAndRequestPermissions() async {
    // iOS is not supported for Nearby Connections (Android-only feature)
    if (!Platform.isAndroid) {
      debugPrint(
        '[EnhancedTransferService] Nearby sharing is only supported on Android',
      );
      return false;
    }

    if (_sdkInt == null) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      _sdkInt = androidInfo.version.sdkInt;
    }
    final sdkInt = _sdkInt!;

    final permissions = <Permission>[];

    if (sdkInt >= 33) {
      // Android 13+
      permissions.addAll([
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.nearbyWifiDevices,
      ]);
    } else if (sdkInt >= 31) {
      // Android 12
      permissions.addAll([
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.location,
      ]);
    } else {
      // Android 11 and below
      permissions.addAll([Permission.bluetooth, Permission.location]);
    }

    for (final permission in permissions) {
      final status = await permission.status;
      if (!status.isGranted) {
        await permission.request();
      }
    }

    // Auto-enable location service if disabled (mirrors Bluetooth auto-enable)
    if (await Permission.location.serviceStatus.isDisabled) {
      debugPrint(
        '[EnhancedTransferService] Location service disabled, prompting user',
      );
      try {
        final intent = const AndroidIntent(
          action: 'android.settings.LOCATION_SOURCE_SETTINGS',
        );
        await intent.launch();

        // Wait for user to return and enable location (poll up to 30s)
        for (int i = 0; i < 60; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (await Permission.location.serviceStatus.isEnabled) {
            debugPrint(
              '[EnhancedTransferService] Location service enabled by user',
            );
            break;
          }
        }
      } catch (e) {
        debugPrint(
          '[EnhancedTransferService] Failed to open location settings: $e',
        );
      }
    }

    final missing = await getMissingRequirements();
    return missing.isEmpty;
  }

  /// Get specific error message for missing hardware or permissions
  Future<String?> getHardwareErrorMessage() async {
    // iOS not supported
    if (!Platform.isAndroid) {
      return 'المشاركة القريبة مدعومة فقط على أجهزة Android';
    }

    final missing = await getMissingRequirements();
    if (missing.isEmpty) return null;

    final req = missing.first;
    switch (req) {
      case HardwareRequirement.locationPermission:
        return 'يرجى منح إذن الموقع الجغرافي للمتابعة';
      case HardwareRequirement.bluetoothPermission:
        return 'يرجى منح إذن البلوتوث للمتابعة';
      case HardwareRequirement.nearbyWifiPermission:
        return 'يرجى منح إذن الأجهزة القريبة للمتابعة';
      case HardwareRequirement.locationService:
        return 'يرجى تفعيل الموقع الجغرافي (GPS)';
      case HardwareRequirement.bluetoothService:
        return 'يرجى تفعيل البلوتوث';
    }
  }

  // ==================== DEVICE DISCOVERY ====================

  Future<bool> startAdvertising(
    String deviceName, {
    String? deviceModel,
  }) async {
    try {
      if (_isAdvertising) {
        debugPrint('[EnhancedTransferService] Already advertising');
        return true;
      }

      final deviceId = await _getDeviceId();

      final bool success = await Nearby().startAdvertising(
        deviceName,
        _strategy,
        serviceId: serviceId,
        onConnectionInitiated: (endpointId, info) {
          _handleConnectionInitiated(endpointId, info, deviceId, deviceName);
        },
        onConnectionResult: (endpointId, status) {
          _handleConnectionResult(endpointId, status);
        },
        onDisconnected: (endpointId) {
          _handleDisconnected(endpointId);
        },
      );

      if (success) {
        _isAdvertising = true;
        debugPrint(
          '[EnhancedTransferService] Started advertising as: $deviceName',
        );
      }

      return success;
    } catch (e) {
      debugPrint('[EnhancedTransferService] Error starting advertising: $e');
      return false;
    }
  }

  Future<bool> startDiscovery(String deviceName) async {
    try {
      if (_isDiscovering) {
        debugPrint('[EnhancedTransferService] Already discovering');
        return true;
      }

      final bool success = await Nearby().startDiscovery(
        deviceName,
        _strategy,
        serviceId: serviceId,
        onEndpointFound: (endpointId, endpointName, serviceId) {
          _handleEndpointFound(endpointId, endpointName);
        },
        onEndpointLost: (endpointId) {
          if (endpointId != null) {
            _handleEndpointLost(endpointId);
          }
        },
      );

      if (success) {
        _isDiscovering = true;
        debugPrint('[EnhancedTransferService] Started discovery');
      }

      return success;
    } catch (e) {
      debugPrint('[EnhancedTransferService] Error starting discovery: $e');
      return false;
    }
  }

  Future<void> stopAll() async {
    // Cancel all active transfers first
    for (final sessionId in _activeSessions.keys.toList()) {
      await cancelTransfer(sessionId);
    }

    // Close all open files
    for (final file in _openFiles.values) {
      try {
        await file.close();
      } catch (e) {
        debugPrint('[EnhancedTransferService] Error closing file: $e');
      }
    }
    _openFiles.clear();

    // Reset windows
    for (final window in _windows.values) {
      window.reset();
    }
    _windows.clear();

    if (_isAdvertising) {
      await Nearby().stopAdvertising();
      _isAdvertising = false;
    }
    if (_isDiscovering) {
      await Nearby().stopDiscovery();
      _isDiscovering = false;
    }
    await Nearby().stopAllEndpoints();

    debugPrint('[EnhancedTransferService] Stopped all operations');
  }

  // ==================== CONNECTION HANDLERS ====================

  void _handleEndpointFound(String endpointId, String endpointName) {
    final device = TransferDevice(
      deviceId: endpointId,
      deviceName: endpointName,
      endpointId: endpointId,
      discoveredAt: DateTime.now(),
    );

    onDeviceDiscovered?.call(device);
  }

  void _handleEndpointLost(String endpointId) {
    onDeviceLost?.call(
      TransferDevice(
        deviceId: endpointId,
        deviceName: 'Unknown',
        discoveredAt: DateTime.now(),
      ),
    );
  }

  void _handleConnectionInitiated(
    String endpointId,
    ConnectionInfo info,
    String localDeviceId,
    String localDeviceName,
  ) {
    debugPrint(
      '[EnhancedTransferService] Connection initiated from: ${info.endpointName}',
    );

    // Auto-accept for trusted devices, otherwise notify UI
    _database.getDevice(endpointId).then((device) {
      if (device?.isTrusted == true) {
        acceptConnection(endpointId);
      } else {
        onTransferRequested?.call(
          '', // Will be set when metadata received
          TransferDevice(
            deviceId: endpointId,
            deviceName: info.endpointName,
            endpointId: endpointId,
            discoveredAt: DateTime.now(),
          ),
        );
      }
    });
  }

  void _handleConnectionResult(String endpointId, Status status) {
    debugPrint('[EnhancedTransferService] Connection result: $status');

    if (status == Status.CONNECTED) {
      // Connection established - ready for transfers
      debugPrint('[EnhancedTransferService] Connected to: $endpointId');
    } else {
      _handleConnectionFailure(
        endpointId,
        'Connection rejected or failed: $status',
      );
    }
  }

  void _handleDisconnected(String endpointId) {
    debugPrint('[EnhancedTransferService] Disconnected: $endpointId');

    // Find and pause any active sessions on this endpoint
    for (final entry in _activeSessions.entries) {
      if (entry.value.deviceId == endpointId && entry.value.isActive) {
        _pauseSession(entry.key, 'Connection lost');
      }
    }
  }

  void _handleConnectionFailure(String endpointId, String reason) {
    debugPrint('[EnhancedTransferService] Connection failed: $reason');

    for (final entry in _activeSessions.entries) {
      if (entry.value.deviceId == endpointId) {
        _failSession(entry.key, reason);
      }
    }
  }

  // ==================== CONNECTION MANAGEMENT ====================

  Future<bool> acceptConnection(String endpointId) async {
    try {
      return await Nearby().acceptConnection(
        endpointId,
        onPayLoadRecieved: (id, payload) {
          _handlePayloadReceived(id, payload);
        },
        onPayloadTransferUpdate: (id, update) {
          _handlePayloadTransferUpdate(id, update);
        },
      );
    } catch (e) {
      debugPrint('[EnhancedTransferService] Error accepting connection: $e');
      return false;
    }
  }

  Future<bool> requestConnection(String deviceName, String endpointId) async {
    try {
      return await Nearby().requestConnection(
        deviceName,
        endpointId,
        onConnectionInitiated: (id, info) {
          // Already handled by connection callbacks
        },
        onConnectionResult: (id, status) {
          _handleConnectionResult(id, status);
        },
        onDisconnected: (id) {
          _handleDisconnected(id);
        },
      );
    } catch (e) {
      debugPrint('[EnhancedTransferService] Error requesting connection: $e');
      return false;
    }
  }

  // ==================== DISK SPACE CHECK ====================

  Future<bool> _checkDiskSpace(int requiredBytes) async {
    try {
      final directory = await getTemporaryDirectory();

      // We can't easily check free space in vanilla Flutter without a plugin.
      // However, we can attempt to create a file of a reasonable size as a probe
      // if the required size is very large, or just rely on a small write test.
      final testFile = File(
        '${directory.path}/.space_probe_${DateTime.now().millisecondsSinceEpoch}',
      );
      try {
        // Attempt to write 100KB as a basic "is filesystem alive" test
        await testFile.writeAsBytes(Uint8List(100 * 1024));
        await testFile.delete();

        // Note: Real disk full errors will be caught during the actual write process
        // in [_processReceivedChunk].
        return true;
      } catch (e) {
        debugPrint('[EnhancedTransferService] Disk space probe failed: $e');
        return false;
      }
    } catch (e) {
      debugPrint('[EnhancedTransferService] Error checking disk space: $e');
      return false;
    }
  }

  // ==================== TRANSFER OPERATIONS ====================

  Future<TransferSession?> sendFile(
    String endpointId,
    File file, {
    String? customTransferId,
    int chunkSize = defaultChunkSize,
  }) async {
    RandomAccessFile? raf;

    try {
      // Validate file exists and is readable
      if (!await file.exists()) {
        throw Exception('الملف غير موجود: ${file.path}');
      }

      final fileSize = await file.length();
      if (fileSize == 0) {
        throw Exception('لا يمكن نقل ملف فارغ');
      }

      // Validate file size (security: prevent storage exhaustion)
      if (fileSize > maxFileSize) {
        final sizeMB = (fileSize / (1024 * 1024)).toStringAsFixed(1);
        final maxMB = (maxFileSize / (1024 * 1024)).toStringAsFixed(0);
        throw Exception(
          'حجم الملف كبير جداً ($sizeMB MB). الحد الأقصى: $maxMB MB',
        );
      }

      final fileName = file.path.split('/').last;

      // Validate file type (security: prevent malware distribution)
      final fileExtension = '.${fileName.split('.').last.toLowerCase()}';
      if (blockedFileExtensions.contains(fileExtension)) {
        throw Exception('نوع الملف غير مدعوم لأسباب أمنية ($fileExtension)');
      }

      // Calculate file hash (streaming to avoid memory issues)
      final fileHash = await _calculateFileHashStreaming(file);
      final mimeType = _getMimeType(fileName);
      final fileType = _getFileType(mimeType);

      // Create chunks
      final totalChunks = (fileSize / chunkSize).ceil();
      final chunks = List.generate(totalChunks, (index) {
        final startByte = index * chunkSize;
        final endByte = (index + 1) * chunkSize > fileSize
            ? fileSize
            : (index + 1) * chunkSize;
        return FileChunk(index: index, startByte: startByte, endByte: endByte);
      });

      // Create transfer session
      final session = TransferSession(
        sessionId: customTransferId ?? _uuid.v4(),
        deviceId: endpointId,
        deviceName: 'Unknown',
        direction: TransferDirection.sending,
        state: TransferState.pending,
        metadata: TransferMetadata(
          transferId: customTransferId ?? _uuid.v4(),
          fileName: fileName,
          filePath: file.path,
          fileSize: fileSize,
          mimeType: mimeType,
          fileHash: fileHash,
          fileType: fileType,
          totalChunks: totalChunks,
          chunkSize: chunkSize,
          createdAt: DateTime.now(),
        ),
        chunks: chunks,
      );

      // Save to database
      await _database.saveSession(session);
      _activeSessions[session.sessionId] = session;

      // Open file for reading (keep handle for chunked reading)
      raf = await file.open(mode: FileMode.read);
      _openFiles[session.sessionId] = raf;

      // Start transfer with handshake
      await _initiateTransfer(session);

      return session;
    } catch (e) {
      // Cleanup on error
      if (raf != null) {
        await raf.close();
        _openFiles.remove(customTransferId ?? _uuid.v4());
      }
      debugPrint('[EnhancedTransferService] Error creating send session: $e');
      return null;
    }
  }

  Future<void> _initiateTransfer(TransferSession session) async {
    try {
      _updateSessionState(session.sessionId, TransferState.connecting);

      // Create handshake completer
      _pendingHandshakes[session.sessionId] = Completer<void>();

      // Send metadata to receiver
      final metadataMessage = {
        'type': TransferProtocol.metadata.name,
        'sessionId': session.sessionId,
        'metadata': session.metadata.toJson(),
        'windowSize': defaultWindowSize,
      };

      await _sendMessage(session.deviceId, metadataMessage);

      // Wait for acknowledgment with timeout
      try {
        await _pendingHandshakes[session.sessionId]!.future.timeout(
          handshakeTimeout,
          onTimeout: () {
            throw TimeoutException('Handshake timeout');
          },
        );

        // Initialize sliding window
        _windows[session.sessionId] = SlidingWindow(
          windowSize: defaultWindowSize,
        );

        // Start background service to ensure transfer persistence
        await _backgroundService.startService();

        // Start chunked transfer
        await _transferChunksWithFlowControl(session.sessionId);
      } catch (e) {
        await _failSession(session.sessionId, 'Handshake failed: $e');
      } finally {
        _pendingHandshakes.remove(session.sessionId);
      }
    } catch (e) {
      await _failSession(session.sessionId, 'Failed to initiate transfer: $e');
    }
  }

  Future<void> _transferChunksWithFlowControl(String sessionId) async {
    final session = _activeSessions[sessionId];
    if (session == null) return;

    final window = _windows[sessionId];
    if (window == null) {
      await _failSession(sessionId, 'Window not initialized');
      return;
    }

    _updateSessionState(sessionId, TransferState.transferring);
    session.startedAt = DateTime.now();

    final raf = _openFiles[sessionId];
    if (raf == null) {
      await _failSession(sessionId, 'File not open');
      return;
    }

    try {
      int currentChunk = session.completedChunks;

      while (currentChunk < session.metadata.totalChunks) {
        // Check for pause/cancel
        if (session.state == TransferState.paused) {
          debugPrint('[EnhancedTransferService] Transfer paused: $sessionId');
          await _waitForResume(sessionId);
          continue;
        }

        if (session.state == TransferState.cancelled) {
          debugPrint(
            '[EnhancedTransferService] Transfer cancelled: $sessionId',
          );
          break;
        }

        // Wait for window space
        while (!window.canSend && session.isActive) {
          await Future.delayed(const Duration(milliseconds: 10));
        }

        if (!session.isActive) break;

        // Send chunk
        final chunk = session.chunks[currentChunk];

        try {
          // Read chunk data
          final chunkData = Uint8List(chunk.size);
          await raf.setPosition(chunk.startByte);
          final bytesRead = await raf.readInto(chunkData);

          if (bytesRead != chunk.size) {
            throw Exception('Failed to read chunk $currentChunk');
          }

          // Calculate chunk checksum
          final chunkHash = sha256.convert(chunkData).toString();

          // Send chunk metadata (actual data sent as separate payload)
          final chunkMessage = {
            'type': TransferProtocol.chunkData.name,
            'sessionId': sessionId,
            'chunkIndex': currentChunk,
            'checksum': chunkHash,
            'size': chunk.size,
          };

          // Send metadata via bytes payload
          await _sendMessage(session.deviceId, chunkMessage);

          // Send actual chunk data via bytes payload for reliability (avoids temp file race conditions)
          await Nearby().sendBytesPayload(session.deviceId, chunkData);

          // Wait for ACK (handled by sliding window)
          await window.sendChunk(currentChunk);

          // Update progress
          session.completedChunks = currentChunk + 1;
          session.updateStats(
            chunk.size,
            DateTime.now().difference(session.startedAt!),
          );
          _notifySessionUpdate(session);

          currentChunk++;
        } catch (e) {
          debugPrint(
            '[EnhancedTransferService] Error sending chunk $currentChunk: $e',
          );
          session.failedChunks++;

          // Retry logic
          if (session.failedChunks < maxRetries) {
            debugPrint(
              '[EnhancedTransferService] Retrying chunk $currentChunk',
            );
            await Future.delayed(Duration(seconds: session.failedChunks));
            continue; // Retry same chunk
          } else {
            throw Exception('Max retries exceeded for chunk $currentChunk');
          }
        }
      }

      // All chunks sent - request verification
      if (session.state == TransferState.transferring) {
        await _requestVerification(sessionId);
      }
    } catch (e) {
      await _failSession(sessionId, 'Transfer failed: $e');
    } finally {
      // Cleanup is now handled centrally by _cleanupSession called inside _failSession/_completeSession
      await _cleanupSession(sessionId);
    }
  }

  Future<void> _waitForResume(String sessionId) async {
    final session = _activeSessions[sessionId];
    if (session == null) return;

    // Wait for state change
    while (session.state == TransferState.paused) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _requestVerification(String sessionId) async {
    final session = _activeSessions[sessionId];
    if (session == null) return;

    _pendingVerifications[sessionId] = Completer<bool>();

    final verifyMessage = {
      'type': TransferProtocol.verifyRequest.name,
      'sessionId': sessionId,
      'fileHash': session.metadata.fileHash,
    };

    await _sendMessage(session.deviceId, verifyMessage);

    try {
      final isValid = await _pendingVerifications[sessionId]!.future.timeout(
        verificationTimeout,
        onTimeout: () {
          throw TimeoutException('Verification timeout');
        },
      );

      if (isValid) {
        await _completeSession(sessionId);
      } else {
        await _failSession(
          sessionId,
          'File verification failed - hash mismatch',
        );
      }
    } catch (e) {
      await _failSession(sessionId, 'Verification failed: $e');
    } finally {
      _pendingVerifications.remove(sessionId);
    }
  }

  // ==================== MESSAGE HANDLING ====================

  void _handlePayloadReceived(String endpointId, Payload payload) async {
    try {
      if (payload.type == PayloadType.BYTES) {
        final bytes = payload.bytes!;
        try {
          // Attempt to parse as JSON protocol message first
          final content = utf8.decode(bytes);
          if (content.startsWith('{')) {
            final data = jsonDecode(content);
            _handleProtocolMessage(endpointId, data);
            return;
          }
        } catch (_) {
          // Not a JSON message, treat as raw chunk data
        }

        // Handle as raw chunk bytes
        await _handleIncomingChunkBytes(endpointId, bytes);
      } else if (payload.type == PayloadType.FILE) {
        // FILE payloads can arrive before or after metadata
        // We need to buffer them until metadata arrives
        final path = payload.uri != null
            ? Uri.parse(payload.uri!).toFilePath()
            : null;
        if (path != null) {
          final file = File(path);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();

            // Try to parse as chunk data with index prefix
            if (bytes.length >= 4) {
              final byteData = bytes.buffer.asByteData(bytes.offsetInBytes, 4);
              final chunkIndex = byteData.getInt32(0);
              final chunkData = bytes.sublist(4);

              // Find session to get session ID
              try {
                final session = _activeSessions.values.firstWhere(
                  (s) =>
                      s.deviceId == endpointId &&
                      s.direction == TransferDirection.receiving,
                );

                // Buffer the file payload by session ID and chunk index
                _filePayloadBuffer.putIfAbsent(
                  session.sessionId,
                  () => {},
                )[chunkIndex] = chunkData;

                // Check if metadata is already here
                final metadata =
                    _sessionBufferedChunkMetadata[session
                        .sessionId]?[chunkIndex];
                if (metadata != null) {
                  // Metadata already here, process immediately
                  await _processReceivedChunk(
                    session.sessionId,
                    chunkIndex,
                    metadata['checksum'] as String,
                    metadata['size'] as int,
                  );
                } else {
                  // Metadata not here yet, will be processed when it arrives
                  debugPrint(
                    '[EnhancedTransferService] Buffered FILE payload for chunk $chunkIndex',
                  );
                }
              } catch (_) {
                // No session found yet, buffer by endpoint ID
                _filePayloadBuffer.putIfAbsent(endpointId, () => {})[0] = bytes;
              }
            } else {
              // Legacy FILE payload without index prefix
              await _handleIncomingChunkBytes(
                endpointId,
                bytes,
                isLegacy: true,
              );
            }

            // Cleanup temporary file
            try {
              await file.delete();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('[EnhancedTransferService] Error handling payload: $e');
    }
  }

  void _handlePayloadTransferUpdate(
    String endpointId,
    PayloadTransferUpdate update,
  ) {
    // Track transfer progress for debugging
    if (update.status == PayloadStatus.IN_PROGRESS) {
      final progress = update.totalBytes > 0
          ? update.bytesTransferred / update.totalBytes
          : 0.0;
      debugPrint(
        '[EnhancedTransferService] Transfer progress: ${(progress * 100).toStringAsFixed(1)}%',
      );
    }
  }

  Future<void> _handleIncomingChunkBytes(
    String endpointId,
    Uint8List payload, {
    bool isLegacy = false,
  }) async {
    // Find session for this endpoint
    final session = _activeSessions.values.firstWhere(
      (s) =>
          s.deviceId == endpointId &&
          s.direction == TransferDirection.receiving,
      orElse: () => throw Exception('No receiving session found for endpoint'),
    );

    int chunkIndex;
    Uint8List chunkData;

    if (!isLegacy && payload.length >= 4) {
      // New protocol: Read chunk index from prefix (4-byte int32)
      final byteData = payload.buffer.asByteData(payload.offsetInBytes, 4);
      chunkIndex = byteData.getInt32(0);
      chunkData = payload.sublist(4);
    } else {
      // Legacy protocol: Match with the next pending chunk index from the queue
      final pendingIndices = _sessionPendingChunkIndices[session.sessionId];
      if (pendingIndices != null && pendingIndices.isNotEmpty) {
        chunkIndex = pendingIndices.removeAt(0);
        chunkData = payload;
      } else {
        debugPrint(
          '[EnhancedTransferService] Received legacy chunk data but no pending indices for session ${session.sessionId}',
        );
        return;
      }
    }

    // Store temporarily for matching with metadata if it hasn't arrived yet
    _sessionBufferedChunkData.putIfAbsent(
      session.sessionId,
      () => {},
    )[chunkIndex] = chunkData;

    // Check if metadata is already here
    final metadata =
        _sessionBufferedChunkMetadata[session.sessionId]?[chunkIndex];
    if (metadata != null) {
      await _processReceivedChunk(
        session.sessionId,
        chunkIndex,
        metadata['checksum'] as String,
        metadata['size'] as int,
      );
    } else {
      // Also check file payload buffer (for race condition where FILE arrived first)
      final filePayload = _filePayloadBuffer[session.sessionId]?[chunkIndex];
      if (filePayload != null) {
        // Use the buffered file payload instead
        _sessionBufferedChunkData[session.sessionId]![chunkIndex] = filePayload;
        _filePayloadBuffer[session.sessionId]?.remove(chunkIndex);
        debugPrint(
          '[EnhancedTransferService] Using buffered FILE payload for chunk $chunkIndex',
        );
      }
    }
  }

  Future<void> _processReceivedChunk(
    String sessionId,
    int chunkIndex,
    String expectedChecksum,
    int expectedSize,
  ) async {
    final session = _activeSessions[sessionId];
    if (session == null) return;

    final data = _sessionBufferedChunkData[sessionId]?.remove(chunkIndex);
    if (data == null) return;

    // Clean up metadata buffer
    _sessionBufferedChunkMetadata[sessionId]?.remove(chunkIndex);

    // Clean up pending chunk indices buffer (memory leak fix)
    _sessionPendingChunkIndices[sessionId]?.remove(chunkIndex);

    try {
      // 1. Verify size
      if (data.length != expectedSize) {
        throw Exception(
          'Chunk $chunkIndex size mismatch: expected $expectedSize, got ${data.length}',
        );
      }

      // 2. Verify checksum
      final actualChecksum = sha256.convert(data).toString();
      if (actualChecksum != expectedChecksum) {
        throw Exception(
          'Chunk $chunkIndex checksum mismatch: expected $expectedChecksum, got $actualChecksum',
        );
      }

      // 3. Write to file
      final raf = _openFiles[sessionId];
      if (raf == null) {
        throw Exception('File not open for session $sessionId');
      }

      final chunk = session.chunks[chunkIndex];
      await raf.setPosition(chunk.startByte);
      await raf.writeFrom(data);

      // 4. Mark as received
      session.chunks[chunkIndex] = FileChunk(
        index: chunk.index,
        startByte: chunk.startByte,
        endByte: chunk.endByte,
        isReceived: true,
        receivedAt: DateTime.now(),
        checksum: actualChecksum,
      );

      // 5. Update progress
      session.completedChunks++;
      session.updateStats(
        data.length,
        DateTime.now().difference(session.startedAt!),
      );
      _notifySessionUpdate(session);

      // Batch database updates to reduce I/O overhead (performance fix)
      await _scheduleProgressUpdate(
        sessionId,
        session.completedChunks,
        session.bytesTransferred,
      );
      await _database.markChunkReceived(sessionId, chunkIndex);

      // 6. Send ACK
      final ackMessage = {
        'type': TransferProtocol.chunkAck.name,
        'sessionId': sessionId,
        'chunkIndex': chunkIndex,
      };
      await _sendMessage(session.deviceId, ackMessage);
    } catch (e) {
      debugPrint(
        '[EnhancedTransferService] Error processing chunk $chunkIndex: $e',
      );
      session.failedChunks++;

      // Send NACK/Error
      final nackMessage = {
        'type': TransferProtocol.error.name,
        'sessionId': sessionId,
        'chunkIndex': chunkIndex,
        'error': e.toString(),
      };
      await _sendMessage(session.deviceId, nackMessage);
    }
  }

  Future<void> _handleProtocolMessage(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    final type = message['type'] as String?;
    if (type == null) return;

    final protocol = TransferProtocol.values.firstWhere(
      (p) => p.name == type,
      orElse: () {
        debugPrint('[EnhancedTransferService] Unknown protocol type: $type');
        throw Exception('Unknown protocol type: $type');
      },
    );

    switch (protocol) {
      case TransferProtocol.metadata:
        await _handleMetadataMessage(endpointId, message);
        break;
      case TransferProtocol.metadataAck:
        await _handleMetadataAck(message);
        break;
      case TransferProtocol.chunkRequest:
        await _handleChunkRequest(message);
        break;
      case TransferProtocol.chunkData:
        await _handleChunkData(endpointId, message);
        break;
      case TransferProtocol.chunkAck:
        await _handleChunkAck(message);
        break;
      case TransferProtocol.verifyRequest:
        await _handleVerifyRequest(endpointId, message);
        break;
      case TransferProtocol.verifyResponse:
        await _handleVerifyResponse(message);
        break;
      case TransferProtocol.pause:
        await _handlePause(message);
        break;
      case TransferProtocol.resume:
        await _handleResume(message);
        break;
      case TransferProtocol.cancel:
        await _handleCancel(message);
        break;
      case TransferProtocol.error:
        await _handleError(message);
        break;
      case TransferProtocol.windowUpdate:
        await _handleWindowUpdate(message);
        break;
      default:
        debugPrint('[EnhancedTransferService] Unhandled protocol: $type');
    }
  }

  Future<void> _handleMetadataMessage(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    final sessionId = message['sessionId'] as String;
    final metadataJson = message['metadata'] as Map<String, dynamic>;
    final windowSize = message['windowSize'] as int? ?? defaultWindowSize;
    final metadata = TransferMetadata.fromJson(metadataJson);

    // Check disk space
    final hasSpace = await _checkDiskSpace(metadata.fileSize);
    if (!hasSpace) {
      // Send rejection
      final rejectMessage = {
        'type': TransferProtocol.metadataAck.name,
        'sessionId': sessionId,
        'accepted': false,
        'reason': 'Insufficient disk space',
      };
      await _sendMessage(endpointId, rejectMessage);
      return;
    }

    // Generate unique file path to avoid conflicts
    final downloadsDir = await _getDownloadsDirectory();
    var filePath = '${downloadsDir.path}/${metadata.fileName}';

    // Handle file name conflicts
    final originalPath = filePath;
    int counter = 1;
    while (await File(filePath).exists()) {
      final extIndex = originalPath.lastIndexOf('.');
      if (extIndex > 0) {
        filePath =
            '${originalPath.substring(0, extIndex)}_($counter)${originalPath.substring(extIndex)}';
      } else {
        filePath = '${originalPath}_($counter)';
      }
      counter++;
    }

    // Create receiving session
    final chunks = List.generate(metadata.totalChunks, (index) {
      final startByte = index * metadata.chunkSize;
      final endByte = (index + 1) * metadata.chunkSize > metadata.fileSize
          ? metadata.fileSize
          : (index + 1) * metadata.chunkSize;
      return FileChunk(index: index, startByte: startByte, endByte: endByte);
    });

    final session = TransferSession(
      sessionId: sessionId,
      deviceId: endpointId,
      deviceName: 'Sender',
      direction: TransferDirection.receiving,
      state: TransferState.transferring,
      metadata: TransferMetadata(
        transferId: metadata.transferId,
        fileName: metadata.fileName,
        filePath: filePath,
        fileSize: metadata.fileSize,
        mimeType: metadata.mimeType,
        fileHash: metadata.fileHash,
        fileType: metadata.fileType,
        totalChunks: metadata.totalChunks,
        chunkSize: metadata.chunkSize,
        createdAt: metadata.createdAt,
      ),
      chunks: chunks,
      startedAt: DateTime.now(),
    );

    await _database.saveSession(session);
    _activeSessions[sessionId] = session;

    // Initialize window for flow control
    _windows[sessionId] = SlidingWindow(windowSize: windowSize);

    // Start background service to ensure transfer persistence
    await _backgroundService.startService();

    // Create file for writing
    final file = File(filePath);
    await file.create(recursive: true);
    _openFiles[sessionId] = await file.open(mode: FileMode.write);

    // Send acknowledgment
    final ackMessage = {
      'type': TransferProtocol.metadataAck.name,
      'sessionId': sessionId,
      'accepted': true,
    };
    await _sendMessage(endpointId, ackMessage);

    _notifySessionUpdate(session);
  }

  Future<void> _handleMetadataAck(Map<String, dynamic> message) async {
    final sessionId = message['sessionId'] as String;
    final accepted = message['accepted'] as bool? ?? false;
    final reason = message['reason'] as String?;

    final completer = _pendingHandshakes[sessionId];
    if (completer != null && !completer.isCompleted) {
      if (accepted) {
        completer.complete();
      } else {
        completer.completeError(Exception(reason ?? 'Transfer rejected'));
      }
    }
  }

  Future<void> _handleChunkData(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    final sessionId = message['sessionId'] as String;
    final chunkIndex = message['chunkIndex'] as int;
    final checksum = message['checksum'] as String;
    final size = message['size'] as int;

    final session = _activeSessions[sessionId];
    if (session == null) return;

    try {
      // Store metadata and track pending data payload
      _sessionBufferedChunkMetadata.putIfAbsent(
        sessionId,
        () => {},
      )[chunkIndex] = {
        'checksum': checksum,
        'size': size,
      };

      _sessionPendingChunkIndices
          .putIfAbsent(sessionId, () => [])
          .add(chunkIndex);

      // Check if data is already here (from BYTES payload)
      if (_sessionBufferedChunkData[sessionId]?.containsKey(chunkIndex) ==
          true) {
        await _processReceivedChunk(sessionId, chunkIndex, checksum, size);
      } else {
        // Check if FILE payload arrived first (race condition fix)
        final filePayload = _filePayloadBuffer[sessionId]?[chunkIndex];
        if (filePayload != null) {
          debugPrint(
            '[EnhancedTransferService] FILE payload arrived first for chunk $chunkIndex',
          );
          // Use the buffered FILE payload
          _sessionBufferedChunkData.putIfAbsent(
            sessionId,
            () => {},
          )[chunkIndex] = filePayload;
          _filePayloadBuffer[sessionId]?.remove(chunkIndex);
          await _processReceivedChunk(sessionId, chunkIndex, checksum, size);
        } else {
          // Data not here yet, Nearby Connections will deliver it via FILE payload
          debugPrint(
            '[EnhancedTransferService] Waiting for chunk $chunkIndex data payload',
          );
        }
      }
    } catch (e) {
      debugPrint('[EnhancedTransferService] Error handling chunk metadata: $e');
      session.failedChunks++;

      // Send NACK
      final nackMessage = {
        'type': TransferProtocol.error.name,
        'sessionId': sessionId,
        'chunkIndex': chunkIndex,
        'error': e.toString(),
      };
      await _sendMessage(endpointId, nackMessage);
    }
  }

  Future<void> _handleChunkRequest(Map<String, dynamic> message) async {
    final sessionId = message['sessionId'] as String;
    final chunkIndex = message['chunkIndex'] as int;

    final session = _activeSessions[sessionId];
    if (session == null || session.direction != TransferDirection.sending) {
      return;
    }

    final raf = _openFiles[sessionId];
    if (raf == null) {
      debugPrint(
        '[EnhancedTransferService] File not open for session $sessionId',
      );
      return;
    }

    try {
      final chunk = session.chunks[chunkIndex];
      final chunkData = Uint8List(chunk.size);

      await raf.setPosition(chunk.startByte);
      final bytesRead = await raf.readInto(chunkData);

      if (bytesRead != chunk.size) {
        throw Exception('Failed to read chunk $chunkIndex');
      }

      // Prefix with chunk index for reliable matching on receiver side
      // use 4-byte big endian int32
      final payload = Uint8List(4 + chunkData.length);
      final byteData = ByteData.view(payload.buffer);
      byteData.setInt32(0, chunkIndex);
      payload.setRange(4, payload.length, chunkData);

      // Send chunk data via bytes payload for reliability
      await Nearby().sendBytesPayload(session.deviceId, payload);
    } catch (e) {
      debugPrint('[EnhancedTransferService] Error handling chunk request: $e');
    }
  }

  Future<void> _handleChunkAck(Map<String, dynamic> message) async {
    final sessionId = message['sessionId'] as String;
    final chunkIndex = message['chunkIndex'] as int;

    final window = _windows[sessionId];
    if (window != null) {
      window.acknowledge(chunkIndex);

      final session = _activeSessions[sessionId];
      if (session != null) {
        // Batch database updates to reduce I/O overhead (performance fix)
        await _scheduleProgressUpdate(
          sessionId,
          session.completedChunks,
          session.bytesTransferred,
        );
        await _database.markChunkReceived(sessionId, chunkIndex);
      }
    }
  }

  Future<void> _handleVerifyRequest(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    final sessionId = message['sessionId'] as String;
    final expectedHash = message['fileHash'] as String;

    final session = _activeSessions[sessionId];
    if (session == null) return;

    try {
      // Calculate actual file hash
      final file = File(session.metadata.filePath!);
      final actualHash = await _calculateFileHashStreaming(file);

      final isValid = actualHash == expectedHash;

      // Send response
      final responseMessage = {
        'type': TransferProtocol.verifyResponse.name,
        'sessionId': sessionId,
        'valid': isValid,
      };
      await _sendMessage(endpointId, responseMessage);

      if (isValid) {
        await _completeSession(sessionId);
      } else {
        await _failSession(
          sessionId,
          'File verification failed - hash mismatch',
        );
      }
    } catch (e) {
      debugPrint('[EnhancedTransferService] Verification error: $e');

      final responseMessage = {
        'type': TransferProtocol.verifyResponse.name,
        'sessionId': sessionId,
        'valid': false,
      };
      await _sendMessage(endpointId, responseMessage);

      await _failSession(sessionId, 'Verification failed: $e');
    }
  }

  Future<void> _handleVerifyResponse(Map<String, dynamic> message) async {
    final sessionId = message['sessionId'] as String;
    final isValid = message['valid'] as bool? ?? false;

    final completer = _pendingVerifications[sessionId];
    if (completer != null && !completer.isCompleted) {
      completer.complete(isValid);
    }
  }

  Future<void> _handlePause(Map<String, dynamic> message) async {
    final sessionId = message['sessionId'] as String;
    await _pauseSession(sessionId, 'Paused by peer');
  }

  Future<void> _handleResume(Map<String, dynamic> message) async {
    final sessionId = message['sessionId'] as String;
    final session = _activeSessions[sessionId];

    if (session != null && session.state == TransferState.paused) {
      _updateSessionState(sessionId, TransferState.transferring);
    }
  }

  Future<void> _handleCancel(Map<String, dynamic> message) async {
    final sessionId = message['sessionId'] as String;
    await _cancelSession(sessionId);
  }

  Future<void> _handleError(Map<String, dynamic> message) async {
    final sessionId = message['sessionId'] as String;
    final error = message['error'] as String? ?? 'Unknown error';
    final chunkIndex = message['chunkIndex'] as int?;

    debugPrint(
      '[EnhancedTransferService] Received error for session $sessionId: $error',
    );

    if (chunkIndex != null) {
      // Specific chunk error - will be retried
      debugPrint('[EnhancedTransferService] Chunk $chunkIndex error: $error');
    } else {
      // Session error
      await _failSession(sessionId, error);
    }
  }

  Future<void> _handleWindowUpdate(Map<String, dynamic> message) async {
    // Future: Handle dynamic window size adjustment
    debugPrint('[EnhancedTransferService] Window update received');
  }

  // ==================== SESSION MANAGEMENT ====================

  Future<void> pauseTransfer(String sessionId) async {
    final session = _activeSessions[sessionId];
    if (session == null) return;

    _updateSessionState(sessionId, TransferState.paused);

    // Notify peer
    final message = {
      'type': TransferProtocol.pause.name,
      'sessionId': sessionId,
    };
    await _sendMessage(session.deviceId, message);
  }

  Future<void> resumeTransfer(String sessionId) async {
    TransferSession? session = _activeSessions[sessionId];

    // 1. Reload from database if not in memory (app restart case)
    if (session == null) {
      session = await _database.getSession(sessionId);
      if (session != null && session.canResume) {
        _activeSessions[sessionId] = session;
      }
    }

    if (session == null) {
      debugPrint(
        '[EnhancedTransferService] Session $sessionId not found for resume',
      );
      return;
    }

    if (!session.canResume) {
      debugPrint('[EnhancedTransferService] Cannot resume session $sessionId');
      return;
    }

    _updateSessionState(sessionId, TransferState.transferring);
    session.retryCount++;

    // 2. Ensure file handle is open (app restart case)
    if (session.direction == TransferDirection.sending &&
        !_openFiles.containsKey(sessionId)) {
      final file = File(session.metadata.filePath!);
      if (await file.exists()) {
        _openFiles[sessionId] = await file.open(mode: FileMode.read);
      } else {
        await _failSession(sessionId, 'الملف الأصلي لم يعد موجوداً');
        return;
      }
    } else if (session.direction == TransferDirection.receiving &&
        !_openFiles.containsKey(sessionId)) {
      final file = File(session.metadata.filePath!);
      // Use FileMode.write instead of append to ensure setPosition works reliably
      // on all platforms for resuming at specific offsets.
      _openFiles[sessionId] = await file.open(mode: FileMode.write);
    }

    // Notify peer
    final message = {
      'type': TransferProtocol.resume.name,
      'sessionId': sessionId,
    };
    await _sendMessage(session.deviceId, message);

    // Resume from last successful chunk
    if (session.direction == TransferDirection.sending) {
      // Re-initialize window and continue
      _windows[sessionId] = SlidingWindow(windowSize: defaultWindowSize);
      await _transferChunksWithFlowControl(sessionId);
    }
  }

  Future<void> cancelTransfer(String sessionId) async {
    await _cancelSession(sessionId);
  }

  Future<void> _cancelSession(String sessionId) async {
    final session = _activeSessions[sessionId];
    if (session == null) return;

    _updateSessionState(sessionId, TransferState.cancelled);

    // Notify peer
    final message = {
      'type': TransferProtocol.cancel.name,
      'sessionId': sessionId,
    };
    await _sendMessage(session.deviceId, message);

    // Cleanup
    await _cleanupSession(sessionId);
  }

  Future<void> _cleanupSession(String sessionId) async {
    // Close file handles
    final raf = _openFiles.remove(sessionId);
    if (raf != null) {
      try {
        await raf.close();
      } catch (e) {
        debugPrint('[EnhancedTransferService] Error closing file: $e');
      }
    }

    // Reset window
    final window = _windows.remove(sessionId);
    window?.reset();

    // Close stream controller
    _sessionControllers[sessionId]?.close();
    _sessionControllers.remove(sessionId);

    // Cancel timers
    _sessionTimers[sessionId]?.cancel();
    _sessionTimers.remove(sessionId);

    // Clear memory buffers to prevent leaks
    _sessionPendingChunkIndices.remove(sessionId);
    _sessionBufferedChunkData.remove(sessionId);
    _sessionBufferedChunkMetadata.remove(sessionId);
    _filePayloadBuffer.remove(
      sessionId,
    ); // Clear file payload buffer (memory leak fix)

    // Remove from active sessions
    _activeSessions.remove(sessionId);

    // Stop background service if no more active transfers
    if (_activeSessions.isEmpty) {
      await _backgroundService.stopService();
    }
  }

  Future<void> resumeInterruptedTransfers() async {
    final sessions = await _database.getResumableSessions();

    for (final session in sessions) {
      // Only auto-resume if within reasonable time (e.g., 24 hours)
      if (session.lastActivityAt != null) {
        final elapsed = DateTime.now().difference(session.lastActivityAt!);
        if (elapsed.inHours < 24) {
          _activeSessions[session.sessionId] = session;
          // Don't auto-start, just make available for manual resume
        }
      }
    }
  }

  // ==================== HELPER METHODS ====================

  Future<void> _sendMessage(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    try {
      // Compress message to reduce bandwidth (especially for large metadata)
      final jsonBytes = utf8.encode(jsonEncode(message));
      final compressed = _compressBytes(jsonBytes);

      // Encrypt for end-to-end security (placeholder - see _encryptData)
      // In production, enable this after proper key exchange:
      // final secret = await _generateSharedSecret(endpointId);
      // final encrypted = _encryptData(compressed, secret);
      // await Nearby().sendBytesPayload(endpointId, encrypted);

      // For now, send without encryption (WiFi Direct has WPA2 encryption)
      await Nearby().sendBytesPayload(endpointId, compressed);
    } catch (e) {
      debugPrint('[EnhancedTransferService] Error sending message: $e');
      throw Exception('Failed to send message: $e');
    }
  }

  /// Compress bytes using a simple RLE-like compression for repetitive data
  /// For production, consider using gzip package
  Uint8List _compressBytes(Uint8List input) {
    // For now, just return input (gzip compression can be added later)
    // This is a placeholder for future compression implementation
    return input;
  }

  /// Schedule a progress update with debouncing to reduce database writes
  Future<void> _scheduleProgressUpdate(
    String sessionId,
    int completedChunks,
    int bytesTransferred,
  ) async {
    // Cancel existing timer
    _progressDebounceTimers[sessionId]?.cancel();

    // Track pending update
    _pendingProgressUpdates[sessionId] = completedChunks;

    // Schedule debounced update
    _progressDebounceTimers[sessionId] = Timer(progressDebounceDelay, () async {
      final pendingChunks = _pendingProgressUpdates.remove(sessionId);
      if (pendingChunks != null) {
        final session = _activeSessions[sessionId];
        if (session != null) {
          try {
            await _database.updateSessionProgress(
              sessionId,
              pendingChunks,
              session.bytesTransferred,
            );
          } catch (e) {
            debugPrint('[EnhancedTransferService] Error updating progress: $e');
          }
        }
      }
      _progressDebounceTimers.remove(sessionId);
    });

    // Force update every N chunks regardless of debounce
    if (completedChunks % progressUpdateInterval == 0) {
      _progressDebounceTimers[sessionId]?.cancel();
      final pendingChunks = _pendingProgressUpdates.remove(sessionId);
      if (pendingChunks != null && _activeSessions.containsKey(sessionId)) {
        try {
          await _database.updateSessionProgress(
            sessionId,
            pendingChunks,
            _activeSessions[sessionId]!.bytesTransferred,
          );
        } catch (e) {
          debugPrint('[EnhancedTransferService] Error updating progress: $e');
        }
      }
      _progressDebounceTimers.remove(sessionId);
    }
  }

  /// Flush all pending progress updates (called on session completion/failure)
  Future<void> _flushProgressUpdate(String sessionId) async {
    _progressDebounceTimers[sessionId]?.cancel();
    _progressDebounceTimers.remove(sessionId);

    final pendingChunks = _pendingProgressUpdates.remove(sessionId);
    if (pendingChunks != null) {
      final session = _activeSessions[sessionId];
      if (session != null) {
        try {
          await _database.updateSessionProgress(
            sessionId,
            pendingChunks,
            session.bytesTransferred,
          );
        } catch (e) {
          debugPrint('[EnhancedTransferService] Error flushing progress: $e');
        }
      }
    }
  }

  void _updateSessionState(String sessionId, TransferState state) {
    final session = _activeSessions[sessionId];
    if (session == null) return;

    session.state = state;
    session.lastActivityAt = DateTime.now();

    _database.updateSessionState(sessionId, state);
    _notifySessionUpdate(session);
  }

  Future<void> _completeSession(String sessionId) async {
    final session = _activeSessions[sessionId];
    if (session == null) return;

    session.state = TransferState.completed;
    session.completedAt = DateTime.now();

    // Flush any pending progress updates before completing
    await _flushProgressUpdate(sessionId);

    await _database.updateSessionState(sessionId, TransferState.completed);
    await _database.addToHistory(session);

    // Cleanup
    await _cleanupSession(sessionId);

    _notifySessionUpdate(session);
    onTransferCompleted?.call(sessionId);
  }

  Future<void> _failSession(String sessionId, String error) async {
    final session = _activeSessions[sessionId];
    if (session == null) return;

    session.state = TransferState.failed;
    session.errorMessage = error;

    // Flush any pending progress updates before failing
    await _flushProgressUpdate(sessionId);

    await _database.updateSessionState(
      sessionId,
      TransferState.failed,
      errorMessage: error,
    );

    // Cleanup
    await _cleanupSession(sessionId);

    _notifySessionUpdate(session);
    onTransferFailed?.call(sessionId, error);
  }

  Future<void> _pauseSession(String sessionId, String reason) async {
    final session = _activeSessions[sessionId];
    if (session == null || !session.isActive) return;

    session.state = TransferState.paused;
    await _database.updateSessionState(sessionId, TransferState.paused);
    _notifySessionUpdate(session);
  }

  void _notifySessionUpdate(TransferSession session) {
    if (_sessionControllers[session.sessionId]?.isClosed == false) {
      _sessionControllers[session.sessionId]?.add(session);
    }

    // Update background service progress
    if (_backgroundService.isRunning) {
      final progress = session.metadata.totalChunks > 0
          ? (session.completedChunks * 100 ~/ session.metadata.totalChunks)
          : 0;
      _backgroundService.updateProgress(
        progress,
        title: session.direction == TransferDirection.sending
            ? 'جاري الإرسال: ${session.metadata.fileName}'
            : 'جاري الاستلام: ${session.metadata.fileName}',
        body: '$progress% مكتمل',
      );
    }
  }

  Future<String> _calculateFileHashStreaming(File file) async {
    final stream = file.openRead();
    final hash = await sha256.bind(stream).first;
    return hash.toString();
  }

  String _getMimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    final mimeTypes = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'mp4': 'video/mp4',
      'mp3': 'audio/mpeg',
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'zip': 'application/zip',
    };
    return mimeTypes[ext] ?? 'application/octet-stream';
  }

  TransferFileType _getFileType(String mimeType) {
    if (mimeType.startsWith('image/')) return TransferFileType.image;
    if (mimeType.startsWith('video/')) return TransferFileType.video;
    if (mimeType.startsWith('audio/')) return TransferFileType.audio;
    if (mimeType.contains('pdf') ||
        mimeType.contains('word') ||
        mimeType.contains('excel') ||
        mimeType.contains('powerpoint')) {
      return TransferFileType.document;
    }
    if (mimeType.contains('zip') ||
        mimeType.contains('rar') ||
        mimeType.contains('7z')) {
      return TransferFileType.archive;
    }
    if (mimeType.contains('android')) return TransferFileType.application;
    return TransferFileType.other;
  }

  Future<String> _getDeviceId() async {
    // Return cached device ID if available
    if (_cachedDeviceId != null) {
      return _cachedDeviceId!;
    }

    // Try to load from secure storage
    try {
      String? deviceId = await _secureStorage.read(key: 'device_id');

      if (deviceId == null || deviceId.isEmpty) {
        // Generate new device ID
        deviceId = _uuid.v4();
        await _secureStorage.write(key: 'device_id', value: deviceId);
      }

      _cachedDeviceId = deviceId;
      return deviceId;
    } catch (e) {
      debugPrint(
        '[EnhancedTransferService] Error accessing secure storage: $e',
      );
      // Fallback to in-memory generation (not ideal but prevents crash)
      final deviceId = _uuid.v4();
      _cachedDeviceId = deviceId;
      return deviceId;
    }
  }

  Future<Directory> _getDownloadsDirectory() async {
    if (Platform.isAndroid) {
      // Try to get Downloads directory
      final downloads = Directory('/storage/emulated/0/Download');
      if (await downloads.exists()) {
        return downloads;
      }
    }
    // Fallback to app documents
    return await getApplicationDocumentsDirectory();
  }
}
