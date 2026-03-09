import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import '../../presentation/providers/auth_provider.dart';
import '../../app/routes.dart';
import '../../presentation/widgets/animated_toast.dart';
import '../../presentation/widgets/custom_dialog.dart';
import 'notification_navigator.dart';

enum DeepLinkResult { success, invalidKey, loginFailed, noKey }

class DeepLinkService {
  static DeepLinkService? _instance;

  static DeepLinkService get instance {
    _instance ??= DeepLinkService._internal();
    return _instance!;
  }

  factory DeepLinkService() => instance;

  DeepLinkService._internal();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  AuthProvider? _authProvider;

  StreamController<DeepLinkResult>? _resultController;
  StreamController<DeepLinkResult> get resultController {
    _resultController ??= StreamController<DeepLinkResult>.broadcast();
    return _resultController!;
  }

  Stream<DeepLinkResult> get resultStream => resultController.stream;

  void init(AuthProvider authProvider) {
    _authProvider = authProvider;

    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleLink(uri);
    });

    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) => _handleLink(uri),
      onError: (err) => debugPrint('[DeepLinkService] Stream error: $err'),
    );
  }

  Future<void> _handleLink(Uri uri) async {
    debugPrint('[DeepLinkService] New link detected: $uri');

    if (uri.scheme == 'almudeer') {
      if (uri.host == 'login') {
        final key = uri.queryParameters['key'];
        if (key == null || key.isEmpty) {
          resultController.add(DeepLinkResult.noKey);
          return;
        }

        if (_authProvider == null) {
          resultController.add(DeepLinkResult.loginFailed);
          return;
        }

        final normalizedKey = key.toUpperCase().trim();
        if (!_authProvider!.validateLicenseFormat(normalizedKey)) {
          resultController.add(DeepLinkResult.invalidKey);
          return;
        }

        // SECURITY FIX #21: Add user confirmation for deep link authentication
        // This prevents malicious apps or websites from hijacking accounts
        final context = navigatorKey.currentContext;
        if (context != null) {
          final confirmed = await _showDeepLinkConfirmationDialog(context, normalizedKey);
          if (!confirmed) {
            debugPrint('[DeepLinkService] User cancelled deep link authentication');
            resultController.add(DeepLinkResult.loginFailed);
            return;
          }
        }

        debugPrint(
          '[DeepLinkService] Triggering auto-login for key: $normalizedKey',
        );
        final success = await _authProvider!.login(normalizedKey);

        if (success) {
          resultController.add(DeepLinkResult.success);
          _navigateToDashboard();
        } else {
          resultController.add(DeepLinkResult.loginFailed);
        }
      } else {
        _navigateToPath(uri.path, uri.queryParameters);
      }
    }
  }

  /// SECURITY FIX #21: Show confirmation dialog for deep link authentication
  /// This prevents malicious apps from hijacking accounts via deep links
  Future<bool> _showDeepLinkConfirmationDialog(
    BuildContext context,
    String licenseKey,
  ) async {
    // Mask the license key for display (show only first and last 4 chars)
    String maskedKey;
    if (licenseKey.length > 8) {
      maskedKey = '${licenseKey.substring(0, 4)}...${licenseKey.substring(licenseKey.length - 4)}';
    } else {
      maskedKey = '****';
    }

    final confirmed = await CustomDialog.show<bool>(
      context,
      title: 'تأكيد تسجيل الدخول',
      type: DialogType.confirm,
      message:
          'طلب تسجيل الدخول عبر رابط خارجي\n\nمفتاح الاشتراك: $maskedKey\n\nهل أنت متأكد أنك تريد تسجيل الدخول باستخدام هذا المفتاح؟',
      confirmText: 'تأكيد',
      cancelText: 'إلغاء',
      barrierDismissible: false,
    );

    return confirmed ?? false;
  }

  void _navigateToPath(String path, Map<String, String> queryParams) {
    if (navigatorKey.currentState == null) return;

    final routeName = _mapPathToRouteName(path);
    if (routeName == null) {
      debugPrint('[DeepLinkService] Unknown route path: $path');
      return;
    }

    debugPrint('[DeepLinkService] Navigating to: $routeName');
    navigatorKey.currentState!.pushNamed(
      routeName,
      arguments: queryParams.isNotEmpty ? queryParams : null,
    );
  }

  String? _mapPathToRouteName(String path) {
    final routeMappings = {
      '/': AppRoutes.root,
      '/inbox': AppRoutes.inbox,
      '/dashboard': AppRoutes.dashboard,
      '/customers': AppRoutes.customers,
      '/tasks': AppRoutes.tasks,
      '/library': AppRoutes.library,
      '/settings': AppRoutes.settingsRoute,
      '/subscription': AppRoutes.subscription,
      '/browser': AppRoutes.browser,
    };
    return routeMappings[path];
  }

  @visibleForTesting
  Future<void> handleLinkForTest(Uri uri) => _handleLink(uri);

  @visibleForTesting
  void setAuthProviderForTest(AuthProvider provider) {
    _authProvider = provider;
  }

  @visibleForTesting
  static void resetForTesting() {
    _instance?._linkSubscription?.cancel();
    _instance?._resultController?.close();
    _instance = null;
  }

  void _navigateToDashboard() {
    if (navigatorKey.currentState != null) {
      navigatorKey.currentState!.pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (_, _, _) => const DashboardShell(initialIndex: 0),
          transitionDuration: const Duration(milliseconds: 300),
          settings: const RouteSettings(name: AppRoutes.dashboard),
        ),
        (route) => false,
      );
    }
  }

  void showResultToast(DeepLinkResult result) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    switch (result) {
      case DeepLinkResult.success:
        AnimatedToast.success(context, 'تم تسجيل الدخول بنجاح');
        break;
      case DeepLinkResult.invalidKey:
        AnimatedToast.error(context, 'مفتاح الترخيص غير صالح');
        break;
      case DeepLinkResult.loginFailed:
        AnimatedToast.error(context, 'فشل تسجيل الدخول');
        break;
      case DeepLinkResult.noKey:
        AnimatedToast.error(context, 'لم يتم العثور على مفتاح الترخيص');
        break;
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
    _resultController?.close();
  }
}
