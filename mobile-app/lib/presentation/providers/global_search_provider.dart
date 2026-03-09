import 'package:flutter/foundation.dart';

/// Global search provider to manage search state across all dashboard screens
class GlobalSearchProvider extends ChangeNotifier {
  String _searchQuery = '';
  bool _isSearching = false;
  bool _shouldSearchUsers = false;

  /// Current search query
  String get searchQuery => _searchQuery;

  /// Whether search is currently active
  bool get isSearching => _isSearching;

  /// Whether to search users (when query is short or specifically for users)
  bool get shouldSearchUsers => _shouldSearchUsers;

  /// Start search mode
  void startSearch() {
    _isSearching = true;
    _shouldSearchUsers = false;
    notifyListeners();
  }

  /// Update search query
  void updateQuery(String query) {
    _searchQuery = query;
    // Search users when query is 2+ characters
    _shouldSearchUsers = query.length >= 2;
    notifyListeners();
  }

  /// Clear search and exit search mode
  void clearSearch() {
    _searchQuery = '';
    _isSearching = false;
    _shouldSearchUsers = false;
    notifyListeners();
  }

  /// Exit search mode but keep query (for switching tabs)
  void stopSearch() {
    _isSearching = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _searchQuery = '';
    _isSearching = false;
    _shouldSearchUsers = false;
    super.dispose();
  }
}
