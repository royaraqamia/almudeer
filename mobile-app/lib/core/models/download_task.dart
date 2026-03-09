import 'package:hive/hive.dart';

@HiveType(typeId: 10)
enum DownloadStatus {
  @HiveField(0)
  pending,
  @HiveField(1)
  downloading,
  @HiveField(2)
  paused,
  @HiveField(3)
  completed,
  @HiveField(4)
  failed,
  @HiveField(5)
  canceled,
}

@HiveType(typeId: 11)
class DownloadTask {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String url;
  @HiveField(2)
  String fileName;
  @HiveField(3)
  String savedPath;
  @HiveField(4)
  DownloadStatus status;
  @HiveField(5)
  double progress;
  @HiveField(6)
  int currentSize;
  @HiveField(7)
  int totalSize;
  @HiveField(8)
  final DateTime timestamp;
  @HiveField(9)
  String? error;
  @HiveField(10)
  double networkSpeed; // in bytes per second
  @HiveField(11)
  Duration? timeRemaining;

  DownloadTask({
    required this.id,
    required this.url,
    required this.fileName,
    required this.savedPath,
    this.status = DownloadStatus.pending,
    this.progress = 0,
    this.currentSize = 0,
    this.totalSize = 0,
    required this.timestamp,
    this.error,
    this.networkSpeed = 0,
    this.timeRemaining,
  });

  DownloadTask copyWith({
    DownloadStatus? status,
    double? progress,
    int? currentSize,
    int? totalSize,
    String? error,
    double? networkSpeed,
    Duration? timeRemaining,
  }) {
    return DownloadTask(
      id: id,
      url: url,
      fileName: fileName,
      savedPath: savedPath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      currentSize: currentSize ?? this.currentSize,
      totalSize: totalSize ?? this.totalSize,
      timestamp: timestamp,
      error: error ?? this.error,
      networkSpeed: networkSpeed ?? this.networkSpeed,
      timeRemaining: timeRemaining ?? this.timeRemaining,
    );
  }
}

class DownloadStatusAdapter extends TypeAdapter<DownloadStatus> {
  @override
  final int typeId = 10;

  @override
  DownloadStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return DownloadStatus.pending;
      case 1:
        return DownloadStatus.downloading;
      case 2:
        return DownloadStatus.paused;
      case 3:
        return DownloadStatus.completed;
      case 4:
        return DownloadStatus.failed;
      case 5:
        return DownloadStatus.canceled;
      default:
        return DownloadStatus.pending;
    }
  }

  @override
  void write(BinaryWriter writer, DownloadStatus obj) {
    writer.writeByte(obj.index);
  }
}

class DownloadTaskAdapter extends TypeAdapter<DownloadTask> {
  @override
  final int typeId = 11;

  @override
  DownloadTask read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DownloadTask(
      id: fields[0] as String,
      url: fields[1] as String,
      fileName: fields[2] as String,
      savedPath: fields[3] as String,
      status: fields[4] as DownloadStatus,
      progress: fields[5] as double,
      currentSize: fields[6] as int,
      totalSize: fields[7] as int,
      timestamp: fields[8] as DateTime,
      error: fields[9] as String?,
      networkSpeed: (fields[10] as double?) ?? 0.0,
      timeRemaining: fields[11] as Duration?,
    );
  }

  @override
  void write(BinaryWriter writer, DownloadTask obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.url)
      ..writeByte(2)
      ..write(obj.fileName)
      ..writeByte(3)
      ..write(obj.savedPath)
      ..writeByte(4)
      ..write(obj.status)
      ..writeByte(5)
      ..write(obj.progress)
      ..writeByte(6)
      ..write(obj.currentSize)
      ..writeByte(7)
      ..write(obj.totalSize)
      ..writeByte(8)
      ..write(obj.timestamp)
      ..writeByte(9)
      ..write(obj.error)
      ..writeByte(10)
      ..write(obj.networkSpeed)
      ..writeByte(11)
      ..write(obj.timeRemaining);
  }
}
