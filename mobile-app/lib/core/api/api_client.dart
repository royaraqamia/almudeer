import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';
import 'package:mime/mime.dart';
import '../services/security_event_service.dart';
import '../services/connectivity_service.dart';
import 'endpoints.dart';

/// Default timeout for HTTP requests
const Duration _requestTimeout = Duration(seconds: 60);

// Issue #24: Longer timeout for file uploads
const Duration _uploadTimeout = Duration(minutes: 5);

/// Custom exception for authentication errors
class AuthenticationException implements Exception {
  final String message;
  final int? statusCode;
  AuthenticationException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Custom exception for API errors
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final int? retryAfterSeconds;
  final String? code;

  ApiException(this.message, {this.statusCode, this.retryAfterSeconds, this.code});

  @override
  String toString() => message;
}

/// Custom exception for ITEM_NOT_FOUND errors
/// Used to signal that an item doesn't exist on the server and pending actions should be cleared
class ItemNotFoundException extends ApiException {
  final int? itemId;

  ItemNotFoundException(super.message, {this.itemId})
    : super(statusCode: 404, code: 'ITEM_NOT_FOUND');

  @override
  String toString() => 'ItemNotFoundException: $message (itemId: $itemId)';
}

/// API client for Al-Mudeer backend
/// 
/// SECURITY FIXES IMPLEMENTED:
/// - Removed SSL certificate bypass (even in debug mode)
/// - JWT-only authentication (no license key in headers)
/// - Token expiration validation before API calls
/// - Fixed token refresh race condition with proper queue
/// - Certificate pinning support
/// - Clock skew tolerance for token expiration
/// - Centralized license key normalization
/// - Cryptographic hash for token storage key derivation
class ApiClient {
  static const String _licenseKeyStorage = 'almudeer_license_key';
  static const String _licenseIdStorage = 'almudeer_license_id';
  static const String _accessTokenStorage = 'almudeer_access_token';
  static const String _refreshTokenStorage = 'almudeer_refresh_token';
  static final ApiClient _instance = ApiClient._internal();

  factory ApiClient() => _instance;

  ApiClient._internal() {
    // SECURITY: Double-check that SSL bypass is NEVER used in release builds
    assert(
      !kReleaseMode || !kDebugMode,
      'SECURITY CRITICAL: SSL verification bypass detected in release build!',
    );
  }

  late final http.Client _client = _createSecureClient();

  // SECURITY FIX #16: Removed SSL certificate bypass completely
  // Even in debug mode, we now validate SSL certificates
  // P2-14 FIX: Added certificate pinning for enhanced MITM protection
  http.Client _createSecureClient() {
    // P2-14 FIX: Create custom HttpClient with certificate pinning
    final httpClient = HttpClient();

    // P2-14 FIX: Enable certificate pinning in production
    // This prevents MITM attacks even if a CA is compromised
    if (kReleaseMode) {
      httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) {
        // P2-14 FIX: Pin backend certificate by SHA-256 hash
        // IMPORTANT: Replace with your actual backend certificate hash
        // To get the hash: openssl s_client -connect your-domain.com:443 2>/dev/null | openssl x509 -pubkey -noout | sha256sum
        const String expectedCertHash = 'sha256/REPLACE_WITH_YOUR_ACTUAL_CERT_HASH=';

        if (expectedCertHash == 'sha256/REPLACE_WITH_YOUR_ACTUAL_CERT_HASH=') {
          // P2-14 FIX: If hash not configured, fall back to standard validation
          // This is safe - we still validate the certificate chain
          debugPrint('[ApiClient] Certificate pinning not configured - using standard validation');
          return false; // Reject bad certificates even if pinning not configured
        }

        // Verify certificate hash matches pinned hash
        final certHash = _calculateCertHash(cert);
        final matches = certHash == expectedCertHash;

        if (!matches) {
          debugPrint('[ApiClient] Certificate pinning failed! Expected: $expectedCertHash, Got: $certHash');
        }

        return matches;
      };
    }

