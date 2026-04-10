/// Platform indicator - mobile version
library;

import 'dart:io';

bool get isMobilePlatform => Platform.isAndroid || Platform.isIOS;
bool get isAndroidPlatform => Platform.isAndroid;
bool get isIOSPlatform => Platform.isIOS;
