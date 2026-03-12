import 'package:hive_flutter/hive_flutter.dart';
import '../models/browser_bookmark.dart';

class BrowserBookmarkService {
  static final BrowserBookmarkService _instance =
      BrowserBookmarkService._internal();
  factory BrowserBookmarkService() => _instance;
  BrowserBookmarkService._internal();

  static const String _boxName = 'browser_bookmarks';
  late Box<BrowserBookmark> _box;

  Future<void> init() async {
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(BrowserBookmarkAdapter());
    }
    _box = await Hive.openBox<BrowserBookmark>(_boxName);
  }

  Future<void> toggleBookmark(String url, String title) async {
    if (!_box.isOpen) await init();

    final existingIndex = _box.values.toList().indexWhere((e) => e.url == url);
    if (existingIndex != -1) {
      await _box.deleteAt(existingIndex);
    } else {
      await _box.add(
        BrowserBookmark(url: url, title: title, timestamp: DateTime.now()),
      );
    }
  }

  bool isBookmarked(String url) {
    return _box.values.any((e) => e.url == url);
  }

  List<BrowserBookmark> getBookmarks() {
    return _box.values.toList().reversed.toList();
  }

  Future<void> deleteBookmark(int index) async {
    if (!_box.isOpen) await init();

    // getBookmarks() returns reversed list, so index 0 is the newest (last in box)
    // Box stores in insertion order, so we need to convert reversed index to box index
    final bookmarks = _box.values.toList();
    final reversedIndex = bookmarks.length - 1 - index;

    if (reversedIndex < 0 || reversedIndex >= bookmarks.length) return;

    await _box.deleteAt(reversedIndex);
  }

  Future<void> restoreBookmark(BrowserBookmark bookmark) async {
    if (!_box.isOpen) await init();
    await _box.add(bookmark);
  }

  Future<void> clearAll() async {
    if (!_box.isOpen) await init();
    await _box.clear();
  }
}
