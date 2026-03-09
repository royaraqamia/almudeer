import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almudeer_mobile_app/core/services/offline_sync_service.dart';
import '../../data/local/athkar_data.dart';

class AthkarProvider extends ChangeNotifier {
  static const String _storageKey = 'athkar_counts';
  static const String _lastResetDateKey = 'athkar_last_reset_date';
  static const String _misbahaKey = 'misbaha_count';

  final OfflineSyncService? _syncService;
  Map<String, int> _counts = {};
  int _misbahaCount = 0;
  bool _isLoading = true;
  Timer? _debounceTimer;

  Map<String, int> get counts => _counts;
  int get misbahaCount => _misbahaCount;
  bool get isLoading => _isLoading;

  AthkarProvider({OfflineSyncService? syncService})
    : _syncService = syncService {
    _init();
  }
  // ... (rest of the file handles sync in _saveToStorage)

  Future<void> _init() async {
    await _loadFromStorage();
    await _checkDailyReset();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final String? jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null) {
        final Map<String, dynamic> decoded = json.decode(jsonStr);
        _counts = decoded.map((key, value) => MapEntry(key, value as int));
      }

      _misbahaCount = prefs.getInt(_misbahaKey) ?? 0;
    } catch (e) {
      debugPrint('Error loading athkar counts: $e');
      _counts = {};
    }
  }

  Future<void> _checkDailyReset() async {
    final prefs = await SharedPreferences.getInstance();
    final String? lastResetStr = prefs.getString(_lastResetDateKey);
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    if (lastResetStr != todayStr) {
      await resetAll();
      await prefs.setString(_lastResetDateKey, todayStr);
    }
  }

  Future<void> checkAndResetIfNeeded() async {
    await _checkDailyReset();
  }

  int getCount(String id) {
    return _counts[id] ?? 0;
  }

  bool isCompleted(AthkarItem item) {
    return getCount(item.id) >= item.count;
  }

  void increment(AthkarItem item) {
    final current = getCount(item.id);
    if (current < item.count) {
      _counts[item.id] = current + 1;
      notifyListeners();
      _saveToStorageDebounced();
    }
  }

  void decrement(AthkarItem item) {
    final current = getCount(item.id);
    if (current > 0) {
      _counts[item.id] = current - 1;
      notifyListeners();
      _saveToStorageDebounced();
    }
  }

  void incrementMisbaha() {
    _misbahaCount++;
    notifyListeners();
    _saveToStorageDebounced();
  }

  void resetMisbaha() {
    _misbahaCount = 0;
    notifyListeners();
    _saveToStorageDebounced();
  }

  Future<void> resetAll() async {
    _counts = {};
    _misbahaCount = 0;
    notifyListeners();
    await _saveToStorage();
  }

  void _saveToStorageDebounced() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _saveToStorage();
    });
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, json.encode(_counts));
      await prefs.setInt(_misbahaKey, _misbahaCount);

      if (_syncService != null) {
        await _syncService.queueAthkarProgress(_counts, _misbahaCount);
      }
    } catch (e) {
      debugPrint('Error saving athkar counts: $e');
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
