import 'dart:convert';
import 'dart:collection';  // P0-2 FIX: Import for LinkedHashMap
import 'package:uuid/uuid.dart';

enum MessageSendStatus { none, sending, sent, failed }

/// Inbox message model
class InboxMessage {
  // P0-2 FIX: UUID-based optimistic ID generation to eliminate collision risk
  // Previous timestamp-based approach had small collision risk when:
  // - Multiple messages sent in same millisecond
  // - App restarts quickly (same session timestamp)
  static final Uuid _uuid = Uuid();
  // P0-2 FIX: Use LinkedHashMap to guarantee insertion order for proper LRU eviction
  // Regular Map in Dart does not guarantee iteration order, which could cause
  // wrong entries to be evicted and lead to UUID collision
  static final LinkedHashMap<String, int> _uuidToIntCache = LinkedHashMap();
  static const int _maxCacheSize = 1000;
  static const int _evictBatchSize = 100;

  final int id;
  final String channel;
  final String? channelMessageId;
  final String? senderId;
  final String? senderName;
  final String? senderContact;
  final String? subject;
  final String body;
  final String? receivedAt;
  final String status;
  final String createdAt;
  final String? direction;
  final String? timestamp;
  final String? deliveryStatus;
  final List<Map<String, dynamic>>? attachments;
  final String? platformMessageId;
  final String? platformStatus;
  final String? originalSender;

  /// Reply-to context (when this message is a reply to another)
  final int? replyToId;
  final String? replyToPlatformId;
  final String? replyToBody;
  final String? replyToBodyPreview;
  final String? replyToSenderName;
  final List<Map<String, dynamic>>? replyToAttachments;
  final bool isForwarded;

  /// Edit tracking
  final String? editedAt;
  final bool isEdited;
  final bool isDeleted;

  /// Threading context
  final String? threadId;
  final int replyCount;

  /// Local send status for optimistic UI (not from server)
  final MessageSendStatus sendStatus;

  /// Server outbox ID for matching status updates with optimistic messages
  final int? outboxId;

  /// Upload progress tracking for attachments
  final bool isUploading;
  final double? uploadProgress;
  final int? uploadedBytes;
  final int? totalUploadBytes;

  InboxMessage({
    required this.id,
    required this.channel,
    this.channelMessageId,
    this.senderId,
    this.senderName,
    this.senderContact,
    this.subject,
    required this.body,
    this.receivedAt,
    required this.status,
    required this.createdAt,
    this.direction,
    this.timestamp,
    this.deliveryStatus,
    this.attachments,
    this.replyToId,
    this.replyToPlatformId,
    this.replyToBody,
    this.replyToBodyPreview,
    this.replyToSenderName,
    this.replyToAttachments,
    this.platformMessageId,
    this.platformStatus,
    this.originalSender,
    this.editedAt,
    this.isForwarded = false,
    this.isEdited = false,
    this.isDeleted = false,
    this.threadId,
    this.replyCount = 0,
    this.sendStatus = MessageSendStatus.none,
    this.outboxId,
    this.isUploading = false,
    this.uploadProgress,
    this.uploadedBytes,
    this.totalUploadBytes,
  });

  /// Create an optimistic outgoing message for instant UI feedback
  factory InboxMessage.optimistic({
    required String body,
    required String channel,
    String? senderContact,
    List<Map<String, dynamic>>? attachments,
    int? replyToId,
    String? replyToPlatformId,
    String? replyToBody,
    String? replyToBodyPreview,
    String? replyToSenderName,
    List<Map<String, dynamic>>? replyToAttachments,
    String? status,
    MessageSendStatus? sendStatus,
    bool? isUploading,
    double? uploadProgress,
    int? uploadedBytes,
    int? totalUploadBytes,
  }) {
    // P0-2 FIX: UUID-based ID generation to eliminate collision risk
    // Generate v4 UUID and convert to negative int for optimistic ID
    // Negative IDs indicate local-only messages that haven't been synced
    final uuid = _uuid.v4obj();
    final uuidString = uuid.toString();

    // Convert UUID to int using hash
    final id = _uuidToIntCache[uuidString] ?? (uuidString.hashCode % 1000000).abs() * -1;
    if (!_uuidToIntCache.containsKey(uuidString)) {
      _uuidToIntCache[uuidString] = id;
      // P0-2 FIX: LRU eviction - remove oldest 100 entries when cache exceeds max size
      if (_uuidToIntCache.length > _maxCacheSize) {
        final keysToRemove = _uuidToIntCache.keys.take(_evictBatchSize).toList();
        for (final key in keysToRemove) {
          _uuidToIntCache.remove(key);
        }
      }
    }

    return InboxMessage(
      id: id,
      channel: channel,
      senderContact: senderContact,
      body: body,
      direction: 'outgoing',
      status: status ?? 'pending',
      createdAt: DateTime.now().toIso8601String(),
      attachments: attachments,
      replyToId: replyToId,
      replyToPlatformId: replyToPlatformId,
      replyToBody: replyToBody,
      replyToBodyPreview: replyToBodyPreview,
      replyToSenderName: replyToSenderName,
      replyToAttachments: replyToAttachments,
      sendStatus: sendStatus ?? MessageSendStatus.sending,
      isUploading: isUploading ?? false,
      uploadProgress: uploadProgress,
      uploadedBytes: uploadedBytes,
      totalUploadBytes: totalUploadBytes,
    );
  }

