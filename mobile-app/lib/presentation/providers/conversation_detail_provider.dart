import 'dart:async';
import 'package:flutter/material.dart';

import '../../data/models/inbox_message.dart';
import '../../data/models/conversation.dart';
import '../../data/repositories/inbox_repository.dart';
import 'inbox_provider.dart';
import '../../core/services/websocket_service.dart';
import '../../core/services/message_cache_service.dart';
import '../../core/services/persistent_cache_service.dart';
import '../../core/services/sound_service.dart';
import '../../core/errors/failures.dart';

/// State for conversation detail
enum ConversationState { initial, loading, loaded, error, loadingMore }

/// Provider for managing conversation details
/// Now supports caching multiple conversations in memory for instant switching
class ConversationDetailProvider extends ChangeNotifier {
  final InboxRepository _inboxRepository;
  final WebSocketService _webSocketService;
  final MessageCacheService _messageCacheService;
  final PersistentCacheService _cache = PersistentCacheService();

  // WebSocket subscriptions
  StreamSubscription? _wsStateSubscription;
  StreamSubscription? _wsMessageSubscription;

  // LRU Cache for memory management - prevents unbounded growth
  static const int _maxCachedConversations = 10;
  final List<String> _conversationAccessOrder = [];

  // Active conversation
  String? _activeContact;

  // In-memory cache per contact
  final Map<String, List<InboxMessage>> _memoryMessages = {};
  final Map<String, ConversationState> _memoryStates = {};
  final Map<String, String?> _memoryCursors = {};
  final Map<String, bool> _memoryHasMore = {};
  final Map<String, String?> _memorySenderNames = {};
  final Map<String, String?> _memoryChannels = {};
  final Map<String, bool> _memoryTypingFields = {};
  final Map<String, bool> _memoryRecordingFields = {};
  final Map<String, bool> _memoryOnlineStatus = {};
  final Map<String, String?> _memoryLastSeen = {};
  final Map<String, Timer?> _typingTimers = {};
  final Map<String, Timer?> _recordingTimers = {};
  final Map<String, String> _memoryDrafts = {};
  List<Map<String, dynamic>> _whatsappTemplates = [];
  bool _isDisposed = false;

  // Search Mode State
  bool _isSearching = false;
  String _searchQuery = '';
  List<int> _searchResultIds = [];
  int _currentSearchIndex = -1;

  // Selection Mode State
  bool _isSelectionMode = false;
  final Set<int> _selectedMessageIds = {};

  // Undo Support for Delete Operations
  List<InboxMessage>? _lastDeletedMessages;
  Timer? _undoTimer;

  // Reply Context
  InboxMessage? _replyToMessage;

  // Editing State
  int? _editingMessageId;
  String? _editingMessageBody;

  Failure? _failure;

  // Error callback for UI to display error messages (e.g., edit failures)
  ValueChanged<String>? onError;

  // Throttled notification for high-frequency events
  Timer? _throttleTimer;
  bool _pendingNotification = false;

  // Rate limiting for typing indicators - prevents server flooding
  Timer? _typingDebounceTimer;
  bool _lastTypingStatusSent = false;

  // P1-2 FIX: Deduplication with timestamp tracking to prevent memory leak
  // Previous Set-based approach could grow unbounded during long conversations
  // Now using Map with timestamps for proper LRU eviction based on time
  final Map<int, DateTime> _recentlyProcessedMessageIds = {};
  static const int _maxRecentMessageIds = 100;
  static const Duration _messageIdTTL = Duration(minutes: 5);

  // P1-9: Periodic memory cleanup timer
  Timer? _memoryCleanupTimer;

  ConversationDetailProvider({
    InboxRepository? inboxRepository,
    WebSocketService? webSocketService,
    MessageCacheService? messageCacheService,
  }) : _inboxRepository = inboxRepository ?? InboxRepository(),
       _webSocketService = webSocketService ?? WebSocketService(),
       _messageCacheService = messageCacheService ?? MessageCacheService() {
    _initWebSocketListener();
    _initWebSocketStateListener();
    _messageCacheService.initialize();
    SoundService().init();
    // P1-9: Start periodic memory cleanup every 2 minutes
    _startMemoryCleanup();
  }

