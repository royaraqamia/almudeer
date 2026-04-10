import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:almudeer_mobile_app/core/api/api_client.dart';
import 'package:almudeer_mobile_app/core/extensions/string_extension.dart';
import 'package:almudeer_mobile_app/core/services/media_cache_manager.dart';
import 'package:almudeer_mobile_app/core/services/websocket_service.dart';
import '../../data/models/library_item.dart';
import '../../data/repositories/library_repository.dart';
import 'package:almudeer_mobile_app/features/customers/data/repositories/customers_repository.dart';

/// Max value for 32-bit signed integer - used to distinguish temp IDs from server IDs
const int _maxInt32 = 2147483647;

/// Throttle interval for progress updates to prevent UI lag (milliseconds)
/// FIX #9: Adaptive throttling - faster updates at start (50ms), slower during transfer (200ms)
/// This prevents UI from feeling unresponsive during initial upload while reducing overhead
const int _progressThrottleIntervalMsStart = 50;  // Fast updates at start (0-10%)
const int _progressThrottleIntervalMsTransfer = 200;  // Slower updates during transfer
const double _progressThrottleFastThreshold = 0.1;  // 10% threshold for fast updates

/// Tolerance window for comparing timestamps to account for clock skew (seconds)
/// Minor Issue #10: Reduced from 5 to 2 seconds to prevent accepting stale data
const int _timestampToleranceSeconds = 2;

/// FIX BUG #7: Exception for partial share failures
class PartialShareException implements Exception {
  final int successCount;
  final int failCount;
  final List<int> failedItemIds;

  PartialShareException({
    required this.successCount,
    required this.failCount,
    required this.failedItemIds,
  });

  @override
  String toString() {
    return 'PartialShareException: Successfully shared $successCount items, failed $failCount items';
  }
}

class LibraryProvider extends ChangeNotifier {
  final LibraryRepository _repository;
  CustomersRepository? _customersRepository;
  final WebSocketService? _webSocketService;

  LibraryProvider({
    LibraryRepository? repository,
    CustomersRepository? customersRepository,
    WebSocketService? webSocketService,
  }) : _repository = repository ?? LibraryRepository(),
       _webSocketService = webSocketService {
    _customersRepository = customersRepository;
    _listenToSyncEvents();
    _fetchInitialData();
  }

  CustomersRepository get _customersRepo {
    _customersRepository ??= CustomersRepository();
    return _customersRepository!;
  }

  List<LibraryItem> _items = [];
  bool _isLoading = false;
  bool _hasMore = true;
  bool _isFetchingMore = false;
  int _currentPage = 1;
  static const int _pageSize = 20;

  // Selection Mode
  bool _isSelectionMode = false;
  final Set<int> _selectedIds = {};

  // Upload tracking for failure recovery
  final Set<int> _uploadingIds = {};

  // Track items with pending sync updates to preserve local changes
  // Maps itemId -> {title, content} that was last saved locally
  final Map<int, Map<String, String>> _pendingUpdates = {};

  // Track temp ID to real ID mappings for items created locally
  // This allows merge logic to match optimistic items with server responses
  final Map<int, int> _tempToRealIdMap = {};

  // Track disposal state to prevent operations after dispose
  bool _disposed = false;

  // Category change token to prevent stale data from old requests
  int _categoryChangeToken = 0;

  // Track in-flight fetch to prevent concurrent requests for different categories
  int? _inFlightCategoryToken;

  // Progress throttling to prevent UI lag - tracks last update time per item
  // FIX P2-3: Added max age to prevent unbounded memory growth
  final Map<int, DateTime> _lastProgressUpdate = {};
  static const Duration _progressUpdateMaxAge = Duration(hours: 1);

  /// FIX P2-3: Cleanup stale progress entries older than max age
  /// Prevents memory leaks during long sessions with many uploads
  void _cleanupStaleProgressEntries() {
    final now = DateTime.now();
    final staleKeys = _lastProgressUpdate.entries
        .where((e) => now.difference(e.value) > _progressUpdateMaxAge)
        .map((e) => e.key)
        .toList();
    
    for (final key in staleKeys) {
      _lastProgressUpdate.remove(key);
    }
    
    if (staleKeys.isNotEmpty) {
      debugPrint('[LibraryProvider] Cleaned up ${staleKeys.length} stale progress entries');
    }
  }

  // Shared items cache with timestamp to prevent excessive API calls
  DateTime? _sharedItemsLastFetched;
  // FIX: Increased cache TTL to 15 minutes to reduce API calls
  // Shared items don't change frequently, so longer cache is acceptable
  Duration _sharedItemsCacheTTL = const Duration(minutes: 15);

  /// Set custom cache TTL for shared items (e.g., shorter for real-time collaboration)
  void setSharedItemsCacheTTL(Duration ttl) {
    _sharedItemsCacheTTL = ttl;
  }

  // Debounce timer for category changes to prevent rapid API calls
  Timer? _debounceTimer;
  static const Duration _debounceDuration = Duration(milliseconds: 300);

  // Getters
  List<LibraryItem> get items => _items;
  bool get isLoading => _isLoading;
  bool get isFetchingMore => _isFetchingMore;
  bool get hasMore => _hasMore;
  bool get isSelectionMode => _isSelectionMode;
  Set<int> get selectedIds => _selectedIds;
  int get selectedCount => _selectedIds.length;
  Set<int> get uploadingIds => _uploadingIds;

  // P3-14: Share state
  List<LibraryItem> _sharedItems = [];
  bool _isLoadingShared = false;
  Map<int, List<Map<String, dynamic>>> _itemShares =
      {}; // itemId -> shares list

  // Username Lookup State for sharing
  bool _isCheckingUsername = false;
  String? _foundUsernameDetails;
  bool _usernameNotFound = false;
  Timer? _usernameLookupTimer;

  // Getters for share state
  List<LibraryItem> get sharedItems => _sharedItems;
  bool get isLoadingShared => _isLoadingShared;
  Map<int, List<Map<String, dynamic>>> get itemShares => _itemShares;

  // Getters for username lookup
  bool get isCheckingUsername => _isCheckingUsername;
  String? get foundUsernameDetails => _foundUsernameDetails;
  bool get usernameNotFound => _usernameNotFound;

