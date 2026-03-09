import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/models/user.dart';
import '../../data/repositories/users_repository.dart';

class UsersProvider extends ChangeNotifier {
  final UsersRepository _repository;

  List<User> _users = [];
  bool _isSearching = false;
  String? _error;
  String _searchQuery = '';
  Timer? _debounceTimer;

  // Getters
  List<User> get users => _users;
  bool get isSearching => _isSearching;
  String? get error => _error;
  String get searchQuery => _searchQuery;

  UsersProvider({
    UsersRepository? repository,
  }) : _repository = repository ?? UsersRepository();

  /// Search users with debounce
  void searchUsers(String query) {
    if (_searchQuery == query) return;
    
    _searchQuery = query;
    notifyListeners();

    // Cancel previous timer
    _debounceTimer?.cancel();

    if (query.isEmpty) {
      _users = [];
      _error = null;
      notifyListeners();
      return;
    }

    // Debounce search by 300ms
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  /// Perform the actual search
  Future<void> _performSearch(String query) async {
    if (_isSearching) return;
    
    _isSearching = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _repository.searchUsers(
        query: query,
        limit: 20,
      );

      if (response['error'] != null) {
        _error = response['error'];
        _users = [];
      } else {
        _users = _repository.parseSearchResults(response);
      }
    } catch (e) {
      _error = e.toString();
      _users = [];
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  /// Clear search results
  void clearSearch() {
    _searchQuery = '';
    _users = [];
    _error = null;
    _debounceTimer?.cancel();
    notifyListeners();
  }

  /// Refresh search with current query
  Future<void> refreshSearch() async {
    if (_searchQuery.isNotEmpty) {
      await _performSearch(_searchQuery);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
