import 'dart:convert';
import 'dart:io'; // P2-11 FIX: For SocketException, HttpException
import 'dart:async'; // For TimeoutException
import 'package:flutter/foundation.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/services/persistent_cache_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../models/conversation.dart';
import '../models/inbox_message.dart';
import '../datasources/local/inbox_local_datasource.dart';

// P2-11 FIX: Error classification for better retry logic
enum MessageSendErrorType {
  network, // Connection timeout, no internet
  server, // 5xx server errors
  validation, // 4xx client errors (bad request, invalid data)
  auth, // 401/403 authentication errors
  unknown, // Any other error
}

class MessageSendException implements Exception {
  final String message;
  final MessageSendErrorType errorType;
  final int? statusCode;
  final Exception? originalException;

  MessageSendException(
    this.message, {
    this.errorType = MessageSendErrorType.unknown,
    this.statusCode,
    this.originalException,
  });

  @override
  String toString() => 'MessageSendException($errorType): $message';

  /// Whether this error is retryable
  bool get isRetryable =>
      errorType == MessageSendErrorType.network ||
      errorType == MessageSendErrorType.server;
}

/// Repository for inbox/conversation operations (Local-First)
class InboxRepository {
  final ApiClient _apiClient;
  final PersistentCacheService _cache;
  final ConnectivityService _connectivityService;
  final InboxLocalDataSource _localDataSource;

  InboxRepository({
    ApiClient? apiClient,
    PersistentCacheService? cache,
    ConnectivityService? connectivityService,
    InboxLocalDataSource? localDataSource,
  }) : _apiClient = apiClient ?? ApiClient(),
       _cache = cache ?? PersistentCacheService(),
       _connectivityService = connectivityService ?? ConnectivityService(),
       _localDataSource = localDataSource ?? InboxLocalDataSource();

  ApiClient get apiClient => _apiClient;

  /// Get conversations list (with selective persistent caching)
  Future<ConversationsResponse> getConversations({
    int limit = 25,
    int offset = 0,
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };

    final accountHash = await _apiClient.getAccountCacheHash();
    final cacheKey = '${accountHash}_list_$offset';

    // Always try cache first for instant load
    final cached = await _cache.get<Map<String, dynamic>>(
      PersistentCacheService.boxInbox,
      cacheKey,
    );

    if (_connectivityService.isOffline) {
      // Offline: always return cached data, never throw error
      if (cached != null) {
        return ConversationsResponse.fromJson(cached);
      }
      // Return empty response instead of throwing
      return ConversationsResponse(
        conversations: [],
        statusCounts: {},
        total: 0,
        hasMore: false,
      );
    }

    // Online: fetch fresh data
    try {
      final response = await _apiClient.get(
        Endpoints.conversations,
        queryParams: queryParams,
      );
      await _cache.put(PersistentCacheService.boxInbox, cacheKey, response);
      return ConversationsResponse.fromJson(response);
    } catch (e) {
      // On error, return cached data if available
      if (cached != null) {
        return ConversationsResponse.fromJson(cached);
      }
      rethrow;
    }
  }

  /// Delete a conversation
  Future<void> deleteConversation(String senderContact) async {
    // 1. Clear Locally (Optimistic)
    await _localDataSource.clearChatHistory(senderContact);

    // 2. Clear on Server if online
    if (_connectivityService.isOnline) {
      await _apiClient.delete(Endpoints.deleteConversation(senderContact));
      final hash = await _apiClient.getAccountCacheHash();
      await _cache.deleteByPrefix(PersistentCacheService.boxInbox, hash);
    }
  }

  /// Archive a conversation
  Future<void> archiveConversation(String senderContact) async {
    if (_connectivityService.isOnline) {
      await _apiClient.post(Endpoints.archiveConversation(senderContact));
      final hash = await _apiClient.getAccountCacheHash();
      await _cache.deleteByPrefix(PersistentCacheService.boxInbox, hash);
    }
  }

