import 'package:almudeer_mobile_app/features/inbox/data/models/inbox_message.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:almudeer_mobile_app/core/services/message_cache_service.dart';

class MockHiveInterface extends Mock implements HiveInterface {}

class FakeStringBox implements Box<String> {
  final Map<dynamic, String> _store = {};
  int putCalls = 0;

  @override
  Iterable<dynamic> get keys => _store.keys;

  @override
  String? get(dynamic key, {String? defaultValue}) =>
      _store.containsKey(key) ? _store[key] : defaultValue;

  @override
  Future<void> put(dynamic key, String value) async {
    putCalls++;
    _store[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MessageCacheService service;
  late MockHiveInterface mockHive;
  late FakeStringBox mockMessagesBox;
  late FakeStringBox mockConversationsBox;
  late FakeStringBox mockMetadataBox;

  setUp(() {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          return '.';
        });

    mockHive = MockHiveInterface();
    mockMessagesBox = FakeStringBox();
    mockConversationsBox = FakeStringBox();
    mockMetadataBox = FakeStringBox();
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
    when(mockHive.init('.')).thenAnswer((_) {});
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

      expect(mockMessagesBox.putCalls, 1);
      expect(mockMessagesBox.get('messages_user1'), isNotNull);
    });

    test('getCachedMessages returns parsed list', () async {
      await service.initialize();

      final cachedJson =
          '{"messages": [{"id": 1, "body": "Hi", "channel": "whatsapp", "status": "sent", "created_at": "2024-01-01T10:00:00.000"}], "cached_at": "${DateTime.now().toIso8601String()}"}';

      await mockMessagesBox.put('messages_user1', cachedJson);

      final result = await service.getCachedMessages('user1');

      expect(result?.length, 1);
      expect(result?.first.body, 'Hi');
    });
  });
}
