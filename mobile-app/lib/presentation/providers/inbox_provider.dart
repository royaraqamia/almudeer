import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/models/conversation.dart';

import '../../data/models/inbox_message.dart';
import '../../data/repositories/inbox_repository.dart';
import '../../core/services/websocket_service.dart';
import '../../core/services/message_cache_service.dart';
import '../../core/services/persistent_cache_service.dart';

/// Inbox state
enum InboxState { initial, loading, loaded, loadingMore, error }

/// Inbox provider for managing conversations and messages
class InboxProvider extends ChangeNotifier {
  final InboxRepository _inboxRepository;
  final WebSocketService _webSocketService;
  final MessageCacheService _messageCacheService;

  InboxState _state = InboxState.initial;
  List<Conversation> _conversations = [];
  Map<String, int>? _statusCounts;
  String? _errorMessage;
  int _total = 0;
  bool _hasMore = false;
  bool _isDisposed = false;
  String _searchQuery = ''; // Search query for message search
  List<String> _recentSearches = []; // Track recent search queries

  StreamSubscription? _wsSubscription;

  // Track locally read conversations to prevent stale server data from reverting UI
  // Key: ID, Value: Timestamp when it was marked read locally
  final Map<int, DateTime> _locallyReadConversations = {};

  // Cleanup timer for local read cache to prevent memory leaks
  Timer? _cleanupTimer;

  // Typing indicators
  final Map<String, bool> _typingStatus = {}; // contact -> isTyping
  final Map<String, Timer> _typingTimers = {};

  // Sorting
  String _sortBy = 'date'; // 'date', 'name', 'unread'
  bool _sortDescending = true;

  // Conversation detail state
  // Filters removed - all chats appear in unified list

  // Cache for instant switching (using Hive service now)
  // keeping minimal in-memory for immediate state if needed,
  // but we will rely on cache service.

  InboxProvider({
    InboxRepository? inboxRepository,
    WebSocketService? webSocketService,
    MessageCacheService? messageCacheService,
  }) : _inboxRepository = inboxRepository ?? InboxRepository(),
       _webSocketService = webSocketService ?? WebSocketService(),
       _messageCacheService = messageCacheService ?? MessageCacheService() {
    _initServices();
    _startCacheCleanup();
    loadRecentSearches(); // [NEW] Load searches on start
  }