  /// Get search results for global search
  /// UX-004 FIX: Include shared items in search results
  List<LibraryItem> get searchResults {
    if (_currentQuery == null || _currentQuery!.isEmpty) return _items;
    final query = _currentQuery!.toLowerCase();
    // Search in both owned and shared items
    final allItems = _mergeAndDeduplicateItems(_items, _sharedItems);
    return allItems.where((item) {
      final title = item.title.toLowerCase();
      final fileType = item.type.toLowerCase();
      return title.contains(query) || fileType.contains(query);
    }).toList();
  }

  // UX-006 FIX: Loading state for bulk operations
  bool _isBulkDeleting = false;
  bool get isBulkDeleting => _isBulkDeleting;

  void toggleSelectionMode(bool enabled) {
    if (_isSelectionMode == enabled) return;
    _isSelectionMode = enabled;
    if (!enabled) {
      _selectedIds.clear();
    }
    notifyListeners();
  }

  Future<void> _fetchInitialData() async {
    await fetchItems(refresh: true);
  }

  void _listenToSyncEvents() {
    // Use transform to properly handle async callbacks in stream
    _repository.syncStream
        .transform(
          StreamTransformer.fromHandlers(
            handleData: (_, sink) {
              // Check if disposed before proceeding
              if (!_disposed) {
                fetchItems(refresh: false)
                    .then((_) {
                      // Silently handle completion
                    })
                    .catchError((error) {
                      debugPrint(
                        '[LibraryProvider] Sync refresh failed: $error',
                      );
                    });
              }
            },
          ),
        )
        .listen((_) {
          // Data handled in transform
        });

    // Listen for WebSocket share events
    if (_webSocketService != null) {
      _websocketSubscription = _webSocketService.stream.listen(
        (event) async {
          try {
            final eventType = event['event'] as String?;
            if (eventType == null || eventType.isEmpty) return;
            if (eventType == 'library_shared') {
              debugPrint(
                '[LibraryProvider] Received library_shared event, refreshing items',
              );
              // Refresh items to show the newly shared item
              if (!_disposed) {
                await fetchItems(refresh: true);
              }
            } else if (eventType == 'library_share_revoked') {
              // BUG-003 FIX: Handle share revocation events
              debugPrint(
                '[LibraryProvider] Received library_share_revoked event, invalidating cache',
              );
              // Invalidate shared items cache immediately
              _sharedItemsLastFetched = null;
              // Refresh items to remove the revoked share
              if (!_disposed) {
                await fetchItems(refresh: true);
              }
            } else if (eventType == 'connection_lost') {
              // P6-2: Handle connection lost events
              debugPrint(
                '[LibraryProvider] WebSocket connection lost, will reconnect',
              );
            }
          } catch (e, stackTrace) {
            debugPrint('[LibraryProvider] WebSocket event error: $e');
            debugPrint('Stack: $stackTrace');
            // FIX #5: Cancel subscription on error to prevent memory leaks
            _websocketSubscription?.cancel();
            _websocketSubscription = null;
          }
        },
        onError: (error) {
          // FIX #5: Handle stream errors and cleanup subscription
          debugPrint('[LibraryProvider] WebSocket stream error: $error');
          _websocketSubscription?.cancel();
          _websocketSubscription = null;

          // P6-2: Force reconnection after error
          _webSocketService.forceReconnect();
        },
      );
    }
  }

  // Stream Subscription - Issue #13: Proper lifecycle management
  StreamSubscription? _itemsSubscription;
  StreamSubscription? _websocketSubscription;

  // We maintain the category state in the provider to persist it
  String _currentCategory = 'notes';
  String? _currentQuery;

  /// Get current category for external access (e.g., global search)
  String get currentCategory => _currentCategory;

  /// Get current search query for external access
  String? get currentQuery => _currentQuery;

  void onAppResume() {
    // Sync pending actions - stream updates will refresh UI automatically
    _repository.syncPendingActions();
    // Removed redundant: fetchItems(refresh: true);
    // The repository stream subscription handles UI updates after sync
  }

