import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';

class ApiClient {
  static const String _baseUrlKey = 'api_base_url';
  static const String _defaultBaseUrl = 'http://localhost:8000';

  final Logger _logger = Logger();
  http.Client _client = http.Client();
  String? _accessToken;

  String get baseUrl => _baseUrl;
  String _baseUrl = _defaultBaseUrl;

  set accessToken(String? token) {
    _accessToken = token;
  }

  String? get accessToken => _accessToken;

  /// Initialize the API client with stored base URL
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_baseUrlKey) ?? _defaultBaseUrl;
    _logger.i('ApiClient initialized with base URL: $_baseUrl');
  }

  /// Update the base URL and persist it
  Future<void> setBaseUrl(String url) async {
    _baseUrl = url.replaceAll(RegExp(r'/$'), ''); // Remove trailing slash
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, _baseUrl);
    _logger.i('Base URL updated to: $_baseUrl');
  }

  /// Check if the backend is reachable
  Future<bool> checkHealth() async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      _logger.e('Health check failed: $e');
      return false;
    }
  }

  /// Get API version info
  Future<Map<String, dynamic>?> getVersion() async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/api/v1/version'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      _logger.e('Failed to get version: $e');
    }
    return null;
  }

  /// Build URI with base URL
  Uri uri(String path, [Map<String, String>? queryParams]) {
    final uri = Uri.parse('$_baseUrl$path');
    if (queryParams != null && queryParams.isNotEmpty) {
      return uri.replace(queryParameters: {...uri.queryParameters, ...queryParams});
    }
    return uri;
  }

  /// Perform GET request
  Future<http.Response> get(
    String path, {
    Map<String, String>? queryParams,
    Map<String, String>? headers,
  }) async {
    final uri = this.uri(path, queryParams);
    final allHeaders = {..._defaultHeaders, if (headers != null) ...headers};
    _logger.d('GET $uri');
    return _client.get(uri, headers: allHeaders);
  }

  /// Perform POST request
  Future<http.Response> post(
    String path, {
    Map<String, String>? queryParams,
    Map<String, String>? headers,
    dynamic body,
  }) async {
    final uri = this.uri(path, queryParams);
    final allHeaders = {..._defaultHeaders, if (headers != null) ...headers};
    _logger.d('POST $uri');
    return _client.post(
      uri,
      headers: allHeaders,
      body: body != null ? jsonEncode(body) : null,
    );
  }

  /// Perform PUT request
  Future<http.Response> put(
    String path, {
    Map<String, String>? queryParams,
    Map<String, String>? headers,
    dynamic body,
  }) async {
    final uri = this.uri(path, queryParams);
    final allHeaders = {..._defaultHeaders, if (headers != null) ...headers};
    _logger.d('PUT $uri');
    return _client.put(
      uri,
      headers: allHeaders,
      body: body != null ? jsonEncode(body) : null,
    );
  }

  /// Perform PATCH request
  Future<http.Response> patch(
    String path, {
    Map<String, String>? queryParams,
    Map<String, String>? headers,
    dynamic body,
  }) async {
    final uri = this.uri(path, queryParams);
    final allHeaders = {..._defaultHeaders, if (headers != null) ...headers};
    _logger.d('PATCH $uri');
    return _client.patch(
      uri,
      headers: allHeaders,
      body: body != null ? jsonEncode(body) : null,
    );
  }

  /// Perform DELETE request
  Future<http.Response> delete(
    String path, {
    Map<String, String>? queryParams,
    Map<String, String>? headers,
  }) async {
    final uri = this.uri(path, queryParams);
    final allHeaders = {..._defaultHeaders, if (headers != null) ...headers};
    _logger.d('DELETE $uri');
    return _client.delete(uri, headers: allHeaders);
  }

  Map<String, String> get _defaultHeaders {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    return headers;
  }

  /// Dispose the HTTP client
  void dispose() {
    _client.close();
  }
}
