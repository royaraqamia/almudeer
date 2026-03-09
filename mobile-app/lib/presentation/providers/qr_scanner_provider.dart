import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// QR Scan result model
class QrScanResult {
  final String id;
  final String data;
  final String? type; // 'url', 'deep_link', 'text'
  final DateTime scannedAt;

  QrScanResult({
    required this.id,
    required this.data,
    this.type,
    required this.scannedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'data': data,
      'type': type,
      'scannedAt': scannedAt.toIso8601String(),
    };
  }

  factory QrScanResult.fromJson(Map<String, dynamic> json) {
    return QrScanResult(
      id: json['id'] as String,
      data: json['data'] as String,
      type: json['type'] as String?,
      scannedAt: DateTime.parse(json['scannedAt'] as String),
    );
  }
}

/// Provider for QR scanner state management and scan history
class QrScannerProvider extends ChangeNotifier {
  static const String _boxName = 'qr_scanner_history';
  static const String _settingsKey = 'scanner_settings';

  Box<Map>? _historyBox;
  bool _isInitialized = false;

  // Settings
  bool _soundEnabled = false;
  bool _vibrationEnabled = true;
  bool _flashEnabled = false;
  int _maxHistoryItems = 100;

  // Getters
  bool get isInitialized => _isInitialized;
  bool get soundEnabled => _soundEnabled;
  bool get vibrationEnabled => _vibrationEnabled;
  bool get flashEnabled => _flashEnabled;
  int get maxHistoryItems => _maxHistoryItems;

  /// Initialize the provider and load history
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Open Hive box for history
      _historyBox = await Hive.openBox<Map>(_boxName);

      // Load settings
      await _loadSettings();

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing QrScannerProvider: $e');
      }
      // Continue without history if Hive fails
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Load scanner settings from Hive
  Future<void> _loadSettings() async {
    try {
      if (_historyBox != null) {
        final settings = _historyBox?.get(_settingsKey);
        if (settings is Map) {
          _soundEnabled = settings['sound_enabled'] as bool? ?? false;
          _vibrationEnabled = settings['vibration_enabled'] as bool? ?? true;
          _flashEnabled = settings['flash_enabled'] as bool? ?? false;
          _maxHistoryItems = settings['max_history_items'] as int? ?? 100;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading settings: $e');
      }
    }
  }

  /// Save scanner settings to Hive
  Future<void> _saveSettings() async {
    try {
      if (_historyBox != null) {
        await _historyBox?.put(
          _settingsKey,
          {
            'sound_enabled': _soundEnabled,
            'vibration_enabled': _vibrationEnabled,
            'flash_enabled': _flashEnabled,
            'max_history_items': _maxHistoryItems,
          },
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving settings: $e');
      }
    }
  }

  /// Get all scan history items
  List<QrScanResult> getHistory() {
    if (_historyBox == null) return [];

    final items = <QrScanResult>[];
    final keys = _historyBox!.keys.toList();

    for (final key in keys) {
      if (key == _settingsKey) continue;

      final data = _historyBox!.get(key);
      if (data is Map) {
        try {
          items.add(QrScanResult.fromJson(Map<String, dynamic>.from(data)));
        } catch (e) {
          if (kDebugMode) {
            print('Error parsing history item: $e');
          }
        }
      }
    }

    // Sort by scannedAt descending (newest first)
    items.sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
    return items;
  }

  /// Add a scan result to history
  Future<void> addToHistory(String data, {String? type}) async {
    try {
      if (_historyBox == null) return;

      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final result = QrScanResult(
        id: id,
        data: data,
        type: type,
        scannedAt: DateTime.now(),
      );

      await _historyBox!.put(id, result.toJson());

      // Enforce max history limit
      await _enforceHistoryLimit();

      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error adding to history: $e');
      }
    }
  }

  /// Enforce maximum history items limit
  Future<void> _enforceHistoryLimit() async {
    if (_historyBox == null) return;

    final items = getHistory();
    if (items.length > _maxHistoryItems) {
      // Remove oldest items
      final toRemove = items.sublist(_maxHistoryItems);
      for (final item in toRemove) {
        await _historyBox!.delete(item.id);
      }
    }
  }

  /// Clear all scan history
  Future<void> clearHistory() async {
    try {
      if (_historyBox == null) return;

      final keys = _historyBox!.keys.toList();
      for (final key in keys) {
        if (key != _settingsKey) {
          await _historyBox!.delete(key);
        }
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error clearing history: $e');
      }
    }
  }

  /// Delete a specific scan result from history
  Future<void> deleteFromHistory(String id) async {
    try {
      if (_historyBox == null) return;

      await _historyBox!.delete(id);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting from history: $e');
      }
    }
  }

  /// Get the last scanned result
  QrScanResult? getLastScan() {
    final history = getHistory();
    return history.isNotEmpty ? history.first : null;
  }

  /// Update settings
  Future<void> updateSettings({
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? flashEnabled,
    int? maxHistoryItems,
  }) async {
    if (soundEnabled != null) _soundEnabled = soundEnabled;
    if (vibrationEnabled != null) _vibrationEnabled = vibrationEnabled;
    if (flashEnabled != null) _flashEnabled = flashEnabled;
    if (maxHistoryItems != null) _maxHistoryItems = maxHistoryItems;

    await _saveSettings();
    notifyListeners();
  }

  /// Search history
  List<QrScanResult> searchHistory(String query) {
    final allHistory = getHistory();
    if (query.isEmpty) return allHistory;

    final lowerQuery = query.toLowerCase();
    return allHistory
        .where((item) => item.data.toLowerCase().contains(lowerQuery))
        .toList();
  }

  @override
  void dispose() {
    // Close Hive box if needed (optional, Hive manages this)
    super.dispose();
  }
}