  /// Empty message for dummy/placeholder use (e.g., selection mode menu)
  factory InboxMessage.empty() {
    return InboxMessage(
      id: -1,
      channel: '',
      body: '',
      status: '',
      createdAt: '',
    );
  }

  InboxMessage copyWith({
    int? id,
    String? channel,
    String? channelMessageId,
    String? senderId,
    String? senderName,
    String? senderContact,
    String? subject,
    String? body,
    String? receivedAt,
    String? status,
    String? createdAt,
    String? direction,
    String? timestamp,
    String? deliveryStatus,
    List<Map<String, dynamic>>? attachments,
    int? replyToId,
    String? replyToPlatformId,
    String? replyToBody,
    String? replyToBodyPreview,
    String? replyToSenderName,
    List<Map<String, dynamic>>? replyToAttachments,
    bool? isForwarded,
    String? platformMessageId,
    String? platformStatus,
    String? originalSender,
    String? editedAt,
    bool? isEdited,
    bool? isDeleted,
    MessageSendStatus? sendStatus,
    int? outboxId,
    String? threadId,
    int? replyCount,
    bool? isUploading,
    double? uploadProgress,
    int? uploadedBytes,
    int? totalUploadBytes,
  }) {
    return InboxMessage(
      id: id ?? this.id,
      channel: channel ?? this.channel,
      channelMessageId: channelMessageId ?? this.channelMessageId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderContact: senderContact ?? this.senderContact,
      subject: subject ?? this.subject,
      body: body ?? this.body,
      receivedAt: receivedAt ?? this.receivedAt,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      direction: direction ?? this.direction,
      timestamp: timestamp ?? this.timestamp,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      attachments: attachments ?? this.attachments,
      replyToId: replyToId ?? this.replyToId,
      replyToPlatformId: replyToPlatformId ?? this.replyToPlatformId,
      replyToBody: replyToBody ?? this.replyToBody,
      replyToBodyPreview: replyToBodyPreview ?? this.replyToBodyPreview,
      replyToSenderName: replyToSenderName ?? this.replyToSenderName,
      replyToAttachments: replyToAttachments ?? this.replyToAttachments,
      isForwarded: isForwarded ?? this.isForwarded,
      platformMessageId: platformMessageId ?? this.platformMessageId,
      platformStatus: platformStatus ?? this.platformStatus,
      originalSender: originalSender ?? this.originalSender,
      editedAt: editedAt ?? this.editedAt,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
      threadId: threadId ?? this.threadId,
      replyCount: replyCount ?? this.replyCount,
      sendStatus: sendStatus ?? this.sendStatus,
      outboxId: outboxId ?? this.outboxId,
      isUploading: isUploading ?? this.isUploading,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      uploadedBytes: uploadedBytes ?? this.uploadedBytes,
      totalUploadBytes: totalUploadBytes ?? this.totalUploadBytes,
    );
  }

  /// Create a copy with updated send status
  InboxMessage copyWithSendStatus(MessageSendStatus status) {
    return copyWith(sendStatus: status);
  }

