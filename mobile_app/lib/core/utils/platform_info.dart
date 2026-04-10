/// Platform utilities - web stub implementation
/// This file is used on web platform where dart:io is not available
library;

bool get isMobilePlatform => false;
bool get isAndroidPlatform => false;
bool get isIOSPlatform => false;

String get currentPlatformName => 'web';

String? getDeviceId() => null;
