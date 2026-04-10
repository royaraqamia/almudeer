import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:almudeer_mobile_app/features/settings/data/repositories/subscriptions_repository.dart';
import 'package:almudeer_mobile_app/core/api/api_client.dart';
import 'package:almudeer_mobile_app/core/api/endpoints.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SubscriptionsRepository repository;
  late MockApiClient mockApiClient;

  setUp(() {
    mockApiClient = MockApiClient();
    when(
      mockApiClient.getAccountCacheHash(),
    ).thenAnswer((_) async => 'test-hash');
    repository = SubscriptionsRepository(apiClient: mockApiClient);

    // Mock path_provider MethodChannel to avoid MissingPluginException
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            return '.';
          },
        );
  });

  group('SubscriptionsRepository', () {
    test('getSubscriptions calls list endpoint', () async {
      when(
        mockApiClient.get(
          Endpoints.subscriptionList,
          queryParams: anyNamed('queryParams'),
        ),
      ).thenAnswer((_) async => {'results': []});

      await repository.getSubscriptions(limit: 10);

      verify(
        mockApiClient.get(
          Endpoints.subscriptionList,
          queryParams: {'active_only': 'false', 'limit': '10'},
        ),
      ).called(1);
    });

    test('createSubscription calls post', () async {
      when(
        mockApiClient.post(
          Endpoints.subscriptionCreate,
          body: anyNamed('body'),
        ),
      ).thenAnswer((_) async => {'success': true});

      await repository.createSubscription({'plan': 'basic'});

      verify(
        mockApiClient.post(
          Endpoints.subscriptionCreate,
          body: {'plan': 'basic'},
        ),
      ).called(1);
    });
  });
}
