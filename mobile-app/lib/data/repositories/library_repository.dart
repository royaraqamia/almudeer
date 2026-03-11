import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../models/library_item.dart';
import '../local/library_database.dart';

/// Max value for 32-bit signed integer - used to distinguish temp IDs from server IDs
const int _maxInt32 = 2147483647;

/// Helper function to check if an ID is a temporary (local) ID
bool _isTempId(int id) => id > _maxInt32;

/// Library Repository - Offline-first architecture
///
/// Fixes applied:
/// - Issue #13: Optimistic delete now marks as pending instead of removing
/// - Issue #14: File uploads now queued for offline scenarios
/// - Issue #16: Error notifications for failed syncs with retry limits
/// - Issue #23: Category mapping standardized to backend expectations
/// - P0-4 FIX: Added dispose handling to prevent sync during disposal
class LibraryRepository {
  final ApiClient _apiClient = ApiClient();
  final LibraryDatabase _db = LibraryDatabase();
  final _syncController = StreamController<void>.broadcast();

  // FIX Issue #2: Mutex lock to prevent concurrent sync operations
  final Lock _syncLock = Lock();
  
  // P0-4 FIX: Track disposal state to prevent operations during/after disposal
  bool _isDisposed = false;

  // P1-7 FIX: Track local versions for conflict detection
  final Map<int, int> _localVersions = {};

  // Issue #16: Track failed sync attempts
  final Map<int, int> _failedSyncAttempts = {};
  static const int maxSyncRetries = 3;

  // FIX: Track sync scheduling to prevent race conditions from multiple rapid calls
  bool _syncScheduled = false;

  ApiClient get apiClient => _apiClient;
  Stream<void> get syncStream => _syncController.stream;

  /// Get items (Offline First strategy)
  /// Returns a stream that emits local data first, then updates with remote data
  /// When skipCacheEmission is true, only emits remote data (useful for category switches)
  Stream<List<LibraryItem>> getItemsStream({
    int? customerId,
    String? category,
    String? searchQuery,
    int page = 1,
    int pageSize = 20,
    bool skipCacheEmission = false,
  }) async* {
    // Get license ID - the API client will handle JWT authentication
    // The backend requires JWT token which is sent automatically by ApiClient
    int? licenseId = await _apiClient.getLicenseId();

    // Debug logging to help diagnose authentication issues
    if (licenseId == null) {
      final licenseKey = await _apiClient.getLicenseKey();
      final accessToken = await _apiClient.getAccessToken();
      debugPrint('[LibraryRepository] licenseId=null, licenseKey=${licenseKey != null ? "${licenseKey.substring(0, 4)}..." : "null"}, accessToken=${accessToken != null ? "present" : "null"}');
      
      // Try one more time with explicit key if we have it
      if (licenseKey != null && licenseKey.isNotEmpty) {
        // We have a license key but no ID - this is OK, use a placeholder
        // The backend will authenticate via JWT token
        licenseId = 0; // Placeholder - backend doesn't actually use this for API calls
        debugPrint('[LibraryRepository] Using placeholder licenseId=0, JWT auth will handle it');
      }
    }

    if (licenseId == null) {
      debugPrint('[LibraryRepository] No license ID or key found - returning empty list');
      yield [];
      return;
    }

    // 1. Emit cached data first (only for the first page)
    // P0-3: Check cache validity before using cached data
    // Skip cache emission when explicitly requested (e.g., category switches to prevent flash of wrong items)
    if (page == 1 && !skipCacheEmission) {
      final isCacheValid = await _db.isCacheValid(licenseKeyId: licenseId, type: category);
      final cachedItems = await _db.getCachedItems(
        licenseKeyId: licenseId,
        type: category,
      );

      if (searchQuery != null && searchQuery.isNotEmpty) {
        yield cachedItems
            .where(
              (item) =>
                  item.title.toLowerCase().contains(searchQuery.toLowerCase()),
            )
            .toList();
      } else {
        yield cachedItems;
      }

      // P0-3: If cache is expired, force refresh from remote
      // Cache exists but is stale - continue to fetch fresh data below
      if (!isCacheValid && cachedItems.isNotEmpty) {
        debugPrint('[LibraryRepository] Cache expired, will refresh from remote');
      }
    }

    try {
      // 2. Fetch remote data
      debugPrint('[LibraryRepository] About to fetch remote items for category=$category');
      final remoteItems = await _fetchRemoteItems(
        customerId: customerId,
        category: category,
        searchQuery: searchQuery,
        page: page,
        pageSize: pageSize,
      );
      debugPrint('[LibraryRepository] Successfully fetched ${remoteItems.length} remote items');

      // 3. Cache remote data (only if not searching, or implement advanced caching logic)
      if (page == 1 && (searchQuery == null || searchQuery.isEmpty)) {
        debugPrint('[LibraryRepository] Caching ${remoteItems.length} items');
        await _db.cacheItems(remoteItems);
        // 4. Emit remote items directly to avoid stale cached data
        // The cache is updated above, but we yield remoteItems to ensure fresh data
        debugPrint('[LibraryRepository] Yielding remote items directly');
        yield remoteItems;
      } else {
        // For search or next pages, yield remote results directly
        yield remoteItems;
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('LibraryRepository: Error fetching remote items: $e');
        print('Stack trace: $stackTrace');
      }
      // Don't rethrow - we already emitted cached data
    }
  }

