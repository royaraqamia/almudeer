import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:almudeer_mobile_app/core/api/api_client.dart';
import 'package:almudeer_mobile_app/core/api/endpoints.dart';
import 'package:almudeer_mobile_app/features/users/data/models/user_info.dart';

/// Repository for authentication operations
class AuthRepository {
  final FlutterSecureStorage _secureStorage;
  final ApiClient _apiClient;

  AuthRepository({ApiClient? apiClient, FlutterSecureStorage? secureStorage})
    : _apiClient = apiClient ?? ApiClient(),
      _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Validate a license key
  Future<LicenseValidation> validateLicense(String key) async {
    try {
      final response = await _apiClient.post(
        Endpoints.login,
        body: {'license_key': key},
        requiresAuth: false,
      );

      final jwtAuth = JwtAuthResponse.fromJson(response);

      await _apiClient.setLicenseInfo(
        key: key,
        id: jwtAuth.user?.licenseId,
        accessToken: jwtAuth.accessToken,
        refreshToken: jwtAuth.refreshToken,
      );

      return LicenseValidation(
        valid: true,
        licenseId: jwtAuth.user?.licenseId,
        fullName: jwtAuth.user?.fullName,
        profileImageUrl: jwtAuth.user?.profileImageUrl,
        createdAt: jwtAuth.user?.createdAt,
        expiresAt: jwtAuth.user?.expiresAt,
        isTrial: jwtAuth.user?.isTrial ?? false,
        referralCode: jwtAuth.user?.referralCode,
        referralCount: jwtAuth.user?.referralCount ?? 0,
        username: jwtAuth.user?.username,
      );
    } on ApiException catch (e) {
      return LicenseValidation(
        valid: false,
        error: e.message,
        retryAfterSeconds: e.retryAfterSeconds,
      );
    } catch (e) {
      return LicenseValidation(
        valid: false,
        error: e is AuthenticationException ? e.message : 'ط­ط¯ط« ط®ط·ط£ ظپظٹ ط§ظ„ط§طھطµط§ظ„',
      );
    }
  }

  /// Get current user info
  ///
  /// FIX: Uses /api/auth/me endpoint instead of /api/auth/login
  /// This avoids creating new tokens on every user info refresh
  Future<UserInfo> getUserInfo({String? key}) async {
    final licenseKey = key ?? await getLicenseKey();
    if (licenseKey == null) {
      throw AuthenticationException('No license key found');
    }

    final response = await _apiClient.get(
      Endpoints.userInfo,
      requiresAuth: true,
      overrideLicenseKey: licenseKey,
    );

    if (response['success'] != true || response['user'] == null) {
      throw AuthenticationException('ظپط´ظ„ ظپظٹ ط§ط³طھط±ط¯ط§ط¯ ظ…ط¹ظ„ظˆظ…ط§طھ ط§ظ„ظ…ط³طھط®ط¯ظ…');
    }

    final userData = response['user'] as Map<String, dynamic>;

    // Update stored license info with fresh data from server
    await _apiClient.setLicenseInfo(
      key: licenseKey,
      id: userData['licenseId'] as int?,
    );

    return UserInfo.fromJson(userData).copyWith(licenseKey: licenseKey);
  }

  /// Store license key after successful validation
  Future<void> storeLicenseKey(String key, {int? id}) async {
    final currentKey = await _apiClient.getLicenseKey();
    if (currentKey == key) {
      final accessToken = await _apiClient.getAccessToken();
      if (accessToken != null) {
        await _apiClient.setLicenseInfo(
          key: key,
          id: id,
          accessToken: accessToken,
        );
        return;
      }
    }
    await _apiClient.setLicenseInfo(key: key, id: id);
  }

  /// Clear stored license key (logout)
  Future<void> logout() async {
    try {
      await _apiClient.post(Endpoints.logout, requiresAuth: true);
    } catch (e) {
      // Best effort
    }
    await _apiClient.clearLicenseKey();
  }

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    return await _apiClient.isAuthenticated();
  }

  /// Get stored license key
  Future<String?> getLicenseKey() async {
    return await _apiClient.getLicenseKey();
  }

  static const String _accountsStorageKey = 'almudeer_saved_accounts';

  Future<List<UserInfo>> getSavedAccounts() async {
    final String? accountsJson = await _secureStorage.read(
      key: _accountsStorageKey,
    );
    if (accountsJson == null) return [];
    try {
      final List<dynamic> decoded = jsonDecode(accountsJson);
      return decoded.map((json) => UserInfo.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveAccount(UserInfo user) async {
    if (user.licenseKey == null) return;
    final normalizedKey = user.licenseKey!.toUpperCase().trim();
    final accounts = await getSavedAccounts();
    final index = accounts.indexWhere((u) {
      return u.licenseKey?.toUpperCase().trim() == normalizedKey;
    });
    if (index != -1) {
      accounts[index] = user;
    } else {
      accounts.add(user);
    }
    await _saveAccountsList(accounts);
  }

  Future<void> removeAccount(UserInfo user) async {
    if (user.licenseKey == null) return;
    final normalizedKey = user.licenseKey!.toUpperCase().trim();
    final accounts = await getSavedAccounts();
    accounts.removeWhere(
      (u) => u.licenseKey?.toUpperCase().trim() == normalizedKey,
    );
    await _saveAccountsList(accounts);
  }

  Future<void> _saveAccountsList(List<UserInfo> accounts) async {
    final String encoded = jsonEncode(accounts.map((u) => u.toJson()).toList());
    await _secureStorage.write(key: _accountsStorageKey, value: encoded);
  }
}
