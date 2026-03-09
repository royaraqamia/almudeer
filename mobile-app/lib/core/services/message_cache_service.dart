import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../data/models/inbox_message.dart';
import '../../../data/models/conversation.dart';

/// Service for caching messages and conversations offline using Hive.
///
/// Features:
/// - Cache messages per conversation
/// - Cache conversations list
/// - Auto-expire cached data after 7 days
/// - Merge cached with fresh data
/// - FIX P1-2: Stores Maps directly in Hive to avoid redundant JSON encoding
class MessageCacheService {
  final HiveInterface _hive;

  MessageCacheService({HiveInterface? hive}) : _hive = hive ?? Hive;

  // FIX P1-8: Consolidated to single box with namespaced keys to reduce file handles
  static const String _boxName = 'cache';
  static const String _keyConversationsPrefix = 'conversations:';

  static const Duration _cacheExpiry = Duration(days: 7);

  // FIX P1-2 & P1-8: Single Box<Map> for all caching needs
  Box<Map>? _cacheBox;

  bool _isInitialized = false;

  /// Initialize Hive and open boxes
  /// FIX P1-8: Single box for all cache data
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _hive.initFlutter();

    // FIX P1-2 & P1-8: Single box with Map type
    _cacheBox = await _hive.openBox<Map>(_boxName);

    _isInitialized = true;

