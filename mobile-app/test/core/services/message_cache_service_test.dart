import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:almudeer_mobile_app/core/services/message_cache_service.dart';
import 'package:almudeer_mobile_app/data/models/inbox_message.dart';

// Generate Mocks
@GenerateMocks([HiveInterface, Box])
import 'message_cache_service_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MessageCacheService service;
  late MockHiveInterface mockHive;
  late MockBox<String> mockMessagesBox;
  late MockBox<String> mockConversationsBox;
  late MockBox<String> mockMetadataBox;

  setUp(() {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          return '.';
        });

    mockHive = MockHiveInterface();
    mockMessagesBox = MockBox<String>();
    mockConversationsBox = MockBox<String>();
    mockMetadataBox = MockBox<String>();
    service = MessageCacheService(hive: mockHive);

    // Default mocks
    when(
      mockHive.openBox<String>('cached_messages'),
    ).thenAnswer((_) async => mockMessagesBox);
    when(
      mockHive.openBox<String>('cached_conversations'),
    ).thenAnswer((_) async => mockConversationsBox);
    when(
      mockHive.openBox<String>('cache_metadata'),
    ).thenAnswer((_) async => mockMetadataBox);
    when(mockHive.init(any)).thenAnswer((_) {});

    when(mockMessagesBox.keys).thenReturn([]);
    when(mockConversationsBox.keys).thenReturn([]);
    when(mockMetadataBox.keys).thenReturn([]);
  });

  group('MessageCacheService', () {
    test('initialize opens boxes', () async {
      await service.initialize();

      verify(mockHive.openBox<String>('cached_messages')).called(1);
      verify(mockHive.openBox<String>('cached_conversations')).called(1);
    });

    test('cacheMessages matches data structure', () async {
      await service.initialize();

      final messages = [
        InboxMessage(
          id: 1,
          body: 'Hi',
          channel: 'whatsapp',
          status: 'sent',
          createdAt: DateTime.now().toIso8601String(),
        ),
      ];
      await service.cacheMessages('user1', messages);

      verify(mockMessagesBox.put('messages_user1', any)).called(1);
    });

    test('getCachedMessages returns parsed list', () async {
      await service.initialize();

      final cachedJson =
          '{"messages": [{"id": 1, "body": "Hi", "channel": "whatsapp", "status": "sent", "created_at": "2024-01-01T10:00:00.000"}], "cached_at": "${DateTime.now().toIso8601String()}"}';

      when(mockMessagesBox.get('messages_user1')).thenReturn(cachedJson);

      final result = await service.getCachedMessages('user1');

      expect(result?.length, 1);
      expect(result?.first.body, 'Hi');
    });
  });
}