  void _startCacheCleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      final now = DateTime.now();
      _locallyReadConversations.removeWhere(
        (id, time) => now.difference(time).inMinutes > 30,
      );
    });
  }

  // Throttled notification for high-frequency events
  Timer? _throttleTimer;
  bool _pendingNotification = false;

  // Message Prefetching (FIX: P2-4.3)
  final Set<String> _prefetchedContacts = {};
  // FIX P1-6: Add cooldown tracking to prevent excessive prefetching
  final Map<String, DateTime> _prefetchCooldowns = {};
  // P2-9 FIX: Increased cooldown from 5 to 15 minutes to reduce unnecessary API calls
  // and save battery/data usage in active conversations
  static const Duration _prefetchCooldownDuration = Duration(minutes: 15);

  void _throttledNotify() {
    if (_throttleTimer?.isActive ?? false) {
      _pendingNotification = true;
      return;
    }

    notifyListeners();
    _pendingNotification = false;

    _throttleTimer = Timer(const Duration(milliseconds: 100), () {
      if (_pendingNotification && !_isDisposed) {
        _throttledNotify();
      }
    });
  }

  /// Prefetch messages for top conversations (FIX: P2-4.3)
  /// Called after conversations list is loaded
  /// FIX P1-6: Added cooldown to prevent excessive prefetching
  void _prefetchTopConversations() {
    // Prefetch messages for top 3 conversations with unread messages
    final topConversations = _conversations
        .where((c) => c.unreadCount > 0 && c.senderContact != null)
        .take(3)
        .toList();

    final now = DateTime.now();

    for (final convo in topConversations) {
      final contact = convo.senderContact!;

      // FIX P1-6: Check cooldown - skip if prefetched recently
      final lastPrefetch = _prefetchCooldowns[contact];
      if (lastPrefetch != null &&
          now.difference(lastPrefetch) < _prefetchCooldownDuration) {
        continue; // Still in cooldown
      }

      if (!_prefetchedContacts.contains(contact)) {
        _prefetchedContacts.add(contact);
        _prefetchCooldowns[contact] = now;

        // Prefetch in background
        _inboxRepository
            .getConversationMessagesCursor(contact, limit: 25)
            .then((response) {
              // Cache the prefetched messages
              _messageCacheService.cacheMessages(contact, response.messages);
            })
            .catchError((_) {
              // Ignore prefetch errors
              _prefetchedContacts.remove(contact);
              _prefetchCooldowns.remove(contact);
            });
      }
    }
  }

  Future<void> _initServices() async {
    await _messageCacheService.initialize();
    _initWebSocket();
  }

  InboxState get state => _state;
  List<Conversation> get conversations => _conversations;
  Map<String, int>? get statusCounts => _statusCounts;
  String? get errorMessage => _errorMessage;
  int get total => _total;
  bool get hasMore => _hasMore;
  String get searchQuery => _searchQuery;
  List<String> get recentSearches => _recentSearches;
  bool get isLoading => _state == InboxState.loading;
  bool get isLoadingMore => _state == InboxState.loadingMore;

  int get unreadCount => _statusCounts?['unread'] ?? 0;

  /// Get total count of chats with unread messages (for bottom nav badge)
  /// Like WhatsApp/Telegram, this shows number of CHATS with unreads, not total messages
  /// Updates instantly when entering a chat
  int get totalUnreadCount => _conversations
      .where(
        (c) => c.senderContact != '__saved_messages__' && c.unreadCount > 0,
      )
      .length;

  // ============ Typing Indicators ============

  /// Get typing status for a contact
  bool isTyping(String contact) => _typingStatus[contact] ?? false;

  /// Set typing status for a contact
  void setTypingStatus(String contact, bool isTyping) {
    // Clear existing timer
    _typingTimers[contact]?.cancel();

    if (isTyping) {
      _typingStatus[contact] = true;
      // Auto-clear after 3 seconds of inactivity
      _typingTimers[contact] = Timer(const Duration(seconds: 3), () {
        _typingStatus[contact] = false;
        notifyListeners();
      });
    } else {
      _typingStatus[contact] = false;
    }
    notifyListeners();
  }

  /// Clear typing status for a contact
  void clearTypingStatus(String contact) {
    _typingTimers[contact]?.cancel();
    _typingTimers.remove(contact);
    _typingStatus[contact] = false;
    notifyListeners();
  }

  // ============ Sorting ============

  /// Get current sort mode
  String get sortBy => _sortBy;
  bool get sortDescending => _sortDescending;

  /// Set sort mode
  void setSortBy(String sortBy, {bool? descending}) {
    if (_sortBy == sortBy) {
      // Toggle direction if same sort
      _sortDescending = !_sortDescending;
    } else {
      _sortBy = sortBy;
      _sortDescending = descending ?? true;
    }
    _sortConversations();
    notifyListeners();
  }

  /// Sort conversations based on current settings
  void _sortConversations() {
    _conversations.sort((a, b) {
      int result;
      switch (_sortBy) {
        case 'name':
          result = a.displayName.compareTo(b.displayName);
          break;
        case 'unread':
          result = b.unreadCount.compareTo(a.unreadCount);
          break;
        case 'date':
        default:
          final aDate = DateTime.tryParse(a.createdAt) ?? DateTime(0);
          final bDate = DateTime.tryParse(b.createdAt) ?? DateTime(0);
          result = aDate.compareTo(bDate);
          break;
      }
      return _sortDescending ? -result : result;
    });
  }

  /// Load conversations with cache-first approach (WhatsApp/Telegram pattern)
  ///
  /// OFFLINE-FIRST FIX:
  /// 1. ALWAYS show cached data instantly (even if "old")
  /// 2. Fetch fresh data in background (non-blocking)
  /// 3. Update cache when fresh data arrives
  /// 4. NEVER show empty state if cache exists
  ///
  /// [forceRefresh] - if true, fetch fresh data in background (UI still shows cache first)
  /// [skipAutoRefresh] - if true, only load cache and never auto-fetch (for app resume)
  Future<void> loadConversations({
    bool refresh = false,
    bool forceRefresh = false,
    bool skipAutoRefresh = false,
  }) async {
    // If already loading, skip to avoid double fetch
    if (_state == InboxState.loading && !refresh && !forceRefresh) {
      return;
    }

    _errorMessage = null;

    // 1. ALWAYS check persistent cache first for instant display
    bool hasCache = false;

    if (!refresh && !forceRefresh) {
      try {
        final apiClient = _inboxRepository.apiClient;
        final accountHash = await apiClient.getAccountCacheHash();
        final cache = PersistentCacheService();
        final cacheEntry = await cache.getWithMeta<Map<String, dynamic>>(
          PersistentCacheService.boxInbox,
          '${accountHash}_list_0',
        );

        if (cacheEntry != null) {
          final response = ConversationsResponse.fromJson(cacheEntry.data);
          _conversations = response.conversations;
          _statusCounts = response.statusCounts;
          _total = response.total;
          _hasMore = response.hasMore;
          _state = InboxState.loaded;
          _ensureSavedMessagesEntry();
          hasCache = true;
          
          // OFFLINE-FIRST FIX: Always show cache immediately
          notifyListeners();
          
          // Background refresh only if we have cache and not skipping auto-refresh
          if (!skipAutoRefresh) {
            _fetchFreshDataInBackground();
          }
          return; // Done - cache shown, refresh happens in background
        } else if (_conversations.isEmpty) {
          _state = InboxState.loading;
          notifyListeners();
        }
      } catch (_) {
        if (_conversations.isEmpty) {
          _state = InboxState.loading;
          notifyListeners();
        }
      }
    }

    // 2. Skip auto-refresh if requested AND we have cache
    if (skipAutoRefresh && hasCache) {
      return;
    }

    // 3. Fetch fresh data if:
    //    - forceRefresh is true (user pulled to refresh), OR
    //    - no cache exists
    // OFFLINE-FIRST FIX: Never block UI - show cache first, update when fresh data arrives
    if (forceRefresh || !hasCache) {
      await _fetchFreshDataInBackground();
    }
  }

  /// Fetch fresh data in background without blocking UI
  /// OFFLINE-FIRST FIX: Non-blocking fetch - cache is always shown first
  Future<void> _fetchFreshDataInBackground() async {
    try {
      final responseModel = await _inboxRepository.getConversations(
        limit: 25,
        offset: 0,
      );

      _conversations = responseModel.conversations.map((c) {
        // Apply local read state override
        if (_locallyReadConversations.containsKey(c.id)) {
          final readTime = _locallyReadConversations[c.id]!;
          final msgTime = DateTime.tryParse(c.createdAt) ?? DateTime(0);

          // If we read it locally AFTER the last message time, it should be read
          if (readTime.isAfter(msgTime)) {
            return c.copyWith(unreadCount: 0);
          }
        }
        return c;
      }).toList();

      _total = responseModel.total;
      _hasMore = responseModel.hasMore;
      _statusCounts = responseModel.statusCounts;

      _state = InboxState.loaded;
      _ensureSavedMessagesEntry();

      // Update persistent cache with the merged/corrected data
      _updatePersistentCache();

      // FIX: P2-4.3 - Prefetch messages for top conversations
      _prefetchTopConversations();
      
      notifyListeners();
    } catch (e) {
      // OFFLINE-FIRST FIX: Keep showing cached data when offline
      // Only log error, don't change UI state
      debugPrint('[InboxProvider] Background refresh failed (likely offline): $e');
    }
  }

  /// Load more conversations (pagination)
  Future<void> loadMoreConversations() async {
    if (_state == InboxState.loadingMore || !_hasMore) return;

    _state = InboxState.loadingMore;
    notifyListeners();

    try {
      final response = await _inboxRepository.getConversations(
        limit: 25,
        offset: _conversations.length,
      );

      _conversations.addAll(response.conversations);
      _hasMore = response.hasMore;
      _state = InboxState.loaded;
      _ensureSavedMessagesEntry();
    } catch (e) {
      _state = InboxState.loaded; // Keep existing data on pagination error
    }

    notifyListeners();
  }

  /// Refresh conversations
  Future<void> refresh() async {
    await loadConversations(refresh: true);
    // Also refresh user info to get latest badge counts if available in UserInfo
    // or specifically fetch unread counts
    await refreshUnreadCounts();
  }

  /// Refresh unread counts
  Future<void> refreshUnreadCounts() async {
    try {
      final counts = await _inboxRepository.getUnreadCounts();
      if (counts != null) {
        _statusCounts = counts;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error refreshing unread counts: $e');
    }
  }

  void _incrementStatusCount(String status) {
    if (_statusCounts == null) return;
    _statusCounts![status] = (_statusCounts![status] ?? 0) + 1;
  }

  void _decrementStatusCount(String status) {
    if (_statusCounts == null) return;
    final current = _statusCounts![status] ?? 0;
    if (current > 0) {
      _statusCounts![status] = current - 1;
    }
  }

  void _updateStatusCounts() {
    if (_statusCounts == null) return;
    _statusCounts = {
      'unread': _conversations.where((c) => c.unreadCount > 0).length,
      'pending': _conversations.where((c) => c.status == 'pending').length,
      'open': _conversations.where((c) => c.status == 'open').length,
      'resolved': _conversations.where((c) => c.status == 'resolved').length,
    };
  }

  // ============ Lifecycle Integration ============

  /// Called when app resumes from background
  void onAppResume() {
    // Load cached data only - no API call
    // WebSocket handles real-time updates, user can pull-to-refresh if needed
    loadConversations(skipAutoRefresh: true);
  }

  // ============ WebSocket Integration ============

  void _initWebSocket() {
    _webSocketService.connect();
    _wsSubscription?.cancel();
    // FIX P2-4: Add error boundary for WebSocket events
    _wsSubscription = _webSocketService.stream.listen((event) {
      try {
        _handleWebSocketEvent(event);
      } catch (e, stackTrace) {
        debugPrint('[InboxProvider] WebSocket event handler error: $e');
        debugPrint('Stack trace: $stackTrace');
        debugPrint('Event data: $event');
      }
    });
  }

  /// FIX P2-4: Extracted WebSocket event handling with error boundaries
  void _handleWebSocketEvent(Map<String, dynamic> event) {
    final type = event['event'];
    final data = event['data'] as Map<String, dynamic>? ?? {};

    switch (type) {
      case 'new_message':
        _handleNewMessageEvent(data);
        break;
      case 'conversation_deleted':
        _handleConversationDeletedEvent(data);
        break;
      case 'chat_cleared':
        _handleChatClearedEvent(data);
        break;
      case 'message_edited':
        _handleMessageEditedEvent(data);
        break;
      case 'message_deleted':
        _handleMessageDeletedEvent(data);
        break;
      case 'conversation_read':
        _handleConversationReadEvent(data);
        break;
      case 'customer_updated':
        _handleCustomerUpdatedEvent(data);
        break;
    }
  }

  /// Handle conversation read event - updates unread counts on other devices
  void _handleConversationReadEvent(Map<String, dynamic> data) {
    final senderContact = data['sender_contact'] as String?;
    if (senderContact != null) {
      // Find the conversation and set unread count to 0
      final index = _conversations.indexWhere(
        (c) => c.senderContact == senderContact,
      );
      if (index != -1) {
        final conversation = _conversations[index];
        if (conversation.unreadCount > 0) {
          _conversations[index] = conversation.copyWith(unreadCount: 0);
          notifyListeners();
        }
      }
    }
  }

  /// Handle customer updated event - migrates conversations when username/profile changes
  /// IMPORTANT: Only affects Almudeer channel conversations (internal users)
  /// WhatsApp/Telegram contacts are NOT affected by profile changes
  void _handleCustomerUpdatedEvent(Map<String, dynamic> data) {
    final senderContact = data['sender_contact'] as String?;
    final oldSenderContact = data['old_sender_contact'] as String?;
    final updatedFields = data['updated_fields'] as Map<String, dynamic>?;

    if (senderContact == null) return;

    debugPrint(
      '[InboxProvider] Customer updated: $oldSenderContact -> $senderContact',
    );

    // Find conversation by old contact or new contact
    int index = _conversations.indexWhere(
      (c) => c.senderContact == senderContact,
    );

    // If not found by new contact, try old contact (username change migration)
    if (index == -1 && oldSenderContact != null) {
      index = _conversations.indexWhere(
        (c) => c.senderContact == oldSenderContact,
      );
    }

    // CRITICAL: Only update Almudeer channel conversations
    // WhatsApp/Telegram contacts should NOT be affected by admin profile changes
    if (index != -1) {
      final conversation = _conversations[index];

      // Skip if this is NOT an Almudeer channel conversation
      if (conversation.channel.toLowerCase() != 'almudeer') {
        debugPrint(
          '[InboxProvider] Ignoring customer update for non-Almudeer channel: ${conversation.channel}',
        );
        return;
      }

      // Update sender name if provided
      String? newSenderName = conversation.senderName;
      if (updatedFields != null && updatedFields.containsKey('full_name')) {
        newSenderName = updatedFields['full_name'];
      }

      // Update avatar if provided
      String? newAvatarUrl = conversation.avatarUrl;
      if (updatedFields != null &&
          updatedFields.containsKey('profile_image_url')) {
        newAvatarUrl = updatedFields['profile_image_url'];
      }

      // If username changed, migrate the conversation to use new sender_contact
      if (oldSenderContact != null && oldSenderContact != senderContact) {
        debugPrint(
          '[InboxProvider] Migrating conversation from $oldSenderContact to $senderContact',
        );

        _conversations[index] = conversation.copyWith(
          senderName: newSenderName,
          avatarUrl: newAvatarUrl,
          senderContact: senderContact,
        );

        // Also update in local database for persistence
        _migrateConversationContact(oldSenderContact, senderContact);
      } else {
        // Just update name/avatar without contact change
        _conversations[index] = conversation.copyWith(
          senderName: newSenderName,
          avatarUrl: newAvatarUrl,
        );
      }

      notifyListeners();
    }
  }

  /// Migrate conversation contact in local database
  Future<void> _migrateConversationContact(
    String oldContact,
    String newContact,
  ) async {
    try {
      await _inboxRepository.migrateConversationContact(oldContact, newContact);
    } catch (e) {
      debugPrint('Failed to migrate conversation contact: $e');
    }
  }

  /// Handle message deleted event incrementally
  void _handleMessageDeletedEvent(Map<String, dynamic> data) {
    final messageId = data['message_id'];
    if (messageId != null) {
      // 1. Refresh UI (if current last message was deleted, we might need a full refresh to get previous last message)
      // Actually, refresh() is safest for the inbox list because a deletion can change the snippet/sort order.
      // But we MUST persist to SQLite either way.
      _inboxRepository
          .applyRemoteMessageDelete(messageId as int)
          .catchError((e) => debugPrint('Error persisting remote delete: $e'));

      refresh();
    }
  }

  /// Handle message edited event incrementally
  void _handleMessageEditedEvent(Map<String, dynamic> data) {
    debugPrint('[InboxProvider] Received message_edited event: $data');

    final senderContact = data['sender_contact'] as String?;
    final recipientContact = data['recipient_contact'] as String?;
    final newBody = data['new_body'] as String?;
    final messageId = data['message_id'];

    // FIX: For peer-to-peer Almudeer messages, use recipient_contact to identify the conversation
    // For self edits or other channels, use sender_contact
    final targetContact = recipientContact ?? senderContact;

    debugPrint(
      '[InboxProvider] targetContact=$targetContact, newBody=$newBody, messageId=$messageId',
    );

    if (targetContact != null && newBody != null) {
      updateMessageEdit(senderContact: targetContact, body: newBody);

      // Also persist to SQLite for long-term consistency
      if (messageId != null) {
        _inboxRepository
            .applyRemoteMessageEdit(
              messageId as int,
              newBody,
              data['edited_at'] as String?,
            )
            .catchError((e) => debugPrint('Error persisting remote edit: $e'));
      }
    } else {
      // Fallback to refresh if data is missing
      debugPrint(
        '[InboxProvider] Missing required data, falling back to refresh',
      );
      refresh();
    }
  }

  /// Handle new message event incrementally (no full refresh!)
  ///
  /// This enables WhatsApp/Telegram-like instant updates where new messages
  /// appear at the top of the inbox without any loading.
  Future<void> _handleNewMessageEvent(Map<String, dynamic> data) async {
    final senderContact = data['sender_contact'] as String?;
    final senderName = data['sender_name'] as String?;
    final body = data['body'] as String?;
    final channel = data['channel'] as String?;
    final timestamp = data['timestamp'] as String?;
    final conversationId = data['conversation_id'] as int?;

    if (senderContact == null) {
      // Fallback to full refresh if we don't have required data
      refresh();
      return;
    }

    // Find existing conversation by sender_contact
    final existingIndex = _conversations.indexWhere(
      (c) => c.senderContact == senderContact,
    );

    // Direction check for outgoing messages (synced from Telegram app)
    final direction = data['direction'] as String? ?? 'incoming';
    final isOutgoing = direction == 'outgoing';
    final status = data['status'] as String? ?? 'analyzed';

    if (existingIndex != -1) {
      // Update existing conversation: move to top (but below pinned Draft)
      final existing = _conversations.removeAt(existingIndex);
      final timestampStr = timestamp ?? existing.createdAt;

      // Guard against race condition: if we recently marked this as read locally,
      // don't let a stale WebSocket event (with unread_count > 0) overwrite our 0.
      int newUnreadCount = data.containsKey('unread_count')
          ? (data['unread_count'] as int)
          : (isOutgoing ? existing.unreadCount : (existing.unreadCount + 1));

      if (newUnreadCount > 0 &&
          _locallyReadConversations.containsKey(existing.id)) {
        final readTime = _locallyReadConversations[existing.id]!;
        final now = DateTime.now();
        if (now.difference(readTime).inSeconds < 10) {
          // Keep it at 0 or whatever it is now if it's less than what the server says
          newUnreadCount = existing.unreadCount;
          debugPrint(
            '[InboxProvider] Guarded against stale unread_count for ${existing.id}',
          );
        }
      }

      final updated = existing.copyWith(
        body: body ?? existing.body,
        createdAt: timestampStr,
        status: status,
        unreadCount: newUnreadCount,
        messageCount: existing.messageCount + 1,
      );

      // Pinned check: If index 0 is saved messages, insert at 1. Otherwise at 0.
      if (_conversations.isNotEmpty &&
          _conversations[0].senderContact == '__saved_messages__' &&
          senderContact != '__saved_messages__') {
        _conversations.insert(1, updated);
      } else {
        _conversations.insert(0, updated);
      }
    } else {
      // New conversation: create from event data or fetch
      if (conversationId != null && body != null && channel != null) {
        final newConversation = Conversation(
          id: conversationId,
          channel: channel,
          senderName: senderName,
          senderContact: senderContact,
          body: body,
          status: status,
          createdAt: timestamp ?? DateTime.now().toIso8601String(),
          messageCount: 1,
          unreadCount: isOutgoing ? 0 : 1,
        );

        if (_conversations.isNotEmpty &&
            _conversations[0].senderContact == '__saved_messages__' &&
            senderContact != '__saved_messages__') {
          _conversations.insert(1, newConversation);
        } else {
          _conversations.insert(0, newConversation);
        }
      } else {
        // Not enough data, do a quick background refresh
        refresh();
        return;
      }
    }

    if (!isOutgoing && status == 'unread') {
      _incrementStatusCount('unread');
    }

    // Persist to local SQLite DB for long-term consistency
    _inboxRepository
        .persistRemoteMessage(data)
        .catchError((e) => debugPrint('Error persisting remote message: $e'));

    // P1-6: Smart prefetch invalidation - invalidate cache when new message arrives
    if (_prefetchedContacts.contains(senderContact)) {
      // Remove from prefetched set - will be re-prefetched on next idle
      _prefetchedContacts.remove(senderContact);
      _prefetchCooldowns.remove(senderContact);
    }

    // Update Unified Persistent Cache with new data
    try {
      final cache = PersistentCacheService();
      final filterKey = 'list_0';

      // We need to re-wrap in the structure expected by ConversationsResponse
      await cache.put(PersistentCacheService.boxInbox, filterKey, {
        'conversations': _conversations.map((c) => c.toJson()).toList(),
        'status_counts': _statusCounts,
        'total': _total,
        'has_more': _hasMore,
      });
    } catch (e) {
      debugPrint('[InboxProvider] Failed to update persistent cache: $e');
    }
    _ensureSavedMessagesEntry();
    _throttledNotify();
  }

  /// Handle conversation deleted event
  void _handleConversationDeletedEvent(Map<String, dynamic> data) {
    final senderContact = data['sender_contact'] as String?;
    if (senderContact == null) return;

    final index = _conversations.indexWhere(
      (c) => c.senderContact == senderContact,
    );

    if (index != -1) {
      final removed = _conversations.removeAt(index);
      _decrementStatusCount(removed.status);
      _throttledNotify();
    }
  }

  /// Handle chat cleared event (messages removed but conversation remains)
  void _handleChatClearedEvent(Map<String, dynamic> data) {
    final senderContact = data['sender_contact'] as String?;
    if (senderContact == null) return;

    final index = _conversations.indexWhere(
      (c) => c.senderContact == senderContact,
    );

    if (index != -1) {
      final existing = _conversations[index];
      // Update the conversation to reflect zero messages and empty body
      final updated = existing.copyWith(
        body: '',
        messageCount: 0,
        unreadCount: 0,
      );
      _conversations[index] = updated;

      // Update cache
      _updatePersistentCache();
      _throttledNotify();
    }
  }

  /// Helper to update persistent cache for current filter
  Future<void> _updatePersistentCache() async {
    try {
      final cache = PersistentCacheService();
      final filterKey = 'list_0';

      await cache.put(PersistentCacheService.boxInbox, filterKey, {
        'conversations': _conversations.map((c) => c.toJson()).toList(),
        'status_counts': _statusCounts,
        'total': _total,
        'has_more': _hasMore,
      });
    } catch (e) {
      debugPrint('[InboxProvider] Failed to update persistent cache: $e');
    }
  }

  /// Search messages (Global or Scoped)
  Future<List<InboxMessage>> searchMessages(
    String query, {
    String? senderContact,
  }) async {
    try {
      return await _inboxRepository.searchMessages(
        query,
        senderContact: senderContact,
      );
    } catch (e) {
      debugPrint('Search error: $e');
      // Return empty list on error for now or rethrow
      rethrow;
    }
  }

  /// Set search query for local filtering of conversation list
  void setSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    notifyListeners();
  }

  /// Get filtered conversations based on search query
  List<Conversation> get filteredConversations {
    if (_searchQuery.isEmpty) return _conversations;
    return _conversations.where((c) {
      final query = _searchQuery.toLowerCase();
      final name = c.senderName?.toLowerCase() ?? '';
      final contact = c.senderContact?.toLowerCase() ?? '';
      final body = c.body.toLowerCase();
      return name.contains(query) ||
          contact.contains(query) ||
          body.contains(query);
    }).toList();
  }

  /// Get search results (alias for filteredConversations for global search)
  List<Conversation> get searchResults => filteredConversations;

  /// Clear error
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Load recent searches from persistent cache
  Future<void> loadRecentSearches() async {
    try {
      final cache = PersistentCacheService();
      final searches = await cache.get<List<dynamic>>(
        PersistentCacheService.boxGeneral,
        'recent_searches',
      );
      if (searches != null) {
        _recentSearches = searches.cast<String>();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[InboxProvider] Failed to load recent searches: $e');
    }
  }

  /// Save a search query to persistent cache
  Future<void> saveSearchQuery(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    // Move to top if already exists, otherwise add to top
    _recentSearches.remove(trimmed);
    _recentSearches.insert(0, trimmed);

    // Keep only last 10 searches
    if (_recentSearches.length > 10) {
      _recentSearches = _recentSearches.sublist(0, 10);
    }

    notifyListeners();

    try {
      final cache = PersistentCacheService();
      await cache.put(
        PersistentCacheService.boxGeneral,
        'recent_searches',
        _recentSearches,
      );
    } catch (e) {
      debugPrint('[InboxProvider] Failed to save search query: $e');
    }
  }

  /// Clear all recent searches
  Future<void> clearRecentSearches() async {
    _recentSearches.clear();
    notifyListeners();
    try {
      final cache = PersistentCacheService();
      await cache.delete(PersistentCacheService.boxGeneral, 'recent_searches');
    } catch (e) {
      debugPrint('[InboxProvider] Failed to clear recent searches: $e');
    }
  }

  /// P3-13 FIX: Delete individual search entry
  /// Allows users to remove specific sensitive searches
  Future<void> deleteIndividualSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    _recentSearches.remove(trimmed);
    notifyListeners();

    try {
      final cache = PersistentCacheService();
      await cache.put(
        PersistentCacheService.boxGeneral,
        'recent_searches',
        _recentSearches,
      );
    } catch (e) {
      debugPrint(
        '[InboxProvider] Failed to update recent searches after delete: $e',
      );
    }
  }

  /// Get frequent contacts based on message count/activity
  List<Conversation> getFrequentContacts() {
    // Sort by message count or recent activity (we already sort by date,
    // but maybe we want top 5 most messaged)
    final sorted = List<Conversation>.from(_conversations)
      ..sort((a, b) => (b.messageCount).compareTo(a.messageCount));

    return sorted.take(5).toList();
  }

  /// Reset provider state (clears all data)
  /// P1-3 FIX: Preserve prefetch cooldowns across resets to prevent excessive API calls
  void reset() {
    // Cancel WebSocket subscription to prevent stale events
    _wsSubscription?.cancel();
    _wsSubscription = null;

    _state = InboxState.initial;
    _conversations = [];
    _statusCounts = null;
    _errorMessage = null;
    _total = 0;
    _hasMore = false;
    _searchQuery = ''; // Reset search query
    _isSelectionMode = false;
    _selectedIds.clear();
    _locallyReadConversations.clear();
    _typingStatus.clear();
    _typingTimers.forEach((_, timer) => timer.cancel());
    _typingTimers.clear();

    // P1-3 FIX: Preserve prefetch cooldowns to prevent rapid re-prefetching after account switch
    // Only clear the prefetched contacts, not the cooldowns
    _prefetchedContacts.clear();
    // Keep _prefetchCooldowns - they will expire naturally

    notifyListeners();
  }

  // ============ Selection Mode Logic ============
  bool _isSelectionMode = false;
  final Set<int> _selectedIds = {};

  bool get isSelectionMode => _isSelectionMode;
  Set<int> get selectedIds => _selectedIds;
  int get selectedCount => _selectedIds.length;

  bool isSelected(int id) => _selectedIds.contains(id);

  void toggleSelectionMode(bool enabled) {
    if (_isSelectionMode == enabled) return;
    _isSelectionMode = enabled;
    if (!enabled) {
      _selectedIds.clear();
    }
    notifyListeners();
  }

  void toggleSelection(int id) {
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
      if (_selectedIds.isEmpty) {
        _isSelectionMode = false;
      }
    } else {
      _selectedIds.add(id);
      _isSelectionMode = true;
    }
    notifyListeners();
  }

  void selectAll() {
    _selectedIds.clear();
    for (var c in _conversations) {
      _selectedIds.add(c.id);
    }
    _isSelectionMode = true;
    notifyListeners();
  }

  void clearSelection() {
    _selectedIds.clear();
    _isSelectionMode = false;
    notifyListeners();
  }

  /// Bulk Delete
  Future<void> bulkDelete() async {
    if (_selectedIds.isEmpty) return;
    try {
      final ids = List<int>.from(_selectedIds);

      // Get contacts for selected IDs
      final contactsToDelete = <String>[];
      for (var id in ids) {
        final index = _conversations.indexWhere((c) => c.id == id);
        if (index != -1) {
          final c = _conversations[index];
          if (c.senderContact != null) {
            contactsToDelete.add(c.senderContact!);
          } else if (c.senderId != null) {
            contactsToDelete.add(c.senderId!);
          }
        }
      }

      // Optimistic remove
      _conversations.removeWhere((c) => ids.contains(c.id));
      _selectedIds.clear();
      _isSelectionMode = false;
      notifyListeners();

      // Execute deletes in parallel (or batch if API supported batch delete by contact)
      // Since API supports batch delete by contact list:
      /* 
         await _inboxRepository.deleteMultipleConversations(contactsToDelete); 
         // But waiting for that implementation, we stick to loop or check if repo has batch?
         // Repo doesn't have batch delete verified yet. Let's loop.
      */

      await Future.wait(
        contactsToDelete.map(
          (contact) => _inboxRepository.deleteConversation(contact),
        ),
      );

      // FIX: Always refresh from server after deletion to ensure deleted
      // conversations stay deleted (server filters out deleted_at IS NOT NULL)
      debugPrint(
        '[InboxProvider] Bulk delete completed (${contactsToDelete.length} items), refreshing from server...',
      );
      await loadConversations(refresh: true);
      debugPrint('[InboxProvider] Refresh completed after bulk delete');
    } catch (e) {
      _errorMessage = 'Failed to delete some items';
      debugPrint(
        '[InboxProvider] Bulk delete failed: $e, refreshing to recover state...',
      );
      await loadConversations(refresh: true);
    }
  }

  /// Delete single conversation
  Future<void> deleteConversation(int id) async {
    if (id == -999) return; // Safeguard: never delete Saved Messages
    final index = _conversations.indexWhere((c) => c.id == id);

    // Valid sender contact/id extraction logic
    String? contactToDelete;
    Conversation? conversation;

    if (index != -1) {
      conversation = _conversations[index];
      contactToDelete = conversation.senderContact ?? conversation.senderId;
    }

    if (contactToDelete == null) {
      // If we can't find the contact info, we can't delete via new API.
      // Could try to fetch message detail? But usually we have list data.
      return;
    }

    // Optimistic remove
    if (index != -1) {
      _conversations.removeAt(index);
      if (conversation != null) {
        _decrementStatusCount(conversation.status);
      }
      notifyListeners();
    }

    try {
      await _inboxRepository.deleteConversation(contactToDelete);
      // FIX: Refresh from server to ensure deleted conversation stays deleted
      // This fetches fresh data which excludes conversations with deleted_at set
      debugPrint(
        '[InboxProvider] Conversation deleted successfully, refreshing from server...',
      );
      await loadConversations(refresh: true);
      debugPrint(
        '[InboxProvider] Refresh completed, deleted conversation should be gone',
      );
    } catch (e) {
      // Revert
      if (conversation != null && index != -1) {
        _conversations.insert(index, conversation);

        // Revert count update
        if (_statusCounts != null) {
          _incrementStatusCount(conversation.status);
        }

        notifyListeners();
      }
      rethrow;
    }
  }

  /// Restore a deleted conversation (for undo functionality)
  void restoreConversation(Conversation conversation) {
    // Check if already exists to avoid duplicates
    final existingIndex = _conversations.indexWhere(
      (c) => c.id == conversation.id,
    );
    if (existingIndex != -1) return;

    // Insert at the top (below Saved Messages if it exists)
    if (_conversations.isNotEmpty &&
        _conversations[0].senderContact == '__saved_messages__') {
      _conversations.insert(1, conversation);
    } else {
      _conversations.insert(0, conversation);
    }

    _incrementStatusCount(conversation.status);
    notifyListeners();
  }

  /// Archive single conversation
  Future<void> archiveConversation(int id) async {
    final index = _conversations.indexWhere((c) => c.id == id);
    if (index == -1) return;

    final conversation = _conversations[index];

    // Optimistic remove
    _conversations.removeAt(index);
    _decrementStatusCount(conversation.status);
    notifyListeners();

    try {
      await _inboxRepository.archiveConversation(
        conversation.senderContact ?? conversation.senderId ?? '',
      );
    } catch (e) {
      // Revert
      _conversations.insert(index, conversation);
      _incrementStatusCount(conversation.status);
      notifyListeners();
      rethrow;
    }
  }

  /// Toggle pin conversation
  Future<void> togglePinConversation(int id) async {
    final index = _conversations.indexWhere((c) => c.id == id);
    if (index == -1) return;

    final conversation = _conversations[index];
    final newPinnedState = !conversation.isPinned;

    // Optimistic update
    _conversations[index] = conversation.copyWith(isPinned: newPinnedState);
    notifyListeners();

    try {
      await _inboxRepository.togglePinConversation(
        conversation.senderContact ?? conversation.senderId ?? '',
        newPinnedState,
      );
    } catch (e) {
      // Revert
      _conversations[index] = conversation;
      notifyListeners();
      rethrow;
    }
  }

  /// Mark all conversations as read
  Future<void> markAllAsRead() async {
    // Optimistic update
    for (int i = 0; i < _conversations.length; i++) {
      if (_conversations[i].unreadCount > 0) {
        _conversations[i] = _conversations[i].copyWith(unreadCount: 0);
      }
    }
    _updateStatusCounts();
    notifyListeners();

    try {
      await _inboxRepository.markAllAsRead();
    } catch (e) {
      // Reload on error
      refresh();
    }
  }

  /// Bulk archive selected conversations
  Future<void> bulkArchive() async {
    if (_selectedIds.isEmpty) return;

    final ids = List<int>.from(_selectedIds);
    final contactsToArchive = <String>[];

    for (var id in ids) {
      final index = _conversations.indexWhere((c) => c.id == id);
      if (index != -1) {
        final c = _conversations[index];
        contactsToArchive.add(c.senderContact ?? c.senderId ?? '');
      }
    }

    // Optimistic remove
    _conversations.removeWhere((c) => ids.contains(c.id));
    _selectedIds.clear();
    _isSelectionMode = false;
    notifyListeners();

    try {
      await Future.wait(
        contactsToArchive.map(
          (contact) => _inboxRepository.archiveConversation(contact),
        ),
      );
    } catch (e) {
      refresh();
    }
  }

  /// Bulk mark as read
  Future<void> bulkMarkAsRead() async {
    if (_selectedIds.isEmpty) return;

    final ids = List<int>.from(_selectedIds);

    for (var id in ids) {
      final index = _conversations.indexWhere((c) => c.id == id);
      if (index != -1 && _conversations[index].unreadCount > 0) {
        _conversations[index] = _conversations[index].copyWith(unreadCount: 0);
      }
    }
    _updateStatusCounts();
    _selectedIds.clear();
    _isSelectionMode = false;
    notifyListeners();

    try {
      await Future.wait(
        ids.map(
          (id) => _inboxRepository.markConversationRead(
            _conversations.firstWhere((c) => c.id == id).senderContact ?? '',
          ),
        ),
      );
    } catch (e) {
      // Ignore
    }
  }

  /// Mark as read
  Future<void> markAsRead(int conversationId) async {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) return;

    final conversation = _conversations[index];
    if (conversation.unreadCount == 0) return;

    // Optimistic update
    final updatedConversation = conversation.copyWith(unreadCount: 0);
    _conversations[index] = updatedConversation;

    // Track locally read
    _locallyReadConversations[conversationId] = DateTime.now();

    notifyListeners();

    // Persist immediately so it survives app restart if offline
    _updatePersistentCache();

    try {
      if (conversation.senderContact != null) {
        await _inboxRepository.markConversationRead(
          conversation.senderContact!,
        );
      }
      // Success - optimistic update already applied
    } catch (e) {
      // Silent fail - keep optimistic UI update, sync will retry later
      // User experience is preserved even if server fails
      debugPrint('[InboxProvider] markAsRead failed (keeping UI state): $e');
    }
  }

  /// Mark conversation as unread (P3-3: power user feature)
  void markAsUnread(int conversationId) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) return;

    final conversation = _conversations[index];
    if (conversation.unreadCount > 0) return; // Already unread

    // Optimistic update — set unread to 1
    _conversations[index] = conversation.copyWith(unreadCount: 1);
    _locallyReadConversations.remove(conversationId);
    _incrementStatusCount('unread');
    notifyListeners();
    _updatePersistentCache();
  }

  /// Optimistically update last message for a conversation (Instant Send Feedback)
  void updateLastMessage({
    required int conversationId,
    required String body,
    required String status,
    required DateTime createdAt,
  }) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index != -1) {
      final old = _conversations.removeAt(index);
      final updated = old.copyWith(
        body: body,
        status: status,
        createdAt: createdAt.toIso8601String(),
        messageCount: old.messageCount + 1,
        unreadCount: 0,
      );

      // Track locally read just in case
      _locallyReadConversations[conversationId] = DateTime.now();

      // Move to top (but below pinned Draft)
      if (_conversations.isNotEmpty &&
          _conversations[0].senderContact == '__saved_messages__' &&
          old.senderContact != '__saved_messages__') {
        _conversations.insert(1, updated);
      } else {
        _conversations.insert(0, updated);
      }

      _updatePersistentCache();
      notifyListeners();
    }
  }

  /// Optimistically update message body for edits (without moving to top or incrementing count)
  void updateMessageEdit({
    required String senderContact,
    required String body,
  }) {
    final index = _conversations.indexWhere(
      (c) => c.senderContact == senderContact,
    );
    if (index != -1) {
      final old = _conversations[index];
      // Update body
      final updated = old.copyWith(body: body);
      _conversations[index] = updated;
      _updatePersistentCache();
      notifyListeners();
    }
  }

  /// Update a conversation from external source (e.g. detail screen)
  /// maintaining list position unless it's a new message
  void updateConversation(Conversation updated) {
    final index = _conversations.indexWhere((c) => c.id == updated.id);
    if (index != -1) {
      _conversations[index] = updated;
      _updatePersistentCache();
      notifyListeners();
    }
  }

  /// Ensures a virtual "Saved Messages" entry exists at the top
  void _ensureSavedMessagesEntry() {
    // Helper to create Saved Messages conversation
    Conversation createSaved() {
      return Conversation(
        id: -999,
        channel: 'saved',
        senderContact: '__saved_messages__',
        senderName: 'المسودَّة',
        body: '',
        status: 'sent',
        createdAt: DateTime.now().toIso8601String(),
        messageCount: 0,
        unreadCount: 0,
      );
    }

    final index = _conversations.indexWhere(
      (c) => c.senderContact == '__saved_messages__',
    );
    if (index != -1) {
      if (index != 0) {
        final saved = _conversations.removeAt(index);
        _conversations.insert(0, saved);
      }
    } else {
      // Always add Saved Messages at the top
      _conversations.insert(0, createSaved());
    }
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _wsSubscription?.cancel();
    _cleanupTimer?.cancel();
    _throttleTimer?.cancel();
    super.dispose();
  }
}
