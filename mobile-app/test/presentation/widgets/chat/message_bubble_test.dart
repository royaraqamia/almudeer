import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:almudeer_mobile_app/features/inbox/presentation/widgets/chat/message_bubble.dart';
import 'package:almudeer_mobile_app/features/inbox/presentation/widgets/chat/video_message_bubble.dart';
import 'package:almudeer_mobile_app/features/inbox/presentation/widgets/chat/file_message_bubble.dart';
import 'package:almudeer_mobile_app/features/inbox/data/models/inbox_message.dart';
import 'package:almudeer_mobile_app/features/viewer/presentation/providers/audio_player_provider.dart';
import 'package:almudeer_mobile_app/features/inbox/presentation/providers/conversation_detail_provider.dart';
import 'package:mockito/mockito.dart';

// Mocks
class MockAudioPlayerProvider extends Mock implements AudioPlayerProvider {
  @override
  bool get isPlaying => false;
  @override
  double get playbackSpeed => 1.0;
  @override
  Duration get currentPosition => Duration.zero;
  @override
  Duration get totalDuration => Duration.zero;
  @override
  double get progress => 0.0;
}

class MockConversationDetailProvider extends Mock
    implements ConversationDetailProvider {
  @override
  bool isMessageSelected(int? id) => false;

  @override
  bool get isSelectionMode => false;
}

void main() {
  Widget createWidgetUnderTest(InboxMessage message) {
    return MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<ConversationDetailProvider>.value(
            value: MockConversationDetailProvider(),
          ),
          ChangeNotifierProvider<AudioPlayerProvider>.value(
            value: MockAudioPlayerProvider(),
          ),
        ],
        child: Scaffold(
          body: MessageBubble(
            message: message,
            channelColor: Colors.blue,
            displayName: 'Test User',
          ),
        ),
      ),
    );
  }

  testWidgets('MessageBubble renders VideoMessageBubble for video attachment', (
    WidgetTester tester,
  ) async {
    final message = InboxMessage(
      id: 1,
      channel: 'whatsapp',
      body: 'Video test',
      status: 'sent',
      createdAt: DateTime.now().toIso8601String(),
      attachments: [
        {'type': 'video', 'url': 'http://example.com/video.mp4'},
      ],
    );

    await tester.pumpWidget(createWidgetUnderTest(message));
    expect(find.byType(VideoMessageBubble), findsOneWidget);
  });

  testWidgets(
    'MessageBubble renders FileMessageBubble for document attachment',
    (WidgetTester tester) async {
      final message = InboxMessage(
        id: 2,
        channel: 'whatsapp',
        body: 'File test',
        status: 'sent',
        createdAt: DateTime.now().toIso8601String(),
        attachments: [
          {
            'type': 'document',
            'filename': 'test.pdf',
            'url': 'http://example.com.pdf',
          },
        ],
      );

      await tester.pumpWidget(createWidgetUnderTest(message));
      expect(find.byType(FileMessageBubble), findsOneWidget);
    },
  );

  testWidgets('MessageBubble renders Image for photo attachment with base64', (
    WidgetTester tester,
  ) async {
    final message = InboxMessage(
      id: 3,
      channel: 'telegram',
      body: 'Image test',
      status: 'sent',
      createdAt: DateTime.now().toIso8601String(),
      attachments: [
        {
          'type': 'photo',
          'base64': 'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
        },
      ],
    );

    await tester.pumpWidget(createWidgetUnderTest(message));
    // It should render an Image widget
    expect(find.byType(Image), findsOneWidget);
  });
}
