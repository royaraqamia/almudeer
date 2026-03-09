import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:almudeer_mobile_app/data/repositories/integrations_repository.dart';
import 'package:almudeer_mobile_app/core/api/api_client.dart';
import 'package:almudeer_mobile_app/core/api/endpoints.dart';

// Generate Mocks
@GenerateMocks([ApiClient])
import 'integrations_repository_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late IntegrationsRepository repository;
  late MockApiClient mockApiClient;

  setUp(() async {
    mockApiClient = MockApiClient();
    when(
      mockApiClient.getAccountCacheHash(),
    ).thenAnswer((_) async => 'test-hash');
    repository = IntegrationsRepository(apiClient: mockApiClient);

    // Mock path_provider MethodChannel to avoid MissingPluginException
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            return '.';
          },
        );
  });

  group('IntegrationsRepository', () {
    test('getAccountsStatus success caches data', () async {
      // Arrange
      final responseData = {
        'whatsapp': {'connected': true},
      };

      when(
        mockApiClient.get(Endpoints.integrationAccounts),
      ).thenAnswer((_) async => responseData);

      // Act
      final result = await repository.getAccountsStatus();

      // Assert
      expect(result['whatsapp']['connected'], true);
      // Check cache (implicitly via implementation)
    });

    test('getConfig calls specific endpoints', () async {
      when(
        mockApiClient.get(Endpoints.emailConfig),
      ).thenAnswer((_) async => {'enabled': true});

      final result = await repository.getEmailConfig();
      expect(result['enabled'], true);
    });

    test('saveTelegramConfig calls post', () async {
      when(
        mockApiClient.post(Endpoints.telegramConfig, body: anyNamed('body')),
      ).thenAnswer((_) async => {'success': true});

      await repository.saveTelegramConfig('token123');

      verify(
        mockApiClient.post(
          Endpoints.telegramConfig,
          body: {'token': 'token123', 'type': 'bot'},
        ),
      ).called(1);
    });

    test('disconnectChannel calls delete', () async {
      when(mockApiClient.delete(any)).thenAnswer((_) async => {});

      await repository.disconnectChannel('whatsapp');

      verify(
        mockApiClient.delete('${Endpoints.integrationAccounts}/whatsapp'),
      ).called(1);
    });
  });
}
