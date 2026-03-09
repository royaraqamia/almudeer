import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:almudeer_mobile_app/data/repositories/inbox_repository.dart';
import 'package:almudeer_mobile_app/core/api/api_client.dart';
import 'package:almudeer_mobile_app/core/api/endpoints.dart';
import 'package:almudeer_mobile_app/core/services/connectivity_service.dart';
import 'package:almudeer_mobile_app/data/datasources/local/inbox_local_datasource.dart';
import 'package:almudeer_mobile_app/core/services/persistent_cache_service.dart';

// Generate Mocks
@GenerateMocks([
  ApiClient,
  ConnectivityService,
  InboxLocalDataSource,
  PersistentCacheService,
])
import 'inbox_repository_test.mocks.dart';

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
        mockApiClient.get(any, queryParams: anyNamed('queryParams')),
      ).thenAnswer((_) async => responseData);
      when(mockLocalDataSource.getChatHistory(any)).thenAnswer((_) async => []);
      when(mockLocalDataSource.clearChatHistory(any)).thenAnswer((_) async {});
      when(
        mockLocalDataSource.cacheMessages(
          any,
          senderContact: anyNamed('senderContact'),
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
          mockApiClient.get(any, queryParams: anyNamed('queryParams')),
        ).thenAnswer((_) async => responseData);
        when(
          mockLocalDataSource.getChatHistory(any, limit: anyNamed('limit')),
        ).thenAnswer((_) async => []);

        // Act
        await repository.getConversationDetail('12345');

        // Assert
        verify(
          mockLocalDataSource.cacheMessages(any, senderContact: '12345'),
        ).called(1);
      },
    );

    test('sendMessage calls API and adds local message', () async {
      // Arrange
      final responseData = {'success': true, 'id': 123};

      when(
        mockApiClient.post(any, body: anyNamed('body')),
      ).thenAnswer((_) async => responseData);
      when(
        mockLocalDataSource.addMessageLocally(
          senderContact: anyNamed('senderContact'),
          body: anyNamed('body'),
          channel: anyNamed('channel'),
          mediaUrl: anyNamed('mediaUrl'),
          replyToId: anyNamed('replyToId'),
          replyToPlatformId: anyNamed('replyToPlatformId'),
          replyToBodyPreview: anyNamed('replyToBodyPreview'),
          replyToSenderName: anyNamed('replyToSenderName'),
          isForwarded: anyNamed('isForwarded'),
          attachments: anyNamed('attachments'),
        ),
      ).thenAnswer((_) async => 1);
      when(
        mockLocalDataSource.markAsSynced(
          any,
          any,
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
          isForwarded: anyNamed('isForwarded'),
          attachments: anyNamed('attachments'),
        ),
      ).called(1);
    });

    test('deleteMessage calls local delete optimistically', () async {
      // Arrange
      when(
        mockApiClient.delete(any),
      ).thenAnswer((_) async => {'success': true});
      when(
        mockLocalDataSource.deleteMessageLocally(any),
      ).thenAnswer((_) async {});

      // Act
      await repository.deleteMessage(123);

      // Assert
      verify(mockLocalDataSource.deleteMessageLocally(123)).called(1);
      verify(mockApiClient.delete(any)).called(1);
    });

    test('deleteConversation calls clearChatHistory optimistically', () async {
      // Arrange
      when(
        mockApiClient.delete(any),
      ).thenAnswer((_) async => {'success': true});
      when(mockLocalDataSource.clearChatHistory(any)).thenAnswer((_) async {});

      // Act
      await repository.deleteConversation('12345');

      // Assert
      verify(mockLocalDataSource.clearChatHistory('12345')).called(1);
      verify(mockApiClient.delete(any)).called(1);
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
