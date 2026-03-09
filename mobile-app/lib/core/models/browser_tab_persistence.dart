import 'package:hive/hive.dart';

@HiveType(typeId: 12)
class BrowserTabPersistence extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String url;

  @HiveField(2)
  final String title;

  @HiveField(3)
  final bool isDesktopMode;

  BrowserTabPersistence({
    required this.id,
    required this.url,
    required this.title,
    this.isDesktopMode = false,
  });
}

class BrowserTabPersistenceAdapter extends TypeAdapter<BrowserTabPersistence> {
  @override
  final int typeId = 12;

  @override
  BrowserTabPersistence read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BrowserTabPersistence(
      id: fields[0] as String,
      url: fields[1] as String,
      title: fields[2] as String,
      isDesktopMode: fields[3] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, BrowserTabPersistence obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.url)
      ..writeByte(2)
      ..write(obj.title)
      ..writeByte(3)
      ..write(obj.isDesktopMode);
  }
}
