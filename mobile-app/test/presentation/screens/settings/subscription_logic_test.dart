import 'package:flutter_test/flutter_test.dart';
import 'package:almudeer_mobile_app/data/models/user_info.dart';

void main() {
  group('Subscription Logic Tests', () {
    test('UserInfo daysUntilExpiry calculates correctly for active subscription', () {
      final now = DateTime.now();
      final expiresAt = now.add(const Duration(days: 180));

      final user = UserInfo(
        fullName: 'Test User',
        expiresAt: expiresAt.toIso8601String(),
      );

      final days = user.daysUntilExpiry;
      expect(days, greaterThan(0));
      expect(days, lessThanOrEqualTo(181)); // Allow 1 day margin for test execution time
    });

    test('UserInfo daysUntilExpiry returns negative for expired subscription', () {
      final now = DateTime.now();
      final expiresAt = now.subtract(const Duration(days: 30));

      final user = UserInfo(
        fullName: 'Expired User',
        expiresAt: expiresAt.toIso8601String(),
      );

      final days = user.daysUntilExpiry;
      expect(days, lessThan(0));
    });

    test('UserInfo isExpired returns true for past date', () {
      final now = DateTime.now();
      final expiresAt = now.subtract(const Duration(days: 1));

      final user = UserInfo(
        fullName: 'Expired User',
        expiresAt: expiresAt.toIso8601String(),
      );

      expect(user.isExpired, isTrue);
    });

    test('UserInfo isExpired returns false for future date', () {
      final now = DateTime.now();
      final expiresAt = now.add(const Duration(days: 1));

      final user = UserInfo(
        fullName: 'Active User',
        expiresAt: expiresAt.toIso8601String(),
      );

      expect(user.isExpired, isFalse);
    });

    test('UserInfo handles empty expiresAt gracefully', () {
      final user = UserInfo(
        fullName: 'Test User',
        expiresAt: '',
      );

      // Should not throw, returns 0 for invalid date
      expect(() => user.daysUntilExpiry, returnsNormally);
      expect(() => user.isExpired, returnsNormally);
    });

    test('UserInfo copyWith preserves licenseKey', () {
      final original = UserInfo(
        fullName: 'Original',
        expiresAt: '2025-12-31',
        licenseKey: 'MUDEER-TEST-1234-5678',
        licenseId: 1,
      );

      final copied = original.copyWith(fullName: 'Updated');

      expect(copied.fullName, equals('Updated'));
      expect(copied.licenseKey, equals('MUDEER-TEST-1234-5678'));
      expect(copied.licenseId, equals(1));
    });

    test('UserInfo fromJson handles null values', () {
      final json = <String, dynamic>{
        'full_name': 'Test Company',
        // Missing optional fields
      };

      final user = UserInfo.fromJson(json);

      expect(user.fullName, equals('Test Company'));
      expect(user.profileImageUrl, isNull);
      expect(user.createdAt, isNull);
      expect(user.expiresAt, equals(''));
      expect(user.isTrial, isFalse);
    });

    test('UserInfo fromJson uses company_name as fallback', () {
      final json = <String, dynamic>{
        'company_name': 'Fallback Company',
      };

      final user = UserInfo.fromJson(json);

      expect(user.fullName, equals('Fallback Company'));
    });
  });
}