  Future<List<LibraryItem>> _fetchRemoteItems({
    int? customerId,
    String? category,
    String? searchQuery,
    int page = 1,
    int pageSize = 20,
  }) async {
    final Map<String, String> queryParams = {
      'page': page.toString(),
      'page_size': pageSize.toString(),
    };

    if (customerId != null) {
      queryParams['customer_id'] = customerId.toString();
    }

    // Issue #23: Fixed category mapping to match backend expectations
    // Backend expects plural forms: 'notes', 'files' (see backend/models/library.py)
    if (category != null) {
      String? backendCategory;
      if (category == 'notes' || category == 'note') {
        backendCategory = 'notes';  // Backend filters: type = 'note'
        // FIX: Include content field for notes so we can compare with local changes
        queryParams['include_content'] = 'true';
        debugPrint('[LibraryRepository] Fetching notes with include_content=true, category=$category');
      } else if (category == 'files' || category == 'file') {
        backendCategory = 'files';  // Backend filters: type IN ('image', 'audio', 'video', 'file')
      } else if (category == 'tools') {
        // Tools category - not implemented in backend yet
        // Return empty list to prevent errors
        debugPrint('[LibraryRepository] Tools category not supported by backend, returning empty');
        return [];
      } else {
        // Unknown category - log warning and fetch without category filter
        debugPrint('[LibraryRepository] Unknown category: $category, fetching without filter');
      }

      if (backendCategory != null) {
        queryParams['category'] = backendCategory;
      }
    }
    // Note: Null category is valid for fetching all items

    if (searchQuery != null && searchQuery.isNotEmpty) {
      queryParams['search'] = searchQuery;
    }

    final response = await _apiClient.get(
      Endpoints.libraryItems,
      queryParams: queryParams,
    );

    if (response['success'] == true) {
      final List itemsJson = response['items'] ?? [];
      final firstContent = itemsJson.isNotEmpty 
          ? (itemsJson.first['content'] ?? 'NULL').toString()
          : 'N/A';
      debugPrint('[LibraryRepository] Fetched ${itemsJson.length} items, first item content: ${firstContent.length > 20 ? firstContent.substring(0, 20) : firstContent}...');
      return itemsJson.map((json) => LibraryItem.fromJson(json)).toList();
    } else {
      throw Exception(response['detail'] ?? 'فشل جلب عناصر المكتبة');
    }
  }

