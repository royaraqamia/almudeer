import 'dart:typed_data';

/// Represents a hardware or permission requirement for transfer
enum HardwareRequirement {
  locationPermission,
  nearbyWifiPermission, // Android 13+
  bluetoothPermission,
  locationService,
  bluetoothService,
}

/// Represents the state of a file transfer
enum TransferState {
  pending, // Waiting to start
  connecting, // Establishing connection
  transferring, // Actively transferring
  paused, // Temporarily paused (can resume)
  completed, // Successfully completed
  failed, // Failed with error
  cancelled, // Cancelled by user
}

/// Direction of transfer
enum TransferDirection { sending, receiving }

/// Type of file being transferred
enum TransferFileType {
  image,
  video,
  audio,
  document,
  application,
  archive,
  other,
}

/// Represents a single chunk of a file
class FileChunk {
  final int index;
  final int startByte;
  final int endByte;
  final Uint8List? data;
  final String? checksum;
  final bool isReceived;
  final DateTime? receivedAt;

  FileChunk({
    required this.index,
    required this.startByte,
    required this.endByte,
    this.data,
    this.checksum,
    this.isReceived = false,
    this.receivedAt,
  });

  int get size => endByte - startByte;

  Map<String, dynamic> toJson() => {
    'index': index,
    'startByte': startByte,
    'endByte': endByte,
    'checksum': checksum,
    'isReceived': isReceived,
    'receivedAt': receivedAt?.toIso8601String(),
  };

  factory FileChunk.fromJson(Map<String, dynamic> json) {
    return FileChunk(
      index: json['index'] as int,
      startByte: json['startByte'] as int,
      endByte: json['endByte'] as int,
      checksum: json['checksum'] as String?,
      isReceived: json['isReceived'] as bool? ?? false,
      receivedAt: json['receivedAt'] != null
          ? DateTime.parse(json['receivedAt'] as String)
          : null,
    );
  }
}

/// Metadata for a file transfer operation
class TransferMetadata {
  final String transferId;
  final String fileName;
  final String? filePath;
  final int fileSize;
  final String mimeType;
  final String fileHash; // SHA256 of entire file
  final TransferFileType fileType;
  final int totalChunks;
  final int chunkSize;
  final DateTime createdAt;
  final String? thumbnailPath; // Local path to thumbnail preview

  TransferMetadata({
    required this.transferId,
    required this.fileName,
    this.filePath,
    required this.fileSize,
    required this.mimeType,
    required this.fileHash,
    required this.fileType,
    required this.totalChunks,
    this.chunkSize = 65536, // 64KB default
    required this.createdAt,
    this.thumbnailPath,
  });

  Map<String, dynamic> toJson() => {
    'transferId': transferId,
    'fileName': fileName,
    'filePath': filePath,
    'fileSize': fileSize,
    'mimeType': mimeType,
    'fileHash': fileHash,
    'fileType': fileType.name,
    'totalChunks': totalChunks,
    'chunkSize': chunkSize,
    'createdAt': createdAt.toIso8601String(),
    'thumbnailPath': thumbnailPath,
  };

  factory TransferMetadata.fromJson(Map<String, dynamic> json) {
    return TransferMetadata(
      transferId: json['transferId'] as String,
      fileName: json['fileName'] as String,
      filePath: json['filePath'] as String?,
      fileSize: json['fileSize'] as int,
      mimeType: json['mimeType'] as String,
      fileHash: json['fileHash'] as String,
      fileType: TransferFileType.values.firstWhere(
        (t) => t.name == json['fileType'],
        orElse: () => TransferFileType.other,
      ),
      totalChunks: json['totalChunks'] as int,
      chunkSize: json['chunkSize'] as int? ?? 65536,
      createdAt: DateTime.parse(json['createdAt'] as String),
      thumbnailPath: json['thumbnailPath'] as String?,
    );
  }

  /// Get human-readable file size
  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// Complete transfer session data
class TransferSession {
  final String sessionId;
  final String deviceId;
  String deviceName;
  final TransferDirection direction;
  TransferState state;
  final TransferMetadata metadata;
  final List<FileChunk> chunks;
  int completedChunks;
  int failedChunks;
  DateTime? startedAt;
  DateTime? completedAt;
  DateTime? lastActivityAt;
  String? errorMessage;
  int retryCount;

  // Transfer statistics
  int bytesTransferred;
  double currentSpeed; // bytes per second
  Duration? estimatedTimeRemaining;

  TransferSession({
    required this.sessionId,
    required this.deviceId,
    required this.deviceName,
    required this.direction,
    this.state = TransferState.pending,
    required this.metadata,
    required this.chunks,
    this.completedChunks = 0,
    this.failedChunks = 0,
    this.startedAt,
    this.completedAt,
    this.lastActivityAt,
    this.errorMessage,
    this.retryCount = 0,
    this.bytesTransferred = 0,
    this.currentSpeed = 0.0,
    this.estimatedTimeRemaining,
  });

