/// User information model
class UserInfo {
  final String fullName;
  final String? profileImageUrl;
  final String? createdAt;
  final String expiresAt;
  final String? licenseKey;
  final int? licenseId;
  final bool isTrial;
  final String? referralCode;
  final int referralCount;
  final String? username;

  UserInfo({
    required this.fullName,
    this.profileImageUrl,
    this.createdAt,
    required this.expiresAt,
    this.licenseKey,
    this.licenseId,
    this.isTrial = false,
    this.referralCode,
    this.referralCount = 0,
    this.username,
  });

  UserInfo copyWith({
    String? fullName,
    String? profileImageUrl,
    String? createdAt,
    String? expiresAt,
    String? licenseKey,
    int? licenseId,
    bool? isTrial,
    String? referralCode,
    int? referralCount,
    String? username,
  }) {
    return UserInfo(
      fullName: fullName ?? this.fullName,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      licenseKey: licenseKey ?? this.licenseKey,
      licenseId: licenseId ?? this.licenseId,
      isTrial: isTrial ?? this.isTrial,
      referralCode: referralCode ?? this.referralCode,
      referralCount: referralCount ?? this.referralCount,
      username: username ?? this.username,
    );
  }

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      fullName:
          json['full_name'] as String? ?? json['company_name'] as String? ?? '',
      profileImageUrl: json['profile_image_url'] as String?,
      createdAt: json['created_at'] as String?,
      expiresAt: json['expires_at'] as String? ?? '',
      licenseKey: json['license_key'] as String?,
      licenseId: json['license_id'] as int?,
      isTrial: json['is_trial'] as bool? ?? false,
      referralCode: json['referral_code'] as String?,
      referralCount: json['referral_count'] as int? ?? 0,
      username: json['username'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'full_name': fullName,
      'profile_image_url': profileImageUrl,
      'created_at': createdAt,
      'expires_at': expiresAt,
      'license_key': licenseKey,
      'license_id': licenseId,
      'is_trial': isTrial,
      'referral_code': referralCode,
      'referral_count': referralCount,
      'username': username,
    };
  }

  /// Check if subscription is expired
  ///
  /// SECURITY FIX #8: Use UTC time for both expiration and current time
  /// to prevent timezone-related bugs
  bool get isExpired {
    try {
      final expiry = DateTime.parse(expiresAt).toUtc();
      return expiry.isBefore(DateTime.now().toUtc());
    } catch (e) {
      return false;
    }
  }

  /// Days until expiration
  ///
  /// SECURITY FIX #8: Use UTC time for consistent calculation
  int get daysUntilExpiry {
    try {
      final expiry = DateTime.parse(expiresAt).toUtc();
      return expiry.difference(DateTime.now().toUtc()).inDays;
    } catch (e) {
      return 0;
    }
  }
}

/// License validation result
class LicenseValidation {
  final bool valid;
  final String? fullName;
  final String? profileImageUrl;
  final String? createdAt;
  final String? expiresAt;
  final int? licenseId;
  final bool isTrial;
  final String? referralCode;
  final int referralCount;
  final String? username;
  final String? error;
  final int? retryAfterSeconds;

  LicenseValidation({
    required this.valid,
    this.licenseId,
    this.fullName,
    this.profileImageUrl,
    this.createdAt,
    this.expiresAt,
    this.isTrial = false,
    this.referralCode,
    this.referralCount = 0,
    this.username,
    this.error,
    this.retryAfterSeconds,
  });

  factory LicenseValidation.fromJson(Map<String, dynamic> json) {
    return LicenseValidation(
      valid: json['valid'] as bool? ?? false,
      licenseId: json['license_id'] as int?,
      fullName: json['full_name'] as String? ?? json['company_name'] as String?,
      profileImageUrl: json['profile_image_url'] as String?,
      createdAt: json['created_at'] as String?,
      expiresAt: json['expires_at'] as String?,
      isTrial: json['is_trial'] as bool? ?? false,
      referralCode: json['referral_code'] as String?,
      referralCount: json['referral_count'] as int? ?? 0,
      username: json['username'] as String?,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'valid': valid,
      'full_name': fullName,
      'profile_image_url': profileImageUrl,
      'created_at': createdAt,
      'expires_at': expiresAt,
      'license_id': licenseId,
      'is_trial': isTrial,
      'referral_code': referralCode,
      'referral_count': referralCount,
      'username': username,
      'error': error,
    };
  }
}

/// JWT Authentication Response
class JwtAuthResponse {
  final String accessToken;
  final String? refreshToken;
  final String tokenType;
  final int expiresIn;
  final UserInfo? user;

  JwtAuthResponse({
    required this.accessToken,
    this.refreshToken,
    this.tokenType = 'bearer',
    required this.expiresIn,
    this.user,
  });

  factory JwtAuthResponse.fromJson(Map<String, dynamic> json) {
    return JwtAuthResponse(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String?,
      tokenType: json['token_type'] as String? ?? 'bearer',
      expiresIn: json['expires_in'] as int? ?? 1800,
      user: json['user'] != null
          ? UserInfo.fromJson(json['user'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'token_type': tokenType,
      'expires_in': expiresIn,
      'user': user?.toJson(),
    };
  }
}
