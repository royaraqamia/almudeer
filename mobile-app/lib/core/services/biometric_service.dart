import 'package:local_auth/local_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// P2-18: Biometric authentication service
/// Manages fingerprint/Face ID unlock for the app.
/// 
/// Usage:
///   final service = BiometricService();
///   final available = await service.isBiometricAvailable();
///   final authenticated = await service.authenticate();
class BiometricService {
  static BiometricService? _instance;
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static const String _biometricEnabledKey = 'almudeer_biometric_enabled';

  static BiometricService get instance {
    _instance ??= BiometricService._internal();
    return _instance!;
  }

  BiometricService._internal();

  /// Check if biometric authentication is available on this device
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) return false;

      final biometrics = await _localAuth.getAvailableBiometrics();
      return biometrics.isNotEmpty;
    } catch (e) {
      debugPrint('[BiometricService] Biometric not available: $e');
      return false;
    }
  }

  /// Get available biometric types
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      debugPrint('[BiometricService] Failed to get biometrics: $e');
      return [];
    }
  }

  /// Check if biometric unlock is enabled by user
  Future<bool> isBiometricEnabled() async {
    final value = await _secureStorage.read(key: _biometricEnabledKey);
    return value == 'true';
  }

  /// Enable or disable biometric unlock
  Future<void> setBiometricEnabled(bool enabled) async {
    if (enabled) {
      // Verify biometric works before enabling
      final available = await isBiometricAvailable();
      if (!available) return;
    }
    await _secureStorage.write(
      key: _biometricEnabledKey,
      value: enabled ? 'true' : 'false',
    );
  }

  /// Authenticate with biometrics
  /// Returns true if authenticated, false otherwise
  Future<bool> authenticate() async {
    try {
      final available = await isBiometricAvailable();
      if (!available) return false;

      final enabled = await isBiometricEnabled();
      if (!enabled) return false;

      return await _localAuth.authenticate(
        localizedReason: 'استخدم بصمة الإصبع أو Face ID لتسجيل الدخول',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      );
    } catch (e) {
      debugPrint('[BiometricService] Authentication failed: $e');
      return false;
    }
  }

  /// Get human-readable biometric type
  String getBiometricLabel(BiometricType type) {
    return switch (type) {
      BiometricType.face => 'Face ID',
      BiometricType.fingerprint => 'بصمة الإصبع',
      BiometricType.iris => 'قزحية العين',
      BiometricType.strong => 'مصادقة قوية',
      BiometricType.weak => 'مصادقة ضعيفة',
    };
  }
}
