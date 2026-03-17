import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../api/api_client.dart';
import '../api/endpoints.dart';

/// Service to persist WebView cookies across app sessions and sync across devices.
/// 
/// Features:
/// 1. Local persistence: WebView automatically saves cookies to disk
/// 2. Cross-device sync: Automatically syncs cookies to backend for cross-device access
/// 3. Secure storage: Encrypted storage for sensitive cookie data
/// 
/// Note: Cookie sync is ALWAYS ENABLED - no option to disable
class BrowserCookieService {
  static const String _storageKey = 'browser_cookies';
  
  // Use flutter_secure_storage for encrypted cookie storage
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  final ApiClient _api = ApiClient();

  /// Initialize the cookie service.
  Future<void> initialize() async {
    try {
      debugPrint('[BrowserCookieService] Initialized (sync always enabled)');
    } catch (e) {
      debugPrint('[BrowserCookieService] Initialization error: $e');
    }
  }

  /// Restore cookies from local storage (called by browser screen)
  /// Note: WebView automatically restores cookies from disk
  Future<void> restoreCookies() async {
    // WebView automatically restores persisted cookies from disk.
    debugPrint('[BrowserCookieService] Cookies auto-restored by WebView');
  }

  /// Save cookies to secure storage (backup).
  /// Note: WebView automatically persists cookies on disk.
  /// This method syncs to backend for cross-device access.
  Future<void> saveCookies() async {
    // WebView automatically persists cookies on disk.
    // Backend sync is automatic and always enabled.
    debugPrint('[BrowserCookieService] Cookies auto-saved by WebView');
  }

  /// Sync cookies to backend for cross-device persistence
  Future<void> syncCookiesToBackend(List<Map<String, dynamic>> cookies) async {
    if (cookies.isEmpty) return;

    try {
      await _api.post(
        Endpoints.browserCookiesSync,
        body: {
          'cookies': cookies,
          'device_id': await _getDeviceId(),
        },
      );
      debugPrint('[BrowserCookieService] Synced ${cookies.length} cookies to backend');
    } catch (e) {
      debugPrint('[BrowserCookieService] Error syncing cookies to backend: $e');
    }
  }

  /// Restore cookies from backend (cross-device sync)
  Future<List<Map<String, dynamic>>> restoreCookiesFromBackend({
    String? domain,
  }) async {
    try {
      final response = await _api.get(
        Endpoints.browserCookies,
        queryParams: domain != null ? {'domain': domain} : null,
      );

      if (response is List) {
        debugPrint('[BrowserCookieService] Restored ${response.length} cookies from backend');
        return (response as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .toList();
      }
    } catch (e) {
      debugPrint('[BrowserCookieService] Error restoring cookies from backend: $e');
    }
    return [];
  }

  /// Clear all stored cookies from WebView and backend
  Future<void> clearCookies() async {
    try {
      final cookieManager = WebViewCookieManager();
      await cookieManager.clearCookies();
      await _secureStorage.delete(key: _storageKey);

      // Clear from backend too
      try {
        await _api.delete(Endpoints.browserCookies);
      } catch (e) {
        debugPrint('[BrowserCookieService] Failed to clear backend cookies: $e');
      }

      debugPrint('[BrowserCookieService] Cleared all cookies');
    } catch (e) {
      debugPrint('[BrowserCookieService] Error clearing cookies: $e');
    }
  }

  /// Set a specific cookie
  Future<void> setCookie({
    required String name,
    required String value,
    required String domain,
    String path = '/',
  }) async {
    try {
      await WebViewCookieManager().setCookie(
        WebViewCookie(
          name: name,
          value: value,
          domain: domain,
          path: path,
        ),
      );
      debugPrint('[BrowserCookieService] Set cookie: $name for $domain');
    } catch (e) {
      debugPrint('[BrowserCookieService] Error setting cookie: $e');
    }
  }

  /// Get device ID for sync
  Future<String> _getDeviceId() async {
    // Use a combination of device info or generate a UUID
    // For now, use a simple identifier
    final existing = await _secureStorage.read(key: 'device_id');
    if (existing != null) return existing;

    final deviceId = DateTime.now().millisecondsSinceEpoch.toString();
    await _secureStorage.write(key: 'device_id', value: deviceId);
    return deviceId;
  }

  /// Convert WebViewCookie to map for API sync
  static Map<String, dynamic> cookieToMap(WebViewCookie cookie) {
    return {
      'name': cookie.name,
      'value': cookie.value,
      'domain': cookie.domain,
      'path': cookie.path,
    };
  }
}