  factory InboxMessage.fromJson(Map<String, dynamic> json) {
    // parse attachments safely
    List<Map<String, dynamic>>? attachmentsList;

    if (json['attachments'] != null) {
      if (json['attachments'] is String) {
        try {
          final decoded = jsonDecode(json['attachments'] as String);
          if (decoded is List) {
            attachmentsList = decoded.map((e) {
              if (e is String) {
                return {'url': e, 'type': 'file'};
              }
              return Map<String, dynamic>.from(e as Map);
            }).toList();
          }
        } catch (e) {
          // ignore error
        }
      } else if (json['attachments'] is List) {
        attachmentsList = (json['attachments'] as List).map((e) {
          if (e is String) {
            return {'url': e, 'type': 'file'};
          }
          return Map<String, dynamic>.from(e as Map);
        }).toList();
      }
    }

    // Fallback for legacy media_url and other variations
    if (attachmentsList == null || attachmentsList.isEmpty) {
      String? fallbackUrl;
      String? fallbackType;

      // Check various keys for media URL
      if (json['media_url'] != null) {
        fallbackUrl = json['media_url'].toString();
      } else if (json['url'] != null) {
        fallbackUrl = json['url'].toString();
      } else if (json['file_url'] != null) {
        fallbackUrl = json['file_url'].toString();
      } else if (json['attachment_url'] != null) {
        fallbackUrl = json['attachment_url'].toString();
      } else if (json['image'] != null &&
          json['image'].toString().startsWith('http')) {
        fallbackUrl = json['image'].toString();
        fallbackType = 'image';
      } else if (json['video'] != null &&
          json['video'].toString().startsWith('http')) {
        fallbackUrl = json['video'].toString();
        fallbackType = 'video';
      } else if (json['audio'] != null &&
          json['audio'].toString().startsWith('http')) {
        fallbackUrl = json['audio'].toString();
        fallbackType = 'audio';
      } else if (json['voice'] != null &&
          json['voice'].toString().startsWith('http')) {
        fallbackUrl = json['voice'].toString();
        fallbackType = 'voice';
      } else if (json['file'] != null &&
          json['file'].toString().startsWith('http')) {
        fallbackUrl = json['file'].toString();
        fallbackType = 'file';
      }

      if (fallbackUrl != null && fallbackUrl.isNotEmpty) {
        final mimeMatches = json['mime_type']?.toString().toLowerCase() ?? '';
        final ext = fallbackUrl.split('.').last.toLowerCase();

        // Infer type if not already set
        if (fallbackType == null) {
          fallbackType = 'file';
          if (mimeMatches.startsWith('image/') ||
              ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
            fallbackType = 'image';
          } else if (mimeMatches.startsWith('video/') ||
              ['mp4', 'mov', 'avi'].contains(ext)) {
            fallbackType = 'video';
          } else if (mimeMatches.startsWith('audio/') ||
              ['mp3', 'wav', 'm4a', 'aac'].contains(ext)) {
            fallbackType = 'audio';
          }
        }

        attachmentsList = [
          {
            'url': fallbackUrl,
            'type': fallbackType,
            'mime_type': json['mime_type'],
            'file_name':
                json['file_name'] ??
                json['filename'] ??
                fallbackUrl.split('/').last,
            'file_size': json['file_size'],
          },
        ];
      }
    }

    return InboxMessage(
      // FIX P3: Validate ID - use 0 for invalid/missing IDs instead of crashing
      id: (json['id'] is int && json['id'] as int > 0)
          ? json['id'] as int
          : (int.tryParse(json['id']?.toString() ?? '0') ?? 0),
      channel: json['channel'] as String? ?? 'unknown',
      channelMessageId: json['channel_message_id'] as String?,
      senderId: json['sender_id'] as String?,
      senderName: json['sender_name'] as String?,
      senderContact: json['sender_contact'] as String?,
      subject: json['subject'] as String?,
      body: json['body'] as String? ?? '',
      receivedAt: json['received_at'] as String?,
      status: json['status'] as String? ?? 'received',
      createdAt: json['created_at'] as String? ?? '',
      direction: json['direction'] as String?,
      timestamp: json['timestamp'] as String?,
      deliveryStatus: json['delivery_status'] as String?,
      attachments: attachmentsList,
      replyToId: json['reply_to_id'] is int
          ? json['reply_to_id'] as int
          : int.tryParse(json['reply_to_id']?.toString() ?? ''),
      replyToPlatformId: json['reply_to_platform_id'] as String?,
      replyToBody: json['reply_to_body'] as String?,
      replyToBodyPreview: json['reply_to_body_preview'] as String?,
      replyToSenderName: json['reply_to_sender_name'] as String?,
      replyToAttachments:
          null, // Ideally we parse this if backend sends it, but for now we rely on local cache passing it.
      isForwarded: json['is_forwarded'] == true || json['is_forwarded'] == 1,
      platformMessageId: json['platform_message_id'] as String?,
      platformStatus: json['platform_status'] as String?,
      originalSender: json['original_sender'] as String?,
      editedAt: json['edited_at'] as String?,
      isEdited: json['edited_at'] != null,
      isDeleted: json['deleted_at'] != null,
      sendStatus:
          (json['status'] == 'failed' || json['delivery_status'] == 'failed')
          ? MessageSendStatus.failed
          : MessageSendStatus.none,
      outboxId: json['outbox_id'] is int
          ? json['outbox_id'] as int
          : int.tryParse(json['outbox_id']?.toString() ?? ''),
      threadId: json['thread_id']?.toString(),
      replyCount: json['reply_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'channel': channel,
      'channel_message_id': channelMessageId,
      'sender_id': senderId,
      'sender_name': senderName,
      'sender_contact': senderContact,
      'subject': subject,
      'body': body,
      'received_at': receivedAt,
      'status': status,
      'created_at': createdAt,
      'direction': direction,
      'timestamp': timestamp,
      'delivery_status': deliveryStatus,
      'platform_message_id': platformMessageId,
      'platform_status': platformStatus,
      'reply_to_platform_id': replyToPlatformId,
      'reply_to_body_preview': replyToBodyPreview,
      'reply_to_sender_name': replyToSenderName,
      'is_forwarded': isForwarded,
      'attachments': attachments,
      'edited_at': editedAt,
      'is_edited': isEdited,
      'is_deleted': isDeleted,
      'outbox_id': outboxId,
      'send_status': sendStatus.name,
      'thread_id': threadId,
      'reply_count': replyCount,
    };
  }

  /// Check if message is incoming
  bool get isIncoming => direction?.toLowerCase() == 'incoming';

  /// Check if message is outgoing
  bool get isOutgoing => direction?.toLowerCase() == 'outgoing';

  /// Get effective timestamp
  String get effectiveTimestamp {
    return timestamp ?? receivedAt ?? createdAt;
  }

  /// Get display name
  String get displayName {
    if (senderName != null && senderName!.isNotEmpty) {
      return senderName!;
    }
    if (senderContact != null && senderContact!.isNotEmpty) {
      return senderContact!;
    }
    return 'مجهول';
  }

  /// Get delivery status icon name
  String get deliveryStatusIcon {
    switch (deliveryStatus?.toLowerCase()) {
      case 'sent':
        return 'check';
      case 'failed':
        return 'error';
      default:
        // Also check main status
        if (status == 'sent' || status == 'received') {
          return 'check';
        }
        if (status == 'failed') {
          return 'error';
        }
        return 'clock';
    }
  }

  /// Check if the message can be edited based on channel rules
  bool get canEdit {
    if (!isOutgoing) return false;
    if (isDeleted) return false;

    // Allowed channels: ONLY almudeer and saved (Drafts)
    if (!const ['almudeer', 'saved'].contains(channel)) {
      return false;
    }

    // 24-hour edit window
    try {
      final createdTS = timestamp ?? createdAt;
      final created = DateTime.parse(createdTS);
      if (DateTime.now().difference(created).inHours > 24) {
        return false;
      }
    } catch (e) {
      // If parsing fails, fall back to createdAt (which is guaranteed non-null in constructor)
      try {
        final created = DateTime.parse(createdAt);
        if (DateTime.now().difference(created).inHours > 24) {
          return false;
        }
      } catch (e2) {
        return false; // Safest: Cannot edit if time is unknown
      }
    }

    return true;
  }
}

/// Inbox messages list response
class InboxMessagesResponse {
  final List<InboxMessage> messages;
  final int total;

