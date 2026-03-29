import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:almudeer_mobile_app/features/inbox/data/repositories/inbox_repository.dart';
import 'package:almudeer_mobile_app/core/api/api_client.dart';
import 'package:almudeer_mobile_app/core/api/endpoints.dart';
import 'package:almudeer_mobile_app/core/services/connectivity_service.dart';
import 'package:almudeer_mobile_app/features/inbox/data/datasources/local/inbox_local_datasource.dart';
import 'package:almudeer_mobile_app/core/services/persistent_cache_service.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockConnectivityService extends Mock implements ConnectivityService {}

class MockInboxLocalDataSource extends Mock implements InboxLocalDataSource {}

class MockPersistentCacheService extends Mock implements PersistentCacheService {}

void main() {
  late InboxRepository repository;
  late MockApiClient mockApiClient;
  late MockConnectivityService mockConnectivityService;
  late MockInboxLocalDataSource mockLocalDataSource;
  late MockPersistentCacheService mockCache;

  setUp(() {
    mockApiClient = MockApiClient();
    mockConnectivityService = MockConnectivityService();
    mockLocalDataSource = MockInboxLocalDataSource();
    mockCache = MockPersistentCacheService();

    when(
      mockApiClient.getAccountCacheHash(),
    ).thenAnswer((_) async => 'test-hash');
    when(mockConnectivityService.isOnline).thenReturn(true);
    when(mockConnectivityService.isOffline).thenReturn(false);

    repository = InboxRepository(
      apiClient: mockApiClient,
      cache: mockCache,
      connectivityService: mockConnectivityService,
      localDataSource: mockLocalDataSource,
    );
  });

  group('InboxRepository', () {
    test('getConversations returns ConversationsResponse', () async {
      // Arrange
      final responseData = {
        'conversations': [
          {
            'id': 1,
            'channel': 'whatsapp',
            'sender_name': 'John Doe',
            'body': 'Hello',
            'status': 'pending',
            'created_at': '2024-01-01T10:00:00Z',
            'message_count': 1,
            'unread_count': 1,
          },
        ],
        'total': 1,
        'has_more': false,
      };

      when(
        mockApiClient.get(
          Endpoints.conversations,
          queryParams: anyNamed('queryParams'),
        ),
      ).thenAnswer((_) async => responseData);
      when(
        mockCache.get<Map<String, dynamic>>(
          PersistentCacheService.boxInbox,
          'test-hash_list_0',
        ),
      ).thenAnswer((_) async => null);
      when(
        mockCache.put(
          PersistentCacheService.boxInbox,
          'test-hash_list_0',
          any,
        ),
      ).thenAnswer((_) async {});
      when(mockLocalDataSource.getChatHistory('__unused__')).thenAnswer((_) async => []);
      when(mockLocalDataSource.clearChatHistory('__unused__')).thenAnswer((_) async {});
      when(
        mockLocalDataSource.cacheMessages(
          <Map<String, dynamic>>[],
          senderContact: '__unused__',
        ),
      ).thenAnswer((_) async {});

      // Act
      final result = await repository.getConversations();

      // Assert
      expect(result.conversations.length, 1);
    });

    test(
      'getConversationDetail calls cacheMessages with senderContact',
      () async {
        // Arrange
        final responseData = {
          'sender_name': 'John Doe',
          'sender_contact': '12345',
          'messages': [
            {
              'id': 1,
              'sender_contact': '12345',
              'body': 'Hello',
              'created_at': '2024-01-01T10:00:00Z',
            },
          ],
          'total': 1,
        };

        when(
          mockApiClient.get(
            Endpoints.conversationDetail('12345'),
            queryParams: anyNamed('queryParams'),
          ),
        ).thenAnswer((_) async => responseData);
        when(
          mockLocalDataSource.getChatHistory('12345', limit: 100),
        ).thenAnswer((_) async => []);

        // Act
        await repository.getConversationDetail('12345');

        // Assert
        verify(
          mockLocalDataSource.cacheMessages(
            <Map<String, dynamic>>[],
            senderContact: '12345',
          ),
        ).called(1);
      },
    );

    test('sendMessage calls API and adds local message', () async {
      // Arrange
      final responseData = {'success': true, 'id': 123};

      when(
        mockApiClient.post(
          Endpoints.sendMessage('12345'),
          body: anyNamed('body'),
        ),
      ).thenAnswer((_) async => responseData);
      when(
        mockLocalDataSource.addMessageLocally(
          senderContact: '12345',
          body: 'Hello',
          channel: 'whatsapp',
          mediaUrl: anyNamed('mediaUrl'),
          replyToId: anyNamed('replyToId'),
          replyToPlatformId: anyNamed('replyToPlatformId'),
          replyToBodyPreview: anyNamed('replyToBodyPreview'),
          replyToSenderName: anyNamed('replyToSenderName'),
          isForwarded: false,
          attachments: anyNamed('attachments'),
        ),
      ).thenAnswer((_) async => 1);
      when(
        mockLocalDataSource.markAsSynced(
          1,
          123,
          platformMessageId: anyNamed('platformMessageId'),
          channelMessageId: anyNamed('channelMessageId'),
        ),
      ).thenAnswer((_) async {});

      // Act
      await repository.sendMessage('12345', message: 'Hello');

      // Assert
      verify(
        mockApiClient.post(
          Endpoints.sendMessage('12345'),
          body: anyNamed('body'),
        ),
      ).called(1);
      verify(
        mockLocalDataSource.addMessageLocally(
          senderContact: '12345',
          body: 'Hello',
          channel: 'whatsapp',
          mediaUrl: anyNamed('mediaUrl'),
          replyToId: anyNamed('replyToId'),
          replyToPlatformId: anyNamed('replyToPlatformId'),
          replyToBodyPreview: anyNamed('replyToBodyPreview'),
          replyToSenderName: anyNamed('replyToSenderName'),
          isForwarded: false,
          attachments: anyNamed('attachments'),
        ),
      ).called(1);
    });

    test('deleteMessage calls local delete optimistically', () async {
      // Arrange
      when(
        mockApiClient.delete('/api/integrations/messages/123?type=incoming'),
      ).thenAnswer((_) async => {'success': true});
      when(
        mockLocalDataSource.deleteMessageLocally(123),
      ).thenAnswer((_) async {});

      // Act
      await repository.deleteMessage(123);

      // Assert
      verify(mockLocalDataSource.deleteMessageLocally(123)).called(1);
      verify(
        mockApiClient.delete('/api/integrations/messages/123?type=incoming'),
      ).called(1);
    });

    test('deleteConversation calls clearChatHistory optimistically', () async {
      // Arrange
      when(
        mockApiClient.delete(Endpoints.deleteConversation('12345')),
      ).thenAnswer((_) async => {'success': true});
      when(
        mockLocalDataSource.clearChatHistory('12345'),
      ).thenAnswer((_) async {});

      // Act
      await repository.deleteConversation('12345');

      // Assert
      verify(mockLocalDataSource.clearChatHistory('12345')).called(1);
      verify(mockApiClient.delete(Endpoints.deleteConversation('12345'))).called(1);
    });

    test('updateMessageSyncStatus calls local data source', () async {
      // Arrange
      when(
        mockLocalDataSource.updateMessageSyncStatus(123, 'delivered'),
      ).thenAnswer((_) async {});

      // Act
      await repository.updateMessageSyncStatus(123, 'delivered');

      // Assert
      verify(
        mockLocalDataSource.updateMessageSyncStatus(123, 'delivered'),
      ).called(1);
    });
  });
}
