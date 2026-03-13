import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../../core/services/local_database_service.dart';

class InboxLocalDataSource {
  final LocalDatabaseService _dbService;

  InboxLocalDataSource({LocalDatabaseService? dbService})
    : _dbService = dbService ?? LocalDatabaseService();

  Future<Database> get _db async => _dbService.database;

  /// Cache valid messages from server (Sync Down)
  /// If [senderContact] is provided, it will prune local messages for that contact
  /// that are NOT present in the [messages] list (stale messages).
  Future<void> cacheMessages(
    List<Map<String, dynamic>> messages, {
    String? senderContact,
  }) async {
    final db = await _db;
    final batch = db.batch();

    // 1. Insert/Replace fresh messages
    final List<int> remoteIds = [];
    for (var msg in messages) {
      if (msg['id'] != null) remoteIds.add(msg['id']);
      batch.insert('inbox_messages', {
        'remote_id': msg['id'],
        'sender_contact': msg['sender_contact'],
        'channel': msg['channel'],
        'body': msg['body'],
        'media_url': msg['media_url'],
        'intent': msg['intent'],
        'created_at': msg['created_at'],
        'received_at': msg['received_at'],
        'status': msg['status'],
        'delivery_status': msg['delivery_status'],
        'reply_to_id': msg['reply_to_id'],
        'reply_to_platform_id': msg['reply_to_platform_id'],
        'reply_to_body_preview': msg['reply_to_body_preview'],
        'reply_to_sender_name': msg['reply_to_sender_name'],
        'reply_count': msg['reply_count'] ?? 0,
        'sync_status': 'synced',
        'attachments': msg['attachments'] != null
            ? jsonEncode(msg['attachments'])
            : null,
        'is_forwarded':
            (msg['is_forwarded'] == true || msg['is_forwarded'] == 1) ? 1 : 0,
        'urgency': msg['urgency'],
        'sentiment': msg['sentiment'],
        'original_sender': msg['original_sender'],
        'deleted_at': msg['deleted_at'],
        'is_read': (msg['is_read'] == true || msg['is_read'] == 1) ? 1 : 0,

        // v9 fields
        'sender_name': msg['sender_name'],
        'channel_message_id': msg['channel_message_id'],
        'platform_message_id': msg['platform_message_id'],
        'direction': msg['direction'],

        // v12 fields
        'edited_at': msg['edited_at'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    // 2. Prune stale messages if senderContact is provided
    if (senderContact != null) {
      if (remoteIds.isNotEmpty) {
        final placeholders = remoteIds.map((_) => '?').join(',');
        batch.delete(
          'inbox_messages',
          where:
              'sender_contact = ? AND sync_status = ? AND remote_id NOT IN ($placeholders)',
          whereArgs: [senderContact, 'synced', ...remoteIds],
        );
      } else if (messages.isEmpty) {
        // If the server explicitly returns an empty list for a contact, clear all synced messages
        batch.delete(
          'inbox_messages',
          where: 'sender_contact = ? AND sync_status = ?',
          whereArgs: [senderContact, 'synced'],
        );
      }
    }

    await batch.commit(noResult: true);
  }

  /// Delete a single message locally (Optimistic Delete)
  Future<void> deleteMessageLocally(int remoteId) async {
    final db = await _db;
    await db.delete(
      'inbox_messages',
      where: 'remote_id = ?',
      whereArgs: [remoteId],
    );
  }

  /// Add message locally (Offline Send)
  /// P1-1 FIX: Added retry tracking for offline message send
  Future<int> addMessageLocally({
    required String senderContact,
    required String body,
    String channel = 'whatsapp',
    String? mediaUrl,
    int? replyToId,
    String? replyToPlatformId,
    String? replyToBodyPreview,
    String? replyToSenderName,
    bool isForwarded = false,
    List<Map<String, dynamic>>? attachments,
    String? receivedAt,
    String? urgency,
    String? sentiment,
    String? originalSender,
    String? deliveryStatus,
  }) async {
    final db = await _db;
    return await db.insert('inbox_messages', {
      'sender_contact': senderContact,
      'channel': channel,
      'body': body,
      'media_url': mediaUrl,
      'attachments': attachments != null ? jsonEncode(attachments) : null,
      'created_at': DateTime.now().toIso8601String(),
      'received_at': receivedAt,
      'status': 'replied', // Assuming outbound message
      'delivery_status': deliveryStatus,
      'reply_to_id': replyToId,
      'reply_to_platform_id': replyToPlatformId,
      'reply_to_body_preview': replyToBodyPreview,
      'reply_to_sender_name': replyToSenderName,
      'reply_count': 0,
      'is_forwarded': isForwarded ? 1 : 0,
      'sync_status': 'new', // Needs syncing
      'urgency': urgency,
      'sentiment': sentiment,
      'original_sender': originalSender,
      'is_read': 1, // Outgoing messages are always read
      // P1-1 FIX: Initialize retry tracking
      'retry_count': 0,
      'max_retries': 3,
      // v9 fields
      'sender_name': 'أنت', // Default for local outgoing
      'direction': 'outgoing',
      'channel_message_id': null, // populated after sync
      'platform_message_id': null, // populated after sync
    });
  }

  /// Get active chat history for a sender (Active Context)
  /// FIX: Select only necessary columns to avoid CursorWindow overflow
  Future<List<Map<String, dynamic>>> getChatHistory(
    String senderContact, {
    int limit = 50,
  }) async {
    final db = await _db;
    return await db.query(
      'inbox_messages',
      columns: [
        'local_id',
        'remote_id',
        'sender_contact',
        'sender_name',
        'channel',
        'body',
        'media_url',
        'created_at',
        'received_at',
        'edited_at',
        'status',
        'delivery_status',
        'sync_status',
        'reply_to_id',
        'reply_to_platform_id',
        'reply_to_body_preview',
        'reply_to_sender_name',
        'reply_count',
        'is_forwarded',
        'direction',
        'channel_message_id',
        'platform_message_id',
        'intent',
        'urgency',
        'sentiment',
        'is_read',
        'deleted_at',
        // Note: 'attachments' excluded by default to reduce row size
        // It can be fetched separately if needed
      ],
      where: 'sender_contact = ? AND deleted_at IS NULL',
      whereArgs: [senderContact],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  /// Get a single message with attachments (for lazy-loading attachment data)
  /// FIX: Use this method to fetch attachments for specific messages only
  Future<Map<String, dynamic>?> getMessageWithAttachments(int localId) async {
    final db = await _db;
    final results = await db.query(
      'inbox_messages',
      columns: [
        'local_id',
        'remote_id',
        'sender_contact',
        'sender_name',
        'channel',
        'body',
        'media_url',
        'attachments',  // Include attachments for this specific query
        'created_at',
        'received_at',
        'edited_at',
        'status',
        'delivery_status',
        'sync_status',
        'reply_to_id',
        'reply_to_platform_id',
        'reply_to_body_preview',
        'reply_to_sender_name',
        'reply_count',
        'is_forwarded',
        'direction',
        'channel_message_id',
        'platform_message_id',
        'intent',
        'urgency',
        'sentiment',
        'is_read',
      ],
      where: 'local_id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Get pending outbound messages
  Future<List<Map<String, dynamic>>> getPendingMessages() async {
    final db = await _db;
    return await db.query(
      'inbox_messages',
      where: 'sync_status = ?',
      whereArgs: ['new'],
      orderBy: 'created_at ASC',
    );
  }

  /// Get unsynced outgoing messages for a specific contact
  /// Used to merge with API results to preserve optimistic messages
  Future<List<Map<String, dynamic>>> getUnsyncedOutgoingMessages(String senderContact) async {
    final db = await _db;
    return await db.query(
      'inbox_messages',
      columns: [
        'local_id',
        'remote_id',
        'sender_contact',
        'sender_name',
        'channel',
        'body',
        'media_url',
        'attachments',
        'created_at',
        'received_at',
        'edited_at',
        'status',
        'delivery_status',
        'sync_status',
        'reply_to_id',
        'reply_to_platform_id',
        'reply_to_body_preview',
        'reply_to_sender_name',
        'reply_count',
        'is_forwarded',
        'direction',
        'channel_message_id',
        'platform_message_id',
        'intent',
        'urgency',
        'sentiment',
        'is_read',
      ],
      where: 'sender_contact = ? AND direction = ? AND sync_status = ? AND deleted_at IS NULL',
      whereArgs: [senderContact, 'outgoing', 'new'],
      orderBy: 'created_at ASC',
    );
  }

  /// Delete optimistic message after it's been synced
  /// Called when we receive the server-confirmed message to avoid duplicates
  Future<void> deleteOptimisticMessage(int localId) async {
    final db = await _db;
    await db.delete(
      'inbox_messages',
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  /// Mark outbound message as synced
  Future<void> markAsSynced(
    int localId,
    int remoteId, {
    String? platformMessageId,
    String? channelMessageId,
  }) async {
    final db = await _db;
    await db.update(
      'inbox_messages',
      {
        'sync_status': 'synced',
        'remote_id': remoteId,
        'platform_message_id': platformMessageId,
        'channel_message_id': channelMessageId,
        // P1-1 FIX: Reset retry count on successful sync
        'retry_count': 0,
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  /// P1-1 FIX: Increment retry count for a message
  /// Returns the new retry count
  Future<int> incrementRetryCount(int localId) async {
    final db = await _db;
    
    // Get current retry count
    final result = await db.query(
      'inbox_messages',
      where: 'local_id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    
    if (result.isEmpty) return 0;

    final currentRetry = (result.first['retry_count'] as int?) ?? 0;
    final newRetryCount = currentRetry + 1;
    
    // Update retry count and timestamp
    await db.update(
      'inbox_messages',
      {
        'retry_count': newRetryCount,
        'last_retry_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );
    
    return newRetryCount;
  }

  /// P1-1 FIX: Check if message has exceeded max retries
  Future<bool> hasExceededMaxRetries(int localId) async {
    final db = await _db;
    final result = await db.query(
      'inbox_messages',
      where: 'local_id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    
    if (result.isEmpty) return true;
    
    final retryCount = (result.first['retry_count'] as int?) ?? 0;
    final maxRetries = (result.first['max_retries'] as int?) ?? 3;
    
    return retryCount >= maxRetries;
  }

  /// P1-1 FIX: Get messages that can be retried (haven't exceeded max retries)
  Future<List<Map<String, dynamic>>> getRetryableMessages() async {
    final db = await _db;
    return await db.query(
      'inbox_messages',
      where: 'sync_status = ? AND retry_count < max_retries',
      whereArgs: ['new'],
      orderBy: 'created_at ASC',
    );
  }

  /// Update message status locally (e.g. Approve/Ignore)
  Future<void> updateMessageStatus(
    int remoteId,
    String status, {
    String? editedBody,
  }) async {
    final db = await _db;
    final Map<String, dynamic> values = {
      'status': status,
      'sync_status': 'dirty',
    };

    if (editedBody != null) {
      values['body'] = editedBody;
    }

    await db.update(
      'inbox_messages',
      values,
      where: 'remote_id = ?',
      whereArgs: [remoteId],
    );
  }

  /// Delete all messages for a specific contact (Local Clear)
  /// Clear chat history for a sender (with basic Telegram alias support)
  Future<void> clearChatHistory(String senderContact) async {
    final db = await _db;

    final List<String> contactsToClear = [senderContact];
    if (senderContact.startsWith('tg:')) {
      contactsToClear.add(senderContact.substring(3));
    } else if (senderContact.isNotEmpty && !senderContact.contains(':')) {
      // If it looks like a plain Telegram username/id, also try clearing with tg: prefix
      contactsToClear.add('tg:$senderContact');
    }

    final placeholders = contactsToClear.map((_) => '?').join(',');
    await db.delete(
      'inbox_messages',
      where: 'sender_contact IN ($placeholders)',
      whereArgs: contactsToClear,
    );
  }

  /// Update an existing message locally after it has been edited (Remote/Sync Edit)
  Future<void> updateMessageEditLocally(
    int remoteId,
    String newBody,
    String? editedAt,
  ) async {
    final db = await _db;
    await db.update(
      'inbox_messages',
      {
        'body': newBody,
        'edited_at': editedAt,
        'sync_status': 'synced', // Mark as synced after remote update
      },
      where: 'remote_id = ?',
      whereArgs: [remoteId],
    );
  }

  /// Update sync status and remote status for a message (e.g. from WebSocket)
  Future<void> updateMessageSyncStatus(int remoteId, String status) async {
    final db = await _db;
    await db.update(
      'inbox_messages',
      {'status': status, 'sync_status': 'synced'},
      where: 'remote_id = ?',
      whereArgs: [remoteId],
    );
  }

  /// Persist a single remote message (e.g. from WebSocket)
  Future<void> persistRemoteMessage(Map<String, dynamic> msg) async {
    final db = await _db;
    await db.insert('inbox_messages', {
      'remote_id': msg['id'],
      'sender_contact': msg['sender_contact'],
      'channel': msg['channel'],
      'body': msg['body'],
      'media_url': msg['media_url'],
      'intent': msg['intent'],
      'created_at': msg['created_at'] ?? msg['timestamp'],
      'received_at': msg['received_at'],
      'status': msg['status'],
      'delivery_status': msg['delivery_status'],
      'reply_to_id': msg['reply_to_id'],
      'reply_to_platform_id': msg['reply_to_platform_id'],
      'reply_to_body_preview': msg['reply_to_body_preview'],
      'reply_to_sender_name': msg['reply_to_sender_name'],
      'reply_count': msg['reply_count'] ?? 0,
      'sync_status': 'synced',
      'attachments': msg['attachments'] != null
          ? (msg['attachments'] is String
                ? msg['attachments']
                : jsonEncode(msg['attachments']))
          : null,
      'is_forwarded': (msg['is_forwarded'] == true || msg['is_forwarded'] == 1)
          ? 1
          : 0,
      'urgency': msg['urgency'],
      'sentiment': msg['sentiment'],
      'original_sender': msg['original_sender'],
      'deleted_at': msg['deleted_at'],
      'is_read': (msg['is_read'] == true || msg['is_read'] == 1) ? 1 : 0,
      'sender_name': msg['sender_name'],
      'channel_message_id': msg['channel_message_id'],
      'platform_message_id': msg['platform_message_id'],
      'direction': msg['direction'] ?? 'incoming',
      'edited_at': msg['edited_at'],
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ============ Outbox Messages Methods ============

  /// Insert an outbox message locally
  Future<int> insertOutboxMessage({
    required String channel,
    required String body,
    String? recipientId,
    String? recipientContact,
    String? subject,
    int? inboxMessageId,
    int? replyToId,
    String? replyToPlatformId,
    String? replyToBodyPreview,
    String? replyToSenderName,
    List<Map<String, dynamic>>? attachments,
    bool isForwarded = false,
    String status = 'pending',
    String? deliveryStatus,
  }) async {
    final db = await _db;
    return await db.insert('outbox_messages', {
      'channel': channel,
      'body': body,
      'recipient_id': recipientId,
      'recipient_contact': recipientContact,
      'subject': subject,
      'inbox_message_id': inboxMessageId,
      'reply_to_id': replyToId,
      'reply_to_platform_id': replyToPlatformId,
      'reply_to_body_preview': replyToBodyPreview,
      'reply_to_sender_name': replyToSenderName,
      'attachments': attachments != null ? jsonEncode(attachments) : null,
      'is_forwarded': isForwarded ? 1 : 0,
      'status': status,
      'delivery_status': deliveryStatus,
      'sync_status': 'new',
      'retry_count': 0,
      'max_retries': 3,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Get pending outbox messages
  Future<List<Map<String, dynamic>>> getPendingOutboxMessages() async {
    final db = await _db;
    return await db.query(
      'outbox_messages',
      where: 'sync_status = ? AND status IN (?, ?) AND deleted_at IS NULL',
      whereArgs: ['new', 'pending', 'approved'],
      orderBy: 'created_at ASC',
    );
  }

  /// Mark outbox message as synced
  Future<void> markOutboxAsSynced(
    int localId,
    int remoteId, {
    String? platformMessageId,
  }) async {
    final db = await _db;
    await db.update(
      'outbox_messages',
      {
        'sync_status': 'synced',
        'remote_id': remoteId,
        'platform_message_id': platformMessageId,
        'retry_count': 0,
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  /// Update outbox message status
  Future<void> updateOutboxStatus(int remoteId, String status, {String? errorMessage}) async {
    final db = await _db;
    final values = <String, dynamic>{
      'status': status,
      'sync_status': 'synced',
    };
    if (status == 'failed') {
      values['failed_at'] = DateTime.now().toIso8601String();
      if (errorMessage != null) {
        values['error_message'] = errorMessage;
      }
    } else if (status == 'sent') {
      values['sent_at'] = DateTime.now().toIso8601String();
    } else if (status == 'approved') {
      values['approved_at'] = DateTime.now().toIso8601String();
    }
    await db.update(
      'outbox_messages',
      values,
      where: 'remote_id = ?',
      whereArgs: [remoteId],
    );
  }

  /// Delete outbox message (soft delete)
  Future<void> deleteOutboxMessage(int remoteId) async {
    final db = await _db;
    await db.update(
      'outbox_messages',
      {
        'deleted_at': DateTime.now().toIso8601String(),
        'sync_status': 'dirty',
      },
      where: 'remote_id = ?',
      whereArgs: [remoteId],
    );
  }

  // ============ Inbox Conversations Methods ============

  /// Cache conversations list
  Future<void> cacheConversations(List<Map<String, dynamic>> conversations) async {
    final db = await _db;
    final batch = db.batch();
    for (var conv in conversations) {
      batch.insert('inbox_conversations', {
        'sender_contact': conv['sender_contact'],
        'sender_name': conv['sender_name'],
        'channel': conv['channel'],
        'last_message_id': conv['last_message_id'],
        'last_message_body': conv['last_message_body'],
        'last_message_ai_summary': conv['last_message_ai_summary'],
        'last_message_at': conv['last_message_at'],
        'last_message_attachments': conv['last_message_attachments'] != null
            ? jsonEncode(conv['last_message_attachments'])
            : null,
        'status': conv['status'],
        'delivery_status': conv['delivery_status'],
        'unread_count': conv['unread_count'] ?? 0,
        'message_count': conv['message_count'] ?? 0,
        'is_online': (conv['is_online'] == true || conv['is_online'] == 1) ? 1 : 0,
        'peer_license_id': conv['peer_license_id'],
        'avatar_url': conv['avatar_url'],
        'last_seen_at': conv['last_seen_at'],
        'sync_status': 'synced',
        'deleted_at': conv['deleted_at'],
        'last_updated_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Get all conversations
  Future<List<Map<String, dynamic>>> getConversations({int limit = 50, int offset = 0}) async {
    final db = await _db;
    return await db.query(
      'inbox_conversations',
      where: 'deleted_at IS NULL',
      orderBy: 'last_message_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  /// Get conversation by sender contact
  Future<Map<String, dynamic>?> getConversation(String senderContact) async {
    final db = await _db;
    final results = await db.query(
      'inbox_conversations',
      where: 'sender_contact = ?',
      whereArgs: [senderContact],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Update conversation unread count
  Future<void> updateConversationUnreadCount(
    String senderContact,
    int unreadCount,
  ) async {
    final db = await _db;
    await db.update(
      'inbox_conversations',
      {
        'unread_count': unreadCount,
        'last_updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'sender_contact = ?',
      whereArgs: [senderContact],
    );
  }

  /// Update conversation online status
  Future<void> updateConversationOnlineStatus(
    String senderContact,
    bool isOnline,
  ) async {
    final db = await _db;
    await db.update(
      'inbox_conversations',
      {
        'is_online': isOnline ? 1 : 0,
        'last_updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'sender_contact = ?',
      whereArgs: [senderContact],
    );
  }

  /// Mark conversation as read
  Future<void> markConversationAsRead(String senderContact) async {
    final db = await _db;
    await db.update(
      'inbox_conversations',
      {
        'unread_count': 0,
        'last_updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'sender_contact = ?',
      whereArgs: [senderContact],
    );
  }

  /// Delete conversation (soft delete)
  Future<void> deleteConversation(String senderContact) async {
    final db = await _db;
    await db.update(
      'inbox_conversations',
      {
        'deleted_at': DateTime.now().toIso8601String(),
        'sync_status': 'dirty',
      },
      where: 'sender_contact = ?',
      whereArgs: [senderContact],
    );
  }

  /// Clear all conversations data
  Future<void> clearConversations() async {
    final db = await _db;
    await db.delete('inbox_conversations');
  }

  /// P1-5 FIX: Check if a message has pending local operations
  /// Returns true if the message has pending send/edit/delete operations
  Future<bool> hasPendingOperation(int remoteId) async {
    final db = await _db;

    // Check if message exists with pending sync status
    final result = await db.query(
      'inbox_messages',
      columns: ['remote_id'],
      where: 'remote_id = ? AND sync_status != ?',
      whereArgs: [remoteId, 'synced'],
    );

    return result.isNotEmpty;
  }

  /// Migrate conversation contact when username changes
  Future<void> updateConversationContact(
    String oldContact,
    String newContact,
  ) async {
    final db = await _db;

    // Update sender_contact in conversations table
    await db.update(
      'inbox_conversations',
      {'sender_contact': newContact},
      where: 'sender_contact = ?',
      whereArgs: [oldContact],
    );
  }

  /// Migrate message sender_contact when username changes
  Future<void> updateMessageSenderContact(
    String oldContact,
    String newContact,
  ) async {
    final db = await _db;

    // Update sender_contact in inbox_messages table
    await db.update(
      'inbox_messages',
      {'sender_contact': newContact},
      where: 'sender_contact = ?',
      whereArgs: [oldContact],
    );
  }
}
