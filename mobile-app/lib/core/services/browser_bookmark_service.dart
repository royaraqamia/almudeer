import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/browser_bookmark.dart';
import 'browser_sync_service.dart';

class BrowserBookmarkService {
  static final BrowserBookmarkService _instance =
      BrowserBookmarkService._internal();
  factory BrowserBookmarkService() => _instance;
  BrowserBookmarkService._internal();

  static const String _boxName = 'browser_bookmarks';
  late Box<BrowserBookmark> _box;
  final BrowserSyncService _syncService = BrowserSyncService();
  
  // Debounce timer for sync
  DateTime? _lastSyncTime;
  bool _isSyncing = false;

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
      // Sync to backend (debounced)
      _scheduleSync();
    }
  }

  /// Schedule a sync to backend (debounced to avoid too many API calls)
  void _scheduleSync() {
    if (_isSyncing) return;
    
    final now = DateTime.now();
    final lastSync = _lastSyncTime;
    final timeSinceLastSync = lastSync != null 
        ? now.difference(lastSync).inMilliseconds 
        : 5000;
    
    // Debounce: wait at least 5 seconds between syncs
    if (timeSinceLastSync < 5000) {
      Future.delayed(Duration(milliseconds: 5000 - timeSinceLastSync), () {
        _syncToBackend();
      });
    } else {
      _syncToBackend();
    }
  }

  /// Sync bookmarks to backend
  Future<void> _syncToBackend() async {
    if (_isSyncing) return;
    
    try {
      _isSyncing = true;
      
      // Get all bookmarks
      final bookmarks = _box.values.toList();
      
      if (bookmarks.isNotEmpty) {
        final synced = await _syncService.syncBookmarks(bookmarks);
        debugPrint('[BrowserBookmark] Synced $synced bookmarks to backend');
      }
      
      _lastSyncTime = DateTime.now();
    } catch (e) {
      debugPrint('[BrowserBookmark] Sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Sync bookmarks from backend to local
  Future<void> syncFromBackend() async {
    try {
      final remoteBookmarks = await _syncService.getBookmarks();
      
      if (remoteBookmarks.isEmpty) return;
      
      // Merge with local bookmarks (avoid duplicates)
      final localUrls = _box.values.map((e) => e.url).toSet();
      int added = 0;
      
      for (final bookmark in remoteBookmarks) {
        if (!localUrls.contains(bookmark.url)) {
          await _box.add(bookmark);
          added++;
        }
      }
      
      if (added > 0) {
        debugPrint('[BrowserBookmark] Added $added bookmarks from backend');
      }
    } catch (e) {
      debugPrint('[BrowserBookmark] Error syncing from backend: $e');
    }
  }

  bool isBookmarked(String url) {
    if (!_box.isOpen) return false;
    return _box.values.any((e) => e.url == url);
  }

  List<BrowserBookmark> getBookmarks() {
    if (!_box.isOpen) return [];
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
    
    // Also clear on backend
    await _syncService.clearBookmarks();
  }
  
  /// Check if sync is enabled (always true - sync is automatic)
  Future<bool> isSyncEnabled() async {
    return true;
  }
  
  /// Toggle sync (no-op - sync is always enabled)
  Future<void> toggleSync(bool enable) async {
    // Sync is always enabled and automatic
  }
}