  /// Toggle pin status for a conversation
  Future<void> togglePinConversation(
    String senderContact,
    bool isPinned,
  ) async {
    if (_connectivityService.isOnline) {
      await _apiClient.post(
        Endpoints.togglePinConversation(senderContact),
        body: {'is_pinned': isPinned},
      );
    }
  }

  /// Mark all conversations as read
  Future<void> markAllAsRead() async {
    if (_connectivityService.isOnline) {
      await _apiClient.post(Endpoints.markAllAsRead);
    }
  }

  /// Clear all messages in a conversation
  Future<void> clearConversationMessages(String senderContact) async {
    // 1. Clear Locally
    await _localDataSource.clearChatHistory(senderContact);

    // 2. Clear on Server if online
    if (_connectivityService.isOnline) {
      await _apiClient.delete(Endpoints.clearConversation(senderContact));

      // 3. Clear cache for this specific conversation detail
      final hash = await _apiClient.getAccountCacheHash();
      await _cache.delete(
        PersistentCacheService.boxInbox,
        '${hash}_messages_$senderContact',
      );
    }
  }

  /// Get unread counts
  Future<Map<String, int>?> getUnreadCounts() async {
    try {
      if (_connectivityService.isOnline) {
        final response = await _apiClient.get(Endpoints.conversationStats);
        return Map<String, int>.from(response);
      }
    } catch (e) {
      debugPrint('Error getting unread counts: $e');
    }
    return null;
  }

  /// Helper to convert local DB row to InboxMessage
  InboxMessage _mapLocalMessage(Map<String, dynamic> row) {
    final map = Map<String, dynamic>.from(row);
    // Map local/remote ID to 'id'
    // If 'remote_id' is present, use it. Else use negative 'local_id'
    map['id'] = row['remote_id'] ?? -(row['local_id'] as int);
    // Ensure sender_contact is set if missing
    if (!map.containsKey('sender_contact')) map['sender_contact'] = '';

    // Explicitly map is_forwarded from int (0/1) to bool for JSON model
    if (row['is_forwarded'] != null) {
      map['is_forwarded'] = row['is_forwarded'] == 1;
    }

    // Direction defaults to incoming if null (safety, though DB should have it now)
    if (map['direction'] == null) map['direction'] = 'incoming';

    return InboxMessage.fromJson(map);
  }

  /// Get conversation detail (Active Context -> Local First)
  Future<ConversationDetailResponse> getConversationDetail(
    String senderContact, {
    int limit = 100,
  }) async {
    // 1. Get Local Messages
    final localMessages = await _localDataSource.getChatHistory(
      senderContact,
      limit: limit,
    );

    if (_connectivityService.isOffline) {
      if (localMessages.isNotEmpty) {
        return ConversationDetailResponse(
          senderName: senderContact, // Placeholder
          senderContact: senderContact,
          messages: localMessages.map(_mapLocalMessage).toList(),
          total: localMessages.length,
        );
      }
    }

    // 2. Refresh from Server if Online
    try {
      final response = await _apiClient.get(
        Endpoints.conversationDetail(senderContact),
        queryParams: {'limit': limit.toString()},
      );

      if (response['messages'] != null) {
        final List<dynamic> list = response['messages'];
        final List<Map<String, dynamic>> msgs = list
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        await _localDataSource.cacheMessages(
          msgs,
          senderContact: senderContact,
        );
      }

      return ConversationDetailResponse.fromJson(response);
    } catch (e) {
      // Special case for Saved Messages: if not found on server, return virtual empty state
      if (senderContact == '__saved_messages__') {
        return ConversationDetailResponse(
          senderName: 'الرَّسائل المحفوظة',
          senderContact: '__saved_messages__',
          messages: [],
          total: 0,
        );
      }

      if (localMessages.isNotEmpty) {
        return ConversationDetailResponse(
          senderName: senderContact,
          senderContact: senderContact,
          messages: localMessages.map(_mapLocalMessage).toList(),
          total: localMessages.length,
        );
      }
      rethrow;
    }
  }

