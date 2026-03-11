/// Conversation model for chat-style inbox
class Conversation {
  final int id;
  final String channel;
  final String? senderName;
  final String? senderContact;
  final String? senderId;
  final String? subject;
  final String body;
  final String status;
  final String createdAt;
  final int messageCount;
  final int unreadCount;
  final String? avatarUrl;
  final String? lastSeenAt;
  final bool isOnline;
  final List<dynamic>? attachments;
  final bool isPinned;
  final String? deliveryStatus;

  /// Associated customer (optional - used for custom name lookup)
  final dynamic customer;

  Conversation({
    required this.id,
    required this.channel,
    this.senderName,
    this.senderContact,
    this.senderId,
    this.subject,
    required this.body,
    required this.status,
    required this.createdAt,
    required this.messageCount,
    required this.unreadCount,
    this.avatarUrl,
    this.lastSeenAt,
    this.isOnline = false,
    this.attachments,
    this.isPinned = false,
    this.deliveryStatus,
    this.customer,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    // FIX: Validate ID - use fallback for invalid IDs instead of throwing
    // This prevents crashes when backend returns 0 or null IDs
    final idValue = json['id'] as int?;
    int validId = idValue ?? 0;

    // If ID is invalid (0 or negative), generate a temporary ID based on sender_contact
    // This ensures the UI doesn't crash while still showing the conversation
    if (validId <= 0) {
      final senderContact = json['sender_contact'] as String? ?? '';
      final channel = json['channel'] as String? ?? '';
      // Generate consistent temp ID from sender_contact + channel
      validId = '${senderContact}_$channel'.hashCode.abs() % 1000000;
      // Keep it in a safe range and mark as negative to indicate temp
      validId = -validId;
    }

    return Conversation(
      id: validId,
      channel: json['channel'] as String? ?? 'unknown',
      senderName: json['sender_name'] as String?,
      senderContact: json['sender_contact'] as String?,
      senderId: json['sender_id'] as String?,
      subject: json['subject'] as String?,
      body: json['body'] as String? ?? '',
      status: json['status'] as String? ?? 'received',
      createdAt: json['created_at'] as String? ?? '',
      messageCount: json['message_count'] as int? ?? 0,
      unreadCount: json['unread_count'] as int? ?? 0,
      avatarUrl: json['avatar_url'] as String?,
      lastSeenAt: json['last_seen_at'] as String?,
      isOnline: json['is_online'] as bool? ?? false,
      attachments: json['attachments'] as List<dynamic>?,
      isPinned: json['is_pinned'] as bool? ?? false,
      deliveryStatus: json['delivery_status'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'channel': channel,
      'sender_name': senderName,
      'sender_contact': senderContact,
      'sender_id': senderId,
      'subject': subject,
      'body': body,
      'status': status,
      'created_at': createdAt,
      'message_count': messageCount,
      'unread_count': unreadCount,
      'avatar_url': avatarUrl,
      'last_seen_at': lastSeenAt,
      'is_online': isOnline,
      'attachments': attachments,
      'is_pinned': isPinned,
      'delivery_status': deliveryStatus,
    };
  }

  /// Get display preview for conversation list
  String get displayPreview {
    if (senderContact == '__saved_messages__') {
      return '';
    }

    // If no messages left AND body is empty, show specialized placeholder
    if (messageCount == 0 && body.isEmpty) {
      return 'لا توجد رسائل';
    }

    // If body has content, use it (and prepend emoji if attachments exist)
    if (body.isNotEmpty) {
      final String preview = body.replaceAll('\n', ' ');
      if (attachments != null && attachments!.isNotEmpty) {
        final att = attachments!.first;
        final type = att['type']?.toString().toLowerCase();
        final mime = att['mime_type']?.toString().toLowerCase();
        final filename = (att['filename'] ?? att['file_name'] ?? '')
            .toString()
            .toLowerCase();

        String emoji = '';
        if (type == 'image' ||
            type == 'photo' ||
            mime?.startsWith('image/') == true) {
          emoji = '📸';
        } else if (type == 'video' || mime?.startsWith('video/') == true) {
          emoji = '🎥';
        } else if (type == 'audio' ||
            mime == 'audio/mpeg' ||
            mime == 'audio/mp3') {
          emoji = '🎵';
        } else if (type == 'voice' ||
            type == 'audio' ||
            mime?.startsWith('audio/') == true) {
          emoji = '🎤';
        } else if (type == 'note') {
          emoji = '📝';
        } else if (type == 'task') {
          emoji = '✅';
        } else if (filename.endsWith('.zip') ||
            filename.endsWith('.rar') ||
            filename.endsWith('.7z')) {
          emoji = '📦';
        } else {
          emoji = '📄';
        }

        if (emoji.isNotEmpty) {
          return '$emoji $preview';
        }
      }
      return preview;
    }

    // Check for attachments if body is empty
    if (attachments != null && attachments!.isNotEmpty) {
      final att = attachments!.first;
      final type = att['type']?.toString().toLowerCase();
      final mime = att['mime_type']?.toString().toLowerCase();
      final filename = (att['filename'] ?? att['file_name'] ?? '')
          .toString()
          .toLowerCase();

      if (type == 'image' ||
          type == 'photo' ||
          mime?.startsWith('image/') == true) {
        return '📸 صورة';
      } else if (type == 'video' || mime?.startsWith('video/') == true) {
        return '🎥 فيديو';
      } else if (type == 'audio' ||
          mime == 'audio/mpeg' ||
          mime == 'audio/mp3') {
        return '🎵 ملف صوتي';
      } else if (type == 'voice' ||
          type == 'audio' ||
          mime?.startsWith('audio/') == true) {
        return '🎤 تسجيل صوتي';
      } else if (type == 'note') {
        return '📝 ملاحظة';
      } else if (type == 'task') {
        return '✅ مَهمَّة';
      } else if (filename.endsWith('.zip') ||
          filename.endsWith('.rar') ||
          filename.endsWith('.7z')) {
        return '📦 ملف مضغوط';
      }
      return '📄 ملف';
    }

    // Default case for unknown content
    return 'رسالة';
  }

  /// Get display name (sender name or contact)
  String get displayName {
    if (senderContact == '__saved_messages__') {
      return 'الرَّسائل المحفوظة';
    }
    // Check if we have an associated customer with a custom name
    if (customer != null) {
      final customerName = _getCustomerName();
      if (customerName != null && customerName.isNotEmpty) {
        return customerName;
      }
    }
    if (senderName != null && senderName!.isNotEmpty) {
      return senderName!;
    }
    if (senderContact != null && senderContact!.isNotEmpty) {
      return senderContact!;
    }
    return 'مجهول';
  }

  /// Helper to get customer name if customer exists
  String? _getCustomerName() {
    if (customer == null) return null;
    // Check if customer has a 'name' field with value
    final customerMap = customer is Map
        ? customer as Map<String, dynamic>
        : null;
    if (customerMap != null) {
      final name = customerMap['name'] as String?;
      if (name != null && name.isNotEmpty) {
        return name;
      }
    }
    // Also check for displayName method/field
    final dynamicCustomer = customer as dynamic;
    if (dynamicCustomer.displayName != null) {
      return dynamicCustomer.displayName as String?;
    }
    return null;
  }

  /// Get avatar initials
  String get avatarInitials {
    if (senderContact == '__saved_messages__') return '🔖';
    final name = displayName;
    if (name.isEmpty || name == 'مجهول') return '?';

    final words = name.split(' ');
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}';
    }
    return name[0];
  }

