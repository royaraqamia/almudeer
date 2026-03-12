import 'dart:convert';
import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../models/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// Repository for user settings and preferences
/// 
/// Uses SharedPreferences for local storage with graceful error handling.
/// flutter_secure_storage was removed due to platform compatibility issues.
class SettingsRepository {
  final ApiClient _apiClient;
  static const String _preferencesKey = 'user_preferences_cache';

  SettingsRepository({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  ApiClient get apiClient => _apiClient;

  /// Save preferences locally (Full Cache)
  Future<void> savePreferencesLocally(UserPreferences preferences) async {
    try {
      final accountHash = await _apiClient.getAccountCacheHash();
      final prefs = await SharedPreferences.getInstance();
      final storageKey = '${accountHash}_$_preferencesKey';
      final jsonString = jsonEncode(preferences.toJson());
      await prefs.setString(storageKey, jsonString);
    } catch (e) {
      debugPrint('SettingsRepository: Failed to save preferences locally: $e');
    }
  }

  /// Get local preferences (Full Cache)
  Future<UserPreferences?> getLocalPreferences() async {
    try {
      final accountHash = await _apiClient.getAccountCacheHash();
      final prefs = await SharedPreferences.getInstance();
      final storageKey = '${accountHash}_$_preferencesKey';
      final jsonString = prefs.getString(storageKey);

      if (jsonString != null) {
        return UserPreferences.fromJson(jsonDecode(jsonString));
      }
    } catch (e) {
      debugPrint('SettingsRepository: Failed to get local preferences: $e');
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

  /// Get calculator history from dedicated endpoint
  Future<List<Map<String, dynamic>>> getCalculatorHistory() async {
    try {
      final response = await _apiClient.get(Endpoints.calculatorHistory);
      
      if (response.containsKey('history') && response['history'] is List) {
        final List<dynamic> historyList = response['history'];
        return historyList.map((item) {
          if (item is Map<String, dynamic>) {
            return {
              'entry': item['entry'] as String? ?? '',
              'timestamp': item['timestamp'] as String? ?? DateTime.now().toIso8601String(),
            };
          }
          return <String, dynamic>{};
        }).where((item) => item.isNotEmpty).toList();
      }
      return [];
    } catch (e) {
      debugPrint('SettingsRepository: Failed to get calculator history: $e');
      return [];
    }
  }

  /// Update calculator history via dedicated endpoint
  Future<void> updateCalculatorHistory(List<Map<String, dynamic>> history) async {
    try {
      final historyData = history.map((entry) => {
        'entry': entry['entry'] as String,
        'timestamp': entry['timestamp'] as String,
      }).toList();

      await _apiClient.patch(
        Endpoints.calculatorHistory,
        body: {'history': historyData},
      );
    } catch (e) {
      debugPrint('SettingsRepository: Failed to update calculator history: $e');
      rethrow;
    }
  }

  /// Clear calculator history via dedicated endpoint
  Future<void> clearCalculatorHistory() async {
    try {
      await _apiClient.delete(Endpoints.calculatorHistory);
    } catch (e) {
      debugPrint('SettingsRepository: Failed to clear calculator history: $e');
      rethrow;
    }
  }
}
