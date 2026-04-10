/// Browser Sync API service for Al-Mudeer.
///
/// Handles syncing browser history and bookmarks with the backend.
library;

import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../models/browser_history.dart';
import '../models/browser_bookmark.dart';

/// Service for browser sync operations
class BrowserSyncService {
  static final BrowserSyncService _instance = BrowserSyncService._internal();
  factory BrowserSyncService() => _instance;
  BrowserSyncService._internal();

  final ApiClient _api = ApiClient();

  /// Sync browser history to backend
  /// Returns the number of entries synced successfully
  Future<int> syncHistory(List<BrowserHistoryEntry> entries) async {
    if (entries.isEmpty) return 0;

    try {
      // Convert to sync format
      final syncEntries = entries.map((e) => <String, dynamic>{
        'url': e.url,
        'title': e.title,
        'visited_at': e.timestamp.toIso8601String(),
        'device_id': null,
      }).toList();

      // Send to backend - pass the list directly as body
      final response = await _api.post(
        Endpoints.browserHistorySync,
        body: {'entries': syncEntries},
      );

      // Response could be a list or contain a list
      int count = 0;
      if (response is List) {
        count = response.length;
      } else if (response['data'] is List) {
        count = (response['data'] as List).length;
      }
      
      debugPrint('[BrowserSync] Synced $count history entries to backend');
      return count;
    } catch (e) {
      debugPrint('[BrowserSync] Error syncing history: $e');
      return 0;
    }
  }

  /// Get browser history from backend
  /// Returns list of history entries
  Future<List<BrowserHistoryEntry>> getHistory({
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      final dynamic response = await _api.get(
        Endpoints.browserHistory,
        queryParams: {'limit': limit.toString(), 'offset': offset.toString()},
      );

      // Handle both direct list and wrapped response
      List<dynamic>? listData;
      if (response is List) {
        listData = response;
      } else {
        final map = response as Map<String, dynamic>;
        listData = map['data'] as List? ?? map['results'] as List?;
      }

      if (listData == null) {
        debugPrint('[BrowserSync] Unexpected history response format: ${response.runtimeType}');
        return [];
      }

      final entries = <BrowserHistoryEntry>[];
      for (int i = 0; i < listData.length; i++) {
        final item = listData[i] as Map<String, dynamic>;
        entries.add(BrowserHistoryEntry(
          url: item['url'] as String,
          title: (item['title'] as String?) ?? '',
          timestamp: DateTime.parse(item['visited_at'] as String),
        ));
      }

      return entries;
    } catch (e) {
      debugPrint('[BrowserSync] Error getting history: $e');
      return [];
    }
  }

  /// Delete a history entry on backend
  Future<bool> deleteHistoryEntry(int historyId) async {
    try {
      final response = await _api.delete(
        Endpoints.browserHistoryEntry(historyId),
      );

      if (response['success'] == true) {
        debugPrint('[BrowserSync] Deleted history entry $historyId from backend');
        return true;
      } else {
        debugPrint('[BrowserSync] Failed to delete history entry');
        return false;
      }
    } catch (e) {
      debugPrint('[BrowserSync] Error deleting history entry: $e');
      return false;
    }
  }

  /// Clear all history on backend
  Future<bool> clearHistory() async {
    try {
      final response = await _api.post(Endpoints.browserHistoryClear);

      if (response['success'] == true) {
        debugPrint('[BrowserSync] Cleared all history on backend');
        return true;
      } else {
        debugPrint('[BrowserSync] Failed to clear history');
        return false;
      }
    } catch (e) {
      debugPrint('[BrowserSync] Error clearing history: $e');
      return false;
    }
  }

