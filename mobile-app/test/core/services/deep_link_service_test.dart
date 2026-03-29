import 'dart:async';
import 'package:almudeer_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:almudeer_mobile_app/core/services/deep_link_service.dart';

import '../../presentation/screens/subscription_screen_test.dart';


@GenerateMocks([AuthProvider])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAuthProvider mockAuthProvider;

  setUp(() {
    mockAuthProvider = MockAuthProvider();
    DeepLinkService.resetForTesting();
  });

  tearDown(() {
    DeepLinkService.resetForTesting();
  });

  group('DeepLinkService', () {
    group('handleLinkForTest', () {
      test(
        'emits DeepLinkResult.noKey when key parameter is missing',
        () async {
          final service = DeepLinkService();
          service.setAuthProviderForTest(mockAuthProvider);

          final completer = Completer<DeepLinkResult>();
          final subscription = service.resultStream.listen(completer.complete);

          await service.handleLinkForTest(Uri.parse('almudeer://login'));

          final result = await completer.future.timeout(
            const Duration(seconds: 2),
          );
          expect(result, DeepLinkResult.noKey);

          await subscription.cancel();
        },
      );

      test('emits DeepLinkResult.noKey when key parameter is empty', () async {
        final service = DeepLinkService();
        service.setAuthProviderForTest(mockAuthProvider);

        final completer = Completer<DeepLinkResult>();
        final subscription = service.resultStream.listen(completer.complete);

        await service.handleLinkForTest(Uri.parse('almudeer://login?key='));

        final result = await completer.future.timeout(
          const Duration(seconds: 2),
        );
        expect(result, DeepLinkResult.noKey);

        await subscription.cancel();
      });

      test(
        'emits DeepLinkResult.invalidKey when license format is invalid',
        () async {
          when(mockAuthProvider.validateLicenseFormat('INVALID-KEY')).thenReturn(false);

          final service = DeepLinkService();
          service.setAuthProviderForTest(mockAuthProvider);

          final completer = Completer<DeepLinkResult>();
          final subscription = service.resultStream.listen(completer.complete);

          await service.handleLinkForTest(
            Uri.parse('almudeer://login?key=INVALID-KEY'),
          );

          final result = await completer.future.timeout(
            const Duration(seconds: 2),
          );
          expect(result, DeepLinkResult.invalidKey);

          await subscription.cancel();
        },
      );

      test('emits DeepLinkResult.loginFailed when login fails', () async {
        const validKey = 'MUDEER-ABCD-1234-WXYZ';
        when(mockAuthProvider.validateLicenseFormat(validKey)).thenReturn(true);
        when(mockAuthProvider.login(validKey)).thenAnswer((_) async => false);

        final service = DeepLinkService();
        service.setAuthProviderForTest(mockAuthProvider);

        final completer = Completer<DeepLinkResult>();
        final subscription = service.resultStream.listen(completer.complete);

        await service.handleLinkForTest(
          Uri.parse('almudeer://login?key=$validKey'),
        );

        final result = await completer.future.timeout(
          const Duration(seconds: 2),
        );
        expect(result, DeepLinkResult.loginFailed);

        verify(mockAuthProvider.login(validKey)).called(1);
        await subscription.cancel();
      });

      test('emits DeepLinkResult.success when login succeeds', () async {
        const validKey = 'MUDEER-ABCD-1234-WXYZ';
        when(mockAuthProvider.validateLicenseFormat(validKey)).thenReturn(true);
        when(mockAuthProvider.login(validKey)).thenAnswer((_) async => true);

        final service = DeepLinkService();
        service.setAuthProviderForTest(mockAuthProvider);

        final completer = Completer<DeepLinkResult>();
        final subscription = service.resultStream.listen(completer.complete);

        await service.handleLinkForTest(
          Uri.parse('almudeer://login?key=$validKey'),
        );

        final result = await completer.future.timeout(
          const Duration(seconds: 2),
        );
        expect(result, DeepLinkResult.success);

        verify(mockAuthProvider.login(validKey)).called(1);
        await subscription.cancel();
      });

      test('normalizes key to uppercase before validation', () async {
        const lowercaseKey = 'mudeer-abcd-1234-wxyz';
        const normalizedKey = 'MUDEER-ABCD-1234-WXYZ';
        when(
          mockAuthProvider.validateLicenseFormat(normalizedKey),
        ).thenReturn(true);
        when(
          mockAuthProvider.login(normalizedKey),
        ).thenAnswer((_) async => true);

        final service = DeepLinkService();
        service.setAuthProviderForTest(mockAuthProvider);

        final completer = Completer<DeepLinkResult>();
        final subscription = service.resultStream.listen(completer.complete);

        await service.handleLinkForTest(
          Uri.parse('almudeer://login?key=$lowercaseKey'),
        );

        final result = await completer.future.timeout(
          const Duration(seconds: 2),
        );
        expect(result, DeepLinkResult.success);

        verify(mockAuthProvider.validateLicenseFormat(normalizedKey)).called(1);
        verify(mockAuthProvider.login(normalizedKey)).called(1);
        await subscription.cancel();
      });

      test('ignores non-almudeer schemes', () async {
        final service = DeepLinkService();
        service.setAuthProviderForTest(mockAuthProvider);

        var resultEmitted = false;
        final subscription = service.resultStream.listen((_) {
          resultEmitted = true;
        });

        await service.handleLinkForTest(
          Uri.parse('https://example.com/login?key=test'),
        );

        await Future.delayed(const Duration(milliseconds: 100));
        expect(resultEmitted, false);

        verifyNever(mockAuthProvider.login('test'));
        await subscription.cancel();
      });

      test('ignores non-login hosts', () async {
        final service = DeepLinkService();
        service.setAuthProviderForTest(mockAuthProvider);

        var resultEmitted = false;
        final subscription = service.resultStream.listen((_) {
          resultEmitted = true;
        });

        await service.handleLinkForTest(Uri.parse('almudeer://other?key=test'));

        await Future.delayed(const Duration(milliseconds: 100));
        expect(resultEmitted, false);

        verifyNever(mockAuthProvider.login('test'));
        await subscription.cancel();
      });
    });
  });
}