  /// Get inbox messages
  Future<InboxMessagesResponse> getInboxMessages({
    String? status,
    String? channel,
    int limit = 50,
  }) async {
    final queryParams = <String, String>{'limit': limit.toString()};
    if (status != null) queryParams['status'] = status;
    if (channel != null) queryParams['channel'] = channel;

    final response = await _apiClient.get(
      Endpoints.inbox,
      queryParams: queryParams,
    );
    return InboxMessagesResponse.fromJson(response);
  }

  /// Get single inbox message
  Future<InboxMessage> getInboxMessage(int id) async {
    final response = await _apiClient.get(Endpoints.inboxMessage(id));
    return InboxMessage.fromJson(response['message'] as Map<String, dynamic>);
  }

  /// Mark message as read
  Future<void> markMessageRead(int messageId) async {
    if (_connectivityService.isOnline) {
      await _apiClient.post(Endpoints.markRead(messageId));
    }
  }

  /// Mark all messages in a conversation as read
  Future<void> markConversationRead(String senderContact) async {
    if (_connectivityService.isOnline) {
      await _apiClient.post(Endpoints.markConversationRead(senderContact));
    }
  }

  /// Get WhatsApp Templates (Cached)
  Future<List<Map<String, dynamic>>> getWhatsAppTemplates() async {
    final accountHash = await _apiClient.getAccountCacheHash();
    final cacheKey = '${accountHash}_whatsapp_templates';

    try {
      if (_connectivityService.isOnline) {
        final response = await _apiClient.get(
          '/api/integrations/whatsapp/templates',
        );
        if (response['success'] == true) {
          final data = List<Map<String, dynamic>>.from(response['data'] ?? []);
          await _cache.put(
            PersistentCacheService.boxIntegrations,
            cacheKey,
            data,
          );
          return data;
        }
      }
    } catch (e) {
      debugPrint('Error fetching WhatsApp templates: $e');
    }

    // Try reading from cache if offline or API failed
    final cached = await _cache.get<List<dynamic>>(
      PersistentCacheService.boxIntegrations,
      cacheKey,
    );
    if (cached != null) {
      return List<Map<String, dynamic>>.from(cached);
    }

    return [];
  }