  void _startMemoryCleanup() {
    _memoryCleanupTimer?.cancel();
    _memoryCleanupTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _performMemoryCleanup();
    });
  }

  void _performMemoryCleanup() {
    final now = DateTime.now();

    // Clean up old typing timers
    _typingTimers.removeWhere((contact, timer) {
      timer?.cancel();
      return true; // Remove all and recreate as needed
    });

    // Clean up old recording timers
    _recordingTimers.removeWhere((contact, timer) {
      timer?.cancel();
      return true;
    });

    // P1-2 FIX: Evict message IDs older than TTL instead of just size-based
    // This prevents memory leak during long conversations
    _recentlyProcessedMessageIds.removeWhere(
      (msgId, timestamp) => now.difference(timestamp) > _messageIdTTL,
    );

    // Also enforce size limit with proper LRU eviction
    if (_recentlyProcessedMessageIds.length > _maxRecentMessageIds) {
      // Sort by timestamp and remove oldest entries
      final sorted = _recentlyProcessedMessageIds.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      final toRemove = sorted
          .take(_maxRecentMessageIds ~/ 2)
          .map((e) => e.key)
          .toList();
      for (final id in toRemove) {
        _recentlyProcessedMessageIds.remove(id);
      }
    }

    // Evict conversations not accessed in 10 minutes
    // (LRU already handles this, but this is a safety net)
    while (_conversationAccessOrder.length > _maxCachedConversations ~/ 2) {
      final oldest = _conversationAccessOrder.first;
      _conversationAccessOrder.removeAt(0);
      _evictConversation(oldest);
    }
  }

  void _evictConversation(String contact) {
    _memoryMessages.remove(contact);
    _memoryStates.remove(contact);
    _memoryCursors.remove(contact);
    _memoryHasMore.remove(contact);
    _memorySenderNames.remove(contact);
    _memoryChannels.remove(contact);
    _memoryTypingFields.remove(contact);
    _memoryRecordingFields.remove(contact);
    _memoryOnlineStatus.remove(contact);
    _memoryLastSeen.remove(contact);
    _memoryDrafts.remove(contact);
    _typingTimers[contact]?.cancel();
    _typingTimers.remove(contact);
    _recordingTimers[contact]?.cancel();
    _recordingTimers.remove(contact);
  }

  void _throttledNotify() {
    if (_throttleTimer?.isActive ?? false) {
      _pendingNotification = true;
      return;
    }

    notifyListeners();
    _pendingNotification = false;

    _throttleTimer = Timer(const Duration(milliseconds: 60), () {
      if (_pendingNotification && !_isDisposed) {
        _throttledNotify();
      }
    });
  }

  // Getters for the ACTIVE conversation
  ConversationState get state {
    if (_activeContact == null) return ConversationState.initial;
    return _memoryStates[_activeContact] ?? ConversationState.initial;
  }

  List<InboxMessage> get messages {
    if (_activeContact == null) return [];
    // P1-7 FIX: Update access order when messages are accessed
    // This ensures LRU eviction tracks actual usage, not just loading
    if (_memoryMessages.containsKey(_activeContact!)) {
      _conversationAccessOrder.remove(_activeContact!);
      _conversationAccessOrder.add(_activeContact!);
    }
    return _memoryMessages[_activeContact] ?? [];
  }

  String? get senderContact => _activeContact;

  String? get senderName {
    if (_activeContact == null) return null;
    return _memorySenderNames[_activeContact];
  }

  Failure? get failure => _failure;

  bool get hasMore {
    if (_activeContact == null) return false;
    return _memoryHasMore[_activeContact] ?? false;
  }

  bool get isPeerTyping {
    if (_activeContact == null) return false;
    return _memoryTypingFields[_activeContact] ?? false;
  }

  bool get isPeerRecording {
    if (_activeContact == null) return false;
    return _memoryRecordingFields[_activeContact] ?? false;
  }

  bool get isPeerOnline {
    if (_activeContact == null) return false;
    return _memoryOnlineStatus[_activeContact] ?? false;
  }

  String? get peerLastSeen {
    if (_activeContact == null) return null;
    return _memoryLastSeen[_activeContact];
  }

  bool get isLocalUserOnline => _webSocketService.isConnected;

  String? get activeChannel {
    if (_activeContact == null) return null;
    return _memoryChannels[_activeContact];
  }

  InboxMessage? get replyToMessage => _replyToMessage;

  // Editing State Getters
  int? get editingMessageId => _editingMessageId;
  String? get editingMessageBody => _editingMessageBody;
  bool get isEditing => _editingMessageId != null;

  // Search Mode Getters
  bool get isSearching => _isSearching;
  String get searchQuery => _searchQuery;
  List<int> get searchResultIds => _searchResultIds;
  int get currentSearchIndex => _currentSearchIndex;
  int get totalSearchResults => _searchResultIds.length;
  int? get currentSearchResultId =>
      (_currentSearchIndex != -1 && _searchResultIds.isNotEmpty)
      ? _searchResultIds[_currentSearchIndex]
      : null;

  // Selection Mode Getters
  bool get isSelectionMode => _isSelectionMode;
  Set<int> get selectedMessageIds => _selectedMessageIds;
  int get selectedCount => _selectedMessageIds.length;
  bool isMessageSelected(int id) => _selectedMessageIds.contains(id);

  bool get isLoading => state == ConversationState.loading;
  bool get isLoadingMore => state == ConversationState.loadingMore;

  List<Map<String, dynamic>> get whatsappTemplates => _whatsappTemplates;

  String getDraft(String contact) => _memoryDrafts[contact] ?? '';

  /// LRU Eviction Helper - keeps memory bounded
  void _evictOldConversationsIfNeeded(String activeContact) {
    if (_conversationAccessOrder.contains(activeContact)) {
      _conversationAccessOrder.remove(activeContact);
    }
    _conversationAccessOrder.add(activeContact);

    while (_conversationAccessOrder.length > _maxCachedConversations) {
      final oldest = _conversationAccessOrder.removeAt(0);
      if (oldest != activeContact) {
        _memoryMessages.remove(oldest);
        _memoryStates.remove(oldest);
        _memoryCursors.remove(oldest);
        _memoryHasMore.remove(oldest);
        _memorySenderNames.remove(oldest);
        _memoryChannels.remove(oldest);
        _memoryTypingFields.remove(oldest);
        _memoryRecordingFields.remove(oldest);
        _memoryOnlineStatus.remove(oldest);
        _memoryLastSeen.remove(oldest);
        _memoryDrafts.remove(oldest);
        _typingTimers[oldest]?.cancel();
        _typingTimers.remove(oldest);
        _recordingTimers[oldest]?.cancel();
        _recordingTimers.remove(oldest);
      }
    }
  }

  /// P1-2 FIX: Add message ID to recently processed set with timestamp
  /// This enables proper TTL-based eviction to prevent memory leaks
  void _trackProcessedMessageId(int messageId) {
    // P1-2 FIX: Remove oldest entries if at capacity (LRU eviction)
    if (_recentlyProcessedMessageIds.length >= _maxRecentMessageIds) {
      // Sort by timestamp and remove oldest
      final sorted = _recentlyProcessedMessageIds.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      _recentlyProcessedMessageIds.remove(sorted.first.key);
    }
    // Add with current timestamp for TTL-based cleanup
    _recentlyProcessedMessageIds[messageId] = DateTime.now();
  }

  /// P1-2 FIX: Check if message was recently processed (deduplication)
  bool _isMessageRecentlyProcessed(int messageId) {
    return _recentlyProcessedMessageIds.containsKey(messageId);
  }

  /// Get the latest message for active chat
  InboxMessage? get latestMessage {
    try {
      return messages.first;
    } catch (e) {
      return null;
    }
  }

  /// Load conversation detail
  /// Now includes LRU memory management to prevent unbounded growth
  /// P1-7 FIX: Added access order tracking for proper LRU eviction
  Future<void> loadConversation(
    String senderContact, {
    String? senderName,
    String? channel,
    String? lastSeenAt,
    bool isOnline = false,
    bool fresh = true,
  }) async {
    // FIX: Clean up timers for previous contact before switching
    final previousContact = _activeContact;
    if (previousContact != null && previousContact != senderContact) {
      _typingTimers[previousContact]?.cancel();
      _typingTimers.remove(previousContact);
      _recordingTimers[previousContact]?.cancel();
      _recordingTimers.remove(previousContact);
    }

    // P1-7 FIX: Update access order for LRU tracking
    // This ensures we track which conversations are actively being used
    _conversationAccessOrder.remove(senderContact);
    _conversationAccessOrder.add(senderContact);

    // Evict old conversations if we're at capacity
    _evictOldConversationsIfNeeded(senderContact);

    // Reset selection when switching conversations
    _isSelectionMode = false;
    _selectedMessageIds.clear();

    // 1. Switch context IMMEDIATELY
    _activeContact = senderContact;
    if (senderName != null) {
      _memorySenderNames[senderContact] = senderName;
    }
    if (channel != null) {
      _memoryChannels[senderContact] = channel;
    }

    // Initialize presence: always start with offline to avoid stale "متصل الآن" flash.
    // The fresh API response (below) will set the real online status.
    if (lastSeenAt != null) {
      _memoryLastSeen[senderContact] = lastSeenAt;
    }
    if (!_memoryOnlineStatus.containsKey(senderContact)) {
      _memoryOnlineStatus[senderContact] = false;
    }

    // If not in memory yet, it's initial/loading
    if (!_memoryMessages.containsKey(senderContact)) {
      _memoryStates[senderContact] = ConversationState.loading;
    }

    // Always notify to ensure UI reflects the potentially new _activeContact immediately
    notifyListeners();

    if (fresh) {
      _failure = null;

      // 2. Load from Disk Cache (Unified Persistent Cache)
      try {
        final accountHash = await _inboxRepository.apiClient
            .getAccountCacheHash();
        final cachedRaw = await _cache.get<Map<String, dynamic>>(
          PersistentCacheService.boxInbox,
          '${accountHash}_messages_$senderContact',
        );
        if (cachedRaw != null && cachedRaw['messages'] != null) {
          final cachedMessages = (cachedRaw['messages'] as List)
              .map((m) => InboxMessage.fromJson(m as Map<String, dynamic>))
              .toList();

          _memoryMessages[senderContact] = cachedMessages;
          _memoryStates[senderContact] = ConversationState.loaded;

          if (_activeContact == senderContact) {
            notifyListeners();
          }
        }
      } catch (e) {
        debugPrint('Cache read error for $senderContact: $e');
      }

      try {
        final response = await _inboxRepository.getConversationMessagesCursor(
          senderContact,
          limit: 30,
        );

        final freshMessages = response.messages;

        // P2-15 FIX: Preserve outgoing messages that might not be returned by the API
        // This handles cases where the backend doesn't return outbox messages correctly
        // FIX: Include ALL outgoing messages (both positive and negative IDs for optimistic messages)
        final currentMessages = _memoryMessages[senderContact] ?? [];
        final outgoingMessages = currentMessages
            .where((m) => m.direction == 'outgoing')
            .toList();

        // FIX: Also load unsynced messages from local database
        List<InboxMessage> localUnsyncedMessages = [];
        try {
          localUnsyncedMessages = await _inboxRepository.getUnsyncedOutgoingMessages(senderContact);
        } catch (e) {
          debugPrint('Error loading unsynced messages: $e');
        }

        // Merge fresh messages with local outgoing messages
        // Use a map to avoid duplicates (key by message ID)
        final mergedMessagesMap = <int, InboxMessage>{};

        // Add all fresh messages from API
        for (final msg in freshMessages) {
          mergedMessagesMap[msg.id] = msg;
        }

        // Add in-memory outgoing messages that aren't in the fresh list
        // For optimistic messages (negative IDs), check if we have a synced version
        for (final msg in outgoingMessages) {
          if (msg.id < 0) {
            // Optimistic message - check if we have a synced version by matching:
            // 1. outboxId (if available)
            // 2. body + timestamp (fallback)
            bool alreadySynced = false;
            
            // Check by outboxId first (most reliable)
            if (msg.outboxId != null) {
              alreadySynced = freshMessages.any((m) => m.outboxId == msg.outboxId);
            }
            
            // If not found by outboxId, check by body + similar timestamp
            if (!alreadySynced) {
              alreadySynced = freshMessages.any((m) {
                if (m.body != msg.body) return false;
                // Check if timestamps are within 5 seconds (optimistic was just replaced by synced)
                try {
                  final msgTime = DateTime.parse(msg.createdAt);
                  final freshTime = DateTime.parse(m.createdAt);
                  return freshTime.difference(msgTime).inSeconds.abs() < 5;
                } catch (e) {
                  return false;
                }
              });
            }
            
            // Only add optimistic message if no synced version exists
            if (!alreadySynced) {
              mergedMessagesMap[msg.id] = msg;
            }
          } else {
            // Regular positive ID message
            if (!mergedMessagesMap.containsKey(msg.id)) {
              mergedMessagesMap[msg.id] = msg;
            }
          }
        }

        // Add local unsynced messages from database (not in memory)
        for (final msg in localUnsyncedMessages) {
          // Check if already in merged map (from memory or API)
          final alreadyExists = mergedMessagesMap.values.any((m) {
            // Match by body + timestamp (since unsynced messages don't have remote_id yet)
            if (m.body != msg.body) return false;
            try {
              final mTime = DateTime.parse(m.createdAt);
              final msgTime = DateTime.parse(msg.createdAt);
              return mTime.difference(msgTime).inSeconds.abs() < 2;
            } catch (e) {
              return false;
            }
          });
          
          if (!alreadyExists) {
            mergedMessagesMap[msg.id] = msg;
          }
        }
        
        // Convert back to list and sort by created_at
        final mergedMessages = mergedMessagesMap.values.toList();
        mergedMessages.sort((a, b) {
          // Parse ISO 8601 strings to DateTime for comparison
          DateTime aTime, bTime;
          try {
            aTime = DateTime.parse(a.createdAt);
            bTime = DateTime.parse(b.createdAt);
          } catch (e) {
            // Fallback to string comparison if parsing fails
            return b.createdAt.compareTo(a.createdAt);
          }
          return bTime.millisecondsSinceEpoch.compareTo(aTime.millisecondsSinceEpoch); // DESC order (newest first)
        });

        // Update Memory
        _memoryMessages[senderContact] = mergedMessages;
        _memoryCursors[senderContact] = response.nextCursor;
        _memoryHasMore[senderContact] = response.hasMore;
        _memoryStates[senderContact] = ConversationState.loaded;

        // Sync presence from fresh API response
        _memoryOnlineStatus[senderContact] = response.isOnline;
        if (response.lastSeenAt != null) {
          _memoryLastSeen[senderContact] = response.lastSeenAt;
        }

        // Ensure channel is updated if any messages returned
        if (freshMessages.isNotEmpty) {
          _memoryChannels[senderContact] = freshMessages.first.channel;
        }

        // Update Unified Persistent Cache with merged messages (includes unsynced outgoing)
        final accountHash = await _inboxRepository.apiClient
            .getAccountCacheHash();
        await _cache.put(
          PersistentCacheService.boxInbox,
          '${accountHash}_messages_$senderContact',
          {
            'messages': mergedMessages.map((m) => m.toJson()).toList(),
            'cached_at': DateTime.now().toIso8601String(),
          },
        );

        // Mark as read
        _inboxRepository.markConversationRead(senderContact).catchError((e) {
          debugPrint('Error marking as read: $e');
        });

        // 3. Load Draft for this contact (P2-6: Synced from server)
        final savedDraft = await _cache.get<String>(
          PersistentCacheService.boxInbox,
          '${accountHash}_draft_$senderContact',
        );
        if (savedDraft != null && savedDraft.isNotEmpty) {
          _memoryDrafts[senderContact] = savedDraft;
        } else {
          // P2-6: Try loading from server if not in local cache
          final serverDraft = await _inboxRepository.getDraft(senderContact);
          if (serverDraft != null && serverDraft.isNotEmpty) {
            _memoryDrafts[senderContact] = serverDraft;
            // Cache it locally
            await _cache.put(
              PersistentCacheService.boxInbox,
              '${accountHash}_draft_$senderContact',
              serverDraft,
            );
          }
        }
      } catch (e) {
        // Categorize errors for better user feedback
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('socket') ||
            errorStr.contains('network') ||
            errorStr.contains('connection') ||
            errorStr.contains('timeout')) {
          _failure = const NetworkFailure('لا يوجد اتصال بالإنترنت');
        } else if (errorStr.contains('unauthorized') ||
            errorStr.contains('401') ||
            errorStr.contains('forbidden')) {
          _failure = const AuthFailure('انتهت جلسة المستخدم');
        } else {
          _failure = const ServerFailure('فشل تحميل المحادثة');
        }

        // Only show error state if we don't have cached messages
        if ((_memoryMessages[senderContact]?.isEmpty ?? true)) {
          _memoryStates[senderContact] = ConversationState.error;
        }
      } finally {
        // Ensure we are not stuck in loading state even on API failure
        if (_activeContact == senderContact) {
          if (_memoryStates[senderContact] == ConversationState.loading) {
            _memoryStates[senderContact] = ConversationState.loaded;
          }
          notifyListeners();
        }
      }
    }
  }

  /// Load older messages (pagination)
  Future<void> loadMoreMessages() async {
    final contact = _activeContact;
    if (contact == null ||
        !hasMore ||
        _memoryCursors[contact] == null ||
        isLoadingMore) {
      return;
    }

    _memoryStates[contact] = ConversationState.loadingMore;
    notifyListeners();

    try {
      final response = await _inboxRepository.getConversationMessagesCursor(
        contact,
        cursor: _memoryCursors[contact],
        limit: 25,
        direction: 'older',
      );

      final current = _memoryMessages[contact] ?? [];
      _memoryMessages[contact] = [...current, ...response.messages];
      _memoryCursors[contact] = response.nextCursor;
      _memoryHasMore[contact] = response.hasMore;
      _memoryStates[contact] = ConversationState.loaded;
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('socket') ||
          errorStr.contains('network') ||
          errorStr.contains('connection')) {
        _failure = const NetworkFailure('لا يوجد اتصال بالإنترنت');
      } else {
        _failure = const ServerFailure('فشل تحميل المزيد من الرسائل');
      }
    }

    if (_activeContact == contact) {
      notifyListeners();
    }
  }

  /// Add optimistic message (Called by MessageInputProvider)
  void addOptimisticMessage(InboxMessage message) {
    if (_activeContact == null) return;
    final current = _memoryMessages[_activeContact!] ?? [];
    _memoryMessages[_activeContact!] = [message, ...current];

    // Clear reply context after sending
    _replyToMessage = null;

    // Play outgoing message sound
    SoundService().playMessageOutgoing();

    notifyListeners();
  }

  /// Manage reply state
  void setReplyMessage(InboxMessage? message) {
    _replyToMessage = message;
    notifyListeners();
  }

  void cancelReply() {
    _replyToMessage = null;
    notifyListeners();
  }

  /// Mark message as failed
  void markMessageFailed(int tempId) {
    if (_activeContact == null) return;
    final contact = _activeContact!;
    final current = _memoryMessages[contact] ?? [];

    _memoryMessages[contact] = current.map((msg) {
      if (msg.id == tempId) {
        return msg.copyWithSendStatus(MessageSendStatus.failed);
      }
      return msg;
    }).toList();
    notifyListeners();
  }

  /// Update message upload progress
  void updateMessageUploadProgress(
    int messageId,
    double progress,
    int uploadedBytes,
    int totalBytes,
  ) {
    if (_activeContact == null) return;
    final contact = _activeContact!;
    final current = _memoryMessages[contact] ?? [];

    final index = current.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      final updatedList = List<InboxMessage>.from(current);
      updatedList[index] = updatedList[index].copyWith(
        uploadProgress: progress,
        uploadedBytes: uploadedBytes,
        totalUploadBytes: totalBytes,
        isUploading: progress < 1.0,
      );
      _memoryMessages[contact] = updatedList;
      notifyListeners();
    }
  }

  /// Update message with compressed attachments (after background compression)
  void updateMessageAttachments(
    int messageId,
    List<Map<String, dynamic>> attachments,
  ) {
    if (_activeContact == null) return;
    final contact = _activeContact!;
    final current = _memoryMessages[contact] ?? [];

    final index = current.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      final updatedList = List<InboxMessage>.from(current);
      updatedList[index] = updatedList[index].copyWith(
        attachments: attachments,
      );
      _memoryMessages[contact] = updatedList;
      notifyListeners();
    }
  }

  /// Confirm message sent (Swap optimistic ID with real ID and update status)
  void confirmMessageSent(
    int tempId,
    int realId,
    String status, {
    int? outboxId,
  }) {
    if (_activeContact == null) return;
    final contact = _activeContact!;
    final current = _memoryMessages[contact] ?? [];

    // The status we want to persist MUST be 'sent' if we have an active connection
    const targetStatus = 'sent';
    const targetSendStatus = MessageSendStatus.sent;
    // CRITICAL FIX: Also set deliveryStatus for Almudeer channel to show check marks
    const targetDeliveryStatus = 'sent';

    // Safety check: if realId already exists in list (from socket), ensure it's marked as sent and remove tempId
    final realIndex = current.indexWhere((m) => m.id == realId);
    if (realIndex != -1) {
      final updatedList = current.where((m) => m.id != tempId).map((m) {
        if (m.id == realId) {
          return m.copyWith(
            status: targetStatus,
            deliveryStatus: targetDeliveryStatus,
            sendStatus: targetSendStatus,
            outboxId: outboxId,
          );
        }
        return m;
      }).toList();
      _memoryMessages[contact] = updatedList;
      notifyListeners();
      // FIX: Update persistent cache to prevent stale state on chat reopen
      _updatePersistentCache(contact);
      return;
    }

    final index = current.indexWhere((m) => m.id == tempId);
    if (index != -1) {
      final updatedList = List<InboxMessage>.from(current);
      updatedList[index] = updatedList[index].copyWith(
        id: realId,
        status: targetStatus,
        deliveryStatus: targetDeliveryStatus,
        sendStatus: targetSendStatus,
        outboxId: outboxId,
      );
      _memoryMessages[contact] = updatedList;
      notifyListeners();
      // FIX: Update persistent cache to prevent stale state on chat reopen
      _updatePersistentCache(contact);
    }
  }

  /// Update persistent cache for a contact (called after message mutations)
  Future<void> _updatePersistentCache(String contact) async {
    try {
      final accountHash = await _inboxRepository.apiClient
          .getAccountCacheHash();
      final messages = _memoryMessages[contact] ?? [];
      await _cache.put(
        PersistentCacheService.boxInbox,
        '${accountHash}_messages_$contact',
        {
          'messages': messages.map((m) => m.toJson()).toList(),
          'cached_at': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      debugPrint('Error updating persistent cache for $contact: $e');
    }
  }

  // Edit & Delete
  Future<bool> editMessage(int messageId, String newBody) async {
    if (_activeContact == null) return false;
    final contact = _activeContact!;
    final currentList = _memoryMessages[contact] ?? [];
    final index = currentList.indexWhere((m) => m.id == messageId);
    if (index == -1) return false;

    // Check if message can be edited (channel rules, time window, etc.)
    final message = currentList[index];
    if (!message.canEdit) {
      debugPrint(
        'Message cannot be edited (channel restrictions or time window exceeded)',
      );
      return false;
    }

    // Save original values for rollback (not the entire message reference)
    final originalBody = message.body;
    final originalIsEdited = message.isEdited;
    final originalEditedAt = message.editedAt;

    try {
      // Optimistic Update
      final updatedList = List<InboxMessage>.from(currentList);
      updatedList[index] = updatedList[index].copyWith(
        body: newBody,
        isEdited: true,
        editedAt: DateTime.now().toIso8601String(),
      );
      _memoryMessages[contact] = updatedList;
      notifyListeners();
      // FIX: Update persistent cache immediately after edit
      _updatePersistentCache(contact);

      // API Call (Backgrounded for instant responsiveness)
      _inboxRepository.editMessage(messageId, newBody).catchError((e) {
        debugPrint('Failed to edit message (background): $e');

        // Notify UI of the error so user knows the edit didn't sync
        onError?.call('فشل مزامنة التعديل: ${e.toString()}');

        // Rollback on background failure - use current list state to avoid race condition
        final currentListOnError = _memoryMessages[contact] ?? [];
        final rollbackIndex = currentListOnError.indexWhere(
          (m) => m.id == messageId,
        );
        if (rollbackIndex != -1) {
          final rolledBackList = List<InboxMessage>.from(currentListOnError);
          // Only revert the specific fields that were changed, preserving other modifications
          rolledBackList[rollbackIndex] = rolledBackList[rollbackIndex]
              .copyWith(
                body: originalBody,
                isEdited: originalIsEdited,
                editedAt: originalEditedAt,
              );
          _memoryMessages[contact] = rolledBackList;
          notifyListeners();
          // Rollback cache on failure
          _updatePersistentCache(contact);
        }
        return <String, dynamic>{};
      });

      return true;
    } catch (e) {
      debugPrint('Failed to edit message: $e');

      // Rollback - use current list state to avoid race condition
      final currentListOnError = _memoryMessages[contact] ?? [];
      final rollbackIndex = currentListOnError.indexWhere(
        (m) => m.id == messageId,
      );
      if (rollbackIndex != -1) {
        final rolledBackList = List<InboxMessage>.from(currentListOnError);
        // Only revert the specific fields that were changed
        rolledBackList[rollbackIndex] = rolledBackList[rollbackIndex].copyWith(
          body: originalBody,
          isEdited: originalIsEdited,
          editedAt: originalEditedAt,
        );
        _memoryMessages[contact] = rolledBackList;
        notifyListeners();
        // Rollback cache on failure
        _updatePersistentCache(contact);
      }
      return false;
    }
  }

  Future<bool> deleteMessage(int messageId) async {
    if (_activeContact == null) return false;

    final contact = _activeContact!;
    final current = _memoryMessages[contact] ?? [];
    final index = current.indexWhere((m) => m.id == messageId);

    if (index == -1) return false;

    // Capture original message for rollback
    final originalMessage = current[index];

    // 1. Optimistic Update: Remove from UI immediately
    final updatedList = List<InboxMessage>.from(current);
    updatedList.removeAt(index);
    _memoryMessages[contact] = updatedList;

    // Play delete sound
    SoundService().playActionDeleted();

    notifyListeners();
    // FIX: Update persistent cache immediately after delete
    _updatePersistentCache(contact);

    // 2. Background API Call
    _inboxRepository
        .deleteMessage(messageId, isOutgoing: originalMessage.isOutgoing)
        .then((_) {
          // Success: Do nothing
        })
        .catchError((e) {
          // Failure: Rollback
          debugPrint('Delete failed, rolling back: $e');
          final rolledBackList = _memoryMessages[contact];
          if (rolledBackList != null) {
            final newList = List<InboxMessage>.from(rolledBackList);
            // Re-insert. Try to preserve order by index if list serves as valid reference
            if (index <= newList.length) {
              newList.insert(index, originalMessage);
            } else {
              newList.add(originalMessage);
            }
            _memoryMessages[contact] = newList;
            notifyListeners();
            // Rollback cache on failure
            _updatePersistentCache(contact);
          }
        });

    return true;
  }

  Future<bool> clearActiveChatMessages() async {
    final contact = _activeContact;
    if (contact == null) return false;

    // Snapshot for rollback
    final oldMessages = _memoryMessages[contact];
    final oldCursor = _memoryCursors[contact];
    final oldHasMore = _memoryHasMore[contact];

    try {
      // 1. Optimistic UI Update: Clear memory instantly
      _memoryMessages[contact] = [];
      _memoryCursors[contact] = null;
      _memoryHasMore[contact] = false;

      // Play delete sound
      SoundService().playActionDeleted();

      notifyListeners();

      // 2. Perform remote clear
      await _inboxRepository.clearConversationMessages(contact);

      // 3. Clear from all device cache sources explicitly to prevent reappearance
      final accountHash = await _inboxRepository.apiClient
          .getAccountCacheHash();
      await _cache.delete(
        PersistentCacheService.boxInbox,
        '${accountHash}_messages_$contact',
      );

      // Also clear secondary cache service just in case
      await _messageCacheService.clearConversationCache(contact);

      return true;
    } catch (e) {
      debugPrint('Clear chat failed: $e');

      // Rollback UI
      _memoryMessages[contact] = oldMessages ?? [];
      _memoryCursors[contact] = oldCursor;
      _memoryHasMore[contact] = oldHasMore ?? false;
      notifyListeners();

      return false;
    }
  }

  // ============ Draft Logic (P2-6: Synced Across Devices) ============

  Future<void> saveDraft(String text) async {
    if (_activeContact == null) return;
    final contact = _activeContact!;

    if (text.trim().isEmpty) {
      _memoryDrafts.remove(contact);
    } else {
      _memoryDrafts[contact] = text;
    }

    // Always save locally first (optimistic)
    try {
      final accountHash = await _inboxRepository.apiClient
          .getAccountCacheHash();
      if (text.trim().isEmpty) {
        await _cache.delete(
          PersistentCacheService.boxInbox,
          '${accountHash}_draft_$contact',
        );
      } else {
        await _cache.put(
          PersistentCacheService.boxInbox,
          '${accountHash}_draft_$contact',
          text,
        );
      }
    } catch (e) {
      debugPrint('Error saving draft to local cache: $e');
      // Continue anyway - local cache failure shouldn't block server sync
    }

    // FIX: Retry server sync up to 3 times with exponential backoff
    // This ensures drafts sync across devices even on transient network issues
    int retries = 0;
    const maxRetries = 3;

    while (retries < maxRetries) {
      try {
        await _inboxRepository.saveDraft(contact, text);
        break; // Success, exit retry loop
      } catch (e) {
        retries++;
        if (retries >= maxRetries) {
          debugPrint(
            'Error saving draft to server after $maxRetries attempts: $e',
          );
          // Draft is saved locally, server sync will happen on next attempt
          // Store a flag to indicate pending sync
          _memoryDrafts['${contact}_pending_sync'] = text;
        } else {
          // Wait with exponential backoff before retry
          await Future.delayed(Duration(milliseconds: 500 * retries));
        }
      }
    }
  }

  void clearDraft(String contact) {
    _memoryDrafts.remove(contact);
    _inboxRepository.apiClient.getAccountCacheHash().then((hash) {
      _cache.delete(PersistentCacheService.boxInbox, '${hash}_draft_$contact');
    });
  }

  // ============ WhatsApp Template Logic ============

  Future<void> fetchWhatsAppTemplates() async {
    if (_whatsappTemplates.isNotEmpty) return; // Only fetch once or when forced

    final templates = await _inboxRepository.getWhatsAppTemplates();
    _whatsappTemplates = templates;
    notifyListeners();
  }

  // ============ Selection Mode Logic ============

  void toggleSelectionMode(bool enabled) {
    if (_isSelectionMode == enabled) return;
    _isSelectionMode = enabled;
    if (!enabled) {
      _selectedMessageIds.clear();
    }
    notifyListeners();
  }

  void toggleMessageSelection(int id) {
    if (_selectedMessageIds.contains(id)) {
      _selectedMessageIds.remove(id);
      if (_selectedMessageIds.isEmpty) {
        _isSelectionMode = false;
      }
    } else {
      _selectedMessageIds.add(id);
      _isSelectionMode = true;
    }
    notifyListeners();
  }

  void selectAll() {
    if (_activeContact == null) return;
    final msgs = _memoryMessages[_activeContact!] ?? [];
    _selectedMessageIds.clear();
    for (var m in msgs) {
      if (!m.isDeleted) {
        _selectedMessageIds.add(m.id);
      }
    }
    _isSelectionMode = true;
    notifyListeners();
  }

  void clearSelection() {
    _selectedMessageIds.clear();
    _isSelectionMode = false;
    notifyListeners();
  }

  void exitSelectionMode() {
    clearSelection();
  }

  void selectAllMessages() {
    final currentMessages = messages;
    _selectedMessageIds.clear();
    for (final msg in currentMessages) {
      _selectedMessageIds.add(msg.id);
    }
    _isSelectionMode = true;
    notifyListeners();
  }

  List<InboxMessage> getSelectedMessages() {
    final currentMessages = messages;
    return currentMessages
        .where((m) => _selectedMessageIds.contains(m.id))
        .toList();
  }

  /// Copy selected messages to clipboard
  void copySelectedMessages() {
    final selectedMsgs = getSelectedMessages();
    if (selectedMsgs.isEmpty) return;

    // Combined text is prepared here but clipboard is handled in UI layer
    exitSelectionMode();
  }

  /// Forward selected messages to another conversation
  Future<void> forwardSelectedMessages() async {
    final selectedMsgs = getSelectedMessages();
    if (selectedMsgs.isEmpty) return;

    // Forward dialog is shown in UI layer with conversation picker
    // This will be handled by the UI layer
  }

  // ============ Bulk Actions ============

  Future<void> bulkDeleteMessages() async {
    final contact = _activeContact;
    if (contact == null || _selectedMessageIds.isEmpty) return;

    final idsToDelete = List<int>.from(_selectedMessageIds);
    final current = _memoryMessages[contact] ?? [];

    // Snapshot for possible partial rollback if needed (though we'll do best effort)
    final originalMessages = List<InboxMessage>.from(current);

    // Store deleted messages for undo support
    _lastDeletedMessages = originalMessages
        .where((m) => idsToDelete.contains(m.id))
        .toList();

    // 1. Optimistic Update
    _memoryMessages[contact] = current
        .where((m) => !idsToDelete.contains(m.id))
        .toList();
    _selectedMessageIds.clear();
    _isSelectionMode = false;

    // Play delete sound
    SoundService().playActionDeleted();

    notifyListeners();
    // FIX: Update persistent cache immediately after bulk delete
    _updatePersistentCache(contact);

    // 2. Background Deletion
    try {
      // Find which messages are outgoing for the API
      final messagesToDelete = originalMessages
          .where((m) => idsToDelete.contains(m.id))
          .toList();

      await Future.wait(
        messagesToDelete.map(
          (m) => _inboxRepository.deleteMessage(m.id, isOutgoing: m.isOutgoing),
        ),
      );

      // Clear undo stack after successful deletion
      _lastDeletedMessages = null;
    } catch (e) {
      debugPrint('Bulk delete failed: $e');
      // For simplicity, we might not roll back everything but a refresh is better
      loadConversation(contact, fresh: true);
    }
  }

  /// Undo last bulk delete operation
  bool undoLastBulkDelete() {
    if (_lastDeletedMessages == null || _activeContact == null) {
      return false;
    }

    final contact = _activeContact!;
    final current = _memoryMessages[contact] ?? [];

    // Restore deleted messages
    _memoryMessages[contact] = [...current, ..._lastDeletedMessages!];
    _lastDeletedMessages = null;

    notifyListeners();
    // FIX: Update persistent cache after undo
    _updatePersistentCache(contact);
    return true;
  }

  /// Clear undo stack
  void clearUndoStack() {
    _lastDeletedMessages = null;
    _undoTimer?.cancel();
  }

  /// Share/Forward messages to another conversation
  Future<void> shareMessages(
    List<int> messageIds,
    Conversation targetConversation,
  ) async {
    if (messageIds.isEmpty) return;

    final contact = _activeContact;
    if (contact == null) return;

    final allMessages = _memoryMessages[contact] ?? [];
    final selectedMsgs = allMessages
        .where((m) => messageIds.contains(m.id))
        .toList();

    // Sort by ID to maintain order (assuming ID follows creation)
    selectedMsgs.sort((a, b) => a.id.compareTo(b.id));

    final targetContact = targetConversation.senderContact;
    if (targetContact == null) return;

    // Exit selection mode early to improve responsiveness
    clearSelection();

    // Use Future.wait to send messages concurrently and add optimistic UI
    final sendFutures = selectedMsgs.map((msg) async {
      try {
        final nowIso = DateTime.now().toIso8601String();
        // Create an optimistic message to show immediately
        final optimisticMsg = InboxMessage(
          id:
              -(msg.id +
                  DateTime.now().millisecondsSinceEpoch %
                      100000), // Random temp ID
          channel: targetConversation.channel,
          body: msg.body,
          senderContact: targetContact,
          direction: 'outgoing',
          status: 'sending',
          timestamp: nowIso,
          createdAt: nowIso, // REQUIRED
          isForwarded: true,
          attachments: msg.attachments,
          sendStatus: MessageSendStatus.sending,
        );

        // Add to UI immediately if target is current chat
        if (targetContact == _activeContact) {
          addOptimisticMessage(optimisticMsg);
        }

        await _inboxRepository.sendMessage(
          targetContact,
          message: msg.body,
          channel: targetConversation.channel,
          isForwarded: true,
          attachments: msg.attachments,
        );
      } catch (e) {
        debugPrint('Error forwarding message ${msg.id}: $e');
      }
    });

    // Send all messages in parallel
    await Future.wait(sendFutures);
  }

  void clear() {
    // FIX: Cancel all timers for the active contact before clearing to prevent memory leaks
    if (_activeContact != null) {
      _typingTimers[_activeContact]?.cancel();
      _typingTimers.remove(_activeContact);
      _recordingTimers[_activeContact]?.cancel();
      _recordingTimers.remove(_activeContact);
    }
    _activeContact = null;
    // Defer notification to avoid 'widget tree locked' errors if called during dispose
    Future.microtask(() => notifyListeners());
  }

  // ============ Editing Logic ============

  void startEditingMessage(InboxMessage message) {
    _editingMessageId = message.id;
    _editingMessageBody = message.body;
    _replyToMessage = null; // Clear reply if editing
    notifyListeners();
  }

  void cancelEditing() {
    _editingMessageId = null;
    _editingMessageBody = null;
    notifyListeners();
  }

  Future<bool> saveEditedMessage(
    String newBody,
    InboxProvider inboxProvider,
  ) async {
    final id = _editingMessageId;
    if (id == null) return false;

    // Validate: Prevent empty body
    if (newBody.trim().isEmpty) {
      cancelEditing();
      return false;
    }

    // Perform optimistic update on messages list
    final success = await editMessage(id, newBody);

    // If successful (optimistic) AND active contact is set
    if (success && _activeContact != null) {
      // Check if the edited message is the LATEST one in our memory list
      // The list is typically reversed (index 0 is newest)
      final msgs = _memoryMessages[_activeContact!] ?? [];
      if (msgs.isNotEmpty) {
        final latestMessage = msgs.first;
        if (latestMessage.id == id) {
          // Only then do we update the inbox snippet to reflect the new body
          inboxProvider.updateMessageEdit(
            senderContact: _activeContact!,
            body: newBody,
          );
        }
      }

      // FIX: Clear draft for this contact - edited messages should not be saved as drafts
      // When user edits, they're modifying an existing sent message, not creating a new draft
      _memoryDrafts.remove(_activeContact!);
      try {
        final accountHash = await _inboxRepository.apiClient
            .getAccountCacheHash();
        await _cache.delete(
          PersistentCacheService.boxInbox,
          '${accountHash}_draft_$_activeContact!',
        );
      } catch (e) {
        debugPrint('Error clearing draft after edit: $e');
      }
    }

    cancelEditing();
    return success;
  }

  /// Fully reset state (for account switching)
  void reset() {
    _activeContact = null;
    _memoryMessages.clear();
    _memoryStates.clear();
    _memoryCursors.clear();
    _memoryHasMore.clear();
    _memorySenderNames.clear();
    _failure = null;
    notifyListeners();
  }

  void clearAllCache() {
    _memoryMessages.clear();
    _memoryStates.clear();
    _activeContact = null;
    notifyListeners();
  }

  // Socket
  void _initWebSocketStateListener() {
    _wsStateSubscription?.cancel();
    _wsStateSubscription = _webSocketService.stateStream.listen((state) {
      notifyListeners();
    });
  }

  void _initWebSocketListener() {
    _wsMessageSubscription?.cancel();
    // FIX P2-4: Add error boundary for WebSocket events to prevent crashes
    _wsMessageSubscription = _webSocketService.stream.listen((event) async {
      try {
        await _handleWebSocketEvent(event);
      } catch (e, stackTrace) {
        // Log error but don't crash the listener
        debugPrint(
          '[ConversationDetailProvider] WebSocket event handler error: $e',
        );
        debugPrint('Stack trace: $stackTrace');
        debugPrint('Event data: $event');
      }
    });
  }

  /// FIX P2-4: Extracted WebSocket event handling with error boundaries
  Future<void> _handleWebSocketEvent(Map<String, dynamic> event) async {
    final type = event['event'];
    final data = event['data'] as Map<String, dynamic>? ?? {};

    // For message_edited events, use sender_contact (the original message sender)
    // For other events, use sender_contact or recipient_contact as appropriate
    final contact = data['sender_contact'] as String?;

    if (contact == null) return;

    try {
      if (type == 'new_message') {
        final newMessage = InboxMessage.fromJson(data);

        // Deduplication: Skip if we recently processed this message ID
        // Prevents race conditions when socket events fire multiple times
        if (_isMessageRecentlyProcessed(newMessage.id)) {
          return;
        }
        _trackProcessedMessageId(newMessage.id);

        // Update memory if we have this contact in memory
        if (_memoryMessages.containsKey(contact)) {
          final current = _memoryMessages[contact] ?? [];

          // 1. Check if we already have it (to avoid duplicates with optimistic UI)
          final exists = current.any((m) => m.id == newMessage.id);
          if (!exists) {
            // 2. Handle race condition: Check if this is an OUTGOING message
            // that matches an existing optimistic message (temp negative ID)
            if (newMessage.isOutgoing) {
              // FIX: Use more robust matching - check channel + body + timestamp window
              // Parse timestamp from newMessage for matching
              final newMsgTimestamp = newMessage.timestamp != null
                  ? DateTime.tryParse(newMessage.timestamp!)
                  : null;

              int? bestMatchIndex;
              int bestMatchScore = 0;

              for (int i = 0; i < current.length; i++) {
                final m = current[i];
                if (m.id < 0 && m.body.trim() == newMessage.body.trim()) {
                  // Calculate match score based on additional factors
                  int score = 1; // Base score for body match

                  // Check channel match
                  if (m.channel == newMessage.channel) {
                    score += 2;
                  }

                  // Check timestamp window (within 5 seconds)
                  if (newMsgTimestamp != null && m.timestamp != null) {
                    final optTimestamp = DateTime.tryParse(m.timestamp!);
                    if (optTimestamp != null) {
                      final diff = newMsgTimestamp
                          .difference(optTimestamp)
                          .abs();
                      if (diff.inSeconds < 5) {
                        score += 3;
                      }
                    }
                  }

                  // Use outboxId if available for exact match
                  if (m.outboxId != null &&
                      newMessage.outboxId != null &&
                      m.outboxId == newMessage.outboxId) {
                    score += 10;
                  }

                  // Track best match
                  if (score > bestMatchScore) {
                    bestMatchScore = score;
                    bestMatchIndex = i;
                  }
                }
              }

              if (bestMatchIndex != null && bestMatchScore >= 3) {
                // Replace optimistic message with the real one from socket
                // Force 'sent' status to maintain the "instant sent" UX and avoid flickering to 'pending'
                final updatedList = List<InboxMessage>.from(current);
                updatedList[bestMatchIndex] = newMessage.copyWith(
                  status: 'sent',
                  sendStatus: MessageSendStatus.sent,
                );
                _memoryMessages[contact] = updatedList;
              } else {
                // Not found as optimistic, append normally (index 0 for reversed list)
                _memoryMessages[contact] = [newMessage, ...current];
              }
            } else {
              // Standard incoming message
              _memoryMessages[contact] = [newMessage, ...current];

              // Play incoming message sound
              SoundService().playMessageIncoming();
            }

            // 3. Update Disk Cache
            final accountHash = await _inboxRepository.apiClient
                .getAccountCacheHash();
            _cache
                .put(
                  PersistentCacheService.boxInbox,
                  '${accountHash}_messages_$contact',
                  {
                    'messages': _memoryMessages[contact]!
                        .map((m) => m.toJson())
                        .toList(),
                    'cached_at': DateTime.now().toIso8601String(),
                  },
                )
                .catchError((e) => debugPrint('Cache update error: $e'));

            // Persist to local SQLite DB for long-term consistency
            _inboxRepository
                .persistRemoteMessage(data)
                .catchError(
                  (e) => debugPrint('Error persisting remote message: $e'),
                );

            // 4. Notify if active
            if (_activeContact == contact) {
              _throttledNotify();
            }
          }
        }
      } else if (type == 'typing_indicator') {
        final isSelf = data['is_self'] as bool? ?? false;
        if (isSelf) return;

        final isTyping = data['is_typing'] as bool? ?? false;
        _memoryTypingFields[contact] = isTyping;

        // Auto-clear typing indicator after 10 seconds (matches server Redis TTL)
        // Prevents UI showing "ended" while server still thinks user is typing
        _typingTimers[contact]?.cancel();
        if (isTyping) {
          // Play typing sound only if it's a new indicator (not a repeat within the 10s window)
          if (!(_memoryTypingFields[contact] ?? false)) {
            SoundService().playTypingIndicator();
          }

          _typingTimers[contact] = Timer(const Duration(seconds: 10), () {
            _memoryTypingFields[contact] = false;
            if (_activeContact == contact) _throttledNotify();
          });
        }

        if (_activeContact == contact) _throttledNotify();
      } else if (type == 'recording_indicator') {
        final isSelf = data['is_self'] as bool? ?? false;
        if (isSelf) return;

        final isRecording = data['is_recording'] as bool? ?? false;
        _memoryRecordingFields[contact] = isRecording;

        // Auto-clear recording indicator after 15 seconds (matches server Redis TTL)
        _recordingTimers[contact]?.cancel();
        if (isRecording) {
          // Play recording sound
          SoundService().playRecordingIndicator();

          _recordingTimers[contact] = Timer(const Duration(seconds: 15), () {
            _memoryRecordingFields[contact] = false;
            if (_activeContact == contact) _throttledNotify();
          });
        }

        if (_activeContact == contact) _throttledNotify();
      } else if (type == 'presence_update') {
        final isSelf = data['is_self'] as bool? ?? false;
        if (!isSelf) {
          final isOnline = data['is_online'] as bool? ?? false;
          final lastSeen = data['last_seen'] as String?;
          _memoryOnlineStatus[contact] = isOnline;
          if (lastSeen != null) {
            _memoryLastSeen[contact] = lastSeen;
          }
          if (_activeContact == contact) _throttledNotify();
        }
      } else if (type == 'message_edited') {
        final msgId = data['message_id'];
        final newBody = data['new_body'];
        final senderContact = data['sender_contact'] as String?;
        final recipientContact = data['recipient_contact'] as String?;
        final editedAt = data['edited_at'] as String?;
        final forceRefresh = data['force_refresh'] as bool? ?? false;

        debugPrint(
          '[ConversationDetailProvider] Received message_edited event: msgId=$msgId, senderContact=$senderContact, recipientContact=$recipientContact, newBody=$newBody, forceRefresh=$forceRefresh',
        );

        // Validation: Ensure required fields are present
        if (msgId == null || newBody == null || newBody.isEmpty) {
          debugPrint(
            '[ConversationDetailProvider] Invalid message_edited event: missing required fields',
          );
          return;
        }

        // Validation: Verify edited_at timestamp is reasonable
        if (editedAt != null) {
          try {
            final editedTime = DateTime.parse(editedAt).toUtc();
            final now = DateTime.now().toUtc();
            // Reject if timestamp is in the future (with 5 second grace) or older than 30 days
            if (editedTime.isAfter(now.add(const Duration(seconds: 5))) ||
                editedTime.isBefore(now.subtract(const Duration(days: 30)))) {
              debugPrint(
                '[ConversationDetailProvider] Invalid edited_at timestamp: $editedAt',
              );
              return;
            }
          } catch (e) {
            debugPrint(
              '[ConversationDetailProvider] Failed to parse edited_at: $e',
            );
            return;
          }
        }

        // Determine which contact to update:
        // - If we're viewing the sender's conversation, use sender_contact
        // - If we're viewing the recipient's conversation, use recipient_contact
        // - The event is broadcast to both parties, so we update whichever matches _activeContact
        String? targetContact;
        if (_activeContact != null) {
          if (_activeContact == senderContact) {
            targetContact = senderContact;
          } else if (_activeContact == recipientContact) {
            targetContact = recipientContact;
          }
        }
        // Fallback to the original contact from outer scope if no match
        targetContact ??= contact;

        debugPrint(
          '[ConversationDetailProvider] Using targetContact=$targetContact for message update (activeContact=$_activeContact)',
        );

        if (_memoryMessages.containsKey(targetContact)) {
          final current = _memoryMessages[targetContact] ?? [];
          // Peer-to-peer sync: Recipients use 'alm_{outboxId}' as platformMessageId
          // Also check outboxId for direct matching on recipient side
          final idx = current.indexWhere(
            (m) =>
                m.id == msgId ||
                m.platformMessageId == 'alm_$msgId' ||
                m.outboxId == msgId,
          );
          debugPrint(
            '[ConversationDetailProvider] Found message at index=$idx in contact=$targetContact',
          );
          if (idx != -1) {
            final updatedList = List<InboxMessage>.from(current);
            updatedList[idx] = updatedList[idx].copyWith(
              body: newBody,
              isEdited: true,
              editedAt: editedAt,
            );
            _memoryMessages[targetContact] = updatedList;
            debugPrint(
              '[ConversationDetailProvider] Updated message body to: $newBody',
            );
            if (_activeContact == targetContact) _throttledNotify();

            // Persist to local SQLite DB
            _inboxRepository
                .applyRemoteMessageEdit(
                  msgId as int,
                  newBody as String,
                  editedAt,
                )
                .catchError(
                  (e) => debugPrint('Error persisting remote edit: $e'),
                );
          } else {
            debugPrint(
              '[ConversationDetailProvider] Message not found in local cache. Available message IDs: ${current.map((m) => '${m.id}(platform:${m.platformMessageId})').join(', ')}',
            );
            // If message not found and force_refresh is true, reload the conversation
            if (forceRefresh) {
              debugPrint(
                '[ConversationDetailProvider] force_refresh=true, reloading conversation for contact=$targetContact',
              );
              // Clear cached messages for this contact to force fresh fetch
              _memoryMessages.remove(targetContact);
              // Reload from server
              loadConversation(targetContact, fresh: true);
            }
          }
        } else {
          debugPrint(
            '[ConversationDetailProvider] Contact $targetContact not in memory. Available contacts: ${_memoryMessages.keys.join(', ')}',
          );
          // If force_refresh is true, load the conversation fresh
          if (forceRefresh) {
            debugPrint(
              '[ConversationDetailProvider] force_refresh=true, loading conversation for contact=$contact',
            );
            loadConversation(contact, fresh: true);
          }
        }
      } else if (type == 'message_deleted') {
        if (_memoryMessages.containsKey(contact)) {
          final msgId = data['message_id'];

          // UX Polish: Clear reply/edit state if the affected message is deleted
          if (_activeContact == contact) {
            if (_replyToMessage?.id == msgId) {
              _replyToMessage = null;
            }
            if (_editingMessageId == msgId) {
              _editingMessageId = null;
              _editingMessageBody = null;
            }
          }

          final current = _memoryMessages[contact] ?? [];
          _memoryMessages[contact] = current
              .where((m) => m.id != msgId)
              .toList();
          if (_activeContact == contact) _throttledNotify();
        }
      } else if (type == 'delivery_status') {
        // Handle real-time status updates (Sending -> Sent -> Delivered -> Read)
        final msgId = data['outbox_id'];
        // Support both 'status' and 'delivery_status' fields from backend
        final newStatus = (data['delivery_status'] ?? data['status'])
            ?.toString()
            .toLowerCase();
        final senderContact = data['sender_contact'] as String?;

        if (msgId == null || newStatus == null) {
          debugPrint(
            '[ConversationDetailProvider] Invalid delivery_status event: msgId=$msgId, status=$newStatus',
          );
          return;
        }

        // CRITICAL FIX for multi-account: Update messages even if conversation is not active
        // First try the active conversation, then search all conversations
        String? targetContact = _activeContact;

        // If sender_contact is provided and doesn't match active conversation, use it
        if (senderContact != null && senderContact != targetContact) {
          // Check if we have messages for this contact in memory
          if (_memoryMessages.containsKey(senderContact)) {
            targetContact = senderContact;
          }
        }

        if (targetContact != null &&
            _memoryMessages.containsKey(targetContact)) {
          final current = _memoryMessages[targetContact] ?? [];
          // Match by outboxId (for optimistic messages) or id (for synced messages)
          final idx = current.indexWhere(
            (m) => (m.id == msgId || m.outboxId == msgId) && m.isOutgoing,
          );
          if (idx != -1) {
            final msg = current[idx];

            // PROTECTION: Never downgrade status from 'sent' back to 'pending' in UI
            // This eliminates the flickering reported by users when server emits intermediate pending states
            final isCurrentlySent =
                msg.status.toLowerCase() == 'sent' ||
                msg.sendStatus == MessageSendStatus.sent;

            if (isCurrentlySent && newStatus == 'pending') {
              // Ignore this update to prevent flickering
              debugPrint(
                '[ConversationDetailProvider] Ignoring status downgrade: sent -> pending for message $msgId',
              );
              return;
            }

            debugPrint(
              '[ConversationDetailProvider] Updating message $msgId status: ${msg.status} -> $newStatus (contact=$targetContact)',
            );

            final updatedList = List<InboxMessage>.from(current);
            updatedList[idx] = updatedList[idx].copyWith(
              status: newStatus,
              deliveryStatus: newStatus,
              sendStatus: newStatus == 'sent'
                  ? MessageSendStatus.sent
                  : (newStatus == 'failed'
                        ? MessageSendStatus.failed
                        : MessageSendStatus.sending),
            );
            _memoryMessages[targetContact] = updatedList;

            // Only notify UI if this is the active conversation
            if (_activeContact == targetContact) {
              _throttledNotify();
            }

            // Persist to local SQLite DB
            _inboxRepository
                .updateMessageSyncStatus(msgId, newStatus)
                .catchError(
                  (e) => debugPrint('Error persisting delivery status: $e'),
                );
          } else {
            // Message not found in memory - this can happen if:
            // 1. Message was already confirmed and conversation was reloaded
            // 2. User switched conversations before status update arrived
            // 3. Message is in local DB but not loaded into memory yet
            // This is OK - the message status will be correct when conversation is loaded
          }
        } else {
          debugPrint(
            '[ConversationDetailProvider] Contact $targetContact not in memory',
          );
        }
      } else if (type == 'conversation_deleted') {
        // Handle conversation deletion
        final deletedContact = data['sender_contact'] as String?;
        if (deletedContact != null && deletedContact == _activeContact) {
          // Clear current conversation if it's the one being deleted
          _memoryMessages[deletedContact] = [];
          _memoryStates[deletedContact] = ConversationState.loaded;
          _throttledNotify();
        }
      } else if (type == 'chat_cleared') {
        // Handle chat history cleared
        final clearedContact = data['sender_contact'] as String?;
        if (clearedContact != null && clearedContact == _activeContact) {
          // Clear messages for this conversation
          _memoryMessages[clearedContact] = [];
          _memoryStates[clearedContact] = ConversationState.loaded;
          _memoryCursors[clearedContact] = null;
          _memoryHasMore[clearedContact] = false;
          _throttledNotify();
        }
      } else if (type == 'customer_updated') {
        // Handle customer profile update (username, name, avatar change)
        // IMPORTANT: Only affects Almudeer channel conversations
        final customerContact = data['sender_contact'] as String?;
        final oldCustomerContact = data['old_sender_contact'] as String?;
        final updatedFields = data['updated_fields'] as Map<String, dynamic>?;

        if (customerContact == null) return;

        // Check if this affects the active conversation
        String? targetContact = _activeContact;

        // If username changed, check for old contact
        if (oldCustomerContact != null &&
            oldCustomerContact == _activeContact) {
          // Migrate active contact to new username
          _activeContact = customerContact;
          targetContact = customerContact;

          // Migrate in-memory data
          if (_memoryMessages.containsKey(oldCustomerContact)) {
            _memoryMessages[customerContact] =
                _memoryMessages[oldCustomerContact]!;
            _memoryMessages.remove(oldCustomerContact);
          }
          if (_memoryStates.containsKey(oldCustomerContact)) {
            _memoryStates[customerContact] = _memoryStates[oldCustomerContact]!;
            _memoryStates.remove(oldCustomerContact);
          }
          if (_memoryCursors.containsKey(oldCustomerContact)) {
            _memoryCursors[customerContact] =
                _memoryCursors[oldCustomerContact];
            _memoryCursors.remove(oldCustomerContact);
          }
          if (_memoryHasMore.containsKey(oldCustomerContact)) {
            _memoryHasMore[customerContact] =
                _memoryHasMore[oldCustomerContact]!;
            _memoryHasMore.remove(oldCustomerContact);
          }

          debugPrint(
            '[ConversationDetailProvider] Migrated active conversation from $oldCustomerContact to $customerContact',
          );
        }

        // Update sender name/avatar if we have this conversation in memory
        // Only for Almudeer channel
        if (targetContact != null && updatedFields != null) {
          String? newSenderName = _memorySenderNames[targetContact];

          if (updatedFields.containsKey('full_name')) {
            newSenderName = updatedFields['full_name'];
          }

          _memorySenderNames[targetContact] = newSenderName;
          _throttledNotify();

          debugPrint(
            '[ConversationDetailProvider] Updated customer profile: $targetContact',
          );
        }
      }
    } catch (e, stackTrace) {
      // Inner error boundary for individual event type handlers
      debugPrint(
        '[ConversationDetailProvider] Error processing event type $type: $e',
      );
      debugPrint('Stack trace: $stackTrace');
    }
  }

  /// Send typing indicator to server (with rate limiting)
  /// P1-7 FIX: Improved debouncing - send after 500ms of typing, cancel on stop
  void setTypingStatus(bool isTyping) {
    if (_activeContact == null) return;

    // Skip if status hasn't changed (prevent redundant network calls)
    if (isTyping == _lastTypingStatusSent) return;

    // P1-7 FIX: Cancel any pending timer
    _typingDebounceTimer?.cancel();

    if (isTyping) {
      // P1-7 FIX: Wait 500ms of continuous typing before sending "typing" status
      // This prevents flooding during rapid start/stop typing
      _typingDebounceTimer = Timer(const Duration(milliseconds: 500), () {
        _lastTypingStatusSent = true;
        _inboxRepository
            .setTypingStatus(_activeContact!, true)
            .catchError((e) => debugPrint('Error sending typing status: $e'));
      });
    } else {
      // P1-7 FIX: Send "stopped typing" immediately (no debounce)
      _lastTypingStatusSent = false;
      _inboxRepository
          .setTypingStatus(_activeContact!, false)
          .catchError((e) => debugPrint('Error sending typing status: $e'));
    }
  }

  /// Send recording indicator to server (with rate limiting)
  void setRecordingStatus(bool isRecording) {
    if (_activeContact == null) return;

    // Debounce rapid events
    _typingDebounceTimer?.cancel();
    _typingDebounceTimer = Timer(const Duration(seconds: 2), () {
      _inboxRepository
          .setRecordingStatus(_activeContact!, isRecording)
          .catchError((e) => debugPrint('Error sending recording status: $e'));
    });
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  // --- Search Mode ---

  void startSearching() {
    _isSearching = true;
    _isSelectionMode = false;
    _searchQuery = '';
    _searchResultIds = [];
    _currentSearchIndex = -1;
    notifyListeners();
  }

  void stopSearching() {
    _isSearching = false;
    _searchQuery = '';
    _searchResultIds = [];
    _currentSearchIndex = -1;
    notifyListeners();
  }

  Future<void> updateSearchQuery(String query) async {
    _searchQuery = query;
    if (query.trim().length < 2) {
      _searchResultIds = [];
      _currentSearchIndex = -1;
      notifyListeners();
      return;
    }

    try {
      final results = await _inboxRepository.searchMessages(
        query,
        senderContact: _activeContact,
      );
      _searchResultIds = results.map((m) => m.id).toList();
      _currentSearchIndex = _searchResultIds.isNotEmpty ? 0 : -1;
      notifyListeners();
    } catch (e) {
      debugPrint('Search error: $e');
    }
  }

  void nextSearchResult() {
    if (_searchResultIds.isEmpty) return;
    _currentSearchIndex = (_currentSearchIndex + 1) % _searchResultIds.length;
    notifyListeners();
  }

  void previousSearchResult() {
    if (_searchResultIds.isEmpty) return;
    _currentSearchIndex =
        (_currentSearchIndex - 1 + _searchResultIds.length) %
        _searchResultIds.length;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _wsStateSubscription?.cancel();
    _wsMessageSubscription?.cancel();
    _throttleTimer?.cancel();
    _typingDebounceTimer?.cancel();
    _memoryCleanupTimer?.cancel(); // P1-9: Clean up memory cleanup timer
    for (final timer in _typingTimers.values) {
      timer?.cancel();
    }
    for (final timer in _recordingTimers.values) {
      timer?.cancel();
    }
    // P1-9: Explicitly clear all maps to free memory
    _memoryMessages.clear();
    _memoryStates.clear();
    _memoryCursors.clear();
    _memoryHasMore.clear();
    _memorySenderNames.clear();
    _memoryChannels.clear();
    _memoryTypingFields.clear();
    _memoryRecordingFields.clear();
    _memoryOnlineStatus.clear();
    _memoryLastSeen.clear();
    _memoryDrafts.clear();
    _typingTimers.clear();
    _recordingTimers.clear();
    _recentlyProcessedMessageIds.clear();
    _conversationAccessOrder.clear();
    super.dispose();
  }
}