  bool get isIncoming => direction == TransferDirection.receiving;
  double get scSpeed => currentSpeed;
  String? get error => errorMessage;

  double get progress =>
      metadata.totalChunks > 0 ? completedChunks / metadata.totalChunks : 0.0;

  bool get isCompleted => state == TransferState.completed;
  bool get isFailed => state == TransferState.failed;
  bool get isActive =>
      state == TransferState.transferring || state == TransferState.connecting;
  bool get canResume =>
      state == TransferState.paused || state == TransferState.failed;

  /// Get list of missing chunk indices
  List<int> get missingChunkIndices {
    return chunks.where((c) => !c.isReceived).map((c) => c.index).toList();
  }

  /// Update transfer statistics
  void updateStats(int bytesDelta, Duration elapsed) {
    bytesTransferred += bytesDelta;
    if (elapsed.inSeconds > 0) {
      currentSpeed = bytesDelta / elapsed.inSeconds;

      // Calculate ETA
      final remainingBytes = metadata.fileSize - bytesTransferred;
      if (currentSpeed > 0) {
        estimatedTimeRemaining = Duration(
          seconds: (remainingBytes / currentSpeed).ceil(),
        );
      }
    }
    lastActivityAt = DateTime.now();
  }

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'deviceId': deviceId,
    'deviceName': deviceName,
    'direction': direction.name,
    'state': state.name,
    'metadata': metadata.toJson(),
    'chunks': chunks.map((c) => c.toJson()).toList(),
    'completedChunks': completedChunks,
    'failedChunks': failedChunks,
    'startedAt': startedAt?.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'lastActivityAt': lastActivityAt?.toIso8601String(),
    'errorMessage': errorMessage,
    'retryCount': retryCount,
    'bytesTransferred': bytesTransferred,
  };

  factory TransferSession.fromJson(Map<String, dynamic> json) {
    return TransferSession(
      sessionId: json['sessionId'] as String,
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
      direction: TransferDirection.values.firstWhere(
        (d) => d.name == json['direction'],
      ),
      state: TransferState.values.firstWhere((s) => s.name == json['state']),
      metadata: TransferMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      chunks: (json['chunks'] as List)
          .map((c) => FileChunk.fromJson(c as Map<String, dynamic>))
          .toList(),
      completedChunks: json['completedChunks'] as int? ?? 0,
      failedChunks: json['failedChunks'] as int? ?? 0,
      startedAt: json['startedAt'] != null
          ? DateTime.parse(json['startedAt'] as String)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
      lastActivityAt: json['lastActivityAt'] != null
          ? DateTime.parse(json['lastActivityAt'] as String)
          : null,
      errorMessage: json['errorMessage'] as String?,
      retryCount: json['retryCount'] as int? ?? 0,
      bytesTransferred: json['bytesTransferred'] as int? ?? 0,
    );
  }
}

/// Device information for pairing
class TransferDevice {
  final String deviceId;
  final String deviceName;
  final String? model;
  final String? platform;
  final DateTime discoveredAt;
  final String? endpointId; // Nearby Connections endpoint ID
  bool isTrusted;
  DateTime? lastConnectedAt;
  int connectionCount;
  int failedConnections;

  TransferDevice({
    required this.deviceId,
    required this.deviceName,
    this.model,
    this.platform,
    required this.discoveredAt,
    this.endpointId,
    this.isTrusted = false,
    this.lastConnectedAt,
    this.connectionCount = 0,
    this.failedConnections = 0,
  });

  bool get isReliable => connectionCount > 0 && failedConnections < 3;

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'deviceName': deviceName,
    'model': model,
    'platform': platform,
    'discoveredAt': discoveredAt.toIso8601String(),
    'endpointId': endpointId,
    'isTrusted': isTrusted,
    'lastConnectedAt': lastConnectedAt?.toIso8601String(),
    'connectionCount': connectionCount,
    'failedConnections': failedConnections,
  };

  factory TransferDevice.fromJson(Map<String, dynamic> json) {
    return TransferDevice(
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
      model: json['model'] as String?,
      platform: json['platform'] as String?,
      discoveredAt: DateTime.parse(json['discoveredAt'] as String),
      endpointId: json['endpointId'] as String?,
      isTrusted: json['isTrusted'] as bool? ?? false,
      lastConnectedAt: json['lastConnectedAt'] != null
          ? DateTime.parse(json['lastConnectedAt'] as String)
          : null,
      connectionCount: json['connectionCount'] as int? ?? 0,
      failedConnections: json['failedConnections'] as int? ?? 0,
    );
  }
}