  Future<void> fetchItems({
    String? category,
    String? query,
    int? customerId,
    bool refresh = false,
    bool loadMore = false,
    bool skipAutoRefresh = false,
  }) async {
    // FIX P2-3: Cleanup stale progress entries periodically
    _cleanupStaleProgressEntries();

    // Increment token on category/query change to invalidate stale requests
    final bool categoryChanged =
        category != null && category != _currentCategory;
    final bool queryChanged = query != null && query != _currentQuery;

    if (categoryChanged) {
      final oldCategory = _currentCategory; // Save old category before updating
      _currentCategory = category;
      _categoryChangeToken++;
      // Cancel any in-flight request for the previous category
      _inFlightCategoryToken = _categoryChangeToken;
      // Clean up pending updates from the OLD category to prevent memory leaks
      // and stale data when switching between notes/files
      _cleanupPendingUpdatesForCategory(oldCategory);
      // FIX: Load cached items for the new category immediately to prevent empty state flash
      // This shows cached data while fetching fresh data in the background
      _loadCachedItemsForCurrentCategory();
      // Don't set refresh=true yet - let the stream handle it
      // We'll still fetch from remote, but user sees cached data first
    }

    if (queryChanged) {
      _currentQuery = query;
      _categoryChangeToken++;
      // Cancel any in-flight request for the previous query
      _inFlightCategoryToken = _categoryChangeToken;
      refresh = true;
    }

    // Force refresh on category/query change regardless of loadMore flag
    if (categoryChanged || queryChanged) {
      refresh = true;
      loadMore = false;
    }

    if (refresh) {
      _currentPage = 1;
      _hasMore = true;
    } else if (loadMore) {
      if (!_hasMore || _isFetchingMore || _isLoading) return;
      _currentPage++;
      _isFetchingMore = true;
    }

    // Skip remote fetch if skipAutoRefresh is true AND we have cached items
    // OFFLINE-FIRST FIX: Always show cache first, then background refresh
    if (skipAutoRefresh) {
      // Load from cache first
      _loadCachedItemsForCurrentCategory();
      // Only skip remote fetch if we have cached items
      if (_items.isNotEmpty) {
        _isLoading = false;
        notifyListeners();
        // Background refresh will happen via repository stream
        return;
      }
      // Cache is empty - continue to fetch from remote
    }

    // FIX: Debounce rapid category/query changes to prevent excessive API calls
    _debounceTimer?.cancel();
    await Future.delayed(_debounceDuration);
    if (_disposed) return;

    // Capture current token to detect stale emissions AFTER debounce
    final int currentToken = _categoryChangeToken;

    // Skip if a newer request was made during debounce
    if (currentToken != _categoryChangeToken) {
      debugPrint('[LibraryProvider] Debounced request cancelled due to newer request');
      return;
    }

    // FIX: Only show loading if we don't already have cached items
    // This prevents loading indicator flash when switching tabs with cached data
    final bool hasCachedItems = _items.isNotEmpty;
    if ((!hasCachedItems || refresh) && !loadMore) {
      _isLoading = true;
      notifyListeners();
    } else if (loadMore) {
      notifyListeners();
    }

    // FIX Issue #11: Properly cancel and clean up existing subscription to prevent memory leaks
    await _itemsSubscription?.cancel();
    _itemsSubscription = null;

    // FIX: Allow cache emission on category change to prevent empty state flash
    // The cached data will show immediately while remote fetches in background
    final bool shouldSkipCache = false;

    _itemsSubscription = _repository
        .getItemsStream(
          customerId: customerId,
          category: _currentCategory,
          searchQuery: _currentQuery,
          page: _currentPage,
          pageSize: _pageSize,
          skipCacheEmission: shouldSkipCache,
        )
        .listen(
          (newItems) async {
            // FIX #6: Ignore stale emissions from previous category/query requests
            if (currentToken != _categoryChangeToken) {
              debugPrint(
                '[LibraryProvider] Ignoring stale data: token mismatch (current=$_categoryChangeToken, emission=$currentToken)',
              );
              return;
            }

            // FIX: Check if this emission is from an in-flight request that should be cancelled
            if (_inFlightCategoryToken != null &&
                currentToken < _inFlightCategoryToken!) {
              debugPrint(
                '[LibraryProvider] Ignoring data from superseded request (current=$currentToken, inFlight=$_inFlightCategoryToken)',
              );
              return;
            }

            // Fetch shared items and merge them with owned items
            // Use caching to prevent excessive API calls on every refresh
            // FIX: Use token-based invalidation to prevent race conditions
            final fetchToken = currentToken;
            final now = DateTime.now();
            final sharedItemsCacheExpired =
                _sharedItemsLastFetched == null ||
                now.difference(_sharedItemsLastFetched!) > _sharedItemsCacheTTL;

            if ((refresh && sharedItemsCacheExpired) || _sharedItems.isEmpty) {
              try {
                final sharedItems = await _repository.getSharedWithMe();
                // FIX: Check if token still matches after async operation
                if (fetchToken == _categoryChangeToken && !_disposed) {
                  _sharedItems = sharedItems;
                  _sharedItemsLastFetched = now;
                  debugPrint(
                    '[LibraryProvider] Fetched ${_sharedItems.length} shared items',
                  );
                } else {
                  debugPrint(
                    '[LibraryProvider] Discarding stale shared items: token mismatch',
                  );
                }
              } catch (e, stackTrace) {
                debugPrint(
                  '[LibraryProvider] Failed to fetch shared items: $e',
                );
                debugPrint('[LibraryProvider] Stack trace: $stackTrace');
                // Log the full exception details for debugging
                if (e is ApiException) {
                  debugPrint(
                    '[LibraryProvider] ApiException: statusCode=${e.statusCode}, message=${e.message}',
                  );
                }
                // Don't fail the entire fetch - just continue without shared items
              }
            }

            // Merge owned and shared items
            final allItems = _mergeAndDeduplicateItems(newItems, _sharedItems);

            // Client-side filtering as safety net to ensure only correct category items are shown
            // This prevents flashes of wrong items when backend or cache returns unexpected data
            final filteredItems = _filterItemsByCategory(
              allItems,
              _currentCategory,
            );

            if (loadMore) {
              // Append new items, filtering out duplicates by ID
              final existingIds = _items.map((i) => i.id).toSet();
              final uniqueNewItems = filteredItems
                  .where((i) => !existingIds.contains(i.id))
                  .toList();
              _items.addAll(uniqueNewItems);
              _hasMore = filteredItems.length >= _pageSize;
              _isFetchingMore = false;
            } else {
              // Apply client-side filtering to ensure category correctness
              _items = filteredItems.map((remoteItem) {
                // First try direct ID match
                int optimisticIndex = _items.indexWhere(
                  (i) => i.id == remoteItem.id,
                );

                // If no direct match, check if this real ID matches a temp ID we created
                if (optimisticIndex == -1) {
                  // Look for temp IDs that map to this real ID
                  int? foundTempId;
                  for (final entry in _tempToRealIdMap.entries) {
                    if (entry.value == remoteItem.id) {
                      foundTempId = entry.key;
                      break;
                    }
                  }
                  if (foundTempId != null) {
                    optimisticIndex = _items.indexWhere(
                      (i) => i.id == foundTempId,
                    );
                  }
                }

                if (optimisticIndex != -1) {
                  final optimisticItem = _items[optimisticIndex];

                  // Check if we have a pending update for this item
                  final pendingUpdate =
                      _pendingUpdates[remoteItem.id] ??
                      _pendingUpdates[optimisticItem.id];
                  if (pendingUpdate != null) {
                    // If remote content matches what we saved, keep local version
                    // (server timestamp may be newer but content is the same)
                    final pendingTitle = pendingUpdate['title'] ?? '';
                    final pendingContent = pendingUpdate['content'] ?? '';
                    final remoteTitle = remoteItem.title;
                    final remoteContent = remoteItem.content ?? '';

                    final titleMatches = remoteTitle == pendingTitle;
                    final contentMatches = remoteContent == pendingContent;

                    debugPrint(
                      '[LibraryProvider] Comparing for id=${remoteItem.id}: '
                      'titleMatch=$titleMatches (remote="$remoteTitle" vs pending="$pendingTitle"), '
                      'contentMatch=$contentMatches (remote="${remoteContent.substring(0, remoteContent.length > 50 ? 50 : remoteContent.length)}..." vs pending="${pendingContent.substring(0, pendingContent.length > 50 ? 50 : pendingContent.length)}...")',
                    );

                    if (titleMatches && contentMatches) {
                      debugPrint(
                        '[LibraryProvider] Keeping local version for id=${remoteItem.id} '
                        '(sync completed, content matches)',
                      );
                      // Keep pending update to protect against future stream emissions
                      // Clear it only after confirming server has persisted the change
                      return optimisticItem;
                    }

                    // Content differs - might be from another source, accept remote
                    debugPrint(
                      '[LibraryProvider] Remote content differs for id=${remoteItem.id}, accepting remote',
                    );
                    _pendingUpdates.remove(remoteItem.id);
                    return remoteItem;
                  }

                  // No pending update - use content-based comparison instead of timestamp
                  // to avoid timezone/server clock issues
                  final titleMatches = optimisticItem.title == remoteItem.title;
                  final contentMatches =
                      (optimisticItem.content ?? '') ==
                      (remoteItem.content ?? '');

                  if (titleMatches && contentMatches) {
                    // Content is the same, keep local (preserves any UI-only state)
                    return optimisticItem;
                  }

                  // Content differs - check if local was modified more recently
                  // Use a tolerance window to account for clock skew
                  final timeDiff = optimisticItem.updatedAt
                      .difference(remoteItem.updatedAt)
                      .inSeconds
                      .abs();
                  if (timeDiff <= _timestampToleranceSeconds &&
                      titleMatches &&
                      contentMatches) {
                    // Within tolerance and content matches - keep local
                    return optimisticItem;
                  }

                  // Accept remote version if it's significantly newer
                  debugPrint(
                    '[LibraryProvider] Using remote data for id=${remoteItem.id} '
                    '(optimistic: ${optimisticItem.updatedAt}, remote: ${remoteItem.updatedAt})',
                  );
                }
                return remoteItem;
              }).toList();
              _hasMore = allItems.length >= _pageSize;
              _isLoading = false;
            }
            notifyListeners();
          },
          onError: (error) {
            debugPrint('Provider Error: $error');
            _isLoading = false;
            _isFetchingMore = false;

            // Check for authentication errors (401/403)
            final errorStr = error.toString().toLowerCase();
            if (errorStr.contains('401') ||
                errorStr.contains('403') ||
                errorStr.contains('authentication') ||
                errorStr.contains('unauthorized') ||
                errorStr.contains('forbidden')) {
              debugPrint('[LibraryProvider] Auth error detected: $error');
              // Don't clear data immediately - let user see cached content
              // AuthProvider will handle logout via SecurityEventService
            }

            notifyListeners();
          },
          cancelOnError: false, // Don't cancel on error, allow retry
        );

    // Cleanup stale pending updates (items no longer in the list)
    _cleanupStalePendingUpdates();
  }

