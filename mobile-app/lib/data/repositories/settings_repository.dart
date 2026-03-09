import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../models/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Repository for user settings and preferences
class SettingsRepository {
  final ApiClient _apiClient;
  static const String _preferencesKey = 'user_preferences_cache';

  // SECURITY: Use hardware-backed encrypted storage for cache
  final _secureStorage = const FlutterSecureStorage();

  SettingsRepository({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  ApiClient get apiClient => _apiClient;

  /// Save preferences locally (Full Cache)
  Future<void> savePreferencesLocally(UserPreferences preferences) async {
    final accountHash = await _apiClient.getAccountCacheHash();
    final jsonString = jsonEncode(preferences.toJson());
    await _secureStorage.write(
      key: '${accountHash}_$_preferencesKey',
      value: jsonString,
    );
  }

  /// Get local preferences (Full Cache)
  Future<UserPreferences?> getLocalPreferences() async {
    try {
      final accountHash = await _apiClient.getAccountCacheHash();
      final storageKey = '${accountHash}_$_preferencesKey';

      String? jsonString = await _secureStorage.read(key: storageKey);

      if (jsonString == null) {
        // SECURITY-MIGRATION: Check legacy SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        jsonString = prefs.getString(storageKey);
        if (jsonString != null) {
          await _secureStorage.write(key: storageKey, value: jsonString);
          await prefs.remove(storageKey);
        }
      }

      if (jsonString != null) {
        return UserPreferences.fromJson(jsonDecode(jsonString));
      }
    } catch (e) {
      // Ignore cache errors
    }
    return null;
  }

  /// Update user preferences
  Future<void> updatePreferences(UserPreferences preferences) async {
    // Save locally first for immediate feedback
    await savePreferencesLocally(preferences);
    // Then sync to server
    await _apiClient.patch(Endpoints.preferences, body: preferences.toJson());
  }

  /// Get current preferences
  Future<UserPreferences> getPreferences() async {
    try {
      final response = await _apiClient.get(Endpoints.preferences);

      // Fix: Unwrap 'preferences' key if present
      final data = response.containsKey('preferences')
          ? response['preferences'] as Map<String, dynamic>
          : response;

      final prefs = UserPreferences.fromJson(data);

      // Sync server state to local cache (Server is Source of Truth)
      await savePreferencesLocally(prefs);

      return prefs;
    } catch (e) {
      // If offline or error, try to fallback to local storage
      final localPrefs = await getLocalPreferences();
      if (localPrefs != null) {
        return localPrefs;
      }
      rethrow;
    }
  }
}
