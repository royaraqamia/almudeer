import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:almudeer_mobile_app/presentation/widgets/chat/voice_message_bubble.dart';
import 'package:almudeer_mobile_app/data/models/inbox_message.dart';
import 'package:almudeer_mobile_app/presentation/providers/audio_player_provider.dart';
import 'package:almudeer_mobile_app/core/services/media_cache_manager.dart';
import 'package:almudeer_mobile_app/core/services/audio_waveform_service.dart';

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

class MockMediaCacheManager extends Mock implements MediaCacheManager {
  @override
  Future<String?> getLocalPath(String? url, {String? filename}) async => null;

  @override
  Future<String> downloadFile(
    String url, {
    String? filename,
    Function(double)? onProgress,
    Function(int, int)? onProgressBytes,
  }) async => 'mock/path/file.ogg';
}

class MockAudioWaveformService extends Mock implements AudioWaveformService {
  @override
  Future<WaveformData> getWaveform(String? audioSource, {int? samples}) async {
    return const WaveformData(
      samples: [0.1, 0.2, 0.3],
      duration: Duration(seconds: 1),
    );
  }
}

void main() {
  group('VoiceMessageBubble Widget Tests', () {
    late InboxMessage mockMessage;

    setUp(() {
      // Setup singleton mocks
      MediaCacheManager.mockInstance = MockMediaCacheManager();
      AudioWaveformService.mockInstance = MockAudioWaveformService();

      mockMessage = InboxMessage(
        id: 1,
        channel: 'telegram',
        channelMessageId: 'msg_123',
        senderId: 'user_1',
        senderName: 'Test User',
        senderContact: '+1234567890',
        subject: null,
        body: '', // Voice message has empty body
        receivedAt: DateTime.now().toIso8601String(),
        createdAt: DateTime.now().toIso8601String(),
        status: 'analyzed',
        attachments: [
          {
            'type': 'audio',
            'mime_type': 'audio/ogg',
            'url': 'https://example.com/voice.ogg',
          },
        ],
      );
    });

    tearDown(() {
      MediaCacheManager.mockInstance = null;
      AudioWaveformService.mockInstance = null;
    });

    testWidgets('renders play button initially', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AudioPlayerProvider>.value(
            value: MockAudioPlayerProvider(),
            child: Scaffold(
              body: VoiceMessageBubble(
                message: mockMessage,
                isOutgoing: false,
                color: Colors.blue,
              ),
            ),
          ),
        ),
      );

      // Should show play icon initially
      expect(find.byIcon(SolarBoldIcons.play), findsOneWidget);
      expect(find.byIcon(SolarLinearIcons.pause), findsNothing);
    });

    testWidgets('shows "رسالة صوتية" label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AudioPlayerProvider>.value(
            value: MockAudioPlayerProvider(),
            child: Scaffold(
              body: VoiceMessageBubble(
                message: mockMessage,
                isOutgoing: false,
                color: Colors.blue,
              ),
            ),
          ),
        ),
      );

      // Should show the voice message label
      expect(find.text('رسالة صوتية'), findsOneWidget);
    });

    testWidgets('has correct semantics for accessibility', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AudioPlayerProvider>.value(
            value: MockAudioPlayerProvider(),
            child: Scaffold(
              body: VoiceMessageBubble(
                message: mockMessage,
                isOutgoing: false,
                color: Colors.blue,
              ),
            ),
          ),
        ),
      );

      // Check that the semantics label is set correctly
      final semantics = tester.getSemantics(find.byType(VoiceMessageBubble));
      expect(semantics.label, contains('رسالة صوتية'));
    });

    testWidgets('renders outgoing style correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AudioPlayerProvider>.value(
            value: MockAudioPlayerProvider(),
            child: Scaffold(
              body: VoiceMessageBubble(
                message: mockMessage,
                isOutgoing: true,
                color: Colors.green,
              ),
            ),
          ),
        ),
      );

      // Should render without errors
      expect(find.byType(VoiceMessageBubble), findsOneWidget);
    });

    testWidgets('handles message without attachments gracefully', (
      tester,
    ) async {
      final messageWithoutAttachments = InboxMessage(
        id: 2,
        channel: 'telegram',
        channelMessageId: 'msg_124',
        senderId: 'user_1',
        senderName: 'Test User',
        senderContact: '+1234567890',
        subject: null,
        body: 'Text message',
        receivedAt: DateTime.now().toIso8601String(),
        createdAt: DateTime.now().toIso8601String(),
        status: 'analyzed',
        attachments: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AudioPlayerProvider>.value(
            value: MockAudioPlayerProvider(),
            child: Scaffold(
              body: VoiceMessageBubble(
                message: messageWithoutAttachments,
                isOutgoing: false,
                color: Colors.blue,
              ),
            ),
          ),
        ),
      );

      // Should still render without crashing
      expect(find.byType(VoiceMessageBubble), findsOneWidget);
    });
  });
}