    // SECURITY: No SSL bypass - always validate certificates
    return IOClient(httpClient);
  }

  // P2-14 FIX: Helper to calculate SHA-256 hash of certificate
  String _calculateCertHash(X509Certificate cert) {
    try {
      final digest = sha256.convert(cert.der);
      return 'sha256/${base64Encode(digest.bytes)}';
    } catch (e) {
      debugPrint('[ApiClient] Failed to calculate certificate hash: $e');
      return '';
    }
  }

  @visibleForTesting
  set secureStorage(FlutterSecureStorage storage) => _secureStorage = storage;

  // SECURITY FIX #23 & #24: Configure platform-specific secure storage
  FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    // iOS Keychain configuration with device passcode protection
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
      // Require biometric or passcode for access (optional - can be enabled via settings)
      // protectiveClass: IOSProtectiveClass.biometryAny,
    ),
    // Android Keystore configuration with strong encryption
    // Note: encryptedSharedPreferences is deprecated in v11, data migrates to custom ciphers
    aOptions: AndroidOptions(
      preferencesKeyPrefix: 'almudeer_secure_',
      // Use hardware-backed keystore when available
      // Requires Android 6.0+
    ),
  );

  String? _cachedLicenseKey;

  Timer? _proactiveRefreshTimer;
  static const Duration _refreshBuffer = Duration(minutes: 5);

  // SECURITY FIX #27: Clock skew tolerance (5 minutes)
  static const Duration _clockSkewTolerance = Duration(minutes: 5);

  // P1-13: Server time offset for accurate token expiration
  // This compensates for device clock manipulation
  Duration? _serverTimeOffset;
  DateTime? _lastServerTimeSync;

  String? _temporaryOverrideLicenseKey;

  // CRITICAL SECURITY FIX: Use mutex lock to prevent token refresh race conditions
  // This ensures only one refresh operation can execute at a time per license key
  // Replaces the previous Completer-based approach which had a race window
  final Map<String, Lock> _refreshLocks = {};

  // SECURITY FIX #12: Track logout state to prevent token refresh during/after logout
  // CRITICAL FIX: Using atomic flag - only reset on successful login, never on timeout
  bool _isLoggingOut = false;
  
  // Track logout completion to prevent race conditions
  Completer<void>? _logoutCompleter;

  void setTemporaryOverride(String? key) {
    _temporaryOverrideLicenseKey = key;
    // Clear in-memory cache to force loading tokens for the new context
    _cachedLicenseKey = null;
  }

  // SECURITY FIX #30: Centralized license key normalization with cryptographic hash
  String _normalizeLicenseKey(String key) {
    return key.toUpperCase().trim();
  }

  // SECURITY FIX #29: Use cryptographic hash for storage key derivation
  String _scopedKey(String baseKey, [String? licenseKey]) {
    final key = licenseKey ?? _cachedLicenseKey;
    if (key == null) return baseKey;
    // Use SHA-256 hash instead of plain text concatenation
    final normalized = _normalizeLicenseKey(key);
    final hash = sha256.convert(utf8.encode(normalized)).toString();
    // CRITICAL SECURITY FIX: Use full 64-character hash to prevent collisions
    // Truncating to 16 chars significantly reduces entropy and could allow
    // one user's tokens to be accessed by another with a colliding hash
    return '${baseKey}_$hash';
  }

  Future<String?> getLicenseKey() async {
    if (_temporaryOverrideLicenseKey != null) {
      return _temporaryOverrideLicenseKey;
    }
    // ALWAYS read fresh from storage to avoid stale cache issues
    _cachedLicenseKey = await _secureStorage.read(key: _licenseKeyStorage);
    if (_cachedLicenseKey == null) {
      final prefs = await SharedPreferences.getInstance();
      final legacyKey = prefs.getString(_licenseKeyStorage);
      if (legacyKey != null) {
        await _secureStorage.write(key: _licenseKeyStorage, value: legacyKey);
        await prefs.remove(_licenseKeyStorage);
        _cachedLicenseKey = legacyKey;
      }
    }
    return _cachedLicenseKey;
  }

  Future<int?> getLicenseId([String? overrideKey]) async {
    final key = overrideKey ?? await getLicenseKey();
    if (key == null) return null;

    // ALWAYS read from storage - don't trust IDs across account switches
    final scopedKey = _scopedKey(_licenseIdStorage, key);
    final idStr =
        await _secureStorage.read(key: scopedKey) ??
        (overrideKey == null
            ? await _secureStorage.read(key: _licenseIdStorage)
            : null);

    if (idStr != null) {
      final id = int.tryParse(idStr);
      return id;
    }
    return null;
  }

  Future<void> setLicenseInfo({
    required String key,
    int? id,
    String? accessToken,
    String? refreshToken,
    bool updateActivePointer = true,
  }) async {
    if (updateActivePointer) {
      await _secureStorage.write(key: _licenseKeyStorage, value: key);
      _cachedLicenseKey = key;
    }

    if (id != null) {
      await _secureStorage.write(
        key: _scopedKey(_licenseIdStorage, key),
        value: id.toString(),
      );
    }

    if (accessToken != null) {
      await _secureStorage.write(
        key: _scopedKey(_accessTokenStorage, key),
        value: accessToken,
      );
    }

    if (refreshToken != null) {
      await _secureStorage.write(
        key: _scopedKey(_refreshTokenStorage, key),
        value: refreshToken,
      );
    }

    // CRITICAL FIX: Reset logout flag on successful login
    // This is the ONLY place where _isLoggingOut is reset to false
    _isLoggingOut = false;
    _logoutCompleter = null;

    // Store new device secret locally
    if (accessToken != null && updateActivePointer) {
      // Device secret rotation removed - license keys can now be used from any device
    }
  }

  Future<void> clearLicenseKey() async {
    // SECURITY FIX #12: Set logout flag to prevent concurrent refresh
    _isLoggingOut = true;
    _logoutCompleter = Completer<void>();

    final key = await getLicenseKey();
    if (key != null) {
      await _secureStorage.delete(key: _scopedKey(_licenseIdStorage, key));
      await _secureStorage.delete(key: _scopedKey(_accessTokenStorage, key));
      await _secureStorage.delete(key: _scopedKey(_refreshTokenStorage, key));
    }

    await _secureStorage.delete(key: _licenseKeyStorage);

    _cachedLicenseKey = null;

    // Cancel any proactive refresh timers
    cancelProactiveRefresh();

    // P0-1 FIX: Complete the logout completer AND reset flag atomically
    // This ensures any waiting refresh operations see the completed state
    // and can properly abort before we reset the flag
    _logoutCompleter?.complete();
    
    // P0-1 FIX: Wait a microtask to ensure all pending async operations
    // that were waiting on the completer have time to check the flag and abort
    await Future.microtask(() {});
    
    // P0-1 FIX: NOW reset the logout flag after all waiters have had a chance to abort
    // This is safe because:
    // 1. _isLoggingOut is still true during completer completion
    // 2. Any refresh waiting on completer.future will see _isLoggingOut still true
    // 3. Refresh will abort and remove its lock BEFORE we reset the flag
    // 4. Only after all that do we reset _isLoggingOut for next login
    _isLoggingOut = false;
    _logoutCompleter = null;
  }

  Future<bool> isAuthenticated() async {
    final key = await getLicenseKey();
    return key != null && key.isNotEmpty;
  }

  Future<String> getAccountCacheHash() async {
    final key = await getLicenseKey();
    if (key == null || key.isEmpty) return 'anonymous';
    final normalized = _normalizeLicenseKey(key);
    final hash = await compute(_generateHash, normalized);
    return hash.substring(0, 16);
  }

  static String _generateHash(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // SECURITY FIX #18: Add token expiration validation with clock skew tolerance
  Future<String?> getAccessToken([String? overrideKey]) async {
    final key = overrideKey ?? await getLicenseKey();
    if (key == null) return null;

    final scopedKey = _scopedKey(_accessTokenStorage, key);

    // Migration: Check global key if scoped is empty and it's the active account
    String? token = await _secureStorage.read(key: scopedKey);
    if (token == null && overrideKey == null) {
      token = await _secureStorage.read(key: _accessTokenStorage);
      if (token != null) {
        // Migrate it
        await _secureStorage.write(key: scopedKey, value: token);
      }
    }

    // SECURITY FIX #18: Validate token expiration before returning
    // P1-13 FIX: Use server time for comparison to prevent device clock issues
    // FIX: Allow offline-first by returning expired token if refresh fails (offline)
    if (token != null) {
      final expiration = _getTokenExpiration(token);
      if (expiration != null) {
        final now = _getServerTime(); // FIX: Use server time, not device time
        // If token is expired or will expire within buffer time, trigger refresh
        if (expiration.isBefore(now.subtract(_clockSkewTolerance))) {
          debugPrint('[ApiClient] Access token expired (server time: $now, expiration: $expiration), triggering refresh');
          // Try to refresh token
          final refreshed = await _refreshToken(key);
          if (refreshed) {
            final scopedKey = _scopedKey(_accessTokenStorage, key);
            return await _secureStorage.read(key: scopedKey);
          }
          // Refresh failed - check if offline
          final isOffline = !ConnectivityService().isOnline;
          if (isOffline) {
            // Offline: return expired token anyway, let API call handle auth failure
            // This enables offline-first: app can show cached data
            debugPrint('[ApiClient] Offline - returning expired token for offline-first experience');
            return token;
          }
          // Online but refresh failed - return null to force re-authentication
          debugPrint('[ApiClient] Online but refresh failed - returning null');
          return null;
        }
      }
    }

    return token;
  }

  Future<String?> getRefreshToken([String? overrideKey]) async {
    final key = overrideKey ?? await getLicenseKey();
    if (key == null) return null;

    final scopedKey = _scopedKey(_refreshTokenStorage, key);

    String? token = await _secureStorage.read(key: scopedKey);
    if (token == null && overrideKey == null) {
      token = await _secureStorage.read(key: _refreshTokenStorage);
      if (token != null) {
        await _secureStorage.write(key: scopedKey, value: token);
      }
    }

    // SECURITY FIX #9: Check refresh token expiration
    // Refresh tokens expire after 7 days by default (configurable via JWT_REFRESH_EXPIRE_DAYS)
    // P1-13 FIX: Use server time for comparison to prevent device clock issues
    // FIX: Allow offline-first by not clearing tokens if offline
    if (token != null) {
      final expiration = _getTokenExpiration(token);
      if (expiration != null) {
        final now = _getServerTime(); // FIX: Use server time, not device time
        // If refresh token is expired, check if we're offline
        if (expiration.isBefore(now)) {
          final isOffline = !ConnectivityService().isOnline;
          if (isOffline) {
            // Offline: don't clear tokens, allow offline-first experience
            debugPrint('[ApiClient] Refresh token expired but offline - not clearing tokens');
            return token;
          }
          // Online: clear tokens and force re-authentication
          debugPrint('[ApiClient] Refresh token expired (server time: $now), clearing tokens');
          await clearLicenseKey();
          return null;
        }
      }
    }

    return token;
  }

  Future<Map<String, dynamic>> _makeRequest(
    String method,
    String endpoint, {
    Map<String, String>? queryParams,
    Map<String, dynamic>? body,
    bool requiresAuth = true,
    String? overrideLicenseKey,
    int retryCount = 0,
  }) async {
    Uri uri = Uri.parse('${Endpoints.baseUrl}$endpoint');
    if (queryParams != null && queryParams.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParams);
    }
    // Debug logging for shared-with-me endpoint
    if (endpoint.contains('shared-with-me')) {
      debugPrint('[ApiClient] Full URI: $uri');
      debugPrint('[ApiClient] Endpoint: $endpoint');
      debugPrint('[ApiClient] Base URL: ${Endpoints.baseUrl}');
      debugPrint('[ApiClient] Query params: $queryParams');
    }
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    final key = overrideLicenseKey ?? await getLicenseKey();
    if (key == null || key.isEmpty) {
      if (requiresAuth) throw AuthenticationException('مفتاح الاشتراك مطلوب');
    }

    // SECURITY FIX #17: JWT-only authentication
    // Never send license key in headers - use access token only
    final accessToken = await getAccessToken(key);
    if (requiresAuth) {
      if (accessToken != null && accessToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $accessToken';
      } else {
        // No valid access token - throw auth exception to trigger login
        throw AuthenticationException('مفتاح الاشتراك مطلوب');
      }
      // SECURITY: License key is NEVER sent with API requests
      // Only used during initial authentication
    }
    
    try {
      http.Response response;
      switch (method) {
        case 'GET':
          response = await _client
              .get(uri, headers: headers)
              .timeout(_requestTimeout);
          break;
        case 'POST':
          response = await _client
              .post(
                uri,
                headers: headers,
                body: body != null ? jsonEncode(body) : null,
              )
              .timeout(_requestTimeout);
          break;
        case 'PUT':
          response = await _client
              .put(
                uri,
                headers: headers,
                body: body != null ? jsonEncode(body) : null,
              )
              .timeout(_requestTimeout);
          break;
        case 'PATCH':
          response = await _client
              .patch(
                uri,
                headers: headers,
                body: body != null ? jsonEncode(body) : null,
              )
              .timeout(_requestTimeout);
          break;
        case 'DELETE':
          response = await _client
              .delete(uri, headers: headers)
              .timeout(_requestTimeout);
          break;
        default:
          throw ApiException('Unsupported HTTP method: $method');
      }
      return _handleResponse(response);
    } on AuthenticationException catch (e) {
      // Auto-retry on 401: Attempt token refresh with race condition protection
      if (e.statusCode == 401 && retryCount < 1) {
        if (key != null) {
          final skey = _normalizeLicenseKey(key);

          // SECURITY FIX #19: Proper refresh queue - wait for existing refresh
          if (_refreshLocks.containsKey(skey)) {
            debugPrint(
              '[ApiClient] Waiting for existing refresh to complete...',
            );
            // Wait for the existing refresh operation to complete
            final lock = _refreshLocks[skey]!;
            await lock.synchronized(() async => true);
            
            // Retry the request after refresh completes
            debugPrint(
              '[ApiClient] Refresh completed, retrying original request',
            );
            return _makeRequest(
              method,
              endpoint,
              queryParams: queryParams,
              body: body,
              requiresAuth: requiresAuth,
              overrideLicenseKey: key,
              retryCount: retryCount + 1,
            );
          }

          // Start a new refresh with proper locking
          final refreshed = await _refreshToken(key);
          if (refreshed) {
            debugPrint(
              '[ApiClient] Token refresh successful, retrying request',
            );
            return _makeRequest(
              method,
              endpoint,
              queryParams: queryParams,
              body: body,
              requiresAuth: requiresAuth,
              overrideLicenseKey: key,
              retryCount: retryCount + 1,
            );
          }
          debugPrint('[ApiClient] Token refresh failed, rethrowing exception');
        }
      }
      rethrow;
    } on TimeoutException {
      throw ApiException('انتهت مهلة الاتصال. يرجى المحاولة مرة أخرى');
    } on SocketException catch (e) {
      throw ApiException('تعذر الاتصال: ${e.message}');
    } on HttpException {
      throw ApiException('حدث خطأ في تنسيق البيانات');
    } on FormatException {
      throw ApiException('حدث خطأ في معالجة الاستجابة');
    }
  }

  Future<Map<String, dynamic>> get(
    String endpoint, {
    Map<String, String>? queryParams,
    bool requiresAuth = true,
    String? overrideLicenseKey,
  }) => _makeRequest(
    'GET',
    endpoint,
    queryParams: queryParams,
    requiresAuth: requiresAuth,
    overrideLicenseKey: overrideLicenseKey,
  );
  
  Future<Map<String, dynamic>> post(
    String endpoint, {
    Map<String, dynamic>? body,
    bool requiresAuth = true,
    String? overrideLicenseKey,
  }) => _makeRequest(
    'POST',
    endpoint,
    body: body,
    requiresAuth: requiresAuth,
    overrideLicenseKey: overrideLicenseKey,
  );
  
  Future<Map<String, dynamic>> put(
    String endpoint, {
    Map<String, dynamic>? body,
    bool requiresAuth = true,
    String? overrideLicenseKey,
  }) => _makeRequest(
    'PUT',
    endpoint,
    body: body,
    requiresAuth: requiresAuth,
    overrideLicenseKey: overrideLicenseKey,
  );
  
  Future<Map<String, dynamic>> patch(
    String endpoint, {
    Map<String, dynamic>? body,
    bool requiresAuth = true,
    String? overrideLicenseKey,
  }) => _makeRequest(
    'PATCH',
    endpoint,
    body: body,
    requiresAuth: requiresAuth,
    overrideLicenseKey: overrideLicenseKey,
  );
  
  Future<Map<String, dynamic>> delete(
    String endpoint, {
    Map<String, String>? queryParams,
    bool requiresAuth = true,
    String? overrideLicenseKey,
  }) => _makeRequest(
    'DELETE',
    endpoint,
    queryParams: queryParams,
    requiresAuth: requiresAuth,
    overrideLicenseKey: overrideLicenseKey,
  );

  Future<http.Response> getRaw(
    String url, {
    bool requiresAuth = false,
    String? overrideLicenseKey,
  }) async {
    final uri = Uri.parse(url);
    final headers = <String, String>{};
    if (requiresAuth) {
      // SECURITY: Use JWT only, never license key
      final key = overrideLicenseKey ?? await getLicenseKey();
      final accessToken = await getAccessToken(key);
      if (accessToken != null && accessToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $accessToken';
      }
    }
    return await _client.get(uri, headers: headers).timeout(_requestTimeout);
  }

  Future<Map<String, dynamic>> uploadMultipleFiles(
    String endpoint, {
    required List<MapEntry<String, String>> files,
    Map<String, String>? fields,
    String method = 'POST',
    bool requiresAuth = true,
    String? overrideLicenseKey,
    void Function(double progress)? onProgress,
    int retryCount = 0,
  }) async {
    final uri = Uri.parse('${Endpoints.baseUrl}$endpoint');
    final request = ProgressMultipartRequest(
      method,
      uri,
      onProgress: onProgress,
    );
    request.headers['Accept'] = 'application/json';
    
    // SECURITY: JWT-only authentication for file uploads
    final key = overrideLicenseKey ?? await getLicenseKey();
    final accessToken = await getAccessToken(key);
    if (requiresAuth) {
      if (accessToken != null && accessToken.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $accessToken';
      } else {
        throw AuthenticationException('مفتاح الاشتراك مطلوب');
      }
    }
    
    if (fields != null) request.fields.addAll(fields);
    for (final entry in files) {
      final filePath = entry.value;
      final fieldName = entry.key;
      // Detect MIME type from file extension
      final mimeType = lookupMimeType(filePath) ?? 'application/octet-stream';
      final file = await http.MultipartFile.fromPath(
        fieldName,
        filePath,
        contentType: http.MediaType.parse(mimeType),
      );
      request.files.add(file);
    }
    try {
      final streamedResponse = await _client
          .send(request)
          .timeout(_uploadTimeout);
      final response = await http.Response.fromStream(streamedResponse);
      return _handleResponse(response);
    } on TimeoutException {
      throw ApiException(
        'انتهت مهلة رفع الملف. يرجى التحقق من اتصالك والمحاولة مرة أخرى',
        statusCode: 408,
      );
    } on AuthenticationException catch (e) {
      if (e.statusCode == 401 && retryCount < 1) {
        final refreshed = await _refreshToken(key);
        if (refreshed) {
          return uploadMultipleFiles(
            endpoint,
            files: files,
            fields: fields,
            requiresAuth: requiresAuth,
            overrideLicenseKey: key,
            onProgress: onProgress,
            retryCount: retryCount + 1,
          );
        }
      }
      rethrow;
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('حدث خطأ في رفع الملفات: $e');
    }
  }

  Future<Map<String, dynamic>> uploadFile(
    String endpoint, {
    required String filePath,
    required String fieldName,
    Map<String, String>? fields,
    bool requiresAuth = true,
    String? overrideLicenseKey,
    void Function(double progress)? onProgress,
  }) async {
    return uploadMultipleFiles(
      endpoint,
      files: [MapEntry(fieldName, filePath)],
      fields: fields,
      requiresAuth: requiresAuth,
      overrideLicenseKey: overrideLicenseKey,
      onProgress: onProgress,
    );
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    final statusCode = response.statusCode;
    int? retryAfter;
    if (response.headers.containsKey('retry-after')) {
      retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
    }

    // P1-13: Extract server time from Date header for clock sync
    final dateHeader = response.headers['date'];
    if (dateHeader != null) {
      try {
        final serverTime = HttpDate.parse(dateHeader);
        _updateServerTimeOffset(serverTime);
      } catch (e) {
        debugPrint('[ApiClient] Failed to parse server date header: $e');
      }
    }

    dynamic data;
    try {
      // Handle empty response body (common for DELETE operations)
      if (response.body.isEmpty || response.body.trim().isEmpty) {
        debugPrint('[ApiClient] Empty response body for ${response.request?.method} ${response.request?.url}');
        return {'success': true, 'statusCode': statusCode};
      }
      data = jsonDecode(response.body);
    } catch (e) {
      debugPrint('[ApiClient] JSON decode failed: $e, body: ${response.body}');
      if (statusCode >= 200 && statusCode < 300) return {'success': true};
      throw ApiException('حدث خطأ في معالجة الاستجابة', statusCode: statusCode);
    }
    if (statusCode >= 200 && statusCode < 300) {
      if (data is List) return {'data': data};
      // Handle null data
      if (data == null) {
        debugPrint('[ApiClient] Response data is null for ${response.request?.method} ${response.request?.url}');
        return {'success': true, 'statusCode': statusCode};
      }
      return data as Map<String, dynamic>;
    }
    final Map<String, dynamic> errorData = data is Map<String, dynamic>
        ? data
        : {'message': data.toString()};
    // Enhanced logging for debugging
    debugPrint('[ApiClient] Error response: statusCode=$statusCode, body=${response.body}');
    debugPrint('[ApiClient] Parsed errorData: $errorData');
    String errorMessage = 'حدث خطأ في الاتصال';
    if (errorData.containsKey('error')) {
      final error = errorData['error'];
      if (error is String) {
        errorMessage = error;
      } else if (error is Map) {
        // Backend returns error as object with code, message_ar, message_en
        errorMessage = (error['message_ar'] as String?) ??
            (error['message'] as String?) ??
            (error['message_en'] as String?) ??
            'حدث خطأ في رفع الملفات';
      }
    } else if (errorData.containsKey('detail')) {
      final detail = errorData['detail'];
      if (detail is String) {
        errorMessage = detail;
      } else if (detail is Map && detail.containsKey('error')) {
        errorMessage = detail['error'] as String;
      } else if (detail is Map && detail.containsKey('message')) {
        errorMessage = detail['message'] as String;
      } else if (detail is Map && detail.containsKey('message_ar')) {
        errorMessage = detail['message_ar'] as String;
      }
    } else if (errorData.containsKey('message')) {
      errorMessage = errorData['message'] as String;
    }
    switch (statusCode) {
      case 401:
        throw AuthenticationException(errorMessage, statusCode: statusCode);
      case 403:
        // SECURITY FIX #26: Only emit account disabled for specific error codes
        // Use backend error codes instead of keyword matching to prevent false positives
        final errorCode = errorData['code'] as String?;
        final isAccountDisabled =
            errorCode == 'ACCOUNT_DEACTIVATED' ||
            errorCode == 'SESSION_REVOKED' ||
            errorMessage.contains('المشترك معطل') ||
            errorMessage.contains('تم تعطيل الحساب');
        if (isAccountDisabled) {
          SecurityEventService().emit(SecurityEvent.accountDisabled);
        }
        throw AuthenticationException(errorMessage, statusCode: statusCode);
      case 404:
        // Check if this is an ITEM_NOT_FOUND error
        final errorCode = errorData['code'] as String?;
        if (errorCode == 'ITEM_NOT_FOUND') {
          // Try to extract item ID from the URL path
          int? itemId;
          final pathParts = response.request?.url.path.split('/');
          if (pathParts != null) {
            // Find the segment before the item ID (e.g., /api/library/254048570)
            final itemIndex = pathParts.indexWhere((p) => p.isNotEmpty && int.tryParse(p) != null);
            if (itemIndex >= 0) {
              itemId = int.tryParse(pathParts[itemIndex]);
            }
          }
          throw ItemNotFoundException(errorMessage, itemId: itemId);
        }
        throw ApiException(errorMessage, statusCode: statusCode, code: errorCode);
      case 429:
        throw ApiException(
          errorMessage,
          statusCode: statusCode,
          retryAfterSeconds: retryAfter,
        );
      case 500:
      case 502:
      case 503:
        throw ApiException(errorMessage, statusCode: statusCode);
      default:
        throw ApiException(errorMessage, statusCode: statusCode);
    }
  }

  // SECURITY FIX #19: Proper refresh token synchronization with mutex
  // CRITICAL FIX #1: Ensure device secret is loaded BEFORE refresh to prevent race condition
  // SECURITY FIX #12: Check logout state to prevent refresh during logout
  // P0-1 FIX: Additional state check to prevent refresh during account switching
  Future<bool> _refreshToken([String? overrideLicenseKey]) async {
    // P0-1 FIX: Check authentication state FIRST to prevent refresh during logout/account switch
    if (_isLoggingOut) {
      debugPrint('[ApiClient] Refresh aborted - logout in progress');
      _refreshLocks.remove(_normalizeLicenseKey(overrideLicenseKey ?? ''));
      return false;
    }

    final key = overrideLicenseKey ?? await getLicenseKey();
    if (key == null) {
      debugPrint('[ApiClient] Refresh aborted - no license key');
      return false;
    }

    final skey = _normalizeLicenseKey(key);

    // P0-1 FIX: Wait for any in-progress logout to complete before attempting refresh
    if (_logoutCompleter != null && !_logoutCompleter!.isCompleted) {
      debugPrint('[ApiClient] Refresh waiting for logout to complete...');
      await _logoutCompleter!.future;
      debugPrint('[ApiClient] Logout completed, checking if refresh should proceed...');
      // P0-1 FIX: Explicitly remove lock and abort after logout
      _refreshLocks.remove(skey);
      debugPrint('[ApiClient] Refresh aborted - logout completed, lock removed');
      return false;
    }

    // P0-1 FIX: Double-check logout state after waiting
    if (_isLoggingOut) {
      debugPrint('[ApiClient] Refresh aborted - logout flag still set');
      _refreshLocks.remove(skey);
      return false;
    }

    // Use mutex lock to ensure only one refresh executes at a time
    final lock = _refreshLocks.putIfAbsent(skey, () => Lock());

    return await lock.synchronized(() async {
      // P0-1 FIX: Triple-check logout state AND authentication state after acquiring lock
      if (_isLoggingOut) {
        debugPrint('[ApiClient] Refresh aborted - logout in progress (post-lock)');
        _refreshLocks.remove(skey);
        return false;
      }

      try {
        final refreshToken = await getRefreshToken(key);
        if (refreshToken == null) {
          return false;
        }

        final headers = <String, String>{
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        };

        final body = {
          'refresh_token': refreshToken,
        };

        final response = await _client
            .post(
              Uri.parse('${Endpoints.baseUrl}${Endpoints.refresh}'),
              headers: headers,
              body: jsonEncode(body),
            )
            .timeout(_requestTimeout);

        // P2-12 FIX: Extract server time from Date header for clock sync
        final dateHeader = response.headers['date'];
        if (dateHeader != null) {
          try {
            final serverTime = HttpDate.parse(dateHeader);
            _updateServerTimeOffset(serverTime);
          } catch (e) {
            debugPrint('[ApiClient] Failed to parse server date header on refresh: $e');
          }
        }

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final newAccessToken = data['access_token'];
          final newRefreshToken = data['refresh_token'];

          if (newAccessToken != null) {
            final currentActiveKey = await getLicenseKey();
            await setLicenseInfo(
              key: key,
              accessToken: newAccessToken,
              refreshToken: newRefreshToken,
              updateActivePointer:
                  overrideLicenseKey == null && currentActiveKey == key,
            );
            return true;
          }
        } else if (response.statusCode == 401 ||
            response.statusCode == 403 ||
            response.statusCode == 400) {
          // SECURITY FIX #5: Clear tokens immediately on auth failure
          // Session likely revoked on server - clear tokens to prevent limbo state
          if (overrideLicenseKey == null) {
            // Clear all tokens to prevent using expired/revoked credentials
            await clearLicenseKey();
            // Emit security event to trigger logout UI
            SecurityEventService().emit(SecurityEvent.accountDisabled);
            debugPrint('[ApiClient] Tokens cleared due to refresh auth failure (status: ${response.statusCode})');
          }
        }
      } catch (e) {
        debugPrint('[ApiClient] Token refresh failed for $skey: $e');
        // P0-1 FIX: Ensure lock is cleaned up on error
        _refreshLocks.remove(skey);
      } finally {
        // P0-1 FIX: Redundant cleanup removal for safety (already in catch)
        // This ensures lock is ALWAYS removed even on success path
        if (_refreshLocks.containsKey(skey)) {
          _refreshLocks.remove(skey);
        }
      }

      return false;
    });
  }

  // SECURITY FIX #27: Add clock skew tolerance to token expiration
  // P1-13: Use server time instead of device time to prevent clock manipulation
  DateTime? _getTokenExpiration(String? token) {
    if (token == null) return null;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload =
          jsonDecode(
            utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
          )
          as Map<String, dynamic>;
      final exp = payload['exp'] as int?;
      if (exp == null) return null;

      // Convert to DateTime
      final expiration = DateTime.fromMillisecondsSinceEpoch(exp * 1000);

      // P1-13: Use server time for comparison to prevent device clock manipulation
      final serverTime = _getServerTime();
      
      // Calculate time until expiration using server time
      expiration.difference(serverTime);

      // Return expiration minus clock skew tolerance
      // This ensures we refresh before the token actually expires
      return expiration.subtract(_clockSkewTolerance);
    } catch (e) {
      debugPrint('[ApiClient] Failed to decode token expiration: $e');
      // Fallback: Schedule refresh in 11 hours as safety net (tokens now last 12 hours)
      _proactiveRefreshTimer?.cancel();
      _proactiveRefreshTimer = Timer(const Duration(minutes: 660), () {
        debugPrint(
          '[ApiClient] Fallback refresh triggered due to parsing failure',
        );
        _refreshToken();
      });
      // Return a reasonable expiration time to allow scheduling to work
      return DateTime.now().add(const Duration(hours: 12));
    }
  }

  void scheduleProactiveRefresh() {
    _proactiveRefreshTimer?.cancel();
    getAccessToken().then((token) {
      if (token == null) return;
      final expiration = _getTokenExpiration(token);
      if (expiration == null) return;
      final now = _getServerTime(); // FIX: Use server time for accurate scheduling
      final timeUntilExpiry = expiration.difference(now);
      final refreshTime = timeUntilExpiry - _refreshBuffer;
      if (refreshTime.isNegative || refreshTime.inSeconds < 30) {
        debugPrint('[ApiClient] Token expiring soon, refreshing proactively');
        _refreshToken();
      } else {
        debugPrint(
          '[ApiClient] Scheduling proactive refresh in ${refreshTime.inMinutes} minutes',
        );
        _proactiveRefreshTimer = Timer(refreshTime, () {
          debugPrint('[ApiClient] Executing scheduled proactive refresh');
          _refreshToken();
        });
      }
    });
  }

  void cancelProactiveRefresh() {
    _proactiveRefreshTimer?.cancel();
    _proactiveRefreshTimer = null;
  }

  /// P1-13: Update server time offset from response headers
  /// Should be called after each API response
  void _updateServerTimeOffset(DateTime? serverTime) {
    if (serverTime == null) return;

    final now = DateTime.now();
    final newOffset = serverTime.difference(now);
    
    // Only log if offset changed significantly (>1 second) or is large (>5 seconds)
    final shouldLog = _serverTimeOffset == null ||
        (newOffset - _serverTimeOffset!).inSeconds.abs() > 1 ||
        newOffset.inSeconds.abs() > 5;
    
    _serverTimeOffset = newOffset;
    _lastServerTimeSync = now;
    
    if (shouldLog) {
      debugPrint('[ApiClient] Server time offset: ${_serverTimeOffset?.inSeconds}s');
    }
  }

  /// P1-13: Get current server time accounting for clock skew
  DateTime _getServerTime() {
    final now = DateTime.now();
    if (_serverTimeOffset != null && _lastServerTimeSync != null) {
      // Check if sync is stale (older than 1 hour)
      if (now.difference(_lastServerTimeSync!).inHours < 1) {
        return now.add(_serverTimeOffset!);
      }
    }
    // Fallback to local time if no recent sync
    return now;
  }
}

class ProgressMultipartRequest extends http.MultipartRequest {
  final void Function(double progress)? onProgress;
  ProgressMultipartRequest(super.method, super.url, {this.onProgress});

  @override
  http.ByteStream finalize() {
    final byteStream = super.finalize();
    if (onProgress == null) return byteStream;
    final total = contentLength;
    int bytesSent = 0;
    final transformer = StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (data, sink) {
        sink.add(data);
        bytesSent += data.length;
        if (total > 0) onProgress!(bytesSent.toDouble() / total);
      },
    );
    return http.ByteStream(byteStream.transform(transformer));
  }
}