  /// Create Note (Optimistic)
  Future<int> createNote({
    required String title,
    required String content,
    int? customerId,
    int? localId,
  }) async {
    final licenseId = await _apiClient.getLicenseId();
    // 1. Create temporary item for UI
    final tempId = localId ?? DateTime.now().millisecondsSinceEpoch;
    final newItem = LibraryItem(
      id: tempId,
      licenseKeyId: licenseId ?? 0,
      type: 'note',
      title: title,
      content: content,
      customerId: customerId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // 2. Add to pending actions FIRST to protect it during sync
    await _db.addPendingAction(
      actionType: 'create',
      itemType: 'note',
      payload: {'title': title, 'content': content, 'customer_id': customerId},
      localId: tempId,
    );

    // 3. Cache immediately (Optimistic UI)
    await _db.cacheItems([newItem], force: true);

    // 4. Trigger Sync (This could be moved to a background service)
    if (kDebugMode) {
      print(
        'LibraryRepository: Note created locally with tempId: $tempId. Triggering sync...',
      );
    }
    syncPendingActions();

    return tempId;
  }

  /// Upload File (Issue #14: Now supports offline queue)
  Future<LibraryItem> uploadFile({
    required String filePath,
    String? title,
    int? customerId,
    void Function(double progress)? onProgress,
  }) async {
    // Issue #14: Check connectivity and queue if offline
    final isConnected = await _checkConnectivity();

    if (!isConnected) {
      // Queue for later upload
      final tempId = DateTime.now().millisecondsSinceEpoch;
      await _db.addPendingAction(
        actionType: 'upload',
        itemType: 'file',
        payload: {
          'file_path': filePath,
          'title': title,
          'customer_id': customerId,
        },
        localId: tempId,
      );

      // Create optimistic item
      final fileName = filePath.split('/').last;
      final tempItem = LibraryItem(
        id: tempId,
        licenseKeyId: 0,
        type: 'file',
        title: title ?? fileName,
        customerId: customerId,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isUploading: true,
        uploadProgress: 0.0,
      );

      await _db.cacheItems([tempItem]);
      syncPendingActions(); // Will retry when online

      throw Exception('تمت إضافة الملف إلى قائمة الانتظار (Offline)');
    }

    // Direct upload when online
    final Map<String, String> fields = {};
    if (title != null) fields['title'] = title;
    if (customerId != null) fields['customer_id'] = customerId.toString();

    final response = await _apiClient.uploadFile(
      Endpoints.libraryUpload,
      filePath: filePath,
      fieldName: 'file',
      fields: fields,
      onProgress: onProgress,
    );

    if (response['success'] == true) {
      final item = LibraryItem.fromJson(response['item']);
      await _db.cacheItems([item]);
      return item;
    } else {
      throw Exception(response['detail'] ?? 'فشل رفع الملف');
    }
  }

  /// Update an item (Optimistic)
  /// P1-7 FIX: Added version tracking for conflict detection
  Future<void> updateItem(
    int itemId, {
    String? title,
    String? content,
    int? customerId,
  }) async {
    // P1-7 FIX: Increment local version for conflict detection
    _localVersions[itemId] = (_localVersions[itemId] ?? 0) + 1;
    
    // 1. Add to pending actions with version info
    await _db.addPendingAction(
      actionType: 'update',
      itemType: 'any',
      payload: {
        'id': itemId,
        'title': title,
        'content': content,
        'customer_id': customerId,
        'local_version': _localVersions[itemId],
      },
    );

    // 2. Update local cache (Optimistic)
    // We update only the changed fields locally immediately
    final Map<String, dynamic> updates = {};
    if (title != null) updates['title'] = title;
    if (content != null) updates['content'] = content;

    if (updates.isNotEmpty) {
      await _db.updateItem(itemId, updates);
    }

    syncPendingActions();
  }

  /// Delete Item (Issue #13: Now marks as pending instead of removing)
  Future<void> deleteItem(int itemId) async {
    // 1. Try to cancel any pending create for this item first
    final cancelledCreates = await _db.removePendingCreateAction(itemId);

    // Only add delete action if we DIDN'T just cancel a creation
    if (cancelledCreates == 0) {
      await _db.addPendingAction(
        actionType: 'delete',
        itemType: 'any',
        payload: {'id': itemId},
      );
    }

    // Issue #13: Mark as pending deletion instead of removing
    // This prevents data loss if sync fails
    await _db.updateItem(itemId, {'is_pending_delete': true});

    syncPendingActions();
  }

  /// Bulk Delete
  Future<void> bulkDelete(List<int> itemIds) async {
    await _db.addPendingAction(
      actionType: 'bulk_delete',
      itemType: 'any',
      payload: {'item_ids': itemIds},
    );

    // Issue #13: Mark as pending deletion instead of removing
    for (var id in itemIds) {
      await _db.updateItem(id, {'is_pending_delete': true});
    }

    syncPendingActions();
  }

  /// Sync Logic (Process Pending Actions)
  /// Issue #16: Added retry limits and error tracking
  /// FIX Issue #2: Added mutex lock to prevent concurrent sync operations
  /// P1-8 FIX: Added comprehensive error logging for debugging
  /// P0-4 FIX: Added disposal check to prevent sync during/after disposal
  /// FIX: Schedule sync to run after frame to prevent UI jank
  Future<void> syncPendingActions() async {
    // Schedule sync to run after current frame to avoid UI jank
    // This prevents "Skipped X frames" errors during heavy sync operations
    scheduleSync();
  }

  /// Schedule sync to run asynchronously
  /// FIX: Prevents race conditions from multiple rapid sync requests
  void scheduleSync() {
    // Prevent multiple sync operations from being scheduled simultaneously
    if (_syncScheduled) {
      if (kDebugMode) {
        print('LibraryRepository: Sync already scheduled, skipping duplicate request');
      }
      return;
    }
    
    _syncScheduled = true;
    // Run sync in next microtask to avoid blocking UI
    // Using Future.delayed to ensure it runs after current frame
    Future.delayed(Duration.zero, () async {
      try {
        await _performSyncInternal();
      } finally {
        // Reset flag after sync completes
        _syncScheduled = false;
      }
    });
  }

  /// Internal sync implementation (called from compute or directly)
  Future<void> _performSyncInternal() async {
    // P0-4 FIX: Check if repository is disposed
    if (_isDisposed) {
      if (kDebugMode) {
        print('LibraryRepository: Skipping sync - repository is disposed');
      }
      return;
    }

    // Use mutex to prevent concurrent sync operations
    await _syncLock.synchronized(() async {
      // P0-4 FIX: Check again inside lock (double-check pattern)
      if (_isDisposed) {
        if (kDebugMode) {
          print('LibraryRepository: Skipping sync - repository disposed during lock acquisition');
        }
        return;
      }

      try {
        final pendingActions = await _db.getPendingActions();
        if (pendingActions.isEmpty) return;

        bool anySucceeded = false;

        for (var action in pendingActions) {
          try {
            final payload = jsonDecode(action['payload']);
            bool success = false;
            final int? localId = action['local_id'];
            final int actionId = action['id'];

            // Issue #16: Check retry limit
            if (_failedSyncAttempts.containsKey(actionId) &&
                _failedSyncAttempts[actionId]! >= maxSyncRetries) {
              if (kDebugMode) {
                print(
                  'Sync skipped: Action $actionId exceeded max retries ($maxSyncRetries)',
                );
              }
              // Notify user (could use a notification service here)
              continue;
            }

          switch (action['action_type']) {
          case 'create':
            if (action['item_type'] == 'note') {
              // 1. Check if local item still exists (wasn't deleted while waiting)
              if (localId != null) {
                final exists = await _db.itemExists(localId);
                if (!exists) {
                  // Item deleted locally. Skip creation.
                  success = true; // Mark as handled to remove action
                  break;
                }
              }

              final response = await _apiClient.post(
                Endpoints.libraryNote,
                body: payload,
              );
              if (response['success'] == true && response['item'] != null) {
                // Double check existence before caching (race condition during network call)
                if (localId != null) {
                  final exists = await _db.itemExists(localId);
                  if (!exists) {
                    // Item deleted during network call. Discard result.
                    success = true;
                    break;
                  }
                }

                // Replace temp item with real item in cache
                final realItem = LibraryItem.fromJson(response['item']);
                if (kDebugMode) {
                  print(
                    'LibraryRepository: Sync SUCCESS for note creation. Real ID: ${realItem.id}, Local ID: $localId',
                  );
                }
                await _db.cacheItems([realItem]);

                // Remove the temporary local item if we had one
                if (localId != null) {
                  await _db.deleteItem(localId);
                  
                  // FIX: Update any pending update actions to use the real server ID
                  // This prevents "ITEM_NOT_FOUND" errors when update actions reference
                  // a temp ID that no longer exists after successful creation
                  await _updatePendingActionsForTempId(localId, realItem.id);
                }
                success = true;
                anySucceeded = true;
                // Issue #16: Clear failure count on success
                _failedSyncAttempts.remove(actionId);
              }
            }
            break;

          case 'upload':
            // Issue #14: Handle queued file uploads
            final filePath = payload['file_path'] as String?;
            if (filePath != null && await File(filePath).exists()) {
              try {
                final fields = <String, String>{};
                if (payload['title'] != null) {
                  fields['title'] = payload['title'];
                }
                if (payload['customer_id'] != null) {
                  fields['customer_id'] = payload['customer_id'].toString();
                }

                final response = await _apiClient.uploadFile(
                  Endpoints.libraryUpload,
                  filePath: filePath,
                  fieldName: 'file',
                  fields: fields,
                );

                if (response['success'] == true) {
                  final item = LibraryItem.fromJson(response['item']);
                  await _db.cacheItems([item]);

                  // Remove temp item if exists
                  if (localId != null) {
                    await _db.deleteItem(localId);
                    
                    // FIX: Update any pending update actions to use the real server ID
                    await _updatePendingActionsForTempId(localId, item.id);
                  }
                  success = true;
                  anySucceeded = true;
                  _failedSyncAttempts.remove(actionId);
                }
              } catch (e) {
                if (kDebugMode) {
                  print('Upload failed for action $actionId: $e');
                }
              }
            } else {
              // File no longer exists, skip
              success = true;
            }
            break;

          case 'delete':
            final id = payload['id'] as int;
            // If ID is temporary (large range), don't send to server
            if (_isTempId(id)) {
              await _db.deleteItem(id);
              success = true; // Treated as success locally
            } else {
              try {
                final response = await _apiClient.delete(
                  Endpoints.libraryItem(id),
                );
                success = response['success'] == true;
                if (success) {
                  // Issue #13: Now safe to remove after successful sync
                  await _db.deleteItem(id);
                  anySucceeded = true;
                  _failedSyncAttempts.remove(actionId);
                }
              } on ItemNotFoundException catch (e) {
                // Item already doesn't exist on server - treat as success
                if (kDebugMode) {
                  print('LibraryRepository: Item $id already deleted on server: $e');
                }
                await _clearOrphanedPendingAction(actionId, id);
                success = true;
                anySucceeded = true;
              }
            }
            break;

          case 'update':
            final id = payload['id'] as int;
            final localVersion = payload['local_version'] as int?;

            if (_isTempId(id)) {
              // Temp item - check if there's a pending create action for this ID
              final list = await _db.getPendingActions();
              bool foundCreate = false;
              
              for (var a in list) {
                if (a['action_type'] == 'create' && a['local_id'] == id) {
                  // Merge this update into the pending create action
                  final newPayload = jsonDecode(a['payload']);
                  if (payload['title'] != null) {
                    newPayload['title'] = payload['title'];
                  }
                  if (payload['content'] != null) {
                    newPayload['content'] = payload['content'];
                  }
                  if (payload['customer_id'] != null) {
                    newPayload['customer_id'] = payload['customer_id'];
                  }
                  
                  await _db.removePendingAction(a['id']);
                  await _db.addPendingAction(
                    actionType: 'create',
                    itemType: 'note',
                    payload: newPayload,
                    localId: id,
                  );
                  success = true;
                  foundCreate = true;
                  if (kDebugMode) {
                    print('LibraryRepository: Merged update into pending create for temp ID $id');
                  }
                  break;
                }
              }
              
              if (!foundCreate) {
                // Create action already processed - this update should have been updated by _updatePendingActionsForTempId
                // If we reach here, something went wrong. Clear this orphaned action.
                if (kDebugMode) {
                  print('LibraryRepository: Update for temp ID $id found no pending create - clearing orphaned action');
                }
                success = true; // Mark as success to remove the stale action
                await _db.removePendingAction(actionId);
              }
            } else {
              // P1-7 FIX: Check for conflict with server version
              // First fetch current server version
              int? serverVersion;
              try {
                final currentItem = await _apiClient.get(Endpoints.libraryItem(id));
                if (currentItem['success'] == true && currentItem['item'] != null) {
                  serverVersion = currentItem['item']['version'] as int?;
                }
              } on ItemNotFoundException catch (e) {
                // Item doesn't exist on server - clear stale pending actions
                if (kDebugMode) {
                  print('LibraryRepository: Item $id not found on server - clearing stale pending actions: $e');
                }
                // Mark as success to remove the pending action (item was deleted or never created)
                success = true;
                await _clearOrphanedPendingAction(actionId, id);
                break;
              } catch (e) {
                // If we can't fetch, proceed with update (offline-first)
                if (kDebugMode) {
                  print('LibraryRepository: Could not fetch current version for item $id: $e');
                }
              }

              // P1-7 FIX: Compare versions - if server version is newer, notify conflict
              if (serverVersion != null && localVersion != null && serverVersion > localVersion) {
                if (kDebugMode) {
                  print('LibraryRepository: CONFLICT detected for item $id. '
                      'Server version: $serverVersion, Local version: $localVersion');
                }
                // Conflict resolution UI - Future implementation
                // When re-implementing, you would:
                // 1. Create a ConflictResolutionService
                // 2. Show dialog with both versions (local vs server)
                // 3. Let user choose: keep local, use server, or merge
                // 4. For now, using LWW (Last Write Wins) - proceed with local version
              }

              // Create a copy of payload without the ID
              final apiPayload = Map<String, dynamic>.from(payload)
                ..remove('id')
                ..remove('local_version'); // Don't send internal version to server

              try {
                final response = await _apiClient.patch(
                  Endpoints.libraryItem(id),
                  body: apiPayload,
                );
                success = response['success'] == true;
                if (success) {
                  anySucceeded = true;
                  _failedSyncAttempts.remove(actionId);
                  // P1-7 FIX: Update local version on successful sync
                  _localVersions[id] = serverVersion != null ? serverVersion + 1 : (localVersion ?? 1);
                }
              } on ItemNotFoundException catch (e) {
                // Item doesn't exist on server - clear stale pending actions
                if (kDebugMode) {
                  print('LibraryRepository: Item $id not found during update - clearing stale action: $e');
                }
                // Mark as success to remove the pending action
                success = true;
                await _clearOrphanedPendingAction(actionId, id);
              }
            }
            break;

          case 'bulk_delete':
            final itemsIds = List<int>.from(payload['item_ids']);
            final realIds = <int>[];
            final tempIds = <int>[];

            // Separate real and temp IDs
            for (var id in itemsIds) {
              if (_isTempId(id)) {
                tempIds.add(id);
              } else {
                realIds.add(id);
              }
            }

            // Clean up temp IDs locally immediately
            for (var id in tempIds) {
              await _db.deleteItem(id);
            }

            if (realIds.isNotEmpty) {
              try {
                final response = await _apiClient.post(
                  Endpoints.libraryBulkDelete,
                  body: {'item_ids': realIds},
                );
                success = response['success'] == true;
                if (success) {
                  // Remove verified real IDs from cache
                  for (var id in realIds) {
                    await _db.deleteItem(id);
                  }
                  anySucceeded = true;
                  _failedSyncAttempts.remove(actionId);
                }
              } on ItemNotFoundException catch (e) {
                // Some items don't exist - remove the ones that do exist
                if (kDebugMode) {
                  print('LibraryRepository: Bulk delete partial failure: $e');
                }
                // Still remove all IDs from local cache (they're either deleted or never existed)
                for (var id in realIds) {
                  await _db.deleteItem(id);
                }
                success = true;
                anySucceeded = true;
              }
            } else {
              // If only temp IDs, we are done
              success = true;
              anySucceeded = true;
            }
            break;
        }

        if (success) {
          await _db.removePendingAction(action['id']);
          // Issue #16: Clear failure count on success
          _failedSyncAttempts.remove(action['id']);
        } else {
          // Issue #16: Track failure count
          _failedSyncAttempts[action['id']] =
              (_failedSyncAttempts[action['id']] ?? 0) + 1;
        }
      } catch (e) {
        // Issue #16: Track failure count
        _failedSyncAttempts[action['id']] =
            (_failedSyncAttempts[action['id']] ?? 0) + 1;

        if (kDebugMode) {
          print(
            'Sync failed for action ${action['id']} (${action['action_type']}): $e',
          );
          print('Payload: ${action['payload']}');

          // Issue #16: Notify if approaching retry limit
          final attempts = _failedSyncAttempts[action['id']] ?? 0;
          if (attempts >= maxSyncRetries - 1) {
            print(
              'WARNING: Action ${action['id']} is about to exceed max retries',
            );
          }
        }
        // Keep in queue to retry later
      }
    }

    if (anySucceeded) {
      _syncController.add(null);
    }
  } catch (e, stackTrace) {
    // P1-8 FIX: Log sync errors with stack trace for debugging
    debugPrint('[LibraryRepository] Sync error: $e');
    debugPrint('Stack trace: $stackTrace');
  } finally {
    // P1-8 FIX: Ensure lock is always released
    debugPrint('[LibraryRepository] Sync lock released');
  }
}); // End of mutex lock
}

  /// Issue #14: Check connectivity helper
  Future<bool> _checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }

