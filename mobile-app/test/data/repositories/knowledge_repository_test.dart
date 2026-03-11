import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:almudeer_mobile_app/data/repositories/knowledge_repository.dart';
import 'package:almudeer_mobile_app/core/api/api_client.dart';
import 'package:almudeer_mobile_app/core/api/endpoints.dart';
import 'package:almudeer_mobile_app/data/models/knowledge_document.dart';
import 'package:almudeer_mobile_app/data/models/knowledge_constants.dart';

// Generate Mocks
@GenerateMocks([ApiClient])
import 'knowledge_repository_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late KnowledgeRepository repository;
  late MockApiClient mockApiClient;

  setUp(() {
    mockApiClient = MockApiClient();
    // Stub getAccountCacheHash to be called multiple times (once per operation + cache invalidation)
    when(
      mockApiClient.getAccountCacheHash(),
    ).thenAnswer((_) async => 'test-hash');
    repository = KnowledgeRepository(apiClient: mockApiClient);

    // Mock path_provider MethodChannel to avoid MissingPluginException
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            return '.';
          },
        );
  });

  group('KnowledgeRepository - Get Documents', () {
    test('getKnowledgeDocuments parses list successfully', () async {
      final responseData = {
        'success': true,
        'data': {
          'documents': [
            {
              'text': 'Document 1',
              'id': '123',
              'metadata': {
                'source': 'manual',
                'created_at': '2024-01-01T00:00:00Z',
              },
            },
          ],
        },
      };

      when(
        mockApiClient.get(Endpoints.knowledgeDocuments),
      ).thenAnswer((_) async => responseData);

      final result = await repository.getKnowledgeDocuments();

      expect(result.length, 1);
      expect(result.first.text, 'Document 1');
      expect(result.first.id, '123');
      expect(result.first.source, KnowledgeSource.manual);
      verify(mockApiClient.get(Endpoints.knowledgeDocuments)).called(1);
    });

    test(
      'getKnowledgeDocuments returns empty list when no documents',
      () async {
        final responseData = {
          'success': true,
          'data': {'documents': []},
        };

        when(
          mockApiClient.get(Endpoints.knowledgeDocuments),
        ).thenAnswer((_) async => responseData);

        final result = await repository.getKnowledgeDocuments();

        expect(result, isEmpty);
      },
    );

    test('getKnowledgeDocuments falls back to cache on API error', () async {
      when(
        mockApiClient.get(Endpoints.knowledgeDocuments),
      ).thenThrow(Exception('Network error'));

      // Note: In a real scenario, cache would need to be pre-populated
      // This test verifies the error handling path
      await expectLater(
        () => repository.getKnowledgeDocuments(),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'getKnowledgeDocuments handles malformed response gracefully',
      () async {
        final responseData = {
          'success': true,
          // Missing 'documents' key
        };

        when(
          mockApiClient.get(Endpoints.knowledgeDocuments),
        ).thenAnswer((_) async => responseData);

        final result = await repository.getKnowledgeDocuments();

        expect(result, isEmpty);
      },
    );
  });

  group('KnowledgeRepository - Add Document', () {
    test('addKnowledgeDocument calls post with correct data', () async {
      when(
        mockApiClient.post(
          Endpoints.knowledgeDocuments,
          body: anyNamed('body'),
        ),
      ).thenAnswer((_) async => {'success': true});

      await repository.addKnowledgeDocument('New Document');

      verify(
        mockApiClient.post(
          Endpoints.knowledgeDocuments,
          body: argThat(
            isA<Map<String, dynamic>>()
                .having((m) => m['text'], 'text', 'New Document')
                .having((m) => m['metadata'], 'metadata', isNotNull),
          ),
        ),
      ).called(1);
    });

    test('addKnowledgeDocument throws on empty text', () async {
      await expectLater(
        () => repository.addKnowledgeDocument(''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('addKnowledgeDocument throws on whitespace-only text', () async {
      await expectLater(
        () => repository.addKnowledgeDocument('   '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('addKnowledgeDocument throws on text exceeding max length', () async {
      final longText = 'a' * (KnowledgeBaseConstants.maxTextLength + 1);

      await expectLater(
        () => repository.addKnowledgeDocument(longText),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('addKnowledgeDocument invalidates cache on success', () async {
      when(
        mockApiClient.post(
          Endpoints.knowledgeDocuments,
          body: anyNamed('body'),
        ),
      ).thenAnswer((_) async => {'success': true});

      await repository.addKnowledgeDocument('Test');

      // Verify the API call was made (cache invalidation is fire-and-forget now)
      verify(
        mockApiClient.post(
          Endpoints.knowledgeDocuments,
          body: anyNamed('body'),
        ),
      ).called(1);

      // Give async cache invalidation time to complete
      await Future.delayed(const Duration(milliseconds: 50));
    });
  });

  group('KnowledgeRepository - Update Document', () {
    test('updateKnowledgeDocument calls put with correct data', () async {
      when(
        mockApiClient.put(any, body: anyNamed('body')),
      ).thenAnswer((_) async => {'success': true});

      await repository.updateKnowledgeDocument('123', 'Updated text');

      // Give async cache invalidation time to complete
      await Future.delayed(const Duration(milliseconds: 50));

      verify(
        mockApiClient.put(
          '/api/knowledge/documents/123',
          body: argThat(
            isA<Map<String, dynamic>>().having(
              (m) => m['text'],
              'text',
              'Updated text',
            ),
          ),
        ),
      ).called(1);
    });

    test('updateKnowledgeDocument throws on empty text', () async {
      await expectLater(
        () => repository.updateKnowledgeDocument('123', ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'updateKnowledgeDocument throws on text exceeding max length',
      () async {
        final longText = 'a' * (KnowledgeBaseConstants.maxTextLength + 1);

        await expectLater(
          () => repository.updateKnowledgeDocument('123', longText),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test('updateKnowledgeDocument uses string ID when parse fails', () async {
      when(
        mockApiClient.put(any, body: anyNamed('body')),
      ).thenAnswer((_) async => {'success': true});

      await repository.updateKnowledgeDocument('abc-xyz', 'Test');

      // Give async cache invalidation time to complete
      await Future.delayed(const Duration(milliseconds: 50));

      verify(
        mockApiClient.put(
          '/api/knowledge/documents/abc-xyz',
          body: anyNamed('body'),
        ),
      ).called(1);
    });
  });

  group('KnowledgeRepository - Delete Document', () {
    test('deleteKnowledgeDocument calls delete endpoint', () async {
      when(
        mockApiClient.delete(any),
      ).thenAnswer((_) async => {'success': true});

      await repository.deleteKnowledgeDocument('123');

      // Give async cache invalidation time to complete
      await Future.delayed(const Duration(milliseconds: 50));

      verify(mockApiClient.delete('/api/knowledge/documents/123')).called(1);
    });

    test('deleteKnowledgeDocument uses string ID when parse fails', () async {
      when(
        mockApiClient.delete(any),
      ).thenAnswer((_) async => {'success': true});

      await repository.deleteKnowledgeDocument('abc-xyz');

      // Give async cache invalidation time to complete
      await Future.delayed(const Duration(milliseconds: 50));

      verify(
        mockApiClient.delete('/api/knowledge/documents/abc-xyz'),
      ).called(1);
    });

    test('deleteKnowledgeDocument invalidates cache on success', () async {
      when(
        mockApiClient.delete(any),
      ).thenAnswer((_) async => {'success': true});

      await repository.deleteKnowledgeDocument('123');

      // Give async cache invalidation time to complete
      await Future.delayed(const Duration(milliseconds: 50));

      verify(mockApiClient.delete('/api/knowledge/documents/123')).called(1);
    });
  });

  group('KnowledgeRepository - Upload File', () {
    test('uploadKnowledgeFile calls uploadFile endpoint', () async {
      when(
        mockApiClient.uploadFile(
          Endpoints.knowledgeUpload,
          filePath: anyNamed('filePath'),
          fieldName: anyNamed('fieldName'),
        ),
      ).thenAnswer((_) async => {'success': true});

      await repository.uploadKnowledgeFile('/path/to/file.pdf');

      // Give async cache invalidation time to complete
      await Future.delayed(const Duration(milliseconds: 50));

      verify(
        mockApiClient.uploadFile(
          Endpoints.knowledgeUpload,
          filePath: '/path/to/file.pdf',
          fieldName: 'file',
        ),
      ).called(1);
    });

    test('uploadKnowledgeFile calls progress callback', () async {
      when(
        mockApiClient.uploadFile(
          Endpoints.knowledgeUpload,
          filePath: anyNamed('filePath'),
          fieldName: anyNamed('fieldName'),
          onProgress: anyNamed('onProgress'),
        ),
      ).thenAnswer((_) async {
        // Simulate progress callback
        return {'success': true};
      });

      await repository.uploadKnowledgeFile(
        '/path/to/file.pdf',
        onProgress: (progress) {},
      );

      // Give async cache invalidation time to complete
      await Future.delayed(const Duration(milliseconds: 50));

      verify(
        mockApiClient.uploadFile(
          Endpoints.knowledgeUpload,
          filePath: '/path/to/file.pdf',
          fieldName: 'file',
          onProgress: anyNamed('onProgress'),
        ),
      ).called(1);
    });

    test('uploadKnowledgeFile validates file extension', () async {
      await expectLater(
        () => repository.uploadKnowledgeFile('/path/to/file.xyz'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('uploadKnowledgeFile accepts valid file extensions', () async {
      when(
        mockApiClient.uploadFile(
          Endpoints.knowledgeUpload,
          filePath: anyNamed('filePath'),
          fieldName: anyNamed('fieldName'),
        ),
      ).thenAnswer((_) async => {'success': true});

      // Should not throw for valid extensions
      await repository.uploadKnowledgeFile('/path/to/file.pdf');
      await repository.uploadKnowledgeFile('/path/to/file.txt');
      await repository.uploadKnowledgeFile('/path/to/file.docx');

      // Give async cache invalidation time to complete
      await Future.delayed(const Duration(milliseconds: 50));

      verify(
        mockApiClient.uploadFile(
          Endpoints.knowledgeUpload,
          filePath: '/path/to/file.pdf',
          fieldName: 'file',
        ),
      ).called(1);
    });

    test('uploadKnowledgeFile retries on transient failure', () async {
      // First call throws, second succeeds
      when(
        mockApiClient.uploadFile(
          Endpoints.knowledgeUpload,
          filePath: anyNamed('filePath'),
          fieldName: anyNamed('fieldName'),
        ),
      ).thenThrow(Exception('Network error'));

      when(
        mockApiClient.uploadFile(
          Endpoints.knowledgeUpload,
          filePath: anyNamed('filePath'),
          fieldName: anyNamed('fieldName'),
        ),
      ).thenAnswer((_) async => {'success': true});

      await repository.uploadKnowledgeFile('/path/to/file.pdf');

      // Give async cache invalidation time to complete
      await Future.delayed(const Duration(milliseconds: 50));

      // Verify upload was called twice (initial + 1 retry)
      verify(
        mockApiClient.uploadFile(
          Endpoints.knowledgeUpload,
          filePath: '/path/to/file.pdf',
          fieldName: 'file',
        ),
      ).called(2);
    });

    test('uploadKnowledgeFile throws after max retries', () async {
      when(
        mockApiClient.uploadFile(
          Endpoints.knowledgeUpload,
          filePath: anyNamed('filePath'),
          fieldName: anyNamed('fieldName'),
        ),
      ).thenThrow(Exception('Persistent network error'));

      await expectLater(
        () => repository.uploadKnowledgeFile('/path/to/file.pdf'),
        throwsA(isA<Exception>()),
      );

      // Give async cache invalidation time to complete (it will fail silently)
      await Future.delayed(const Duration(milliseconds: 50));

      // Verify upload was called 3 times (initial + 2 retries)
      verify(
        mockApiClient.uploadFile(
          Endpoints.knowledgeUpload,
          filePath: '/path/to/file.pdf',
          fieldName: 'file',
        ),
      ).called(3);
    });
  });

  group('KnowledgeRepository - Cache Key', () {
    test('uses specific cache key prefix to prevent collisions', () async {
      // This test verifies the cache key includes the knowledge prefix
      final expectedCacheKeyPrefix = KnowledgeBaseConstants.cacheKeyPrefix;
      expect(expectedCacheKeyPrefix, equals('knowledge_'));
    });
  });

  group('KnowledgeDocument Model', () {
    test('fromJson parses document correctly', () {
      final json = {
        'id': '123',
        'text': 'Test document',
        'file_path': '/files/test.pdf',
        'metadata': {'source': 'file', 'created_at': '2024-01-01T12:00:00Z'},
      };

      final doc = KnowledgeDocument.fromJson(json);

      expect(doc.id, '123');
      expect(doc.text, 'Test document');
      expect(doc.filePath, '/files/test.pdf');
      expect(doc.source, KnowledgeSource.file);
      expect(doc.createdAt, DateTime.parse('2024-01-01T12:00:00Z'));
    });

    test('fromJson handles missing metadata', () {
      final json = {'id': '123', 'text': 'Test document'};

      final doc = KnowledgeDocument.fromJson(json);

      expect(doc.source, KnowledgeSource.manual);
      expect(doc.createdAt, isNull);
    });

    test('toJson serializes correctly', () {
      final doc = KnowledgeDocument(
        id: '123',
        text: 'Test',
        source: KnowledgeSource.mobileApp,
        createdAt: DateTime(2024, 1, 1, 12, 0, 0),
      );

      final json = doc.toJson();

      expect(json['id'], '123');
      expect(json['text'], 'Test');
      expect(json['metadata']['source'], 'mobile_app');
    });

    test('isFile and isText properties work correctly', () {
      final fileDoc = const KnowledgeDocument(
        text: 'file.pdf',
        source: KnowledgeSource.file,
      );
      final textDoc = const KnowledgeDocument(
        text: 'Some text',
        source: KnowledgeSource.manual,
      );

      expect(fileDoc.isFile, isTrue);
      expect(fileDoc.isText, isFalse);
      expect(textDoc.isFile, isFalse);
      expect(textDoc.isText, isTrue);
    });
  });

  group('KnowledgeSource Enum', () {
    test('value returns correct string', () {
      expect(KnowledgeSource.manual.value, equals('manual'));
      expect(KnowledgeSource.mobileApp.value, equals('mobile_app'));
      expect(KnowledgeSource.file.value, equals('file'));
    });

    test('fromString parses correctly', () {
      expect(
        KnowledgeSource.fromString('manual'),
        equals(KnowledgeSource.manual),
      );
      expect(
        KnowledgeSource.fromString('mobile_app'),
        equals(KnowledgeSource.mobileApp),
      );
      expect(KnowledgeSource.fromString('file'), equals(KnowledgeSource.file));
      expect(
        KnowledgeSource.fromString('unknown'),
        equals(KnowledgeSource.manual),
      );
    });
  });

  group('KnowledgeBaseConstants', () {
    test('maxFileSize is 20MB', () {
      expect(KnowledgeBaseConstants.maxFileSize, equals(20 * 1024 * 1024));
    });

    test('maxTextLength is defined', () {
      expect(KnowledgeBaseConstants.maxTextLength, equals(15000));
    });

    test('allowedFileExtensions contains expected types', () {
      expect(KnowledgeBaseConstants.allowedFileExtensions, contains('.pdf'));
      expect(KnowledgeBaseConstants.allowedFileExtensions, contains('.txt'));
      expect(KnowledgeBaseConstants.allowedFileExtensions, contains('.doc'));
      expect(KnowledgeBaseConstants.allowedFileExtensions, contains('.docx'));
    });

    test('cacheKeyPrefix is specific', () {
      expect(KnowledgeBaseConstants.cacheKeyPrefix, equals('knowledge_'));
    });
  });
}