  /// Send a message to a conversation
  Future<Map<String, dynamic>> sendMessage(
    String senderContact, {
    required String message,
    String? channel,
    List<Map<String, dynamic>>? attachments,
    int? replyToMessageId,
    String? replyToPlatformId,
    String? replyToBodyPreview,
    String? replyToSenderName,
    bool isForwarded = false,
    void Function(double progress)? onUploadProgress,
  }) async {
    // If replyToMessageId is negative (optimistic local message), don't send it to backend to avoid FK crashes
    final int? safeReplyToMessageId =
        (replyToMessageId != null && replyToMessageId > 0)
        ? replyToMessageId
        : null;

    // Extract first attachment path for local storage (optimistic)
    String? localMediaPath;
    if (attachments != null && attachments.isNotEmpty) {
      final firstAtt = attachments.first;
      if (firstAtt.containsKey('path')) {
        localMediaPath = firstAtt['path'] as String?;
      }
    }

    // 1. Save Locally (Optimistic)
    final localId = await _localDataSource.addMessageLocally(
      senderContact: senderContact,
      body: message,
      channel: channel ?? 'whatsapp',
      mediaUrl: localMediaPath,
      replyToId: safeReplyToMessageId,
      replyToPlatformId: replyToPlatformId,
      replyToBodyPreview: replyToBodyPreview,
      replyToSenderName: replyToSenderName,
      isForwarded: isForwarded,
      attachments: attachments,
    );

    if (_connectivityService.isOffline) {
      return {'success': true, 'pending': true, 'local_id': localId};
    }

    // Process attachments: Convert paths to Base64
    // 2. Prepare for Multiparts/Metadata
    final fields = <String, String>{
      'message': message,
      'channel': channel ?? 'whatsapp',
      'is_forwarded': isForwarded.toString(),
    };

    if (replyToMessageId != null) {
      fields['reply_to_id'] = replyToMessageId.toString();
    }
    if (replyToPlatformId != null) {
      fields['reply_to_platform_id'] = replyToPlatformId;
    }
    if (replyToBodyPreview != null) {
      fields['reply_to_body_preview'] = replyToBodyPreview;
    }
    if (replyToSenderName != null) {
      fields['reply_to_sender_name'] = replyToSenderName;
    }

    final List<MapEntry<String, String>> fileEntries = [];
    final List<Map<String, dynamic>> otherAttachments = [];

    if (attachments != null && attachments.isNotEmpty) {
      for (var att in attachments) {
        if (att.containsKey('path')) {
          fileEntries.add(MapEntry('files', att['path']));
          debugPrint(
            '[InboxRepository] Adding file to multipart: ${att['path']} (type: ${att['type']})',
          );
        } else {
          debugPrint(
            '[InboxRepository] Attachment without path, adding to otherAttachments: ${att['type']}',
          );
          otherAttachments.add(att);
        }
      }
    }

    debugPrint('[InboxRepository] fileEntries count: ${fileEntries.length}');
    debugPrint(
      '[InboxRepository] otherAttachments count: ${otherAttachments.length}',
    );

    if (otherAttachments.isNotEmpty) {
      fields['attachments'] = jsonEncode(otherAttachments);
    }

    // 3. Send via Multipart if we have files, otherwise standard POST
    // P2-11 FIX: Add error classification for better retry logic
    debugPrint('[InboxRepository] Sending message to: ${Endpoints.sendMessage(senderContact)}');
    debugPrint('[InboxRepository] Message body: "$message"');
    debugPrint('[InboxRepository] Fields: $fields');
    
    Map<String, dynamic> result;
    try {
      if (fileEntries.isNotEmpty) {
        debugPrint('[InboxRepository] Sending with files (multipart)');
        result = await _apiClient.uploadMultipleFiles(
          Endpoints.sendMessage(senderContact),
          files: fileEntries,
          fields: fields,
          onProgress: onUploadProgress,
        );
      } else {
        debugPrint('[InboxRepository] Sending text-only message (POST)');
        result = await _apiClient.post(
          Endpoints.sendMessage(senderContact),
          body: {
            ...fields,
            if (otherAttachments.isNotEmpty) 'attachments': otherAttachments,
          },
        );
      }
      debugPrint('[InboxRepository] Message sent successfully, response: $result');
    } on MessageSendException {
      // Re-throw already classified exceptions
      rethrow;
    } on SocketException catch (e) {
      // P2-11 FIX: Classify network errors
      throw MessageSendException(
        'لا يوجد اتصال بالإنترنت',
        errorType: MessageSendErrorType.network,
        originalException: e,
      );
    } on TimeoutException catch (e) {
      // ignore: dead_code_on_catch_subtype
      // P2-11 FIX: Classify timeout as network error
      throw MessageSendException(
        'انتهت مهلة الاتصال',
        errorType: MessageSendErrorType.network,
        originalException: e,
      );
    } on HttpException catch (e) {
      // P2-11 FIX: Classify HTTP errors - dart:io HttpException doesn't have statusCode
      // Use generic server error for HttpException
      throw MessageSendException(
        'خطأ في الخادم، يرجى المحاولة لاحقاً',
        errorType: MessageSendErrorType.server,
        originalException: e,
      );
    } catch (e) {
      // P2-11 FIX: Classify unknown errors
      throw MessageSendException(
        'حدث خطأ غير متوقع: ${e.toString()}',
        errorType: MessageSendErrorType.unknown,
        originalException: e as Exception?,
      );
    }

    // Update Local Status to Synced
    if (result['id'] != null) {
      final responseData = result['data'] ?? result;
      await _localDataSource.markAsSynced(
        localId,
        result['id'],
        platformMessageId: responseData['platform_message_id'] as String?,
        channelMessageId: responseData['channel_message_id'] as String?,
      );
    }

    return result;
  }

  /// Get conversation messages with cursor-based pagination
  Future<CursorPaginatedMessages> getConversationMessagesCursor(
    String senderContact, {
    String? cursor,
    int limit = 25,
    String direction = 'older',
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      'direction': direction,
    };
    if (cursor != null) queryParams['cursor'] = cursor;

    final response = await _apiClient.get(
      '${Endpoints.conversationDetail(senderContact)}/messages',
      queryParams: queryParams,
    );
    return CursorPaginatedMessages.fromJson(response);
  }

