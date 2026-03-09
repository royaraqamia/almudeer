import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:almudeer_mobile_app/presentation/providers/auth_provider.dart';
import 'package:almudeer_mobile_app/core/api/api_client.dart';
import 'package:almudeer_mobile_app/data/repositories/auth_repository.dart';
import 'package:almudeer_mobile_app/data/models/user_info.dart';
import 'package:almudeer_mobile_app/services/fcm_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Generate Mocks
@GenerateMocks([AuthRepository, FcmService, FlutterSecureStorage])
import 'auth_flow_test.mocks.dart';

void main() {
  late AuthProvider authProvider;
  late MockAuthRepository mockAuthRepository;
  late MockFcmService mockFcmService;
  late MockFlutterSecureStorage mockSecureStorage;

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
    mockSecureStorage = MockFlutterSecureStorage();

    // Inject mock storage into ApiClient singleton
    ApiClient().secureStorage = mockSecureStorage;

    SharedPreferences.setMockInitialValues({});

    // Mock secure storage to return null for all keys (prevents platform channel calls)
    when(
      mockSecureStorage.read(key: anyNamed('key')),
    ).thenAnswer((_) async => null);
    when(
      mockSecureStorage.write(key: anyNamed('key'), value: anyNamed('value')),
    ).thenAnswer((_) async {});
    when(
      mockSecureStorage.delete(key: anyNamed('key')),
    ).thenAnswer((_) async {});
    when(
      mockSecureStorage.containsKey(key: anyNamed('key')),
    ).thenAnswer((_) async => false);
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
        when(mockAuthRepository.removeAccount(any)).thenAnswer((_) async {});
        when(mockAuthRepository.saveAccount(any)).thenAnswer((_) async {});
        when(
          mockAuthRepository.storeLicenseKey(any, id: anyNamed('id')),
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
      when(mockAuthRepository.removeAccount(any)).thenAnswer((_) async {});
      when(mockAuthRepository.saveAccount(any)).thenAnswer((_) async {});
      when(
        mockAuthRepository.storeLicenseKey(any, id: anyNamed('id')),
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
          userB.licenseKey,
          id: userB.licenseId,
        ),
      ).called(1);

      // Verify FCM registration for new account
      verify(mockFcmService.registerTokenWithBackend()).called(1);
    });
  });
}
