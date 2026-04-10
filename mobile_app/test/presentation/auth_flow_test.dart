import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:almudeer_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:almudeer_mobile_app/core/api/api_client.dart';
import 'package:almudeer_mobile_app/features/auth/data/repositories/auth_repository.dart';
import 'package:almudeer_mobile_app/features/users/data/models/user_info.dart';
import 'package:almudeer_mobile_app/features/notifications/data/services/fcm_service_mobile.dart'
    if (dart.library.js_interop) 'package:almudeer_mobile_app/features/notifications/data/services/fcm_service_web.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

/// Fake FcmService for testing - provides no-op implementations
class MockFcmService extends FcmService {
  MockFcmService() : super.protected();
}

class FakeFlutterSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<String?> read({
    required String key,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    AppleOptions? mOptions,
  }) async => _store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    AppleOptions? mOptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    AppleOptions? mOptions,
  }) async {
    _store.remove(key);
  }

  @override
  Future<bool> containsKey({
    required String key,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    AppleOptions? mOptions,
  }) async => _store.containsKey(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AuthProvider authProvider;
  late MockAuthRepository mockAuthRepository;
  late MockFcmService mockFcmService;
  late FakeFlutterSecureStorage mockSecureStorage;

  final userA = UserInfo(
    fullName: 'Company A',
    expiresAt: '2025-12-31',
    referralCount: 100,
    licenseKey: 'KEY-A',
    licenseId: 1,
  );

  final userB = UserInfo(
    fullName: 'Company B',
    expiresAt: '2025-12-31',
    referralCount: 100,
    licenseKey: 'KEY-B',
    licenseId: 2,
  );

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    mockAuthRepository = MockAuthRepository();
    mockFcmService = MockFcmService();
    mockSecureStorage = FakeFlutterSecureStorage();

    // Inject mock storage into ApiClient singleton
    ApiClient().secureStorage = mockSecureStorage;

    SharedPreferences.setMockInitialValues({});
  });

  group('Logout & Multi-Account Tests', () {
    test('Initial state is initial', () async {
      when(mockAuthRepository.getSavedAccounts()).thenAnswer((_) async => []);
      when(mockAuthRepository.isAuthenticated()).thenAnswer((_) async => false);
      when(mockAuthRepository.getLicenseKey()).thenAnswer((_) async => null);

      authProvider = AuthProvider(
        authRepository: mockAuthRepository,
        fcmService: mockFcmService,
      );

      expect(authProvider.state, AuthState.initial);
    });

    test(
      'Single Account Logout clears session and calls repo.logout',
      () async {
        // Setup: Authenticate with User A
        when(
          mockAuthRepository.getSavedAccounts(),
        ).thenAnswer((_) async => [userA]);
        when(
          mockAuthRepository.isAuthenticated(),
        ).thenAnswer((_) async => true);
        when(
          mockAuthRepository.getLicenseKey(),
        ).thenAnswer((_) async => userA.licenseKey);
        when(
          mockAuthRepository.getUserInfo(key: anyNamed('key')),
        ).thenAnswer((_) async => userA);
        when(mockAuthRepository.removeAccount(userA)).thenAnswer((_) async {});
        when(mockAuthRepository.saveAccount(userA)).thenAnswer((_) async {});
        when(
          mockAuthRepository.storeLicenseKey(userA.licenseKey!, id: anyNamed('id')),
        ).thenAnswer((_) async {});
        when(mockAuthRepository.logout()).thenAnswer((_) async {});

        authProvider = AuthProvider(
          authRepository: mockAuthRepository,
          fcmService: mockFcmService,
        );

        await authProvider.init();

        expect(authProvider.state, AuthState.authenticated);
        expect(authProvider.userInfo?.fullName, 'Company A');

        // Act: Logout
        await authProvider.logout();

        // Assert - single account logout leads to unauthenticated
        expect(authProvider.state, AuthState.unauthenticated);
        expect(authProvider.userInfo, isNull);

        // Verify cleanup
        verify(mockFcmService.unregisterToken()).called(1);
        verify(mockAuthRepository.logout()).called(1);
      },
    );

    test('Multi-Account Logout switches to next available account', () async {
      // Setup: Authenticate with User A and User B
      when(
        mockAuthRepository.getSavedAccounts(),
      ).thenAnswer((_) async => [userA, userB]);
      when(mockAuthRepository.isAuthenticated()).thenAnswer((_) async => true);
      when(
        mockAuthRepository.getLicenseKey(),
      ).thenAnswer((_) async => userA.licenseKey);
      when(mockAuthRepository.getUserInfo(key: anyNamed('key'))).thenAnswer((
        invocation,
      ) async {
        final key = invocation.namedArguments[#key] as String?;
        if (key == userB.licenseKey) return userB;
        return userA;
      });
      when(mockAuthRepository.removeAccount(userA)).thenAnswer((_) async {});
      when(mockAuthRepository.removeAccount(userB)).thenAnswer((_) async {});
      when(mockAuthRepository.saveAccount(userA)).thenAnswer((_) async {});
      when(mockAuthRepository.saveAccount(userB)).thenAnswer((_) async {});
      when(
        mockAuthRepository.storeLicenseKey(userA.licenseKey!, id: anyNamed('id')),
      ).thenAnswer((_) async {});
      when(mockAuthRepository.logout()).thenAnswer((_) async {});

      authProvider = AuthProvider(
        authRepository: mockAuthRepository,
        fcmService: mockFcmService,
      );

      await authProvider.init();

      expect(authProvider.accounts.length, 2);
      expect(authProvider.userInfo?.fullName, 'Company A');

      // Act: Logout (Remove A)
      await authProvider.logout();

      // Assert - should switch to User B
      expect(authProvider.state, AuthState.authenticated);
      expect(authProvider.userInfo?.fullName, 'Company B');
      expect(authProvider.accounts.length, 1);

      // Verify switch to User B occurred
      verify(
        mockAuthRepository.storeLicenseKey(
          userB.licenseKey!,
          id: userB.licenseId,
        ),
      ).called(1);

      // Verify FCM registration for new account
      verify(mockFcmService.registerTokenWithBackend()).called(1);
    });
  });
}