  /// Get unsynced outgoing messages for a contact (local only)
  Future<List<InboxMessage>> getUnsyncedOutgoingMessages(String senderContact) async {
    final localMessages = await _localDataSource.getUnsyncedOutgoingMessages(senderContact);
    return localMessages.map(_mapLocalMessage).toList();
  }

  /// Edit an outbox message
  Future<Map<String, dynamic>> editMessage(
    int messageId,
    String newBody,
  ) async {
    // Validate message ID - must be a positive synced message
    if (messageId <= 0) {
      throw ArgumentError('Cannot edit unsynced message (id: $messageId)');
    }

    // Local Update
    await _localDataSource.updateMessageStatus(
      messageId,
      'replied',
      editedBody: newBody,
    );

    if (_connectivityService.isOnline) {
      final result = await _apiClient.patch(
        '/api/integrations/messages/$messageId/edit',
        body: {'body': newBody},
      );

      // On success, update local DB with server-confirmed 'edited_at'
      if (result['success'] == true) {
        await applyRemoteMessageEdit(
          messageId,
          newBody,
          result['edited_at'] as String?,
        );
      }
      return result;
    }
    return {'success': true, 'pending': true};
  }

  /// Apply a remote edit to the local database (called when WebSocket event is received)
  Future<void> applyRemoteMessageEdit(
    int messageId,
    String newBody,
    String? editedAt,
  ) async {
    await _localDataSource.updateMessageEditLocally(
      messageId,
      newBody,
      editedAt,
    );
  }

  /// Apply a remote deletion to the local database (called when WebSocket event is received)
  Future<void> applyRemoteMessageDelete(int messageId) async {
    await _localDataSource.deleteMessageLocally(messageId);
  }

  /// Delete an outbox message (soft delete)
  Future<Map<String, dynamic>> deleteMessage(
    int messageId, {
    bool isOutgoing = false,
  }) async {
    // 1. Delete Locally (Optimistic)
    if (messageId > 0) {
      await _localDataSource.deleteMessageLocally(messageId);
    }

    // 2. Sync with Server if online
    if (_connectivityService.isOnline) {
      final type = isOutgoing ? 'outgoing' : 'incoming';
      return await _apiClient.delete(
        '/api/integrations/messages/$messageId?type=$type',
      );
    }
    return {'success': true, 'pending': true};
  }

  /// Restore a deleted message
  Future<Map<String, dynamic>> restoreMessage(int messageId) async {
    return await _apiClient.post(
      '/api/integrations/messages/$messageId/restore',
    );
  }

