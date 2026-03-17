import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/browser_history.dart';
import 'browser_sync_service.dart';

class BrowserHistoryService {
  static final BrowserHistoryService _instance =
      BrowserHistoryService._internal();
  factory BrowserHistoryService() => _instance;
  BrowserHistoryService._internal();

  static const String _boxName = 'browser_history';
  late Box<BrowserHistoryEntry> _box;
  final Map<String, int> _urlIndex = {};
  final BrowserSyncService _syncService = BrowserSyncService();
  
  // Debounce timer for sync
  DateTime? _lastSyncTime;
  bool _isSyncing = false;

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

    try {
      // Rebuild index first to ensure we have fresh data
      // This prevents race conditions when multiple entries are added rapidly
      _rebuildIndex();

      // Remove existing entry for this URL if present
      if (_urlIndex.containsKey(url)) {
        await _box.deleteAt(_urlIndex[url]!);
        // Rebuild index after deletion to ensure consistency
        _rebuildIndex();
      }

      // Add new entry
      final entry = BrowserHistoryEntry(url: url, title: title, timestamp: DateTime.now());
      await _box.add(entry);

      // Rebuild index after addition
      _rebuildIndex();

      // Enforce max history limit
      if (_box.length > 500) {
        await _box.deleteAt(0);
        _rebuildIndex();
      }
      
      // Sync to backend (debounced)
      _scheduleSync();
    } catch (e) {
      debugPrint('[BrowserHistory] Error adding entry: $e');
      // Rebuild index on error to ensure consistency
      _rebuildIndex();
      rethrow;
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

  /// Sync recent history to backend
  Future<void> _syncToBackend() async {
    if (_isSyncing) return;
    
    try {
      _isSyncing = true;
      
      // Get recent entries (last 50)
      final entries = _box.values.toList().reversed.take(50).toList();
      
      if (entries.isNotEmpty) {
        final synced = await _syncService.syncHistory(entries);
        debugPrint('[BrowserHistory] Synced $synced entries to backend');
      }
      
      _lastSyncTime = DateTime.now();
    } catch (e) {
      debugPrint('[BrowserHistory] Sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Sync history from backend to local
  Future<void> syncFromBackend() async {
    try {
      final remoteEntries = await _syncService.getHistory(limit: 500);
      
      if (remoteEntries.isEmpty) return;
      
      // Merge with local history (avoid duplicates)
      final localUrls = _box.values.map((e) => e.url).toSet();
      int added = 0;
      
      for (final entry in remoteEntries) {
        if (!localUrls.contains(entry.url)) {
          await _box.add(entry);
          added++;
        }
      }
      
      if (added > 0) {
        debugPrint('[BrowserHistory] Added $added entries from backend');
        _rebuildIndex();
      }
    } catch (e) {
      debugPrint('[BrowserHistory] Error syncing from backend: $e');
    }
  }

  List<BrowserHistoryEntry> getHistory() {
    if (!_box.isOpen) return [];
    return _box.values.toList().reversed.toList();
  }

  Future<void> clearHistory() async {
    await _box.clear();
    _urlIndex.clear();
    
    // Also clear on backend
    await _syncService.clearHistory();
  }

  Future<void> deleteEntry(int index) async {
    if (!_box.isOpen) await init();

    // getHistory() returns reversed list, so index 0 is the newest (last in box)
    // Box stores in insertion order, so we need to convert reversed index to box index
    final list = _box.values.toList();
    final reversedIndex = list.length - 1 - index;

    if (reversedIndex < 0 || reversedIndex >= list.length) return;

    final entry = list[reversedIndex];
    await _box.deleteAt(reversedIndex);
    _urlIndex.remove(entry.url);
    _rebuildIndex();
    
    // Note: We don't delete from backend immediately to allow cross-device sync
    // The backend entry will be cleaned up during next full sync
  }

  Future<void> restoreEntry(BrowserHistoryEntry entry) async {
    if (!_box.isOpen) await init();
    await _box.add(entry);
    _urlIndex[entry.url] = _box.length - 1;
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
