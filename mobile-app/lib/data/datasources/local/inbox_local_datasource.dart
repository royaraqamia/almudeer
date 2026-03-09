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
        'status': msg['status'],
        'reply_to_id': msg['reply_to_id'],
        'reply_to_platform_id': msg['reply_to_platform_id'],
        'reply_to_body_preview': msg['reply_to_body_preview'],
        'reply_to_sender_name': msg['reply_to_sender_name'],
        'sync_status': 'synced',
        'attachments': msg['attachments'] != null
            ? jsonEncode(msg['attachments'])
            : null,
        'is_forwarded':
            (msg['is_forwarded'] == true || msg['is_forwarded'] == 1) ? 1 : 0,

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
  }) async {
    final db = await _db;
    return await db.insert('inbox_messages', {
      'sender_contact': senderContact,
      'channel': channel,
      'body': body,
      'media_url': mediaUrl,
      'attachments': attachments != null ? jsonEncode(attachments) : null,
      'created_at': DateTime.now().toIso8601String(),
      'status': 'replied', // Assuming outbound message
      'reply_to_id': replyToId,
      'reply_to_platform_id': replyToPlatformId,
      'reply_to_body_preview': replyToBodyPreview,
      'reply_to_sender_name': replyToSenderName,
      'is_forwarded': isForwarded ? 1 : 0,
      'sync_status': 'new', // Needs syncing
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
        'edited_at',
        'status',
        'sync_status',
        'reply_to_id',
        'reply_to_platform_id',
        'reply_to_body_preview',
        'reply_to_sender_name',
        'is_forwarded',
        'direction',
        'channel_message_id',
        'platform_message_id',
        'intent',
        // Note: 'attachments' excluded by default to reduce row size
        // It can be fetched separately if needed
      ],
      where: 'sender_contact = ?',
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
        'edited_at',
        'status',
        'sync_status',
        'reply_to_id',
        'reply_to_platform_id',
        'reply_to_body_preview',
        'reply_to_sender_name',
        'is_forwarded',
        'direction',
        'channel_message_id',
        'platform_message_id',
        'intent',
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
      'status': msg['status'],
      'reply_to_id': msg['reply_to_id'],
      'reply_to_platform_id': msg['reply_to_platform_id'],
      'reply_to_body_preview': msg['reply_to_body_preview'],
      'reply_to_sender_name': msg['reply_to_sender_name'],
      'sync_status': 'synced',
      'attachments': msg['attachments'] != null
          ? (msg['attachments'] is String
                ? msg['attachments']
                : jsonEncode(msg['attachments']))
          : null,
      'is_forwarded': (msg['is_forwarded'] == true || msg['is_forwarded'] == 1)
          ? 1
          : 0,
      'sender_name': msg['sender_name'],
      'channel_message_id': msg['channel_message_id'],
      'platform_message_id': msg['platform_message_id'],
      'direction': msg['direction'] ?? 'incoming',
      'edited_at': msg['edited_at'],
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
    // Note: Conversations are typically cached in memory, but we update any persisted data
    await db.update(
      'conversations',
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
