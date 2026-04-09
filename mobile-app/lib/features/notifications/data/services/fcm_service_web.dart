/// FCM Service stub for web platform
/// Firebase Messaging is not available on web, so this provides a no-op implementation
library;

import 'dart:async';
import 'package:flutter/foundation.dart';

/// Background message handler stub
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(dynamic message) async {
  // No-op on web
}

/// FCM Service stub for web
class FcmService {
  static FcmService? _instance;
  factory FcmService() => _instance ??= FcmService._internal();

  /// Protected constructor for testing purposes
  @visibleForTesting
  FcmService.protected();

  FcmService._internal();

  String? get fcmToken => null;

  Future<void> initialize() async {
    debugPrint('FCM: Skipping on web platform');
    return;
  }

  Future<void> registerTokenWithBackend({int maxRetries = 3}) async {
    // No-op on web
  }

  Future<void> unregisterToken() async {
    // No-op on web
    debugPrint('FCM: Skipping token unregistration on web platform');
  }
}
