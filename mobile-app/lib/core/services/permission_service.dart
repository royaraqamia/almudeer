import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Service to handle special and dangerous Android permissions
/// that require more than just a simple runtime request.
class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  /// Check and request Manage External Storage (Android 11+)
  /// Returns true if granted, false otherwise.
  Future<bool> requestManageExternalStorage() async {
    if (!Platform.isAndroid) return true;

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    if (sdkInt >= 30) {
      // Android 11+ (API 30+)
      if (await Permission.manageExternalStorage.isGranted) {
        return true;
      }
      final status = await Permission.manageExternalStorage.request();
      return status.isGranted;
    } else {
      // Android 10 and below
      if (await Permission.storage.isGranted) {
        return true;
      }
      final status = await Permission.storage.request();
      return status.isGranted;
    }
  }

  /// Check and request System Alert Window (Display over other apps)
  /// Returns true if granted, false otherwise.
  Future<bool> requestSystemAlertWindow() async {
    if (!Platform.isAndroid) return true;

    if (await Permission.systemAlertWindow.isGranted) {
      return true;
    }

    final status = await Permission.systemAlertWindow.request();
    return status.isGranted;
  }

  /// Request Usage Stats permission by opening settings
  /// We cannot easily check this permission status in pure Dart without a specific plugin,
  /// so we generally assume it's needed if the feature is accessed.
  Future<void> openUsageAccessSettings() async {
    if (!Platform.isAndroid) return;

    try {
      const intent = AndroidIntent(
        action: 'android.settings.USAGE_ACCESS_SETTINGS',
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
    } catch (e) {
      debugPrint('Error opening usage access settings: $e');
      await openAppSettings();
    }
  }

  /// Request Notification Listener permission by opening settings
  Future<void> openNotificationListenerSettings() async {
    if (!Platform.isAndroid) return;

    try {
      const intent = AndroidIntent(
        action: 'android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS',
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
    } catch (e) {
      debugPrint('Error opening notification listener settings: $e');
      await openAppSettings();
    }
  }

  /// Check if the current device is Android 13+ (API 33+)
  Future<bool> isAndroid13OrHigher() async {
    if (!Platform.isAndroid) return false;
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    return androidInfo.version.sdkInt >= 33;
  }

  /// Request all critical permissions for "Almudeer" mode
  Future<Map<String, bool>> requestAllCriticalPermissions() async {
    final results = <String, bool>{};

    results['storage'] = await requestManageExternalStorage();
    results['overlay'] = await requestSystemAlertWindow();

    return results;
  }
}
