import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almudeer_mobile_app/features/settings/data/repositories/settings_repository.dart';
import 'package:almudeer_mobile_app/core/api/api_client.dart';
import 'package:almudeer_mobile_app/core/api/endpoints.dart';
import 'package:almudeer_mobile_app/features/settings/data/models/user_preferences.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SettingsRepository repository;
  late MockApiClient mockApiClient;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockApiClient = MockApiClient();
    when(
      mockApiClient.getAccountCacheHash(),
    ).thenAnswer((_) async => 'test-hash');
    repository = SettingsRepository(apiClient: mockApiClient);

    // Mock path_provider MethodChannel to avoid MissingPluginException
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            return '.';
          },
        );
  });

  group('SettingsRepository', () {
    test('getPreferences returns UserPreferences', () async {
      final responseData = {
        'preferences': {'notifications_enabled': true, 'tone': 'friendly'},
      };

      when(
        mockApiClient.get(Endpoints.preferences),
      ).thenAnswer((_) async => responseData);

      final result = await repository.getPreferences();
      expect(result.notificationsEnabled, true);
      expect(result.tone, 'friendly');
    });

    test('updatePreferences calls patch and saves locally', () async {
      final prefs = UserPreferences(notificationsEnabled: false);

      when(
        mockApiClient.patch(Endpoints.preferences, body: anyNamed('body')),
      ).thenAnswer((_) async => {'success': true});

      await repository.updatePreferences(prefs);

      verify(
        mockApiClient.patch(Endpoints.preferences, body: anyNamed('body')),
      ).called(1);

      // Verify local cache works
      final cached = await repository.getLocalPreferences();
      expect(cached?.notificationsEnabled, false);
    });
    test('updatePreferences throws exception on API error', () async {
      final prefs = UserPreferences(notificationsEnabled: false);

      when(
        mockApiClient.patch(Endpoints.preferences, body: anyNamed('body')),
      ).thenThrow(Exception('API Error'));

      expect(() => repository.updatePreferences(prefs), throwsException);
    });
  });
}