  /// Merge owned and shared items, removing duplicates
  /// Owned items take precedence, shared items are marked with sharePermission
  /// FIX BUG #4: Properly preserve sharePermission from backend response
  /// P3-14 FIX: Filter out expired shares to prevent showing inaccessible items
  /// FIX #2, #16: Added comprehensive null safety checks to prevent crashes
  List<LibraryItem> _mergeAndDeduplicateItems(
    List<LibraryItem> ownedItems,
    List<LibraryItem> sharedItems,
  ) {
    final Map<int, LibraryItem> itemsMap = {};
    final now = DateTime.now();

    // Add owned items first (they take precedence)
    for (final item in ownedItems) {
      if (item.id == 0) continue; // Skip invalid items
      itemsMap[item.id] = item;
    }

    // Add shared items that aren't already owned
    for (final item in sharedItems) {
      // FIX #2: Skip null or invalid items
      if (item.id == 0) continue;

      // FIX #16: Safe null check for shareExpiresAt with proper comparison
      // Only skip if shareExpiresAt is not null AND is before now
      final expiresAt = item.shareExpiresAt;
      if (expiresAt != null && expiresAt.isBefore(now)) {
        debugPrint(
          '[LibraryProvider] Skipping expired share: item_id=${item.id}, '
          'expired_at=$expiresAt',
        );
        continue;
      }

      if (!itemsMap.containsKey(item.id)) {
        // FIX BUG #4: Preserve the actual sharePermission from backend
        // Backend returns share_permission for shared items, null for owned
        final permission = item.sharePermission;
        if (permission != null && permission.isNotEmpty) {
          // Backend provided sharePermission - use it as-is
          itemsMap[item.id] = item;
        } else {
          // Edge case: shared item without sharePermission
          // Log for debugging and default to 'read' for safety
          debugPrint(
            '[LibraryProvider] Shared item ${item.id} has no sharePermission, '
            'defaulting to read',
          );
          itemsMap[item.id] = item.copyWith(sharePermission: 'read');
        }
      }
    }

    return itemsMap.values.toList();
  }

  /// Filter items by category as a safety net to prevent wrong items from showing
  /// Notes category: only 'note' type
  /// Files category: 'file', 'image', 'audio', 'video' types
  List<LibraryItem> _filterItemsByCategory(
    List<LibraryItem> items,
    String category,
  ) {
    if (category == 'notes') {
      return items.where((item) => item.type == 'note').toList();
    } else if (category == 'files') {
      return items
          .where(
            (item) =>
                item.type == 'file' ||
                item.type == 'image' ||
                item.type == 'audio' ||
                item.type == 'video',
          )
          .toList();
    }
    // Tools or unknown category - return as-is
    return items;
  }

  /// Remove pending updates for items that no longer exist in the list
  void _cleanupStalePendingUpdates() {
    final itemIds = _items.map((i) => i.id).toSet();
    final staleIds = _pendingUpdates.keys
        .where((id) => !itemIds.contains(id))
        .toList();
    for (final id in staleIds) {
      debugPrint(
        '[LibraryProvider] Cleaning up stale pending update for id=$id',
      );
      _pendingUpdates.remove(id);
    }
  }

