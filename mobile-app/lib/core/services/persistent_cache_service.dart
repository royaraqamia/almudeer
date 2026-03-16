import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';

/// Cache entry with metadata for tracking cache age and expiry
class CacheEntry<T> {
  final T data;
  final DateTime cachedAt;
  final bool isExpired;

  CacheEntry({
    required this.data,
    required this.cachedAt,
    required this.isExpired,
  });
}

/// A generic persistent cache service using Hive.
///
/// Features:
/// - Store and retrieve any JSON-serializable data.
/// - Named boxes for organizational logical separation.
/// - Expiry handling (P0-3 FIX: Standardized TTL to match backend).
class PersistentCacheService {
  static final PersistentCacheService _instance =
      PersistentCacheService._internal();
  factory PersistentCacheService() => _instance;
  PersistentCacheService._internal();

  final HiveInterface _hive = Hive;
  bool _isInitialized = false;

  // OFFLINE-FIRST FIX: All caches are now infinite (WhatsApp pattern)
  // Cache never expires - only cleared on explicit user action (logout/clear cache)
  // Note: These fields are kept for documentation purposes to show the cache strategy
  // static const Duration? _defaultExpiry = null; // Infinite
  // static const Duration? _libraryCacheExpiry = null; // Infinite
  // static const Duration? _inboxCacheExpiry = null; // Infinite
  // static const Duration? _integrationCacheExpiry = null; // Infinite
  // static const Duration? _customerCacheExpiry = null; // Infinite
  // static const Duration? _tasksCacheExpiry = null; // Infinite
  // static const Duration? _settingsCacheExpiry = null; // Infinite

  /// Standard boxes for the app
  static const String boxInbox = 'cache_inbox';
  static const String boxCustomers = 'cache_customers';
  static const String boxKnowledge = 'cache_knowledge';
  static const String boxIntegrations = 'cache_integrations';
  static const String boxSubscriptions = 'cache_subscriptions';
  static const String boxLibrary = 'cache_library';
  static const String boxGeneral = 'cache_general';

  final Set<String> _openedBoxes = {};

  /// Initialize Hive
  Future<void> initialize() async {
    if (_isInitialized) return;
    await _hive.initFlutter();
    _isInitialized = true;
    debugPrint('[PersistentCacheService] Initialized');
  }

  Future<Box<String>> _getBox(String boxName) async {
    if (!_isInitialized) await initialize();
    if (!_openedBoxes.contains(boxName)) {
      try {
        await _hive.openBox<String>(boxName);
      } catch (e, stackTrace) {
        // P2-2 FIX: Handle corrupted Hive boxes with recovery
        debugPrint('[PersistentCacheService] Box $boxName corrupted: $e');
        debugPrint('Stack trace: $stackTrace');
        try {
          // Try to clear the corrupted box
          final box = _hive.box<String>(boxName);
          await box.clear();
          debugPrint('[PersistentCacheService] Cleared corrupted box $boxName');
        } catch (clearError) {
          debugPrint('[PersistentCacheService] Failed to clear box $boxName: $clearError');
        }
        // Re-open the box
        await _hive.openBox<String>(boxName);
        debugPrint('[PersistentCacheService] Box $boxName recovered and reopened');
      }
      _openedBoxes.add(boxName);
    }
    return _hive.box<String>(boxName);
  }

  /// Put data into cache
  /// P0-3 FIX: Added optional expiry parameter for fine-grained TTL control
  Future<void> put(String boxName, String key, dynamic data, {Duration? expiry}) async {
    try {
      final box = await _getBox(boxName);
      final cacheEntry = {
        'data': data,
        'cached_at': DateTime.now().toIso8601String(),
        'expiry_minutes': expiry?.inMinutes, // Store expiry for this entry
      };
      await box.put(key, jsonEncode(cacheEntry));
    } catch (e) {
      debugPrint(
        '[PersistentCacheService] Error putting data in $boxName/$key: $e',
      );
    }
  }

  /// Get data from cache with metadata
  /// OFFLINE-FIRST FIX: No automatic expiration - cache is infinite (WhatsApp pattern)
  /// Returns CacheEntry with data, timestamp, and age info (but never expired)
  Future<CacheEntry<T>?> getWithMeta<T>(String boxName, String key, {Duration? expiry}) async {
    try {
      final box = await _getBox(boxName);
      final rawData = box.get(key);
      if (rawData == null) return null;

      final entry = jsonDecode(rawData) as Map<String, dynamic>;
      final cachedAt = DateTime.parse(entry['cached_at'] as String);

      // OFFLINE-FIRST FIX: No automatic expiration
      // Cache is infinite - always return data even if "old"
      // Caller can check age via cachedAt and decide UI treatment
      final isExpired = false; // Never mark as expired

      return CacheEntry<T>(
        data: entry['data'] as T,
        cachedAt: cachedAt,
        isExpired: isExpired,
      );
    } catch (e) {
      debugPrint(
        '[PersistentCacheService] Error getting data from $boxName/$key: $e',
      );
      return null;
    }
  }

  /// Get data from cache (legacy method for backward compatibility)
  /// OFFLINE-FIRST FIX: Never auto-delete - always return cached data
  Future<T?> get<T>(String boxName, String key, {Duration? expiry}) async {
    final entry = await getWithMeta<T>(boxName, key, expiry: expiry);
    // OFFLINE-FIRST FIX: Don't delete expired entries, just return data
    return entry?.data;
  }

  /// Delete a specific key
  Future<void> delete(String boxName, String key) async {
    final box = await _getBox(boxName);
    await box.delete(key);
  }

  /// Clear an entire box
  Future<void> clearBox(String boxName) async {
    final box = await _getBox(boxName);
    await box.clear();
  }

  /// Delete keys starting with a specific prefix
  Future<void> deleteByPrefix(String boxName, String prefix) async {
    final box = await _getBox(boxName);
    final keysToDelete = box.keys
        .where((k) => k.toString().startsWith(prefix))
        .toList();
    for (final key in keysToDelete) {
      await box.delete(key);
    }
  }

  /// Clear all boxes
  Future<void> clearAll() async {
    for (final boxName in _openedBoxes) {
      await clearBox(boxName);
    }
  }
}
