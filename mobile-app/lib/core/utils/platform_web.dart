/// Platform indicator - web version
library;

// On web, dart:io is not available, so we use kIsWeb
bool get isMobilePlatform => false;
bool get isAndroidPlatform => false;
bool get isIOSPlatform => false;