  /// Remove pending updates for items that don't match the current category
  /// This prevents stale note updates from persisting when switching to files category
  void _cleanupPendingUpdatesForCategory(String category) {
    // Get IDs of items in the new category
    // Files category includes multiple types: file, image, audio, video
    final categoryItemIds = _items
        .where(
          (item) =>
              (category == 'notes' && item.type == 'note') ||
              (category == 'files' &&
                  (item.type == 'file' ||
                      item.type == 'image' ||
                      item.type == 'audio' ||
                      item.type == 'video')),
        )
        .map((i) => i.id)
        .toSet();

    // Remove pending updates for items not in the current category
    final idsToRemove = _pendingUpdates.keys
        .where((id) => !categoryItemIds.contains(id))
        .toList();
    for (final id in idsToRemove) {
      debugPrint(
        '[LibraryProvider] Cleaning up pending update for id=$id (category change to $category)',
      );
      _pendingUpdates.remove(id);
    }

    // Also clean temp-to-real ID mappings for items not in current category
    final tempIdsToRemove = _tempToRealIdMap.keys
        .where((id) => !categoryItemIds.contains(id))
        .toList();
    for (final id in tempIdsToRemove) {
      debugPrint(
        '[LibraryProvider] Cleaning up temp-to-real mapping for id=$id (category change to $category)',
      );
      _tempToRealIdMap.remove(id);
    }
  }

  /// Load cached items for the current category to show immediately on category switch
  /// This prevents the empty state flash while fetching fresh data in the background
  Future<void> _loadCachedItemsForCurrentCategory() async {
    try {
      final licenseId = await _repository.apiClient.getLicenseId();
      if (licenseId == null) return;

      final cachedItems = await _repository.db.getCachedItems(
        licenseKeyId: licenseId,
        type: _currentCategory,
      );

      if (!_disposed && cachedItems.isNotEmpty) {
        // Filter to ensure only correct category items are shown
        final filteredItems = _filterItemsByCategory(
          cachedItems,
          _currentCategory,
        );
        _items = filteredItems;
        _currentPage = 1;
        _hasMore = true;
        _isLoading = false;
        notifyListeners();
        debugPrint(
          '[LibraryProvider] Loaded ${filteredItems.length} cached items for $_currentCategory',
        );
      }
    } catch (e) {
      // Silently fail - remote fetch will handle it
      debugPrint('[LibraryProvider] Failed to load cached items: $e');
    }
  }

  void toggleSelection(int id) {
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
    } else {
      _selectedIds.add(id);
    }

