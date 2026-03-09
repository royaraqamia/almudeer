import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:almudeer_mobile_app/data/repositories/knowledge_repository.dart';
import 'package:almudeer_mobile_app/core/api/api_client.dart';
import 'package:almudeer_mobile_app/core/api/endpoints.dart';

// Generate Mocks
@GenerateMocks([ApiClient])
import 'knowledge_repository_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late KnowledgeRepository repository;
  late MockApiClient mockApiClient;

  setUp(() {
    mockApiClient = MockApiClient();
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

  group('KnowledgeRepository', () {
    test('getKnowledgeDocuments parses list', () async {
      final responseData = {
        'documents': [
          {
            'text': 'Doc 1',
            'metadata': {'source': 'web'},
          },
        ],
      };

      when(
        mockApiClient.get(Endpoints.knowledgeDocuments),
      ).thenAnswer((_) async => responseData);

      final result = await repository.getKnowledgeDocuments();
      expect(result.length, 1);
      expect(result.first.text, 'Doc 1');
      expect(result.first.source, 'web');
    });

    test('addKnowledgeDocument calls post', () async {
      when(
        mockApiClient.post(
          Endpoints.knowledgeDocuments,
          body: anyNamed('body'),
        ),
      ).thenAnswer((_) async => {});

      await repository.addKnowledgeDocument('New Doc');

      verify(
        mockApiClient.post(
          Endpoints.knowledgeDocuments,
          body: anyNamed('body'),
        ),
      ).called(1);
    });

    test('uploadKnowledgeFile calls uploadFile', () async {
      when(
        mockApiClient.uploadFile(
          Endpoints.knowledgeUpload,
          filePath: anyNamed('filePath'),
          fieldName: anyNamed('fieldName'),
        ),
      ).thenAnswer((_) async => {'success': true});

      await repository.uploadKnowledgeFile('/path/to/file.pdf');

      verify(
        mockApiClient.uploadFile(
          Endpoints.knowledgeUpload,
          filePath: '/path/to/file.pdf',
          fieldName: 'file',
        ),
      ).called(1);
    });
  });
}
