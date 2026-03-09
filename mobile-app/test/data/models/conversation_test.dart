import 'package:flutter_test/flutter_test.dart';
import 'package:almudeer_mobile_app/data/models/conversation.dart';

void main() {
  group('Conversation', () {
    test('should create from JSON with all fields', () {
      final json = {
        'id': 1,
        'channel': 'telegram',
        'sender_name': 'أحمد محمد',
        'sender_contact': '+966501234567',
        'sender_id': 'user_123',
        'subject': 'استفسار عن المنتج',
        'body': 'مرحباً، أريد الاستفسار عن أسعاركم',
        'intent': 'inquiry',
        'urgency': 'high',
        'sentiment': 'positive',
        'ai_summary': 'عميل يسأل عن الأسعار',
        'status': 'pending',
        'created_at': '2024-01-15T10:30:00Z',
        'message_count': 5,
        'unread_count': 2,
        'avatar_url': 'https://example.com/avatar.jpg',
      };

      final conversation = Conversation.fromJson(json);

      expect(conversation.id, 1);
      expect(conversation.channel, 'telegram');
      expect(conversation.senderName, 'أحمد محمد');
      expect(conversation.senderContact, '+966501234567');
      expect(conversation.senderId, 'user_123');
      expect(conversation.subject, 'استفسار عن المنتج');
      expect(conversation.body, 'مرحباً، أريد الاستفسار عن أسعاركم');
      expect(conversation.status, 'pending');
      expect(conversation.messageCount, 5);
      expect(conversation.unreadCount, 2);
      expect(conversation.avatarUrl, 'https://example.com/avatar.jpg');
    });

    test('should handle missing optional fields', () {
      final json = {
        'id': 2,
        'body': 'Hello',
        'status': 'pending',
        'created_at': '2024-01-15',
        'message_count': 1,
        'unread_count': 0,
      };

      final conversation = Conversation.fromJson(json);

      expect(conversation.id, 2);
      expect(conversation.channel, 'unknown');
      expect(conversation.senderName, isNull);
      expect(conversation.senderContact, isNull);
      expect(conversation.subject, isNull);
    });

    test('should serialize to JSON correctly', () {
      final conversation = Conversation(
        id: 1,
        channel: 'whatsapp',
        senderName: 'Test User',
        senderContact: '+966500000000',
        body: 'Test message',
        status: 'analyzed',
        createdAt: '2024-01-01',
        messageCount: 3,
        unreadCount: 1,
      );

      final json = conversation.toJson();

      expect(json['id'], 1);
      expect(json['channel'], 'whatsapp');
      expect(json['sender_name'], 'Test User');
      expect(json['sender_contact'], '+966500000000');
      expect(json['body'], 'Test message');
      expect(json['status'], 'analyzed');
      expect(json['message_count'], 3);
      expect(json['unread_count'], 1);
    });

    test('displayPreview returns body when available', () {
      final conversation = Conversation(
        id: 1,
        channel: 'telegram',
        body: 'This is the message body',
        status: 'pending',
        createdAt: '2024-01-01',
        messageCount: 1,
        unreadCount: 0,
      );

      expect(conversation.displayPreview, 'This is the message body');
    });

    test(
      'displayPreview returns appropriate Arabic text for attachments when body is empty',
      () {
        final baseConv = Conversation(
          id: 1,
          channel: 'telegram',
          body: '',
          status: 'pending',
          createdAt: '2024-01-01',
          messageCount: 1,
          unreadCount: 0,
        );

        final types = [
          ({'type': 'image'}, 'صورة'),
          ({'type': 'photo'}, 'صورة'),
          ({'mime_type': 'image/jpeg'}, 'صورة'),
          ({'type': 'video'}, 'فيديو'),
          ({'mime_type': 'video/mp4'}, 'فيديو'),
          ({'type': 'voice'}, 'تسجيل صوتي'),
          ({'mime_type': 'audio/ogg'}, 'تسجيل صوتي'),
          ({'type': 'audio'}, 'ملف صوتي'),
          ({'mime_type': 'audio/mpeg'}, 'ملف صوتي'),
          ({'type': 'note'}, 'ملاحظة'),
          ({'type': 'task'}, 'مَهمَّة'),
          ({'type': 'document'}, 'ملف'),
        ];

        for (final testCase in types) {
          final conv = baseConv.copyWith(
            attachments: [testCase.$1 as Map<String, dynamic>],
          );
          expect(
            conv.displayPreview,
            testCase.$2,
            reason: 'Failed for ${testCase.$1}',
          );
        }
      },
    );

    test('displayPreview defaults to رسالة for unknown content', () {
      final conversation = Conversation(
        id: 1,
        channel: 'telegram',
        body: '',
        status: 'pending',
        createdAt: '2024-01-01',
        messageCount: 1,
        unreadCount: 0,
        attachments: [],
      );

      expect(conversation.displayPreview, 'رسالة');
    });

    test('displayName returns sender name when available', () {
      final conversation = Conversation(
        id: 1,
        channel: 'telegram',
        senderName: 'محمد علي',
        senderContact: '+966500000000',
        body: 'test',
        status: 'pending',
        createdAt: '2024-01-01',
        messageCount: 1,
        unreadCount: 0,
      );

      expect(conversation.displayName, 'محمد علي');
    });

    test('displayName falls back to sender contact', () {
      final conversation = Conversation(
        id: 1,
        channel: 'telegram',
        senderContact: '+966501234567',
        body: 'test',
        status: 'pending',
        createdAt: '2024-01-01',
        messageCount: 1,
        unreadCount: 0,
      );

      expect(conversation.displayName, '+966501234567');
    });

    test('displayName returns مجهول when no name or contact', () {
      final conversation = Conversation(
        id: 1,
        channel: 'telegram',
        body: 'test',
        status: 'pending',
        createdAt: '2024-01-01',
        messageCount: 1,
        unreadCount: 0,
      );

      expect(conversation.displayName, 'مجهول');
    });

    test('avatarInitials returns first letters of two words', () {
      final conversation = Conversation(
        id: 1,
        channel: 'telegram',
        senderName: 'Ahmed Mohamed',
        body: 'test',
        status: 'pending',
        createdAt: '2024-01-01',
        messageCount: 1,
        unreadCount: 0,
      );

      expect(conversation.avatarInitials, 'AM');
    });

    test('hasUnread returns true when unreadCount > 0', () {
      final conversation = Conversation(
        id: 1,
        channel: 'telegram',
        body: 'test',
        status: 'pending',
        createdAt: '2024-01-01',
        messageCount: 5,
        unreadCount: 3,
      );

      expect(conversation.hasUnread, isTrue);
    });

    test('hasUnread returns false when unreadCount is 0', () {
      final conversation = Conversation(
        id: 1,
        channel: 'telegram',
        body: 'test',
        status: 'pending',
        createdAt: '2024-01-01',
        messageCount: 5,
        unreadCount: 0,
      );

      expect(conversation.hasUnread, isFalse);
    });

    test('channelDisplayName returns Arabic name for WhatsApp', () {
      final conversation = Conversation(
        id: 1,
        channel: 'whatsapp',
        body: 'test',
        status: 'pending',
        createdAt: '2024-01-01',
        messageCount: 1,
        unreadCount: 0,
      );

      expect(conversation.channelDisplayName, 'واتساب');
    });

    test('channelDisplayName returns Arabic name for Telegram', () {
      final conversation = Conversation(
        id: 1,
        channel: 'telegram',
        body: 'test',
        status: 'pending',
        createdAt: '2024-01-01',
        messageCount: 1,
        unreadCount: 0,
      );

      expect(conversation.channelDisplayName, 'تيليجرام');
    });

    test('statusDisplayName returns Arabic status', () {
      final pending = Conversation(
        id: 1,
        channel: 'telegram',
        body: 'test',
        status: 'pending',
        createdAt: '2024-01-01',
        messageCount: 1,
        unreadCount: 0,
      );

      expect(pending.statusDisplayName, 'قيد الانتظار');

      final approved = pending.copyWith(status: 'approved');
      expect(approved.statusDisplayName, 'تمت الموافقة');
    });

    test('copyWith creates new instance with updated fields', () {
      final original = Conversation(
        id: 1,
        channel: 'telegram',
        body: 'original',
        status: 'pending',
        createdAt: '2024-01-01',
        messageCount: 1,
        unreadCount: 0,
      );

      final updated = original.copyWith(status: 'approved', unreadCount: 5);

      expect(updated.id, 1);
      expect(updated.body, 'original');
      expect(updated.status, 'approved');
      expect(updated.unreadCount, 5);
      expect(original.status, 'pending'); // Original unchanged
    });
  });

  group('ConversationsResponse', () {
    test('should parse from JSON correctly', () {
      final json = {
        'conversations': [
          {
            'id': 1,
            'channel': 'telegram',
            'body': 'Message 1',
            'status': 'pending',
            'created_at': '2024-01-01',
            'message_count': 1,
            'unread_count': 0,
          },
          {
            'id': 2,
            'channel': 'whatsapp',
            'body': 'Message 2',
            'status': 'analyzed',
            'created_at': '2024-01-02',
            'message_count': 2,
            'unread_count': 1,
          },
        ],
        'total': 10,
        'has_more': true,
        'status_counts': {'pending': 5, 'analyzed': 3, 'approved': 2},
      };

      final response = ConversationsResponse.fromJson(json);

      expect(response.conversations.length, 2);
      expect(response.total, 10);
      expect(response.hasMore, isTrue);
      expect(response.statusCounts?['pending'], 5);
      expect(response.statusCounts?['analyzed'], 3);
    });

    test('should handle empty conversations list', () {
      final json = {'conversations': [], 'total': 0, 'has_more': false};

      final response = ConversationsResponse.fromJson(json);

      expect(response.conversations, isEmpty);
      expect(response.total, 0);
      expect(response.hasMore, isFalse);
    });
  });
}
