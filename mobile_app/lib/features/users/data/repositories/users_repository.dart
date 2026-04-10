import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:almudeer_mobile_app/core/api/api_client.dart';
import 'package:almudeer_mobile_app/core/api/endpoints.dart';
import 'package:almudeer_mobile_app/core/services/connectivity_service.dart';
import '../models/user.dart';

class UsersRepository {
  final ApiClient _apiClient;
  final ConnectivityService _connectivityService;

  UsersRepository({
    ApiClient? apiClient,
    ConnectivityService? connectivityService,
  }) : _apiClient = apiClient ?? ApiClient(),
       _connectivityService = connectivityService ?? ConnectivityService();

  /// Search for Almudeer users
  /// Returns a list of users matching the search query
  Future<Map<String, dynamic>> searchUsers({
    required String query,
    int limit = 20,
  }) async {
    if (!_connectivityService.isOnline) {
      return {
        'results': [],
        'count': 0,
        'query': query,
        'error': 'No internet connection',
      };
    }

    try {
      final response = await _apiClient.get(
        Endpoints.usersSearch,
        queryParams: {
          'q': query,
          'limit': limit.toString(),
        },
      );

      return response;
    } catch (e) {
      debugPrint('[UsersRepository] Search failed: $e');
      return {
        'results': [],
        'count': 0,
        'query': query,
        'error': e.toString(),
      };
    }
  }

  /// Get current user's profile
  Future<User?> getCurrentUser() async {
    try {
      final response = await _apiClient.get(Endpoints.usersMe);
      return User.fromJson(response);
    } catch (e) {
      debugPrint('[UsersRepository] Get current user failed: $e');
      return null;
    }
  }

  /// Get user by username
  Future<User?> getUserByUsername(String username) async {
    try {
      final response = await _apiClient.get(
        Endpoints.userByUsername(username),
      );
      return User.fromJson(response);
    } catch (e) {
      debugPrint('[UsersRepository] Get user by username failed: $e');
      return null;
    }
  }

  /// Parse search results into User objects
  List<User> parseSearchResults(Map<String, dynamic> response) {
    final List<dynamic>? results = response['results'];
    if (results == null) return [];

    return results
        .map((e) => User.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