  /// Check if the last message was outgoing
  bool get isOutgoing =>
      status.toLowerCase() == 'sent' ||
      status.toLowerCase() == 'pending' ||
      status.toLowerCase() == 'failed' ||
      status.toLowerCase() == 'sending' ||
      status.toLowerCase() == 'approved';

  /// Check if has unread messages
  bool get hasUnread => unreadCount > 0;

  /// Get channel display name
  String get channelDisplayName {
    switch (channel.toLowerCase()) {
      case 'whatsapp':
        return 'واتساب';
      case 'telegram':
      case 'telegram_bot':
        return 'تيليجرام';
      case 'email':
        return 'بريد إلكتروني';
      case 'saved':
        return 'الرَّسائل المحفوظة';
      default:
        return channel;
    }
  }

  /// Get status display name
  String get statusDisplayName {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'قيد الانتظار';
      case 'analyzed':
        return 'تم التحليل';
      case 'approved':
        return 'تمت الموافقة';
      case 'ignored':
        return 'تم التجاهل';
      case 'sent':
        return 'تم الإرسال';
      case 'received':
        return 'تم الاستلام';
      case 'failed':
        return 'فشل الإرسال';
      default:
        return status;
    }
  }

  Conversation copyWith({
    int? id,
    String? channel,
    String? senderName,
    String? senderContact,
    String? senderId,
    String? subject,
    String? body,
    String? status,
    String? createdAt,
    int? messageCount,
    int? unreadCount,
    String? avatarUrl,
    String? lastSeenAt,
    bool? isOnline,
    List<dynamic>? attachments,
    bool? isPinned,
    dynamic customer,
  }) {
    return Conversation(
      id: id ?? this.id,
      channel: channel ?? this.channel,
      senderName: senderName ?? this.senderName,
      senderContact: senderContact ?? this.senderContact,
      senderId: senderId ?? this.senderId,
      subject: subject ?? this.subject,
      body: body ?? this.body,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      messageCount: messageCount ?? this.messageCount,
      unreadCount: unreadCount ?? this.unreadCount,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      isOnline: isOnline ?? this.isOnline,
      attachments: attachments ?? this.attachments,
      isPinned: isPinned ?? this.isPinned,
      customer: customer ?? this.customer,
    );
  }
}

/// Conversations list response
class ConversationsResponse {
  final List<Conversation> conversations;
  final int total;
  final bool hasMore;
  final Map<String, int>? statusCounts;

  ConversationsResponse({
    required this.conversations,
    required this.total,
    required this.hasMore,
    this.statusCounts,
  });

  factory ConversationsResponse.fromJson(Map<String, dynamic> json) {
    final conversationsList =
        (json['conversations'] as List<dynamic>?)
            ?.map((e) => Conversation.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    Map<String, int>? statusCounts;
    if (json['status_counts'] != null && json['status_counts'] is Map) {
      statusCounts = {};
      final counts = json['status_counts'] as Map<String, dynamic>;
      counts.forEach((key, value) {
        if (value != null) {
          statusCounts![key] = value is int
              ? value
              : int.tryParse(value.toString()) ?? 0;
        }
      });
    }

    return ConversationsResponse(
      conversations: conversationsList,
      total: json['total'] as int? ?? 0,
      hasMore: json['has_more'] as bool? ?? false,
      statusCounts: statusCounts,
    );
  }
}
