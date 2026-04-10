import 'package:flutter/foundation.dart';

/// Utility to check if running on web platform
class PlatformUtils {
  static bool get isWeb => kIsWeb;
  static bool get isMobile => !kIsWeb;
  static bool get isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
}

/// Stub implementations for mobile-only services on web
class MobileServiceStubs {
  /// Check if a service should be skipped on web
  static bool shouldSkipOnWeb() => kIsWeb;
}
