import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:android_intent_plus/android_intent.dart';

enum NearbySharingState { idle, advertising, discovering, connected }

class NearbySharingService {
  static final NearbySharingService _instance =
      NearbySharingService._internal();
  factory NearbySharingService() => _instance;
  NearbySharingService._internal();

  final Strategy strategy = Strategy.P2P_STAR;
  NearbySharingState _state = NearbySharingState.idle;
  int? _sdkInt;

  NearbySharingState get state => _state;

  final Map<String, ConnectionInfo> connectedDevices = {};

  // Callback for UI updates
  void Function(String endpointId, ConnectionInfo info)? onConnectionInitiated;
  void Function(String endpointId)? onDisconnected;
  void Function(String endpointId, Payload payload)? onPayloadReceived;
  void Function(String endpointId, PayloadTransferUpdate update)?
  onPayloadTransferUpdate;
  void Function(String endpointId, String endpointName)? onEndpointFound;
  void Function(String endpointId)? onEndpointLost;

  Future<bool> checkPermissions() async {
    if (!Platform.isAndroid) return true;

    if (_sdkInt == null) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      _sdkInt = androidInfo.version.sdkInt;
    }
    final sdkInt = _sdkInt!;

    final permissions = <Permission>[];

    if (sdkInt >= 33) {
      // Android 13+
      permissions.addAll([
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.nearbyWifiDevices,
      ]);
    } else if (sdkInt >= 31) {
      // Android 12
      permissions.addAll([
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.location,
      ]);
    } else {
      // Android 11 and below
      permissions.addAll([Permission.bluetooth, Permission.location]);
    }

    // Auto-enable location service if disabled (mirrors Bluetooth auto-enable)
    if (await Permission.location.serviceStatus.isDisabled) {
      debugPrint(
        'NearbySharingService: Location service disabled, prompting user',
      );
      try {
        final intent = const AndroidIntent(
          action: 'android.settings.LOCATION_SOURCE_SETTINGS',
        );
        await intent.launch();

        // Wait for user to return and enable location (poll up to 30s)
        for (int i = 0; i < 60; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (await Permission.location.serviceStatus.isEnabled) {
            debugPrint(
              'NearbySharingService: Location service enabled by user',
            );
            break;
          }
        }
      } catch (e) {
        debugPrint(
          'NearbySharingService: Failed to open location settings: $e',
        );
      }

      // Re-check after prompt - if still disabled, return false
      if (await Permission.location.serviceStatus.isDisabled) {
        return false;
      }
    }

    bool allGranted = true;
    for (var permission in permissions) {
      final status = await permission.status;
      if (!status.isGranted) {
        final result = await permission.request();
        if (!result.isGranted) allGranted = false;
      }
    }

    // Note: We no longer request MANAGE_EXTERNAL_STORAGE as it's a high-risk permission
    // that often leads to Play Store rejection. For Android 13+, granular media permissions
    // or standard Downloads folder access should be used.

    return allGranted;
  }

  Future<String?> getHardwareErrorMessage() async {
    if (!Platform.isAndroid) return null;

    if (_sdkInt == null) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      _sdkInt = androidInfo.version.sdkInt;
    }
    final sdkInt = _sdkInt!;

    if (sdkInt < 33) {
      if (await Permission.location.serviceStatus.isDisabled) {
        return 'يرجى تفعيل الموقع الجغرافي (GPS)';
      }
    }

    final permissions = <Permission>[];
    if (sdkInt >= 33) {
      permissions.addAll([
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.nearbyWifiDevices,
      ]);
    } else if (sdkInt >= 31) {
      permissions.addAll([
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.location,
      ]);
    } else {
      permissions.addAll([Permission.bluetooth, Permission.location]);
    }

    for (final permission in permissions) {
      final status = await permission.status;
      if (status.isPermanentlyDenied) {
        return 'يرجى منح الإذن المطلوب من إعدادات التطبيق';
      }
      if (!status.isGranted) {
        return 'يرجى منح صلاحيات الوصول المطلوبة للمتابعة';
      }
    }

    return null;
  }

  Future<bool> startAdvertising(String userName) async {
    try {
      bool success = await Nearby().startAdvertising(
        userName,
        strategy,
        onConnectionInitiated: (endpointId, info) {
          connectedDevices[endpointId] = info;
          onConnectionInitiated?.call(endpointId, info);
        },
        onConnectionResult: (endpointId, status) {
          if (status == Status.CONNECTED) {
            _state = NearbySharingState.connected;
          } else {
            connectedDevices.remove(endpointId);
          }
        },
        onDisconnected: (endpointId) {
          connectedDevices.remove(endpointId);
          onDisconnected?.call(endpointId);
          if (connectedDevices.isEmpty) _state = NearbySharingState.advertising;
        },
      );
      if (success) _state = NearbySharingState.advertising;
      return success;
    } catch (e) {
      debugPrint("NearbySharingService: Error starting advertising: $e");
      return false;
    }
  }

  Future<bool> startDiscovery(String userName) async {
    try {
      bool success = await Nearby().startDiscovery(
        userName,
        strategy,
        onEndpointFound: (endpointId, endpointName, serviceId) {
          onEndpointFound?.call(endpointId, endpointName);
        },
        onEndpointLost: (endpointId) {
          if (endpointId != null) {
            onEndpointLost?.call(endpointId);
          }
        },
      );
      if (success) _state = NearbySharingState.discovering;
      return success;
    } catch (e) {
      debugPrint("NearbySharingService: Error starting discovery: $e");
      return false;
    }
  }

  Future<void> stopAll() async {
    await Nearby().stopAdvertising();
    await Nearby().stopDiscovery();
    await Nearby().stopAllEndpoints();
    connectedDevices.clear();
    _state = NearbySharingState.idle;
  }

  Future<bool> acceptConnection(String endpointId) async {
    return await Nearby().acceptConnection(
      endpointId,
      onPayLoadRecieved: (endpointId, payload) async {
        if (payload.type == PayloadType.FILE) {
          onPayloadReceived?.call(endpointId, payload);
        } else {
          onPayloadReceived?.call(endpointId, payload);
        }
      },
      onPayloadTransferUpdate: (endpointId, update) {
        onPayloadTransferUpdate?.call(endpointId, update);
      },
    );
  }

  Future<bool> requestConnection(String userName, String endpointId) async {
    return await Nearby().requestConnection(
      userName,
      endpointId,
      onConnectionInitiated: (id, info) {
        connectedDevices[id] = info;
        onConnectionInitiated?.call(id, info);
      },
      onConnectionResult: (id, status) {
        if (status == Status.CONNECTED) {
          _state = NearbySharingState.connected;
        } else {
          connectedDevices.remove(id);
        }
      },
      onDisconnected: (id) {
        connectedDevices.remove(id);
        onDisconnected?.call(id);
      },
    );
  }

  Future<void> sendFile(String endpointId, File file) async {
    await Nearby().sendFilePayload(endpointId, file.path);
  }

  Future<void> sendText(String endpointId, String text) async {
    await Nearby().sendBytesPayload(
      endpointId,
      Uint8List.fromList(text.codeUnits),
    );
  }
}