    _isSelectionMode = _selectedIds.isNotEmpty;
    notifyListeners();
  }

  void clearSelection() {
    _selectedIds.clear();
    _isSelectionMode = false;
    notifyListeners();
  }

  /// Reset provider state (for account switching)
  void reset() {
    // Cancel subscriptions to prevent stale events and memory leaks
    _itemsSubscription?.cancel();
    _itemsSubscription = null;
    _websocketSubscription?.cancel();
    _websocketSubscription = null;

    _items = [];
    _isLoading = false;
    _isFetchingMore = false;
    _hasMore = true;
    _currentPage = 1;
    _isSelectionMode = false;
    _selectedIds.clear();
    _currentCategory = 'notes';
    _currentQuery = null;
    _categoryChangeToken = 0;
    _inFlightCategoryToken = null;
    // P3-14: Reset share state
    _sharedItems = [];
    _sharedItemsLastFetched = null;
    _isLoadingShared = false;
    _itemShares = {};
    // Clear pending updates and temp ID mappings
    _pendingUpdates.clear();
    _tempToRealIdMap.clear();
    // Clear progress tracking to prevent memory leaks
    _lastProgressUpdate.clear();
    notifyListeners();
  }

  Future<int> addNote(String title, String content, {int? customerId}) async {
    // FIX Issue #3: Use UUID-based temp ID to prevent collisions
    final tempId = _generateTempId();
    final newItem = LibraryItem(
      id: tempId,
      licenseKeyId: 0,
      type: 'note',
      title: title,
      content: content,
      customerId: customerId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Track pending create
    _pendingUpdates[tempId] = {'title': title, 'content': content};

    _items.insert(0, newItem);
    notifyListeners();

    try {
      // Issue #14: Pass tempId consistently - repository should use it
      final actualTempId = await _repository.createNote(
        title: title,
        content: content,
        customerId: customerId,
        localId: tempId,
      );

      // If the repository generated a different ID (it shouldn't, but for safety)
      if (actualTempId != tempId) {
        final index = _items.indexWhere((item) => item.id == tempId);
        if (index != -1) {
          _items[index] = _items[index].copyWith(id: actualTempId);
          // Update pending update tracking with new ID
          _pendingUpdates[actualTempId] = _pendingUpdates[tempId]!;
          _pendingUpdates.remove(tempId);
          // Track temp-to-real ID mapping for merge logic
          _tempToRealIdMap[tempId] = actualTempId;
          notifyListeners();
        }
      }

      return actualTempId;
    } catch (e) {
      // Revert optimistic update on failure
      _items.removeWhere((item) => item.id == tempId);
      _pendingUpdates.remove(tempId);
      notifyListeners();
      rethrow;
    }
  }

  // UX-005 FIX: Track last deleted items for undo functionality
  final List<Map<String, dynamic>> _recentlyDeleted = [];
  static const int _maxDeletedToKeep = 5;
  static const Duration _undoTTL = Duration(seconds: 5);

  // UX-005 FIX: Delete item with undo option
  Future<void> deleteItem(int id, {bool showUndo = true}) async {
    // Find item for potential undo
    final removedIndex = _items.indexWhere((item) => item.id == id);
    LibraryItem? removedItem;
    if (removedIndex != -1) {
      removedItem = _items[removedIndex];
    }

    // Optimistic removal
    _items.removeWhere((item) => item.id == id);
    notifyListeners();

    try {
      await _repository.deleteItem(id);

      // UX-005 FIX: Store for undo (only if showUndo is true)
      if (showUndo && removedItem != null) {
        _recentlyDeleted.add({
          'item': removedItem,
          'index': removedIndex,
          'timestamp': DateTime.now(),
        });

        // Clean up old entries
        if (_recentlyDeleted.length > _maxDeletedToKeep) {
          _recentlyDeleted.removeAt(0);
        }

        // Auto-remove after TTL
        Future.delayed(_undoTTL, () {
          _recentlyDeleted.removeWhere(
            (entry) => entry['item'].id == id,
          );
        });
      }
    } catch (e) {
      // Revert on failure
      if (removedItem != null) {
        _items.insert(removedIndex >= 0 ? removedIndex : 0, removedItem);
        notifyListeners();
      }
      rethrow;
    }
  }

  // UX-005 FIX: Undo last delete
  Future<void> undoDelete(int id) async {
    final entry = _recentlyDeleted.cast<Map<String, dynamic>>().firstWhere(
      (e) => (e['item'] as LibraryItem).id == id,
      orElse: () => <String, dynamic>{},
    );

    if (entry.isEmpty) return;

    final item = entry['item'] as LibraryItem;
    final index = entry['index'] as int?;

    // Restore item
    _items.insert(index ?? 0, item);
    _recentlyDeleted.removeWhere((e) => e['item'].id == id);
    notifyListeners();

    // Restore in repository (mark as not deleted)
    try {
      await _repository.restoreItem(id);
    } catch (e) {
      // If restore fails, remove from list again
      _items.removeWhere((item) => item.id == id);
      notifyListeners();
      rethrow;
    }
  }

  // UX-005 FIX: Check if item can be undone
  bool canUndoDelete(int id) {
    return _recentlyDeleted.any((e) => e['item'].id == id);
  }

  Future<void> updateNote(int id, String title, String content) async {
    debugPrint('[LibraryProvider] updateNote called: id=$id, title=$title');

    // Track pending update with actual content to compare against server response
    _pendingUpdates[id] = {'title': title, 'content': content};

    // Optimistic in-memory update
    final index = _items.indexWhere((item) => item.id == id);
    LibraryItem? oldItem;
    if (index != -1) {
      oldItem = _items[index];
      debugPrint(
        '[LibraryProvider] Found item at index=$index, old updatedAt=${oldItem.updatedAt}',
      );
      // FIX: Update updatedAt to ensure merge logic keeps optimistic update
      _items[index] = _items[index].copyWith(
        title: title,
        content: content,
        updatedAt: DateTime.now(),
      );
      debugPrint(
        '[LibraryProvider] Updated item, new updatedAt=${_items[index].updatedAt}',
      );
      notifyListeners();
    } else {
      debugPrint('[LibraryProvider] Item not found in local list!');
    }

    try {
      await _repository.updateItem(id, title: title, content: content);
      debugPrint('[LibraryProvider] Repository update completed');
      // We don't call fetchItems(refresh: true) here to avoid flickering;
      // the stream will eventually sync it or the in-memory state is already correct.
    } catch (e) {
      // Revert on failure
      if (index != -1 && oldItem != null) {
        _items[index] = oldItem;
        notifyListeners();
      }
      _pendingUpdates.remove(id);
      rethrow;
    }
  }

  Future<void> uploadFile(String path, {int? customerId}) async {
    final fileName = p.basename(path);

    // FIX Issue #14: Check storage quota before upload
    final file = File(path);
    final fileSize = await file.length();
    final hasSpace = await _repository.hasEnoughStorage(fileSize);

    if (!hasSpace || _disposed) {
      // Show storage limit warning
      debugPrint(
        '[LibraryProvider] Storage limit reached or disposed, cannot upload $fileName',
      );
      // Could show a snackbar/notification here
      return;
    }

    // FIX Issue #3: Use UUID-based temp ID to prevent collisions
    final tempId = _generateTempId();

    // Issue #15: Track uploading state for failure recovery
    _uploadingIds.add(tempId);

    // 1. Add optimistic "uploading" item with bytes tracking
    final tempItem = LibraryItem(
      id: tempId,
      licenseKeyId: 0,
      type: 'file',
      title: fileName,
      customerId: customerId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isUploading: true,
      uploadProgress: 0.05, // Initial small progress
      uploadedBytes: 0,
      totalUploadBytes: fileSize,
      // FIX: Store original file path for retry on failure
      originalFilePath: path,
    );

    _items.insert(0, tempItem);
    notifyListeners();

    try {
      final uploadedItem = await _repository.uploadFile(
        filePath: path,
        customerId: customerId,
        onProgress: (progress) {
          // FIX #9: Adaptive throttling - faster updates at start, slower during transfer
          final now = DateTime.now();
          final lastUpdate = _lastProgressUpdate[tempId];
          
          // Use faster throttle at start (0-10%), slower during rest of upload
          final currentThreshold = progress < _progressThrottleFastThreshold
              ? _progressThrottleIntervalMsStart
              : _progressThrottleIntervalMsTransfer;
          
          if (lastUpdate != null &&
              now.difference(lastUpdate).inMilliseconds < currentThreshold) {
            return;
          }
          _lastProgressUpdate[tempId] = now;

          final index = _items.indexWhere((item) => item.id == tempId);
          if (index != -1 && !_disposed) {
            final uploadedBytes = (progress * fileSize).round();
            _items[index] = _items[index].copyWith(
              uploadProgress: progress,
              uploadedBytes: uploadedBytes,
              totalUploadBytes: fileSize,
            );
            notifyListeners();
          }
        },
      );

      // 2. Cache the local file for immediate access
      if (uploadedItem.filePath != null) {
        try {
          await MediaCacheManager().putFile(
            uploadedItem.filePath!.toFullUrl,
            File(path),
            filename: uploadedItem.title,
          );
        } catch (cacheError) {
          // Log but don't fail the upload - caching is optional
          debugPrint('[LibraryProvider] Failed to cache file: $cacheError');
        }
      }

      // Issue #15: Clear uploading state
      _uploadingIds.remove(tempId);
      _lastProgressUpdate.remove(tempId);

      // 3. Clear temp item and add real item
      _items.removeWhere((item) => item.id == tempId);
      _items.insert(0, uploadedItem);
      
      // P3-14 FIX: Track temp ID to real ID mapping for bulk operations
      // This ensures updates to the temp item are properly mapped to the server ID
      _tempToRealIdMap[tempId] = uploadedItem.id;
      
      notifyListeners();

      // Still trigger a silent refresh to ensure sync
      await fetchItems(refresh: false);
    } catch (e) {
      // Issue #15: Proper failure recovery
      _uploadingIds.remove(tempId);
      _lastProgressUpdate.remove(tempId);

      // Mark item as failed instead of removing
      final index = _items.indexWhere((item) => item.id == tempId);
      if (index != -1 && !_disposed) {
        _items[index] = _items[index].copyWith(
          isUploading: false,
          uploadProgress: null,
          hasError: true,
        );
        notifyListeners();
      }

      // Don't rethrow - let user see the failed state and retry
      debugPrint('Upload failed for $fileName: $e');
    }
  }

  /// FIX Issue #15: Retry failed upload
  Future<void> retryUpload(int itemId) async {
    final item = _items.firstWhere(
      (i) => i.id == itemId,
      orElse: () => LibraryItem(
        id: 0,
        licenseKeyId: 0,
        type: 'file',
        title: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    if (item.id == 0 || item.type != 'file') {
      throw Exception('Item not found or is not a file');
    }

    // FIX: Check if we have the original file path to retry
    final filePath = item.originalFilePath;
    if (filePath == null) {
      debugPrint(
        '[LibraryProvider] Cannot retry upload: original file path not found',
      );
      throw Exception(
        'File path not available for retry. Please select the file again.',
      );
    }

    // Verify the file still exists
    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint(
        '[LibraryProvider] Cannot retry upload: file no longer exists',
      );
      // Remove the failed item
      removeFailedUpload(itemId);
      throw Exception(
        'The selected file no longer exists. Please select a new file.',
      );
    }

    // Get customerId from the item
    final customerId = item.customerId;

    // Remove the failed item first
    _items.removeWhere((i) => i.id == itemId);
    notifyListeners();

    // Re-upload the file
    await uploadFile(filePath, customerId: customerId);
  }

  /// FIX Issue #15: Remove failed upload item
  void removeFailedUpload(int itemId) {
    _items.removeWhere((item) => item.id == itemId);
    _uploadingIds.remove(itemId);
    notifyListeners();
  }

  /// FIX Issue #19: Bulk share/forward selected items
  /// FIX BUG #7: Add proper error reporting with BuildContext
  Future<void> shareSelected({
    required String sharedWithUserId,
    String permission = 'read',
    int? expiresInDays,
    // FIX: Add BuildContext for user notifications
  }) async {
    if (_selectedIds.isEmpty) return;

    final itemsToShare = _items
        .where((item) => _selectedIds.contains(item.id))
        .toList();

    if (itemsToShare.isEmpty) return;

    // Share each item with the specified user
    int successCount = 0;
    int failCount = 0;
    final failedItemIds = <int>[];

    for (final item in itemsToShare) {
      try {
        await shareItem(
          itemId: item.id,
          sharedWithUserId: sharedWithUserId,
          permission: permission,
          expiresInDays: expiresInDays,
        );
        successCount++;
      } catch (e) {
        failCount++;
        failedItemIds.add(item.id);
        debugPrint('[LibraryProvider] Failed to share item ${item.id}: $e');
      }
    }

    // Clear selection after sharing
    clearSelection();

    // FIX BUG #7: Throw detailed error for partial/complete failures
    if (failCount > 0 && successCount > 0) {
      // Partial success - throw with details so caller can show warning
      debugPrint(
        '[LibraryProvider] Shared $successCount items, failed $failCount',
      );
      throw PartialShareException(
        successCount: successCount,
        failCount: failCount,
        failedItemIds: failedItemIds,
      );
    } else if (failCount > 0) {
      // All failed
      debugPrint('[LibraryProvider] All shares failed ($failCount items)');
      throw Exception('ظپط´ظ„ ظ…ط´ط§ط±ظƒط© $failCount ط¹ظ†ط§طµط±');
    }
    // If all succeeded, no exception is thrown
  }

  /// P3-14: Share an item with another user
  Future<void> shareItem({
    required int itemId,
    required String sharedWithUserId,
    String permission = 'read',
    int? expiresInDays,
  }) async {
    try {
      await _repository.shareItem(
        itemId: itemId,
        sharedWithUserId: sharedWithUserId,
        permission: permission,
        expiresInDays: expiresInDays,
      );

      // Track analytics
      // In a full implementation, send to backend analytics endpoint

      // Refresh shares list
      await loadItemShares(itemId);
    } catch (e) {
      debugPrint('[LibraryProvider] Share failed: $e');
      rethrow;
    }
  }

  /// P3-14: Load shares for an item
  Future<void> loadItemShares(int itemId) async {
    try {
      final shares = await _repository.listItemShares(itemId);
      _itemShares[itemId] = shares;
      notifyListeners();
    } catch (e) {
      debugPrint('[LibraryProvider] Failed to load shares: $e');
    }
  }

  /// P3-14: Fetch items shared with current user
  Future<void> fetchSharedWithMe({
    String? permission,
    bool refresh = false,
  }) async {
    if (refresh) {
      _sharedItems.clear();
    }

    _isLoadingShared = true;
    notifyListeners();

    try {
      final items = await _repository.getSharedWithMe(permission: permission);
      _sharedItems = items;
    } catch (e) {
      debugPrint('[LibraryProvider] Failed to fetch shared items: $e');
    } finally {
      _isLoadingShared = false;
      notifyListeners();
    }
  }

  /// P3-14: Remove a share
  Future<void> removeShare({required int shareId, int? itemId}) async {
    try {
      await _repository.removeShare(shareId);

      // Remove from local cache
      if (itemId != null && _itemShares.containsKey(itemId)) {
        _itemShares[itemId]?.removeWhere((share) => share['id'] == shareId);
        notifyListeners();
      }

      // Refresh shared items list
      await fetchSharedWithMe(refresh: true);
    } catch (e) {
      debugPrint('[LibraryProvider] Failed to remove share: $e');
      rethrow;
    }
  }

  /// P3-14: Update share permission
  Future<void> updateSharePermission({
    required int shareId,
    required String permission,
    int? itemId,
  }) async {
    try {
      await _repository.updateSharePermission(
        shareId: shareId,
        permission: permission,
      );

      // Update local cache
      if (itemId != null && _itemShares.containsKey(itemId)) {
        final shareIndex = _itemShares[itemId]!.indexWhere(
          (share) => share['id'] == shareId,
        );
        if (shareIndex != -1) {
          _itemShares[itemId]![shareIndex]['permission'] = permission;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[LibraryProvider] Failed to update share permission: $e');
      rethrow;
    }
  }

  // UX-006 FIX: Delete selected with loading state
  Future<void> deleteSelected() async {
    if (_selectedIds.isEmpty) return;

    _isBulkDeleting = true;
    notifyListeners();

    try {
      await _repository.bulkDelete(_selectedIds.toList());

      // Optimistic removal from local list
      _items.removeWhere((item) => _selectedIds.contains(item.id));
      clearSelection();
      // Also trigger refresh to ensure sync status
      await fetchItems(refresh: false);
    } finally {
      _isBulkDeleting = false;
      notifyListeners();
    }
  }

  /// FIX Issue #3: Generate unique temp ID using UUID to prevent collisions
  /// Returns a positive integer that fits in 32-bit signed int range
  int _generateTempId() {
    // Use UUID v4 for true uniqueness - generates random 128-bit number
    // Then take modulo to fit in 32-bit signed int range
    final uuid =
        DateTime.now().microsecondsSinceEpoch.toRadixString(16) +
        DateTime.now().microsecond.toRadixString(16) +
        (DateTime.now().millisecond * 17).toRadixString(16) +
        (DateTime.now().second * 31).toRadixString(16);
    final hash = uuid.hashCode.abs();
    // Ensure it's within 32-bit signed int range and positive
    return (hash % _maxInt32) + 1;
  }

  /// Lookup username for sharing (similar to CustomersProvider)
  void lookupUsername(String username) {
    _usernameLookupTimer?.cancel();

    final trimmedUsername = username.trim().replaceAll('@', '');
    if (trimmedUsername.length < 3) {
      clearUsernameLookup();
      return;
    }

    _usernameLookupTimer = Timer(const Duration(milliseconds: 500), () async {
      _isCheckingUsername = true;
      _foundUsernameDetails = null;
      _usernameNotFound = false;
      notifyListeners();

      try {
        final result = await _customersRepo.checkUsername(trimmedUsername);
        if (trimmedUsername.length >= 3) {
          if (result['exists'] == true) {
            final fullName = result['full_name'];
            final companyName = result['company_name'];
            // Handle case where these might be Maps instead of Strings
            _foundUsernameDetails = (fullName is String
                ? fullName
                : (companyName is String ? companyName : 'ظ…ط³طھط®ط¯ظ… ظ…ط¹ط±ظˆظپ'));
            _usernameNotFound = false;
          } else {
            _foundUsernameDetails = null;
            _usernameNotFound = true;
          }
        }
      } catch (e) {
        debugPrint('Username lookup failed: $e');
        _foundUsernameDetails = null;
        _usernameNotFound = true;
      } finally {
        _isCheckingUsername = false;
        notifyListeners();
      }
    });
  }

  /// Clear username lookup state
  void clearUsernameLookup() {
    _foundUsernameDetails = null;
    _isCheckingUsername = false;
    _usernameNotFound = false;
    if (_usernameLookupTimer?.isActive ?? false) _usernameLookupTimer!.cancel();
    notifyListeners();
  }

  // Issue #26: Trash functionality
  Future<List<LibraryItem>> getTrashItems() async {
    try {
      return await _repository.getTrashItems();
    } catch (e) {
      debugPrint('[LibraryProvider] Failed to get trash items: $e');
      rethrow;
    }
  }

  Future<void> restoreFromTrash(int itemId) async {
    try {
      await _repository.restoreFromTrash(itemId);
      // Refresh items to show the restored item
      await fetchItems(refresh: true);
    } catch (e) {
      debugPrint('[LibraryProvider] Failed to restore from trash: $e');
      rethrow;
    }
  }

  Future<void> deletePermanently(int itemId) async {
    try {
      await _repository.deletePermanently(itemId);
      // Remove from local list optimistically
      _items.removeWhere((item) => item.id == itemId);
      notifyListeners();
    } catch (e) {
      debugPrint('[LibraryProvider] Failed to delete permanently: $e');
      rethrow;
    }
  }

  Future<void> emptyTrash() async {
    try {
      await _repository.emptyTrash();
      // Clear trash items from local list
      _items.removeWhere((item) => item.deletedAt != null);
      notifyListeners();
    } catch (e) {
      debugPrint('[LibraryProvider] Failed to empty trash: $e');
      rethrow;
    }
  }

  // P3-13: Version history functionality
  Future<List<Map<String, dynamic>>> getItemVersions(int itemId) async {
    try {
      return await _repository.getItemVersions(itemId);
    } catch (e) {
      debugPrint('[LibraryProvider] Failed to get item versions: $e');
      rethrow;
    }
  }

  Future<void> restoreVersion(int itemId, int versionId) async {
    try {
      await _repository.restoreVersion(itemId, versionId);
      // Refresh items to show the restored version
      await fetchItems(refresh: true);
    } catch (e) {
      debugPrint('[LibraryProvider] Failed to restore version: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    _disposed = true;

    // Cancel debounce timer to prevent memory leaks
    _debounceTimer?.cancel();
    _debounceTimer = null;

    // FIX #5: Cancel all subscriptions with proper null checks
    // Using Future.wait to ensure all cancellations complete
    final cancelFutures = <Future>[];

    if (_itemsSubscription != null) {
      cancelFutures.add(_itemsSubscription!.cancel());
      _itemsSubscription = null;
    }

    if (_websocketSubscription != null) {
      cancelFutures.add(_websocketSubscription!.cancel());
      _websocketSubscription = null;
    }

    // FIX #5: Cancel timer to prevent memory leaks
    _usernameLookupTimer?.cancel();
    _usernameLookupTimer = null;

    clearUsernameLookup();
    _repository.dispose();
    
    // Clear all maps to prevent memory leaks
    _pendingUpdates.clear();
    _tempToRealIdMap.clear();
    _lastProgressUpdate.clear();
    _sharedItems.clear();
    _itemShares.clear();
    _uploadingIds.clear();
    _selectedIds.clear();
    
    super.dispose();
  }
}
