import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:almudeer_mobile_app/services/fcm_service.dart';
import 'package:almudeer_mobile_app/core/api/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:firebase_messaging_platform_interface/firebase_messaging_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// Generate Mocks
@GenerateMocks([
  FirebaseMessaging,
  FlutterLocalNotificationsPlugin,
  ApiClient,
  NotificationSettings,
])
import 'fcm_service_test.mocks.dart';

class MockPlatform extends FirebaseMessagingPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<NotificationSettings> requestPermission({
    bool alert = true,
    bool announcement = false,
    bool badge = true,
    bool carPlay = false,
    bool criticalAlert = false,
    bool providesAppNotificationSettings = false,
    bool provisional = false,
    bool sound = true,
  }) async {
    return MockNotificationSettings();
  }

  @override
  Future<void> setForegroundNotificationPresentationOptions({
    bool alert = false,
    bool badge = false,
    bool sound = false,
  }) async {}

  @override
  Future<void> registerBackgroundMessageHandler(
    BackgroundMessageHandler handler,
  ) async {}

  void onBackgroundMessage(BackgroundMessageHandler handler) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock FirebaseMessagingPlatform to avoid onBackgroundMessage error
  FirebaseMessagingPlatform.instance = MockPlatform();
  late FcmService service;
  late MockFirebaseMessaging mockMessaging;
  late MockFlutterLocalNotificationsPlugin mockLocalNotifications;
  // late MockApiClient mockClient; // We don't inject client yet? Oh, FcmService creates it internally?
  // FcmService.test(...) doesn't accept ApiClient currently in my replacement?
  // Wait, I forgot to inject ApiClient in the refactor?
  // Let me check my previous step replacement.
  // I replaced FcmService.test({messaging, localNotifications}).
  // ApiClient is instantiated inside methods: `final client = ApiClient();`.
  // This is hard to test unless I refactor ApiClient usage or inject it.
  // The service uses ApiClient in `registerTokenWithBackend` and `_showLocalNotification` (image download).
  // Ideally, I should inject ApiClient factory or singleton instance setter?
  // Or assuming ApiClient is a singleton, I can mock the singleton if possible?
  // ApiClient is a singleton. `ApiClient()`.
  // I can't easily mock `ApiClient()` call unless `ApiClient` allows replacing instance.
  // Let's check `ApiClient` code.

  // For now, I will test `initialize` which uses `messaging` and `localNotifications`.

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockMessaging = MockFirebaseMessaging();
    mockLocalNotifications = MockFlutterLocalNotificationsPlugin();
    service = FcmService.test(
      messaging: mockMessaging,
      localNotifications: mockLocalNotifications,
    );

    // Default stubs
    when(
      mockMessaging.requestPermission(
        alert: anyNamed('alert'),
        badge: anyNamed('badge'),
        sound: anyNamed('sound'),
        announcement: anyNamed('announcement'),
        carPlay: anyNamed('carPlay'),
        criticalAlert: anyNamed('criticalAlert'),
        provisional: anyNamed('provisional'),
      ),
    ).thenAnswer((_) async => MockNotificationSettings());

    // Mock static-like behaviors via method channel mockery if needed,
    // but here we just need to ensure the mock object behaves correctly.

    final settings = MockNotificationSettings();
    when(
      settings.authorizationStatus,
    ).thenReturn(AuthorizationStatus.authorized);
    when(mockMessaging.getToken()).thenAnswer((_) async => 'token');
    when(
      mockMessaging.onTokenRefresh,
    ).thenAnswer((_) => Stream.fromIterable([]));
    when(
      mockMessaging.setForegroundNotificationPresentationOptions(
        alert: anyNamed('alert'),
        badge: anyNamed('badge'),
        sound: anyNamed('sound'),
      ),
    ).thenAnswer((_) async {});
    when(mockMessaging.getInitialMessage()).thenAnswer((_) async => null);
    when(mockMessaging.subscribeToTopic(any)).thenAnswer((_) async {});
    when(
      mockLocalNotifications.initialize(
        settings: anyNamed('settings'),
        onDidReceiveNotificationResponse: anyNamed(
          'onDidReceiveNotificationResponse',
        ),
      ),
    ).thenAnswer((_) async => true);
  });

  group('FcmService', () {
    test('initialize requests permission and gets token', () async {
      final settings = MockNotificationSettings();
      when(
        settings.authorizationStatus,
      ).thenReturn(AuthorizationStatus.authorized);

      // Mock Flutter Secure Storage
      const secureStorageChannel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorageChannel, (
            MethodCall methodCall,
          ) async {
            if (methodCall.method == 'read') {
              return null; // Simulate no stored token
            }
            if (methodCall.method == 'write') {
              return null;
            }
            if (methodCall.method == 'delete') {
              return null;
            }
            return null;
          });

      when(
        mockMessaging.requestPermission(
          alert: anyNamed('alert'),
          badge: anyNamed('badge'),
          sound: anyNamed('sound'),
          announcement: anyNamed('announcement'),
          carPlay: anyNamed('carPlay'),
          criticalAlert: anyNamed('criticalAlert'),
          provisional: anyNamed('provisional'),
          providesAppNotificationSettings: anyNamed(
            'providesAppNotificationSettings',
          ),
        ),
      ).thenAnswer((_) async => settings);

      await service.initialize();

      verify(
        mockMessaging.requestPermission(
          alert: anyNamed('alert'),
          badge: anyNamed('badge'),
          sound: anyNamed('sound'),
          announcement: anyNamed('announcement'),
          carPlay: anyNamed('carPlay'),
          criticalAlert: anyNamed('criticalAlert'),
          provisional: anyNamed('provisional'),
          providesAppNotificationSettings: anyNamed(
            'providesAppNotificationSettings',
          ),
        ),
      ).called(1);

      verify(mockMessaging.getToken()).called(1);
    });
  });
}
