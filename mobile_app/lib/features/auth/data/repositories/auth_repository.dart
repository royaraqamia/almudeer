import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:almudeer_mobile_app/core/api/api_client.dart';
import 'package:almudeer_mobile_app/core/api/endpoints.dart';
import 'package:almudeer_mobile_app/features/users/data/models/user_info.dart';
import 'package:almudeer_mobile_app/features/auth/data/models/username_availability.dart';

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
      final deviceFingerprint = await _apiClient.getDeviceFingerprint();
      final response = await _apiClient.post(
        Endpoints.login,
        body: {'license_key': key, 'device_fingerprint': deviceFingerprint},
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
    // FIX: Retry logout up to 3 times before clearing local tokens
    // This ensures server-side session is invalidated when possible
    int attempts = 0;
    const maxAttempts = 3;
    bool serverLogoutSuccess = false;

    while (attempts < maxAttempts && !serverLogoutSuccess) {
      try {
        await _apiClient.post(Endpoints.logout, requiresAuth: true);
        serverLogoutSuccess = true;
      } catch (e) {
        attempts++;
        if (attempts < maxAttempts) {
          // Exponential backoff: 500ms, 1s, 2s
          await Future.delayed(Duration(milliseconds: 500 * (1 << (attempts - 1))));
          debugPrint('[AuthRepository] Logout attempt $attempts failed, retrying: $e');
        } else {
          debugPrint('[AuthRepository] Server logout failed after $maxAttempts attempts: $e');
          // Best effort — local tokens will still be cleared below
        }
      }
    }

    // Always clear local tokens regardless of server logout success
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

  // ==================== Email/Password Auth Methods ====================

  /// Check if username is available (real-time validation)
  Future<UsernameAvailability> checkUsernameAvailability(String username) async {
    try {
      final endpoint = Endpoints.checkUsername(username);
      debugPrint('[AuthRepo] Checking username: $username');
      debugPrint('[AuthRepo] Endpoint: $endpoint');
      debugPrint('[AuthRepo] Base URL: ${Endpoints.baseUrl}');
      
      final response = await _apiClient.get(
        endpoint,
        requiresAuth: false,
      );
      
      debugPrint('[AuthRepo] Response: $response');
      return UsernameAvailability.fromJson(response);
    } catch (e, stackTrace) {
      // Log the actual error for debugging
      debugPrint('[AuthRepo] Username availability check failed: $e');
      debugPrint('[AuthRepo] Stack trace: $stackTrace');

      // Provide more specific error messages based on error type
      String message;
      if (e is SocketException) {
        message = 'لا يوجد اتصال بالإنترنت';
      } else if (e is TimeoutException) {
        message = 'انتهت مهلة الاتصال بالخادم';
      } else if (e is ApiException) {
        message = e.message;
      } else if (e is AuthenticationException) {
        message = 'خطأ في المصادقة';
      } else {
        message = 'فشل في التحقق من توفر اسم المستخدم';
      }

      return UsernameAvailability(
        available: false,
        validFormat: true,
        message: message,
        isUnknown: true,
      );
    }
  }

  /// Sign up with email and password
  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    required String fullName,
    required String username,
  }) async {
    try {
      final response = await _apiClient.post(
        Endpoints.signup,
        body: {
          'email': email,
          'password': password,
          'full_name': fullName,
          'username': username,
        },
        requiresAuth: false,
      );
      return response;
    } on ApiException catch (e) {
      throw AuthenticationException(e.message);
    } catch (e) {
      throw AuthenticationException('حدث خطأ في الاتصال');
    }
  }

  /// Verify OTP code
  Future<Map<String, dynamic>> verifyOTP(String email, String otpCode) async {
    try {
      final response = await _apiClient.post(
        Endpoints.verifyOTP,
        body: {'email': email, 'otp_code': otpCode},
        requiresAuth: false,
      );
      return response;
    } on ApiException catch (e) {
      throw AuthenticationException(e.message);
    } catch (e) {
      throw AuthenticationException('حدث خطأ في التحقق');
    }
  }

  /// Resend OTP code
  Future<Map<String, dynamic>> resendOTP(String email) async {
    try {
      final response = await _apiClient.post(
        Endpoints.resendOTP,
        body: {'email': email},
        requiresAuth: false,
      );
      return response;
    } on ApiException catch (e) {
      throw AuthenticationException(e.message);
    } catch (e) {
      throw AuthenticationException('حدث خطأ في إعادة الإرسال');
    }
  }

  /// Login with email and password
  Future<LicenseValidation> loginWithEmail(String email, String password) async {
    try {
      final deviceFingerprint = await _apiClient.getDeviceFingerprint();
      final response = await _apiClient.post(
        Endpoints.login,
        body: {'email': email, 'password': password, 'device_fingerprint': deviceFingerprint},
        requiresAuth: false,
      );

      final jwtAuth = JwtAuthResponse.fromJson(response);

      // Store tokens scoped to email
      // FIX: Also store user_id for unique account identification
      await _apiClient.setLicenseInfo(
        key: email,
        id: jwtAuth.user?.licenseId,
        accessToken: jwtAuth.accessToken,
        refreshToken: jwtAuth.refreshToken,
        userId: jwtAuth.user?.userId,
      );

      return LicenseValidation(
        valid: true,
        userId: jwtAuth.user?.userId,
        email: jwtAuth.user?.email,
        licenseId: jwtAuth.user?.licenseId,
        fullName: jwtAuth.user?.fullName,
        profileImageUrl: jwtAuth.user?.profileImageUrl,
        isApprovedByAdmin: jwtAuth.user?.isApprovedByAdmin ?? true,
        approvalStatus: 'approved',
      );
    } on ApiException catch (e) {
      // Check for pending approval response
      if (e.message.contains('PENDING_APPROVAL') ||
          (e.data != null && e.data!['error_code'] == 'PENDING_APPROVAL')) {
        return LicenseValidation(
          valid: false,
          error: e.message,
          approvalStatus: 'pending',
          userId: e.data?['user_id'],
          email: email,
          isApprovedByAdmin: false,
        );
      }
      if (e.message.contains('EMAIL_NOT_VERIFIED')) {
        return LicenseValidation(
          valid: false,
          error: 'يجب التحقق من البريد الإلكتروني أولاً',
          email: email,
        );
      }
      return LicenseValidation(
        valid: false,
        error: e.message,
        retryAfterSeconds: e.retryAfterSeconds,
      );
    } catch (e) {
      return LicenseValidation(
        valid: false,
        error: e is AuthenticationException ? e.message : 'حدث خطأ في الاتصال',
      );
    }
  }

  /// Forgot password - send reset email
  Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      final response = await _apiClient.post(
        Endpoints.forgotPassword,
        body: {'email': email},
        requiresAuth: false,
      );
      return response;
    } on ApiException catch (e) {
      throw AuthenticationException(e.message);
    } catch (e) {
      throw AuthenticationException('حدث خطأ في الاتصال');
    }
  }

  /// Reset password with token
  Future<Map<String, dynamic>> resetPassword(String token, String newPassword) async {
    try {
      final response = await _apiClient.post(
        Endpoints.resetPassword,
        body: {'token': token, 'new_password': newPassword},
        requiresAuth: false,
      );
      return response;
    } on ApiException catch (e) {
      throw AuthenticationException(e.message);
    } catch (e) {
      throw AuthenticationException('حدث خطأ في إعادة التعيين');
    }
  }

  /// Check approval status (requires authenticated user)
  Future<Map<String, dynamic>> getApprovalStatus() async {
    try {
      final response = await _apiClient.get(
        Endpoints.approvalStatus,
        requiresAuth: true,
      );
      return response;
    } catch (e) {
      throw Exception('فشل في التحقق من حالة الموافقة');
    }
  }
}

