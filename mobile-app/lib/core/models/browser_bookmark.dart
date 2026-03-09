import 'package:hive/hive.dart';

@HiveType(typeId: 14)
class BrowserBookmark extends HiveObject {
  @HiveField(0)
  final String url;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final DateTime timestamp;

  BrowserBookmark({
    required this.url,
    required this.title,
    required this.timestamp,
  });
}

class BrowserBookmarkAdapter extends TypeAdapter<BrowserBookmark> {
  @override
  final int typeId = 14;

  @override
  BrowserBookmark read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BrowserBookmark(
      url: fields[0] as String,
      title: fields[1] as String,
      timestamp: fields[2] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, BrowserBookmark obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.url)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.timestamp);
  }
}