    // Clean up expired entries on init
    await _cleanupExpired();
  }

  /// Ensure boxes are open
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  // ============ Messages Caching ============

  /// Cache messages for a conversation
  /// FIX P1-2: Stores Map directly instead of JSON string
  /// FIX P1-8: Uses consolidated cache box
  Future<void> cacheMessages(
    String senderContact,
    List<InboxMessage> messages,
  ) async {
    await _ensureInitialized();

    final key = _messagesCacheKey(senderContact);
    final data = {
      'messages': messages.map((m) => m.toJson()).toList(),
      'cached_at': DateTime.now().toIso8601String(),
    };

    // FIX P1-2 & P1-8: Store Map directly in consolidated box
    await _cacheBox?.put(key, data);
  }

  /// Get cached messages for a conversation
  /// FIX P1-2: Reads Map directly, no JSON decoding needed
  /// FIX P1-8: Uses consolidated cache box
  Future<List<InboxMessage>?> getCachedMessages(String senderContact) async {
    await _ensureInitialized();

    final key = _messagesCacheKey(senderContact);
    final cached = _cacheBox?.get(key);

    if (cached == null) return null;

    try {
      // FIX P1-2: cached is already a Map, no need to jsonDecode
      final data = cached as Map<String, dynamic>;

      // Check if expired
      final cachedAt = DateTime.parse(data['cached_at'] as String);
      if (DateTime.now().difference(cachedAt) > _cacheExpiry) {
        await _cacheBox?.delete(key);
        return null;
      }

      final messagesList = (data['messages'] as List<dynamic>)
          .map((m) => InboxMessage.fromJson(m as Map<String, dynamic>))
          .toList();

      return messagesList;
    } catch (e) {
      // Corrupted cache, delete it
      await _cacheBox?.delete(key);
      return null;
    }
  }

  /// Merge cached messages with fresh messages from API
  /// Returns combined list with fresh messages taking precedence
  ///
  /// FIX: Added proper error handling and edge case management
  List<InboxMessage> mergeMessages(
    List<InboxMessage> cached,
    List<InboxMessage> fresh,
  ) {
    // Handle edge cases
    if (cached.isEmpty && fresh.isEmpty) {
      return [];
    }
    if (cached.isEmpty) {
      return fresh;
    }
    if (fresh.isEmpty) {
      return cached;
    }

    final Map<int, InboxMessage> merged = {};

    // Add cached messages first
    for (final msg in cached) {
      // Skip messages with invalid IDs
      if (msg.id <= 0) continue;
      merged[msg.id] = msg;
    }

    // Override with fresh messages
    for (final msg in fresh) {
      // Skip messages with invalid IDs
      if (msg.id <= 0) continue;
      merged[msg.id] = msg;
    }

    // Sort by timestamp with null safety
    final result = merged.values.toList();
    try {
      result.sort((a, b) {
        return a.effectiveTimestamp.compareTo(b.effectiveTimestamp);
      });
    } catch (e) {
      // If sorting fails, return unsorted rather than crashing
      debugPrint('Warning: Message sorting failed: $e');
    }

    return result;
  }

  /// Clear cached messages for a specific conversation
  /// FIX P1-8: Uses consolidated cache box
  Future<void> clearConversationCache(String senderContact) async {
    await _ensureInitialized();
    await _cacheBox?.delete(_messagesCacheKey(senderContact));
  }

  // ============ Conversations Caching ============

  /// Cache conversations list
  /// FIX P1-2: Stores Map directly instead of JSON string
  /// FIX P1-8: Uses consolidated cache box with namespaced key
  Future<void> cacheConversations(List<Conversation> conversations) async {
    await _ensureInitialized();

    final data = {
      'conversations': conversations.map((c) => c.toJson()).toList(),
      'cached_at': DateTime.now().toIso8601String(),
    };

    // FIX P1-2 & P1-8: Store Map directly with namespaced key
    await _cacheBox?.put('$_keyConversationsPrefix all', data);
  }

  /// Get cached conversations
  /// FIX P1-2: Reads Map directly, no JSON decoding needed
  /// FIX P1-8: Uses consolidated cache box
  Future<List<Conversation>?> getCachedConversations() async {
    await _ensureInitialized();

    final cached = _cacheBox?.get('$_keyConversationsPrefix all');
    if (cached == null) return null;

    try {
      // FIX P1-2: cached is already a Map
      final data = cached as Map<String, dynamic>;

      // Check if expired
      final cachedAt = DateTime.parse(data['cached_at'] as String);
      if (DateTime.now().difference(cachedAt) > _cacheExpiry) {
        await _cacheBox?.delete('$_keyConversationsPrefix all');
        return null;
      }

      final conversationsList = (data['conversations'] as List<dynamic>)
          .map((c) => Conversation.fromJson(c as Map<String, dynamic>))
          .toList();

      return conversationsList;
    } catch (e) {
      await _cacheBox?.delete('$_keyConversationsPrefix all');
      return null;
    }
  }

  /// Cache conversations by filter key (status_channel format)
  ///
  /// This enables instant display for all filter tabs, not just the main list.
  /// Key format: "${status ?? 'all'}_${channel ?? 'all'}"
  Future<void> cacheConversationsByFilter(
    String filterKey,
    List<Conversation> conversations,
  ) async {
    await _ensureInitialized();

    final data = {
      'conversations': conversations.map((c) => c.toJson()).toList(),
      'cached_at': DateTime.now().toIso8601String(),
    };

    await _cacheBox?.put('filter_$filterKey', data);
  }

  /// Get cached conversations by filter key
  ///
  /// Returns null if cache is empty, expired, or corrupted.
  Future<List<Conversation>?> getCachedConversationsByFilter(
    String filterKey,
  ) async {
    await _ensureInitialized();

    final cacheKey = 'filter_$filterKey';
    final cached = _cacheBox?.get(cacheKey);

    if (cached == null) return null;

    try {
      // FIX P1-2: cached is already a Map, no need to jsonDecode
      final data = cached as Map<String, dynamic>;

      // Check if expired
      final cachedAt = DateTime.parse(data['cached_at'] as String);
      if (DateTime.now().difference(cachedAt) > _cacheExpiry) {
        await _cacheBox?.delete(cacheKey);
        return null;
      }

      final conversationsList = (data['conversations'] as List<dynamic>)
          .map((c) => Conversation.fromJson(c as Map<String, dynamic>))
          .toList();

      return conversationsList;
    } catch (e) {
      await _cacheBox?.delete(cacheKey);
      return null;
    }
  }

  // ============ Cache Management ============

  /// Clear all cached data
  Future<void> clearAll() async {
    await _ensureInitialized();
    await _cacheBox?.clear();
  }

  /// Get cache size info
  Future<Map<String, int>> getCacheStats() async {
    await _ensureInitialized();

    return {
      'entries': _cacheBox?.length ?? 0,
    };
  }

  // ============ Private Helpers ============

  String _messagesCacheKey(String senderContact) {
    return 'messages_$senderContact';
  }

  Future<void> _cleanupExpired() async {
    final keysToDelete = <String>[];

    // Check messages cache
    for (final key in _cacheBox?.keys ?? []) {
      final cached = _cacheBox?.get(key);
      if (cached != null) {
        try {
          // FIX P1-2: cached is already a Map, no need to jsonDecode
          final data = cached as Map<String, dynamic>;
          final cachedAt = DateTime.parse(data['cached_at'] as String);
          if (DateTime.now().difference(cachedAt) > _cacheExpiry) {
            keysToDelete.add(key);
          }
        } catch (e) {
          keysToDelete.add(key);
        }
      }
    }

    for (final key in keysToDelete) {
      await _cacheBox?.delete(key);
    }
  }

  /// Dispose and close boxes
  Future<void> dispose() async {
    await _cacheBox?.close();
    _isInitialized = false;
  }
}