  /// Sync bookmarks to backend
  /// Returns the number of bookmarks synced successfully
  Future<int> syncBookmarks(List<BrowserBookmark> bookmarks) async {
    if (bookmarks.isEmpty) return 0;

    try {
      // Convert to sync format
      final syncEntries = bookmarks.map((b) => <String, dynamic>{
        'url': b.url,
        'title': b.title,
        'folder': 'default',
        'icon': null,
      }).toList();

      // Send to backend
      final response = await _api.post(
        Endpoints.browserBookmarksSync,
        body: {'bookmarks': syncEntries},
      );

      int count = 0;
      if (response is List) {
        count = response.length;
      } else if (response['data'] is List) {
        count = (response['data'] as List).length;
      }
      
      debugPrint('[BrowserSync] Synced $count bookmarks to backend');
      return count;
    } catch (e) {
      debugPrint('[BrowserSync] Error syncing bookmarks: $e');
      return 0;
    }
  }

  /// Get bookmarks from backend
  Future<List<BrowserBookmark>> getBookmarks({String? folder}) async {
    try {
      Map<String, String>? queryParams;
      if (folder != null) {
        queryParams = {'folder': folder};
      }

      final dynamic response = await _api.get(
        Endpoints.browserBookmarks,
        queryParams: queryParams,
      );

      // Handle both direct list and wrapped response
      List<dynamic>? listData;
      if (response is List) {
        listData = response;
      } else {
        final map = response as Map<String, dynamic>;
        listData = map['data'] as List? ?? map['results'] as List?;
      }

      if (listData == null) {
        debugPrint('[BrowserSync] Unexpected bookmarks response format: ${response.runtimeType}');
        return [];
      }

      final bookmarks = <BrowserBookmark>[];
      for (int i = 0; i < listData.length; i++) {
        final item = listData[i] as Map<String, dynamic>;
        bookmarks.add(BrowserBookmark(
          url: item['url'] as String,
          title: item['title'] as String,
          timestamp: DateTime.parse(item['created_at'] as String),
        ));
      }

      return bookmarks;
    } catch (e) {
      debugPrint('[BrowserSync] Error getting bookmarks: $e');
      return [];
    }
  }

  /// Delete a bookmark on backend
  Future<bool> deleteBookmark(int bookmarkId) async {
    try {
      final response = await _api.delete(
        Endpoints.browserBookmark(bookmarkId),
      );

      if (response['success'] == true) {
        debugPrint('[BrowserSync] Deleted bookmark $bookmarkId from backend');
        return true;
      } else {
        debugPrint('[BrowserSync] Failed to delete bookmark');
        return false;
      }
    } catch (e) {
      debugPrint('[BrowserSync] Error deleting bookmark: $e');
      return false;
    }
  }

  /// Clear all bookmarks on backend
  Future<bool> clearBookmarks() async {
    try {
      final response = await _api.post(Endpoints.browserBookmarksClear);

      if (response['success'] == true) {
        debugPrint('[BrowserSync] Cleared all bookmarks on backend');
        return true;
      } else {
        debugPrint('[BrowserSync] Failed to clear bookmarks');
        return false;
      }
    } catch (e) {
      debugPrint('[BrowserSync] Error clearing bookmarks: $e');
      return false;
    }
  }

  /// Get sync metadata
  Future<BrowserSyncMetadata?> getSyncMetadata() async {
    try {
      final response = await _api.get(Endpoints.browserSyncMetadata);
      return BrowserSyncMetadata.fromJson(response);
    } catch (e) {
      debugPrint('[BrowserSync] Error getting sync metadata: $e');
      return null;
    }
  }
}

/// Sync metadata
class BrowserSyncMetadata {
  final DateTime? lastHistorySyncAt;
  final DateTime? lastBookmarkSyncAt;
  final DateTime updatedAt;

  BrowserSyncMetadata({
    this.lastHistorySyncAt,
    this.lastBookmarkSyncAt,
    required this.updatedAt,
  });

  factory BrowserSyncMetadata.fromJson(Map<String, dynamic> json) {
    return BrowserSyncMetadata(
      lastHistorySyncAt: json['last_history_sync_at'] != null
          ? DateTime.parse(json['last_history_sync_at'] as String)
          : null,
      lastBookmarkSyncAt: json['last_bookmark_sync_at'] != null
          ? DateTime.parse(json['last_bookmark_sync_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }
}
