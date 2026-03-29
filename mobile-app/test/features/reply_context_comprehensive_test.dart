/// Comprehensive tests for Reply Context Feature
/// Tests reply functionality across all channels (WhatsApp, Telegram, Almudeer)
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almudeer_mobile_app/features/inbox/data/models/inbox_message.dart';
import 'package:almudeer_mobile_app/features/inbox/presentation/widgets/chat/reply_preview.dart';

void main() {
  group('Reply Context Feature - Comprehensive Tests', () {
    
    group('InboxMessage Model', () {
      test('InboxMessage should have all reply context fields', () {
        final message = InboxMessage(
          id: 1,
          channel: 'whatsapp',
          body: 'Test reply',
          status: 'received',
          createdAt: DateTime.now().toIso8601String(),
          direction: 'incoming',
          replyToId: 100,
          replyToPlatformId: 'platform_msg_123',
          replyToBody: 'Original message body',
          replyToBodyPreview: 'Original message preview',
          replyToSenderName: 'John Doe',
          replyToAttachments: [
            {'type': 'photo', 'url': 'https://example.com/photo.jpg'}
          ],
          replyCount: 2,
        );
        
        expect(message.replyToId, equals(100));
        expect(message.replyToPlatformId, equals('platform_msg_123'));
        expect(message.replyToBody, equals('Original message body'));
        expect(message.replyToBodyPreview, equals('Original message preview'));
        expect(message.replyToSenderName, equals('John Doe'));
        expect(message.replyToAttachments, isNotEmpty);
        expect(message.replyCount, equals(2));
        expect(message.isOutgoing, isFalse);
      });
      
      test('InboxMessage optimistic should include reply context', () {
        final optimisticMessage = InboxMessage.optimistic(
          body: 'Optimistic reply',
          channel: 'whatsapp',
          senderContact: '+1234567890',
          replyToId: 50,
          replyToPlatformId: 'platform_456',
          replyToBodyPreview: 'Preview text',
          replyToSenderName: 'Jane Smith',
          status: 'sending',
          sendStatus: MessageSendStatus.sending,
        );
        
        expect(optimisticMessage.replyToId, equals(50));
        expect(optimisticMessage.replyToPlatformId, equals('platform_456'));
        expect(optimisticMessage.replyToBodyPreview, equals('Preview text'));
        expect(optimisticMessage.replyToSenderName, equals('Jane Smith'));
        expect(optimisticMessage.sendStatus, equals(MessageSendStatus.sending));
      });
      
      test('InboxMessage copyWith should preserve reply context', () {
        final original = InboxMessage(
          id: 1,
          channel: 'whatsapp',
          body: 'Original',
          status: 'received',
          createdAt: DateTime.now().toIso8601String(),
          direction: 'incoming',
          replyToId: 100,
          replyToPlatformId: 'platform_100',
          replyToBodyPreview: 'Original preview',
          replyToSenderName: 'Sender Name',
          replyCount: 0,
        );
        
        final updated = original.copyWith(body: 'Updated body');
        
        expect(updated.body, equals('Updated body'));
        expect(updated.replyToId, equals(100));
        expect(updated.replyToPlatformId, equals('platform_100'));
        expect(updated.replyToBodyPreview, equals('Original preview'));
        expect(updated.replyToSenderName, equals('Sender Name'));
      });
      
      test('InboxMessage fromJson should parse reply context fields', () {
        final json = {
          'id': 1,
          'channel': 'whatsapp',
          'body': 'Test message',
          'status': 'received',
          'direction': 'incoming',
          'createdAt': DateTime.now().toIso8601String(),
          'reply_to_id': 100,
          'reply_to_platform_id': 'platform_123',
          'reply_to_body_preview': 'Preview text',
          'reply_to_sender_name': 'Sender Name',
          'reply_count': 3,
        };
        
        final message = InboxMessage.fromJson(json);
        
        expect(message.replyToId, equals(100));
        expect(message.replyToPlatformId, equals('platform_123'));
        expect(message.replyToBodyPreview, equals('Preview text'));
        expect(message.replyToSenderName, equals('Sender Name'));
        expect(message.replyCount, equals(3));
      });
      
      test('InboxMessage handles null reply context fields', () {
        final message = InboxMessage(
          id: 1,
          channel: 'whatsapp',
          body: 'Message without reply context',
          status: 'received',
          createdAt: DateTime.now().toIso8601String(),
          direction: 'incoming',
        );
        
        expect(message.replyToId, isNull);
        expect(message.replyToPlatformId, isNull);
        expect(message.replyToBody, isNull);
        expect(message.replyToBodyPreview, isNull);
        expect(message.replyToSenderName, isNull);
        expect(message.replyToAttachments, isNull);
        expect(message.replyCount, equals(0));
      });
      
      test('InboxMessage replyCount defaults to 0', () {
        final message = InboxMessage(
          id: 1,
          channel: 'whatsapp',
          body: 'Test',
          status: 'received',
          createdAt: DateTime.now().toIso8601String(),
          direction: 'incoming',
        );
        
        expect(message.replyCount, equals(0));
      });
      
      test('InboxMessage isOutgoing getter works correctly', () {
        final incoming = InboxMessage(
          id: 1,
          channel: 'whatsapp',
          body: 'Test',
          status: 'received',
          createdAt: DateTime.now().toIso8601String(),
          direction: 'incoming',
        );
        
        final outgoing = InboxMessage(
          id: 2,
          channel: 'whatsapp',
          body: 'Test',
          status: 'sent',
          createdAt: DateTime.now().toIso8601String(),
          direction: 'outgoing',
        );
        
        expect(incoming.isOutgoing, isFalse);
        expect(outgoing.isOutgoing, isTrue);
      });
    });
    
    group('ReplyPreview Widget', () {
      testWidgets('ReplyPreview displays incoming message reply correctly', (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReplyPreview(
                senderName: 'John Doe',
                messageBody: 'This is the original message',
                isOutgoing: false,
                onCancel: () {},
              ),
            ),
          ),
        );
        
        // Verify sender name is displayed
        expect(find.text('John Doe'), findsOneWidget);
        
        // Verify message body is displayed
        expect(find.text('This is the original message'), findsOneWidget);
        
        // Verify cancel button exists (check for semantics label)
        expect(find.bySemanticsLabel('ط¥ظ„ط؛ط§ط، ط§ظ„ط±ظژظ‘ط¯'), findsOneWidget);
      });
      
      testWidgets('ReplyPreview displays outgoing message with "ط£ظ†طھ" label', (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReplyPreview(
                senderName: 'John Doe',
                messageBody: 'My original message',
                isOutgoing: true,
                onCancel: () {},
              ),
            ),
          ),
        );
        
        // For outgoing messages, should show "ط£ظ†طھ" (You)
        expect(find.text('ط£ظ†طھ'), findsOneWidget);
        expect(find.text('My original message'), findsOneWidget);
      });
      
      testWidgets('ReplyPreview cancel button triggers callback', (WidgetTester tester) async {
        bool cancelCalled = false;
        
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReplyPreview(
                senderName: 'John',
                messageBody: 'Message',
                isOutgoing: false,
                onCancel: () {
                  cancelCalled = true;
                },
              ),
            ),
          ),
        );
        
        // Tap cancel button using semantics label
        await tester.tap(find.bySemanticsLabel('ط¥ظ„ط؛ط§ط، ط§ظ„ط±ظژظ‘ط¯'));
        await tester.pump();
        
        expect(cancelCalled, isTrue);
      });
    });
    
    group('Channel-Specific Reply Context', () {
      test('WhatsApp message with reply context', () {
        final message = InboxMessage(
          id: 1,
          channel: 'whatsapp',
          body: 'WhatsApp reply',
          status: 'received',
          createdAt: DateTime.now().toIso8601String(),
          direction: 'incoming',
          replyToPlatformId: 'wamid.HBgNMTIzNDU2Nzg5MA==',
          replyToSenderName: 'WhatsApp User',
        );
        
        expect(message.channel, equals('whatsapp'));
        expect(message.replyToPlatformId?.startsWith('wamid.'), isTrue);
      });
      
      test('Telegram message with reply context', () {
        final message = InboxMessage(
          id: 2,
          channel: 'telegram_bot',
          body: 'Telegram reply',
          status: 'received',
          createdAt: DateTime.now().toIso8601String(),
          direction: 'incoming',
          replyToPlatformId: '123456',
          replyToSenderName: 'Telegram User',
        );
        
        expect(message.channel, equals('telegram_bot'));
        expect(int.tryParse(message.replyToPlatformId!), isNotNull);
      });
      
      test('Almudeer message with reply context', () {
        final message = InboxMessage(
          id: 3,
          channel: 'almudeer',
          body: 'Almudeer reply',
          status: 'received',
          createdAt: DateTime.now().toIso8601String(),
          direction: 'incoming',
          replyToId: 100,
          replyToSenderName: 'ط£ظ†ط§',
        );
        
        expect(message.channel, equals('almudeer'));
        expect(message.replyToId, equals(100));
      });
    });
    
    group('Reply Context Edge Cases', () {
      test('InboxMessage handles empty string reply fields', () {
        final message = InboxMessage(
          id: 1,
          channel: 'whatsapp',
          body: 'Test',
          status: 'received',
          createdAt: DateTime.now().toIso8601String(),
          direction: 'incoming',
          replyToBodyPreview: '',
          replyToSenderName: '',
        );
        
        expect(message.replyToBodyPreview, equals(''));
        expect(message.replyToSenderName, equals(''));
      });
      
      test('InboxMessage canEdit returns false for incoming messages', () {
        final incoming = InboxMessage(
          id: 1,
          channel: 'whatsapp',
          body: 'Test',
          status: 'received',
          createdAt: DateTime.now().toIso8601String(),
          direction: 'incoming',
        );
        
        expect(incoming.canEdit, isFalse);
      });
    });
  });
}
