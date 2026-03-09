import 'package:flutter_test/flutter_test.dart';
import 'package:almudeer_mobile_app/data/models/inbox_message.dart';

void main() {
  group('MessageSendStatus', () {
    test('should have correct enum values', () {
      expect(MessageSendStatus.values.length, 4);
      expect(MessageSendStatus.none.index, 0);
      expect(MessageSendStatus.sending.index, 1);
      expect(MessageSendStatus.sent.index, 2);
      expect(MessageSendStatus.failed.index, 3);
    });
  });

  group('InboxMessage', () {
    test('should create from JSON with all fields', () {
      final json = {
        'id': 1,
        'channel': 'telegram',
        'channel_message_id': 'msg_12345',
        'sender_id': 'user_123',
        'sender_name': 'أحمد محمد',
        'sender_contact': '+966501234567',
        'subject': 'استفسار',
        'body': 'مرحباً، أريد المساعدة',
        'received_at': '2024-01-15T10:30:00Z',
        'intent': 'inquiry',
        'urgency': 'high',
        'sentiment': 'neutral',
        'language': 'ar',
        'dialect': 'gulf',
        'ai_summary': 'عميل يطلب مساعدة',
        'ai_draft_response': 'مرحباً، كيف يمكنني مساعدتك؟',
        'status': 'analyzed',
        'created_at': '2024-01-15T10:30:00Z',
        'direction': 'incoming',
        'timestamp': '2024-01-15T10:30:00Z',
        'delivery_status': 'delivered',
        'attachments': [
          {'type': 'image', 'url': 'https://example.com/image.jpg'},
        ],
        'reply_to_id': 100,
        'reply_to_body': 'Previous message',
        'reply_to_sender_name': 'System',
        'edited_at': null,
      };

      final message = InboxMessage.fromJson(json);

      expect(message.id, 1);
      expect(message.channel, 'telegram');
      expect(message.channelMessageId, 'msg_12345');
      expect(message.senderId, 'user_123');
      expect(message.senderName, 'أحمد محمد');
      expect(message.senderContact, '+966501234567');
      expect(message.subject, 'استفسار');
      expect(message.body, 'مرحباً، أريد المساعدة');
      expect(message.status, 'analyzed');
      expect(message.direction, 'incoming');
      expect(message.deliveryStatus, 'delivered');
      expect(message.attachments?.length, 1);
      expect(message.replyToId, 100);
      expect(message.replyToBody, 'Previous message');
      expect(message.isEdited, isFalse);
    });

    test('should handle missing optional fields', () {
      final json = {
        'id': 2,
        'body': 'Simple message',
        'status': 'pending',
        'created_at': '2024-01-15',
      };

      final message = InboxMessage.fromJson(json);

      expect(message.id, 2);
      expect(message.channel, 'unknown');
      expect(message.senderName, isNull);
      expect(message.senderContact, isNull);
      expect(message.attachments, isNull);
    });

    test('should serialize to JSON correctly', () {
      final message = InboxMessage(
        id: 1,
        channel: 'whatsapp',
        senderName: 'Test User',
        senderContact: '+966500000000',
        body: 'Test message',
        status: 'sent',
        createdAt: '2024-01-01',
        direction: 'outgoing',
        deliveryStatus: 'delivered',
      );

      final json = message.toJson();

      expect(json['id'], 1);
      expect(json['channel'], 'whatsapp');
      expect(json['sender_name'], 'Test User');
      expect(json['sender_contact'], '+966500000000');
      expect(json['body'], 'Test message');
      expect(json['status'], 'sent');
      expect(json['direction'], 'outgoing');
      expect(json['delivery_status'], 'delivered');
    });

    test('isIncoming returns true for incoming messages', () {
      final message = InboxMessage(
        id: 1,
        channel: 'telegram',
        body: 'test',
        status: 'pending',
        createdAt: '2024-01-01',
        direction: 'incoming',
      );

      expect(message.isIncoming, isTrue);
      expect(message.isOutgoing, isFalse);
    });

    test('isOutgoing returns true for outgoing messages', () {
      final message = InboxMessage(
        id: 1,
        channel: 'telegram',
        body: 'test',
        status: 'sent',
        createdAt: '2024-01-01',
        direction: 'outgoing',
      );

      expect(message.isOutgoing, isTrue);
      expect(message.isIncoming, isFalse);
    });

    test('effectiveTimestamp returns timestamp when available', () {
      final message = InboxMessage(
        id: 1,
        channel: 'telegram',
        body: 'test',
        status: 'pending',
        createdAt: '2024-01-01',
        timestamp: '2024-01-02',
        receivedAt: '2024-01-03',
      );

      expect(message.effectiveTimestamp, '2024-01-02');
    });

    test('effectiveTimestamp falls back to receivedAt', () {
      final message = InboxMessage(
        id: 1,
        channel: 'telegram',
        body: 'test',
        status: 'pending',
        createdAt: '2024-01-01',
        receivedAt: '2024-01-03',
      );

      expect(message.effectiveTimestamp, '2024-01-03');
    });

    test('effectiveTimestamp falls back to createdAt', () {
      final message = InboxMessage(
        id: 1,
        channel: 'telegram',
        body: 'test',
        status: 'pending',
        createdAt: '2024-01-01',
      );

      expect(message.effectiveTimestamp, '2024-01-01');
    });

    test('displayName returns sender name when available', () {
      final message = InboxMessage(
        id: 1,
        channel: 'telegram',
        senderName: 'محمد علي',
        senderContact: '+966500000000',
        body: 'test',
        status: 'pending',
        createdAt: '2024-01-01',
      );

      expect(message.displayName, 'محمد علي');
    });

    test('displayName falls back to sender contact', () {
      final message = InboxMessage(
        id: 1,
        channel: 'telegram',
        senderContact: '+966501234567',
        body: 'test',
        status: 'pending',
        createdAt: '2024-01-01',
      );

      expect(message.displayName, '+966501234567');
    });

    test('displayName returns مجهول when no name or contact', () {
      final message = InboxMessage(
        id: 1,
        channel: 'telegram',
        body: 'test',
        status: 'pending',
        createdAt: '2024-01-01',
      );

      expect(message.displayName, 'مجهول');
    });

    test('deliveryStatusIcon returns check for sent', () {
      final message = InboxMessage(
        id: 1,
        channel: 'telegram',
        body: 'test',
        status: 'sent',
        deliveryStatus: 'sent',
        createdAt: '2024-01-01',
      );

      expect(message.deliveryStatusIcon, 'check');
    });

    test('deliveryStatusIcon returns error for failed', () {
      final message = InboxMessage(
        id: 1,
        channel: 'telegram',
        body: 'test',
        status: 'failed',
        deliveryStatus: 'failed',
        createdAt: '2024-01-01',
      );

      expect(message.deliveryStatusIcon, 'error');
    });

    test('copyWith creates new instance with updated fields', () {
      final original = InboxMessage(
        id: 1,
        channel: 'telegram',
        body: 'original',
        status: 'pending',
        createdAt: '2024-01-01',
        sendStatus: MessageSendStatus.none,
      );

      final updated = original.copyWith(
        status: 'approved',
        sendStatus: MessageSendStatus.sent,
        deliveryStatus: 'delivered',
      );

      expect(updated.id, 1);
      expect(updated.body, 'original');
      expect(updated.status, 'approved');
      expect(updated.sendStatus, MessageSendStatus.sent);
      expect(updated.deliveryStatus, 'delivered');
      expect(original.status, 'pending'); // Original unchanged
    });

    test('copyWithSendStatus updates only send status', () {
      final original = InboxMessage(
        id: 1,
        channel: 'telegram',
        body: 'test',
        status: 'pending',
        createdAt: '2024-01-01',
        sendStatus: MessageSendStatus.sending,
      );

      final updated = original.copyWithSendStatus(MessageSendStatus.sent);

      expect(updated.sendStatus, MessageSendStatus.sent);
      expect(updated.body, 'test');
    });
  });

  group('InboxMessage.optimistic', () {
    test('should create optimistic message for sending', () {
      final message = InboxMessage.optimistic(
        body: 'Sending this message',
        channel: 'telegram',
        senderContact: '+966500000000',
      );

      expect(message.id, isNegative); // Temporary negative ID
      expect(message.body, 'Sending this message');
      expect(message.channel, 'telegram');
      expect(message.status, 'sending');
      expect(message.direction, 'outgoing');
      expect(message.sendStatus, MessageSendStatus.sending);
    });
  });

  group('InboxMessagesResponse', () {
    test('should parse from JSON correctly', () {
      final json = {
        'messages': [
          {
            'id': 1,
            'channel': 'telegram',
            'body': 'Message 1',
            'status': 'pending',
            'created_at': '2024-01-01',
          },
          {
            'id': 2,
            'channel': 'whatsapp',
            'body': 'Message 2',
            'status': 'sent',
            'created_at': '2024-01-02',
          },
        ],
        'total': 50,
      };

      final response = InboxMessagesResponse.fromJson(json);

      expect(response.messages.length, 2);
      expect(response.total, 50);
    });
  });

  group('ConversationDetailResponse', () {
    test('should parse from JSON correctly', () {
      final json = {
        'sender_name': 'أحمد محمد',
        'sender_contact': '+966500000000',
        'messages': [
          {
            'id': 1,
            'channel': 'telegram',
            'body': 'Hello',
            'status': 'pending',
            'created_at': '2024-01-01',
            'direction': 'incoming',
          },
        ],
        'total': 10,
      };

      final response = ConversationDetailResponse.fromJson(json);

      expect(response.senderName, 'أحمد محمد');
      expect(response.senderContact, '+966500000000');
      expect(response.messages.length, 1);
      expect(response.total, 10);
    });
  });

  group('PaginatedMessagesResponse', () {
    test('should parse cursor-based pagination', () {
      final json = {
        'messages': [
          {
            'id': 1,
            'channel': 'telegram',
            'body': 'Test',
            'status': 'pending',
            'created_at': '2024-01-01',
          },
        ],
        'next_cursor': 'cursor_abc123',
        'has_more': true,
      };

      final response = PaginatedMessagesResponse.fromJson(json);

      expect(response.messages.length, 1);
      expect(response.nextCursor, 'cursor_abc123');
      expect(response.hasMore, isTrue);
    });

    test('should handle no more pages', () {
      final json = {'messages': [], 'next_cursor': null, 'has_more': false};

      final response = PaginatedMessagesResponse.fromJson(json);

      expect(response.messages, isEmpty);
      expect(response.nextCursor, isNull);
      expect(response.hasMore, isFalse);
    });
  });
}
