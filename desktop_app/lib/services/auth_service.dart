import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'api_client.dart';

class AuthService {
  final ApiClient _apiClient;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final Logger _logger = Logger();

  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';

  String? _accessToken;
  String? _refreshToken;
  Map<String, dynamic>? _userProfile;

  String? get accessToken => _accessToken;
  String? get refreshTokenValue => _refreshToken;
  Map<String, dynamic>? get userProfile => _userProfile;
  bool get isAuthenticated => _accessToken != null;

  AuthService(this._apiClient);

  /// Initialize auth state from stored tokens
  Future<void> init() async {
    _accessToken = await _storage.read(key: _accessTokenKey);
    _refreshToken = await _storage.read(key: _refreshTokenKey);

    if (_accessToken != null) {
      _apiClient.accessToken = _accessToken;
      // Try to fetch user profile
      await _fetchUserProfile();
    }

    _logger.i(
      'AuthService initialized: ${isAuthenticated ? "authenticated" : "anonymous"}',
    );
  }

  /// Login with credentials
  Future<bool> login({
    required String username,
    required String password,
  }) async {
    try {
      final body = <String, dynamic>{
        'username': username,
        'password': password,
      };

      final response = await _apiClient.post(
        '/api/auth/login',
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await _saveTokens(
          accessToken: data['access_token'] as String,
          refreshToken: data['refresh_token'] as String,
        );
        await _fetchUserProfile();
        _logger.i('Login successful for user: $username');
        return true;
      } else {
        _logger.w('Login failed: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      _logger.e('Login error: $e');
      return false;
    }
  }

  /// Refresh access token
  Future<bool> refreshToken() async {
    if (_refreshToken == null) return false;

    try {
      final response = await _apiClient.post(
        '/api/auth/refresh',
        body: {'refresh_token': _refreshToken},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await _saveTokens(
          accessToken: data['access_token'] as String,
          refreshToken: data['refresh_token'] as String,
        );
        _logger.i('Token refreshed successfully');
        return true;
      } else {
        _logger.w('Token refresh failed: ${response.statusCode}');
        await logout();
        return false;
      }
    } catch (e) {
      _logger.e('Token refresh error: $e');
      await logout();
      return false;
    }
  }

  /// Logout and clear tokens
  Future<void> logout() async {
    // Notify backend if possible
    if (_accessToken != null) {
      try {
        await _apiClient.post('/api/auth/logout');
      } catch (e) {
        _logger.w('Logout notification failed: $e');
      }
    }

    await _clearTokens();
    _userProfile = null;
    _logger.i('Logged out');
  }

  /// Fetch current user profile
  Future<Map<String, dynamic>?> _fetchUserProfile() async {
    if (_accessToken == null) return null;

    try {
      final response = await _apiClient.get('/api/auth/me');
      if (response.statusCode == 200) {
        _userProfile = jsonDecode(response.body) as Map<String, dynamic>;
        return _userProfile;
      } else if (response.statusCode == 401) {
        // Token expired, try to refresh
        if (_refreshToken != null) {
          final refreshed = await refreshToken();
          if (refreshed) {
            return _fetchUserProfile();
          }
        }
      }
    } catch (e) {
      _logger.e('Failed to fetch user profile: $e');
    }
    return null;
  }

  /// Fetch current user profile (public method)
  Future<Map<String, dynamic>?> fetchUserProfile() async {
    return _fetchUserProfile();
  }

  /// Save tokens to secure storage and API client
  Future<void> _saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _apiClient.accessToken = accessToken;
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  /// Clear stored tokens
  Future<void> _clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    _apiClient.accessToken = null;
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }
}