  /// Search messages
  Future<List<InboxMessage>> searchMessages(
    String query, {
    String? senderContact,
    int limit = 50,
    int offset = 0,
  }) async {
    final queryParams = <String, String>{
      'query': query,
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    if (senderContact != null) {
      queryParams['sender_contact'] = senderContact;
    }

    final response = await _apiClient.get(
      '/api/integrations/conversations/search',
      queryParams: queryParams,
    );

    final results = response['results'] as List? ?? [];
    return results
        .map((m) => InboxMessage.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  /// Sends typing indicator status
  Future<void> setTypingStatus(String senderContact, bool isTyping) async {
    if (_connectivityService.isOnline) {
      await _apiClient.post(
        '${Endpoints.conversations}/$senderContact/typing',
        body: {'is_typing': isTyping},
      );
    }
  }

  /// Sends recording indicator status
  Future<void> setRecordingStatus(
    String senderContact,
    bool isRecording,
  ) async {
    if (_connectivityService.isOnline) {
      await _apiClient.post(
        '${Endpoints.conversations}/$senderContact/recording',
        body: {'is_recording': isRecording},
      );
    }
  }

  /// P2-6: Get draft from server (synced across devices)
  Future<String?> getDraft(String senderContact) async {
    if (_connectivityService.isOnline) {
      try {
        final response = await _apiClient.get(
          '${Endpoints.conversations}/$senderContact/draft',
        );
        return response['draft'] as String?;
      } catch (e) {
        debugPrint('Error getting draft: $e');
      }
    }
    return null;
  }

  /// P2-6: Save draft to server (synced across devices)
  Future<void> saveDraft(String senderContact, String text) async {
    if (_connectivityService.isOnline) {
      try {
        await _apiClient.post(
          '${Endpoints.conversations}/$senderContact/draft',
          body: {'draft': text},
        );
      } catch (e) {
        debugPrint('Error saving draft: $e');
      }
    }
  }

  /// Update sync status and remote status for a message (e.g. from WebSocket)
  Future<void> updateMessageSyncStatus(int remoteId, String status) async {
    await _localDataSource.updateMessageSyncStatus(remoteId, status);
  }

  /// Persist a remote message to local SQLite (WebSocket path)
  Future<void> persistRemoteMessage(Map<String, dynamic> message) async {
    await _localDataSource.persistRemoteMessage(message);
  }

  /// P1-5 FIX: Check if there's a pending local operation for a message
  /// Returns true if a conflicting local operation exists
  Future<bool> hasConflictingPendingOperation(int messageId) async {
    // Check pending operations in the sync service
    // This requires accessing the PendingOperationsService
    // For now, we check the local data source for pending messages
    return await _localDataSource.hasPendingOperation(messageId);
  }

  /// P1-5 FIX: Apply remote edit only if no conflicting local operation exists
  Future<bool> applyRemoteMessageEditIfNoConflict(
    int messageId,
    String newBody,
    String? editedAt,
  ) async {
    // Check for conflicting local operation
    final hasConflict = await hasConflictingPendingOperation(messageId);
    if (hasConflict) {
      debugPrint(
        '[InboxRepository] Skipping remote edit for message $messageId - pending local operation exists',
      );
      return false;
    }

    // No conflict - apply the remote edit
    await applyRemoteMessageEdit(messageId, newBody, editedAt);
    return true;
  }

  /// P1-5 FIX: Apply remote deletion only if no conflicting local operation exists
  Future<bool> applyRemoteDeleteIfNoConflict(int messageId) async {
    // Check for conflicting local operation
    final hasConflict = await hasConflictingPendingOperation(messageId);
    if (hasConflict) {
      debugPrint(
        '[InboxRepository] Skipping remote delete for message $messageId - pending local operation exists',
      );
      return false;
    }

    // No conflict - apply the remote deletion
    await applyRemoteMessageDelete(messageId);
    return true;
  }

  /// Migrate conversation contact when username changes
  Future<void> migrateConversationContact(
    String oldContact,
    String newContact,
  ) async {
    try {
      // Update conversations in local database
      await _localDataSource.updateConversationContact(oldContact, newContact);

      // Update messages in local database
      await _localDataSource.updateMessageSenderContact(oldContact, newContact);

      debugPrint(
        '[InboxRepository] Migrated conversation contact: $oldContact -> $newContact',
      );
    } catch (e) {
      debugPrint('Failed to migrate conversation contact: $e');
      rethrow;
    }
  }
}

/// Response for cursor-based paginated messages
class CursorPaginatedMessages {
  final List<InboxMessage> messages;
  final String? nextCursor;
  final bool hasMore;
  final String senderContact;
  final bool isOnline;
  final String? lastSeenAt;

  CursorPaginatedMessages({
    required this.messages,
    this.nextCursor,
    required this.hasMore,
    required this.senderContact,
    this.isOnline = false,
    this.lastSeenAt,
  });

  factory CursorPaginatedMessages.fromJson(Map<String, dynamic> json) {
    return CursorPaginatedMessages(
      messages: (json['messages'] as List? ?? [])
          .map((m) => InboxMessage.fromJson(m as Map<String, dynamic>))
          .toList(),
      nextCursor: json['next_cursor'] as String?,
      hasMore: json['has_more'] as bool? ?? false,
      senderContact: json['sender_contact'] as String? ?? '',
      isOnline: json['is_online'] as bool? ?? false,
      lastSeenAt: json['last_seen_at'] as String?,
    );
  }
}
