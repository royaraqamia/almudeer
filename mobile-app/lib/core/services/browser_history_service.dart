import 'package:hive_flutter/hive_flutter.dart';
import '../models/browser_history.dart';

class BrowserHistoryService {
  static final BrowserHistoryService _instance =
      BrowserHistoryService._internal();
  factory BrowserHistoryService() => _instance;
  BrowserHistoryService._internal();

  static const String _boxName = 'browser_history';
  late Box<BrowserHistoryEntry> _box;
  final Map<String, int> _urlIndex = {};

  Future<void> init() async {
    if (!Hive.isAdapterRegistered(13)) {
      Hive.registerAdapter(BrowserHistoryEntryAdapter());
    }
    _box = await Hive.openBox<BrowserHistoryEntry>(_boxName);
    _rebuildIndex();
  }

  void _rebuildIndex() {
    _urlIndex.clear();
    final list = _box.values.toList();
    for (int i = 0; i < list.length; i++) {
      _urlIndex[list[i].url] = i;
    }
  }

  Future<void> addEntry(String url, String title) async {
    if (!_box.isOpen) await init();

    if (_urlIndex.containsKey(url)) {
      await _box.deleteAt(_urlIndex[url]!);
      _rebuildIndex();
    }

    await _box.add(
      BrowserHistoryEntry(url: url, title: title, timestamp: DateTime.now()),
    );

    _urlIndex[url] = _box.length - 1;

    if (_box.length > 500) {
      await _box.deleteAt(0);
      _rebuildIndex();
    }
  }

  List<BrowserHistoryEntry> getHistory() {
    return _box.values.toList().reversed.toList();
  }

  Future<void> clearHistory() async {
    await _box.clear();
    _urlIndex.clear();
  }

  Future<void> deleteEntry(int index) async {
    final list = _box.values.toList();
    if (index < 0 || index >= list.length) return;

    final entry = list[index];
    await _box.deleteAt(index);
    _urlIndex.remove(entry.url);
    _rebuildIndex();
  }

  Future<void> restoreEntry(BrowserHistoryEntry entry) async {
    if (!_box.isOpen) await init();
    await _box.add(entry);
    _urlIndex[entry.url] = _box.length - 1;
  }
}
