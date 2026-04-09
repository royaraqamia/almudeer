import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:almudeer_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:almudeer_mobile_app/features/users/data/models/user_info.dart';
import 'package:almudeer_mobile_app/features/auth/data/repositories/auth_repository.dart';
import 'package:almudeer_mobile_app/features/notifications/data/services/fcm_service_mobile.dart'
    if (dart.library.js_interop) 'package:almudeer_mobile_app/features/notifications/data/services/fcm_service_web.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

/// Fake FcmService for testing - provides no-op implementations
class MockFcmService extends FcmService {
  MockFcmService() : super.protected();
}

void main() {
  group('AuthState', () {
    test('should have correct enum values', () {
      expect(AuthState.values.length, 5);
      expect(AuthState.initial.index, 0);
      expect(AuthState.loading.index, 1);
      expect(AuthState.authenticated.index, 2);
      expect(AuthState.unauthenticated.index, 3);
      expect(AuthState.error.index, 4);
    });
  });

  group('AuthProvider', () {
    late AuthProvider authProvider;
    late MockAuthRepository mockAuthRepository;
    late MockFcmService mockFcmService;

    setUp(() {
      mockAuthRepository = MockAuthRepository();
      mockFcmService = MockFcmService();
      authProvider = AuthProvider(
        authRepository: mockAuthRepository,
        fcmService: mockFcmService,
      );
    });

    test('should start in initial state', () {
      expect(authProvider.state, AuthState.initial);
      expect(authProvider.userInfo, isNull);
      expect(authProvider.errorMessage, isNull);
      expect(authProvider.accounts, isEmpty);
    });

    test('isAuthenticated returns true only when authenticated', () {
      expect(authProvider.isAuthenticated, isFalse);
    });

    test('isLoading returns true only when loading', () {
      expect(authProvider.isLoading, isFalse);
    });

    group('Rate Limiting', () {
      test('isRateLimited starts as false', () {
        expect(authProvider.isRateLimited, isFalse);
      });

      test('remainingLockoutMinutes starts as 0', () {
        expect(authProvider.remainingLockoutMinutes, 0);
      });
    });

    group('License Key Validation', () {
      test('validateLicenseFormat accepts valid format', () {
        expect(
          authProvider.validateLicenseFormat('MUDEER-ABCD-1234-5678'),
          isTrue,
        );
      });

      test('validateLicenseFormat rejects invalid format', () {
        expect(authProvider.validateLicenseFormat('INVALID-KEY'), isFalse);
      });
    });

    group('Error Handling', () {
      test('clearError resets error state', () {
        authProvider.clearError();
        expect(authProvider.errorMessage, isNull);
      });
    });
  });

  group('UserInfo Integration', () {
    test('should handle UserInfo with all fields', () {
      final user = UserInfo(
        fullName: 'ط´ط±ظƒط© ط§ظ„ظ…ط¯ظٹط±',
        expiresAt: '2025-12-31',
        referralCount: 1000,
        createdAt: '2024-01-01',
        licenseKey: 'MUDEER-TEST-1234-5678',
      );

      expect(user.fullName, 'ط´ط±ظƒط© ط§ظ„ظ…ط¯ظٹط±');
      expect(user.expiresAt, '2025-12-31');
      expect(user.referralCount, 1000);
      expect(user.licenseKey, 'MUDEER-TEST-1234-5678');
    });
  });
}