  /// Get total storage usage
  Future<int> getStorageUsage() async {
    try {
      // FIX: Use the correct endpoint for storage statistics
      final response = await _apiClient.get(Endpoints.libraryUsageStats);
      if (response['success'] == true) {
        return response['statistics']?['storage']?['total_bytes'] ?? 0;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  /// FIX Issue #14: Check storage quota before upload
  /// Returns true if there's enough space, false otherwise
  Future<bool> hasEnoughStorage(int fileSizeBytes) async {
    try {
      // FIX: Use the correct endpoint for storage statistics
      final response = await _apiClient.get(Endpoints.libraryUsageStats);
      if (response['success'] == true) {
        final storage = response['statistics']?['storage'];
        final storageUsage = storage?['total_bytes'] ?? 0;
        final storageLimit = storage?['limit_bytes'] ?? (100 * 1024 * 1024); // 100MB default
        final remaining = storageLimit - storageUsage;
        return remaining >= fileSizeBytes;
      }
      // If we can't check, allow the upload to proceed
      return true;
    } catch (e) {
      // If we can't check, allow the upload to proceed
      return true;
    }
  }

  /// Get detailed storage information
  Future<Map<String, int>> getStorageDetails() async {
    try {
      // FIX: Use the correct endpoint for storage statistics
      final response = await _apiClient.get(Endpoints.libraryUsageStats);
      if (response['success'] == true) {
        final storage = response['statistics']?['storage'] ?? {};
        final used = storage['total_bytes'] ?? 0;
        final limit = storage['limit_bytes'] ?? (100 * 1024 * 1024);
        return {
          'used': used,
          'limit': limit,
          'remaining': limit - used,
        };
      }
      return {'used': 0, 'limit': 100 * 1024 * 1024, 'remaining': 100 * 1024 * 1024};
    } catch (e) {
      return {'used': 0, 'limit': 100 * 1024 * 1024, 'remaining': 100 * 1024 * 1024};
    }
  }

  /// FIX Issue #20: Export library items to JSON backup
  Future<Map<String, dynamic>> exportLibraryItems({String? category}) async {
    try {
      final licenseId = await _apiClient.getLicenseId();
      if (licenseId == null) {
        throw Exception('No license ID found');
      }

      // Get all items (may need pagination for large libraries)
      final items = await _db.getCachedItems(licenseKeyId: licenseId, type: category);
      
      final exportData = {
        'exported_at': DateTime.now().toIso8601String(),
        'license_id': licenseId,
        'total_items': items.length,
        'items': items.map((item) => item.toJson()).toList(),
      };

      return exportData;
    } catch (e) {
      throw Exception('Failed to export library: $e');
    }
  }

  /// FIX Issue #20: Import library items from JSON backup
  Future<int> importLibraryItems(Map<String, dynamic> importData) async {
    try {
      final itemsJson = importData['items'] as List?;
      if (itemsJson == null) {
        throw Exception('Invalid import data: no items found');
      }

      int importedCount = 0;
      for (final itemJson in itemsJson) {
        // Create note or file from imported data
        final item = LibraryItem.fromJson(itemJson);
        
        if (item.type == 'note') {
          await createNote(
            title: item.title,
            content: item.content ?? '',
            customerId: item.customerId,
          );
        }
        // For files, we would need the actual file data
        // This is a simplified version - full implementation would handle file uploads
        
        importedCount++;
      }

      return importedCount;
    } catch (e) {
      throw Exception('Failed to import library: $e');
    }
  }

  /// FIX Issue #20: Save export to file
  Future<String?> saveExportToFile(Map<String, dynamic> exportData, String filename) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$filename');

      final jsonString = JsonEncoder.withIndent('  ').convert(exportData);
      await file.writeAsString(jsonString);

      return file.path;
    } catch (e) {
      debugPrint('Failed to save export: $e');
      return null;
    }
  }

  /// P3-14: Share a library item with another user
  Future<Map<String, dynamic>> shareItem({
    required int itemId,
    required String sharedWithUserId,
    String permission = 'read',
    int? expiresInDays,
  }) async {
    final response = await _apiClient.post(
      '/api/library/$itemId/share',
      body: {
        'shared_with_user_id': sharedWithUserId,
        'permission': permission,
        'expires_in_days': expiresInDays,
      },
    );
    
    if (response['success'] == true) {
      return response;
    } else {
      throw Exception(response['detail']?['message_ar'] ?? 'فشل مشاركة العنصر');
    }
  }

  /// P3-14: Get items shared with the current user
  Future<List<LibraryItem>> getSharedWithMe({String? permission}) async {
    final queryParams = <String, String>{
      't': DateTime.now().millisecondsSinceEpoch.toString(), // Cache buster
    };
    if (permission != null) {
      queryParams['permission'] = permission;
    }

    final response = await _apiClient.get(
      '/api/library/shared-with-me',
      queryParams: queryParams,
    );

    debugPrint('[LibraryRepository] getSharedWithMe response: $response');

    if (response['success'] == true) {
      final List itemsJson = response['items'] ?? [];
      return itemsJson.map((json) => LibraryItem.fromJson(json)).toList();
    } else {
      debugPrint('[LibraryRepository] getSharedWithMe failed: detail=${response['detail']}');
      throw Exception(response['detail']?['message_ar'] ?? response['detail']?['message'] ?? 'فشل جلب العناصر المشتركة');
    }
  }

  /// P3-14: List shares for a specific item (owner only)
  Future<List<Map<String, dynamic>>> listItemShares(int itemId) async {
    final response = await _apiClient.get('/api/library/$itemId/shares');
    
    if (response['success'] == true) {
      final List sharesJson = response['shares'] ?? [];
      return sharesJson.map((json) => Map<String, dynamic>.from(json)).toList();
    } else {
      throw Exception(response['detail']?['message_ar'] ?? 'فشل جلب المشاركات');
    }
  }

  /// P3-14: Remove a share (revoke access)
  Future<void> removeShare(int shareId) async {
    final response = await _apiClient.delete('/api/library/shares/$shareId');
    
    if (response['success'] != true) {
      throw Exception(response['detail']?['message_ar'] ?? 'فشل إزالة المشاركة');
    }
  }

  /// P3-14: Update share permission
  Future<void> updateSharePermission({
    required int shareId,
    required String permission,
  }) async {
    final response = await _apiClient.patch(
      '/api/library/shares/$shareId/permission',
      body: {'permission': permission},
    );
    
    if (response['success'] != true) {
      throw Exception(response['detail']?['message_ar'] ?? 'فشل تحديث الصلاحية');
    }
  }

  /// P3-1/Nearby: Pair with another device
  Future<Map<String, dynamic>> pairDevice({
    required String deviceId,
    required String deviceName,
    String? pairingCode,
  }) async {
    final response = await _apiClient.post(
      '/api/devices/pair',
      body: {
        'device_id': deviceId,
        'device_name': deviceName,
        'pairing_code': pairingCode,
      },
    );
    
    if (response['success'] == true) {
      return response;
    } else {
      throw Exception(response['detail']?['message_ar'] ?? 'فشل اقتران الجهاز');
    }
  }

  /// P3-1/Nearby: List paired devices
  Future<List<Map<String, dynamic>>> listPairedDevices() async {
    final response = await _apiClient.get('/api/devices/paired');
    
    if (response['success'] == true) {
      final List devicesJson = response['devices'] ?? [];
      return devicesJson.map((json) => Map<String, dynamic>.from(json)).toList();
    } else {
      throw Exception(response['detail']?['message_ar'] ?? 'فشل جلب الأجهزة المقترنة');
    }
  }

  /// P3-1/Nearby: Unpair a device
  Future<void> unpairDevice(int pairingId) async {
    final response = await _apiClient.delete('/api/devices/unpair/$pairingId');
    
    if (response['success'] != true) {
      throw Exception(response['detail']?['message_ar'] ?? 'فشل إلغاء الاقتران');
    }
  }

  /// P3-1/Nearby: Record device connection
  Future<void> recordDeviceConnection(int pairingId) async {
    await _apiClient.post('/api/devices/paired/$pairingId/connect');
  }

  /// Clear orphaned pending actions for items that don't exist on the server
  /// This is called when ITEM_NOT_FOUND is received to prevent infinite retry loops
  /// P0-5 FIX: Prevents stale sync actions from blocking the queue
  Future<void> _clearOrphanedPendingAction(int actionId, int itemId) async {
    if (kDebugMode) {
      print('LibraryRepository: Clearing orphaned pending action $actionId for item $itemId');
    }
    await _db.removePendingAction(actionId);
    // Also remove from local cache if it exists
    await _db.deleteItem(itemId);
    _failedSyncAttempts.remove(actionId);
  }

  /// FIX: Update pending update actions that reference a temp ID to use the real server ID
  /// This is called after a successful create sync to prevent "ITEM_NOT_FOUND" errors
  /// when update actions reference a temp ID that no longer exists
  Future<void> _updatePendingActionsForTempId(int tempId, int realId) async {
    final pendingActions = await _db.getPendingActions();
    
    for (var action in pendingActions) {
      if (action['action_type'] == 'update') {
        final payload = jsonDecode(action['payload'] as String);
        final id = payload['id'] as int?;
        
        if (id == tempId) {
          // Update the payload with the real server ID
          payload['id'] = realId;
          await _db.removePendingAction(action['id']);
          await _db.addPendingAction(
            actionType: 'update',
            itemType: 'any',
            payload: payload,
          );
          if (kDebugMode) {
            print('LibraryRepository: Updated pending update action from temp ID $tempId to real ID $realId');
          }
        }
      }
    }
  }

  /// P0-4 FIX: Proper dispose handling to prevent sync during disposal
  void dispose() {
    _isDisposed = true;
    _syncController.close();
    // Note: Don't close _db here as it may be used by other repositories
    // The database is a singleton and should be closed only on app termination
  }

  /// P0-4 FIX: Check if repository is disposed
  bool get isDisposed => _isDisposed;

  // Issue #26: Trash functionality
  Future<List<LibraryItem>> getTrashItems() async {
    try {
      int? licenseId = await _apiClient.getLicenseId();
      if (licenseId == null) {
        final licenseKey = await _apiClient.getLicenseKey();
        if (licenseKey != null && licenseKey.isNotEmpty) {
          licenseId = 0;
        }
      }
      if (licenseId == null) {
        return [];
      }

      final response = await _apiClient.get(
        '${Endpoints.libraryItems}trash',
      );

      if (response['success'] == true) {
        final List itemsJson = response['items'] ?? [];
        final items = itemsJson
            .map((json) => LibraryItem.fromJson(json))
            .toList();
        return items;
      }
      return [];
    } catch (e) {
      debugPrint('[LibraryRepository] Failed to get trash items: $e');
      rethrow;
    }
  }

  Future<void> restoreFromTrash(int itemId) async {
    try {
      final response = await _apiClient.post(
        '${Endpoints.libraryItems}$itemId/restore',
      );

      if (response['success'] != true) {
        throw Exception(response['detail']?['message_ar'] ?? 'فشل الاستعادة من سلة المهملات');
      }
    } catch (e) {
      debugPrint('[LibraryRepository] Failed to restore from trash: $e');
      rethrow;
    }
  }

  Future<void> deletePermanently(int itemId) async {
    try {
      final response = await _apiClient.delete(
        '${Endpoints.libraryItems}$itemId',
      );

      if (response['success'] != true) {
        throw Exception(response['detail']?['message_ar'] ?? 'فشل الحذف النهائي');
      }
    } catch (e) {
      debugPrint('[LibraryRepository] Failed to delete permanently: $e');
      rethrow;
    }
  }

  Future<void> emptyTrash() async {
    try {
      final response = await _apiClient.delete(
        '${Endpoints.libraryItems}trash/empty',
      );

      if (response['success'] != true) {
        throw Exception(response['detail']?['message_ar'] ?? 'فشل إفراغ سلة المهملات');
      }
    } catch (e) {
      debugPrint('[LibraryRepository] Failed to empty trash: $e');
      rethrow;
    }
  }

  // P3-13: Version history functionality
  Future<List<Map<String, dynamic>>> getItemVersions(int itemId) async {
    try {
      final response = await _apiClient.get(
        '${Endpoints.libraryItems}$itemId/versions',
      );

      if (response['success'] == true) {
        final List versionsJson = response['versions'] ?? [];
        return versionsJson.map((json) => Map<String, dynamic>.from(json)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('[LibraryRepository] Failed to get item versions: $e');
      rethrow;
    }
  }

  Future<void> restoreVersion(int itemId, int versionId) async {
    try {
      final response = await _apiClient.post(
        '${Endpoints.libraryItems}$itemId/versions/$versionId/restore',
      );

      if (response['success'] != true) {
        throw Exception(response['detail']?['message_ar'] ?? 'فشل استعادة الإصدار');
      }
    } catch (e) {
      debugPrint('[LibraryRepository] Failed to restore version: $e');
      rethrow;
    }
  }
}