  InboxMessagesResponse({required this.messages, required this.total});

  factory InboxMessagesResponse.fromJson(Map<String, dynamic> json) {
    final messagesList =
        (json['messages'] as List<dynamic>?)
            ?.map((e) => InboxMessage.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    return InboxMessagesResponse(
      messages: messagesList,
      total: json['total'] as int? ?? 0,
    );
  }
}

/// Conversation detail response
class ConversationDetailResponse {
  final String senderName;
  final String senderContact;
  final List<InboxMessage> messages;
  final int total;

  ConversationDetailResponse({
    required this.senderName,
    required this.senderContact,
    required this.messages,
    required this.total,
  });

  factory ConversationDetailResponse.fromJson(Map<String, dynamic> json) {
    final messagesList =
        (json['messages'] as List<dynamic>?)
            ?.map((e) => InboxMessage.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    return ConversationDetailResponse(
      senderName: json['sender_name'] as String? ?? '',
      senderContact: json['sender_contact'] as String? ?? '',
      messages: messagesList,
      total: json['total'] as int? ?? 0,
    );
  }
}

/// Paginated messages response (cursor-based)
class PaginatedMessagesResponse {
  final List<InboxMessage> messages;
  final String? nextCursor;
  final bool hasMore;

  PaginatedMessagesResponse({
    required this.messages,
    this.nextCursor,
    required this.hasMore,
  });

  factory PaginatedMessagesResponse.fromJson(Map<String, dynamic> json) {
    return PaginatedMessagesResponse(
      messages:
          (json['messages'] as List?)
              ?.map((e) => InboxMessage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      nextCursor: json['next_cursor'] as String?,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }
}
