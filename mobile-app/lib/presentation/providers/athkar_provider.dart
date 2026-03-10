import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almudeer_mobile_app/core/services/offline_sync_service.dart';
import '../../data/local/athkar_data.dart';

class AthkarProvider extends ChangeNotifier {
  // Namespaced storage keys to prevent collisions
  static const String _prefix = 'almudeer_athkar_';
  static const String _storageKey = '${_prefix}counts';
  static const String _lastResetDateKey = '${_prefix}last_reset_date';
  static const String _misbahaKey = '${_prefix}misbaha_count';
  static const String _misbahaTargetKey = '${_prefix}misbaha_target';

  final OfflineSyncService? _syncService;
  Map<String, int> _counts = {};
  int _misbahaCount = 0;
  int _misbahaTarget = 33;
  bool _isLoading = true;
  bool _disposed = false;
  Timer? _debounceTimer;
  int _consecutiveSyncFailures = 0;
  static const int _maxRetryAttempts = 3;
  Duration _syncRetryDelay = const Duration(seconds: 5);

  Map<String, int> get counts => _counts;
  int get misbahaCount => _misbahaCount;
  int get misbahaTarget => _misbahaTarget;
  bool get isLoading => _isLoading;
  int get consecutiveSyncFailures => _consecutiveSyncFailures;
  // For testing purposes only
  @visibleForTesting
  bool get disposed => _disposed;

  AthkarProvider({OfflineSyncService? syncService})
    : _syncService = syncService {
    _init();
  }

  Future<void> _init() async {
    await _loadFromStorage();
    final lastResetDate = await _getLastResetDate();
    final todayStr = _getTodayString();
    
    // Check if reset is needed before loading server data
    if (lastResetDate != todayStr) {
      await resetAll();
      await _saveLastResetDate(todayStr);
    }
    
    // Load server data only if last reset was today (prevents old server data from overriding reset)
    final shouldMergeServerData = lastResetDate == todayStr;
    if (shouldMergeServerData) {
      await _loadFromServer();
    } else {
      debugPrint('AthkarProvider: Skipping server merge - local reset is newer');
    }
    
    _isLoading = false;
    if (!_disposed) {
      notifyListeners();
    }
  }

  String _getTodayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<String> _getLastResetDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastResetDateKey) ?? '';
  }

  Future<void> _saveLastResetDate(String date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastResetDateKey, date);
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
      _misbahaTarget = prefs.getInt(_misbahaTargetKey) ?? 33;
    } catch (e, stackTrace) {
      debugPrint('AthkarProvider: Failed to load counts from storage: $e');
      debugPrint('AthkarProvider: Stack trace: $stackTrace');
      _counts = {};
    }
  }

  Future<void> _loadFromServer() async {
    if (_syncService == null) return;

    try {
      final serverData = await _syncService.getAthkarProgress();
      if (serverData != null && serverData['success'] == true) {
        final athkar = serverData['athkar'];
        if (athkar != null) {
          final counts = athkar['counts'] as Map<String, dynamic>?;
          final misbaha = athkar['misbaha'] as int?;

          if (counts != null) {
            // Validate and sanitize server data to prevent corruption
            _counts = counts.map((key, value) {
              if (value is int) {
                return MapEntry(key, value >= 0 ? value : 0);
              } else if (value is num) {
                return MapEntry(key, value.toInt());
              } else {
                debugPrint('Invalid athkar count value for $key: $value');
                return MapEntry(key, 0);
              }
            });
          }
          if (misbaha != null && misbaha >= 0) {
            _misbahaCount = misbaha;
          }
          debugPrint('AthkarProvider: Loaded athkar progress from server');
        }
      }
    } catch (e, stackTrace) {
      debugPrint('AthkarProvider: Failed to load athkar progress from server: $e');
      debugPrint('AthkarProvider: Stack trace: $stackTrace');
    }
  }

  Future<void> _checkDailyReset() async {
    final lastResetStr = await _getLastResetDate();
    final todayStr = _getTodayString();

    if (lastResetStr != todayStr) {
      await resetAll();
      await _saveLastResetDate(todayStr);
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

  void setMisbahaTarget(int target) {
    _misbahaTarget = target;
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
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        await _saveToStorage();
      } catch (e, stackTrace) {
        debugPrint('AthkarProvider: Debounced save failed: $e');
        debugPrint('AthkarProvider: Stack trace: $stackTrace');
      }
    });
  }

  Future<void> _saveToStorage() async {
    if (_disposed) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, json.encode(_counts));
      await prefs.setInt(_misbahaKey, _misbahaCount);
      await prefs.setInt(_misbahaTargetKey, _misbahaTarget);

      if (_syncService != null) {
        await _syncService.queueAthkarProgress(_counts, _misbahaCount);
      }
      _consecutiveSyncFailures = 0;
      _syncRetryDelay = const Duration(seconds: 5); // Reset delay on success
    } catch (e, stackTrace) {
      debugPrint('AthkarProvider: Failed to save athkar counts: $e');
      debugPrint('AthkarProvider: Stack trace: $stackTrace');
      _consecutiveSyncFailures++;

      if (_consecutiveSyncFailures >= _maxRetryAttempts) {
        debugPrint('AthkarProvider: ⚠️ Sync failed $_consecutiveSyncFailures times. Data saved locally only. Next retry in ${_syncRetryDelay.inSeconds}s');
        // Exponential backoff: double the delay for next retry (max 5 minutes)
        _syncRetryDelay = Duration(
          seconds: (_syncRetryDelay.inSeconds * 2).clamp(5, 300),
        );
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    super.dispose();
  }
}