// ==================== Data Models ====================

class JwtAuthResponse {
  final String accessToken;
  final String? refreshToken;
  final int expiresIn;
  final JwtUser? user;

  JwtAuthResponse({
    required this.accessToken,
    this.refreshToken,
    required this.expiresIn,
    this.user,
  });

  factory JwtAuthResponse.fromJson(Map<String, dynamic> json) {
    return JwtAuthResponse(
      accessToken: json['access_token'] ?? '',
      refreshToken: json['refresh_token'],
      expiresIn: json['expires_in'] ?? 0,
      user: json['user'] != null ? JwtUser.fromJson(json['user']) : null,
    );
  }
}

class JwtUser {
  final int? licenseId;
  final int? userId;
  final String? email;
  final String? fullName;
  final String? profileImageUrl;
  final String? createdAt;
  final String? expiresAt;
  final bool? isTrial;
  final String? referralCode;
  final int? referralCount;
  final String? username;
  final String? licenseKey;
  final bool? isApprovedByAdmin;
  final String? approvalStatus;

  JwtUser({
    this.licenseId,
    this.userId,
    this.email,
    this.fullName,
    this.profileImageUrl,
    this.createdAt,
    this.expiresAt,
    this.isTrial,
    this.referralCode,
    this.referralCount,
    this.username,
    this.licenseKey,
    this.isApprovedByAdmin,
    this.approvalStatus,
  });

  factory JwtUser.fromJson(Map<String, dynamic> json) {
    return JwtUser(
      licenseId: json['license_id'] as int?,
      userId: json['user_id'] != null ? int.tryParse(json['user_id'].toString()) : null,
      email: json['email'] as String?,
      fullName: json['full_name'] as String?,
      profileImageUrl: json['profile_image_url'] as String?,
      createdAt: json['created_at'] as String?,
      expiresAt: json['expires_at'] as String?,
      isTrial: json['is_trial'] as bool?,
      referralCode: json['referral_code'] as String?,
      referralCount: json['referral_count'] as int?,
      username: json['username'] as String?,
      licenseKey: json['license_key'] as String?,
      isApprovedByAdmin: json['is_approved_by_admin'] as bool?,
      approvalStatus: json['approval_status'] as String?,
    );
  }
}

class LicenseValidation {
  final bool valid;
  final String? error;
  final int? retryAfterSeconds;
  final int? licenseId;
  final int? userId;
  final String? email;
  final String? fullName;
  final String? profileImageUrl;
  final String? createdAt;
  final String? expiresAt;
  final bool? isTrial;
  final String? referralCode;
  final int? referralCount;
  final String? username;
  final String? approvalStatus;
  final bool? isApprovedByAdmin;

  LicenseValidation({
    required this.valid,
    this.error,
    this.retryAfterSeconds,
    this.licenseId,
    this.userId,
    this.email,
    this.fullName,
    this.profileImageUrl,
    this.createdAt,
    this.expiresAt,
    this.isTrial,
    this.referralCode,
    this.referralCount,
    this.username,
    this.approvalStatus,
    this.isApprovedByAdmin,
  });

  Map<String, dynamic> toJson() {
    return {
      'license_id': licenseId,
      'user_id': userId,
      'email': email,
      'full_name': fullName,
      'profile_image_url': profileImageUrl,
      'created_at': createdAt,
      'expires_at': expiresAt,
      'is_trial': isTrial,
      'referral_code': referralCode,
      'referral_count': referralCount,
      'username': username,
      'approval_status': approvalStatus,
      'is_approved_by_admin': isApprovedByAdmin,
    };
  }
}
