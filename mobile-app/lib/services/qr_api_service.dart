import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/api/endpoints.dart';

/// QR Code error codes - centralized constants for consistency
class QrErrorCode {
  static const String notFound = 'NOT_FOUND';
  static const String inactive = 'INACTIVE';
  static const String expired = 'EXPIRED';
  static const String maxUsesReached = 'MAX_USES_REACHED';
  static const String rateLimited = 'RATE_LIMITED';
  static const String serverError = 'SERVER_ERROR';
  static const String networkError = 'NETWORK_ERROR';
  static const String badRequest = 'BAD_REQUEST';
  static const String unauthorized = 'UNAUTHORIZED';
}

/// QR Code verification result from backend
class QrVerificationResult {
  final bool valid;
  final String? error;
  final String? errorCode;
  final Map<String, dynamic>? qrCode;
  final int? useCount;
  final int? maxUses;
  final DateTime? expiresAt;

  QrVerificationResult({
    required this.valid,
    this.error,
    this.errorCode,
    this.qrCode,
    this.useCount,
    this.maxUses,
    this.expiresAt,
  });

  factory QrVerificationResult.fromJson(Map<String, dynamic> json) {
    return QrVerificationResult(
      valid: json['valid'] as bool? ?? false,
      error: json['error'] as String?,
      errorCode: json['error_code'] as String?,
      qrCode: json['qr_code'] as Map<String, dynamic>?,
      useCount: json['use_count'] as int?,
      maxUses: json['max_uses'] as int?,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString())
          : null,
    );
  }

  /// Check if QR code is valid and verified successfully
  bool get isSuccess => valid && error == null;

  /// Check if QR code is expired
  bool get isExpired => errorCode == QrErrorCode.expired;

  /// Check if QR code is inactive
  bool get isInactive => errorCode == QrErrorCode.inactive;

  /// Check if QR code is not found
  bool get isNotFound => errorCode == QrErrorCode.notFound;

  /// Check if QR code has reached maximum uses
  bool get isMaxUsesReached => errorCode == QrErrorCode.maxUsesReached;

  /// Get user-friendly error message
  String get errorMessage {
    if (error == null) return '';

    // Return error message in Arabic for consistency with app UI
    switch (errorCode) {
      case QrErrorCode.notFound:
        return 'رمز QR غير موجود';
      case QrErrorCode.inactive:
        return 'رمز QR غير نشط';
      case QrErrorCode.expired:
        return 'رمز QR منتهي الصلاحية';
      case QrErrorCode.maxUsesReached:
        return 'تم الوصول إلى الحد الأقصى لاستخدام رمز QR';
      default:
        return error!;
    }
  }

  @override
  String toString() {
    return 'QrVerificationResult(valid: $valid, error: $error, errorCode: $errorCode)';
  }
}

/// Service for QR code API operations
class QrApiService {
  static final QrApiService _instance = QrApiService._internal();
  factory QrApiService() => _instance;
  QrApiService._internal();

  final http.Client _client = http.Client();

  /// Verify a QR code with the backend
  /// 
  /// [codeHash] The hash of the QR code to verify
  /// [deviceInfo] Optional device information for analytics
  /// [authToken] Optional JWT token for authenticated requests (better rate limits)
  /// 
  /// Returns [QrVerificationResult] with verification status and QR code details
  Future<QrVerificationResult> verifyQrCode({
    required String codeHash,
    String? deviceInfo,
    String? authToken,
  }) async {
    try {
      // Build URL with query parameters
      final uri = Uri.parse(
        '${Endpoints.baseUrl}/qr/verify/$codeHash'
      ).replace(
        queryParameters: {
          if (deviceInfo != null && deviceInfo.isNotEmpty)
            'device_info': deviceInfo,
        },
      );

      // Prepare headers
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (authToken != null && authToken.isNotEmpty)
          'Authorization': 'Bearer $authToken',
      };

      // Make POST request (verify endpoint expects POST)
      final response = await _client.post(uri, headers: headers);

      // Handle response with comprehensive error code handling
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return QrVerificationResult.fromJson(data);
      } else if (response.statusCode == 404) {
        return QrVerificationResult(
          valid: false,
          error: 'رمز QR غير موجود',
          errorCode: QrErrorCode.notFound,
        );
      } else if (response.statusCode == 429) {
        return QrVerificationResult(
          valid: false,
          error: 'تم تجاوز حد المحاولات. يرجى المحاولة لاحقاً',
          errorCode: QrErrorCode.rateLimited,
        );
      } else if (response.statusCode == 400) {
        return QrVerificationResult(
          valid: false,
          error: 'طلب غير صالح',
          errorCode: QrErrorCode.badRequest,
        );
      } else if (response.statusCode == 401) {
        return QrVerificationResult(
          valid: false,
          error: 'غير مصرح',
          errorCode: QrErrorCode.unauthorized,
        );
      } else {
        return QrVerificationResult(
          valid: false,
          error: 'حدث خطأ أثناء التحقق. يرجى المحاولة مرة أخرى',
          errorCode: QrErrorCode.serverError,
        );
      }
    } on http.ClientException {
      // Network error (ClientException from http package)
      return QrVerificationResult(
        valid: false,
        error: 'فشل الاتصال بالخادم. تحقق من اتصالك بالإنترنت',
        errorCode: QrErrorCode.networkError,
      );
    } on FormatException {
      // JSON parsing error
      return QrVerificationResult(
        valid: false,
        error: 'خطأ في معالجة البيانات',
        errorCode: QrErrorCode.serverError,
      );
    } catch (_) {
      // Any other error
      return QrVerificationResult(
        valid: false,
        error: 'حدث خطأ غير متوقع',
        errorCode: QrErrorCode.serverError,
      );
    }
  }

  /// Check if a QR code looks like it should be verified with backend
  /// 
  /// Backend QR codes are 64-character SHA256 hashes
  static bool looksLikeBackendQr(String code) {
    // Backend QR codes are SHA256 hashes (64 hex characters)
    final hashPattern = RegExp(r'^[a-f0-9]{64}$', caseSensitive: false);
    return hashPattern.hasMatch(code);
  }

  /// Dispose the HTTP client
  void dispose() {
    _client.close();
  }
}
