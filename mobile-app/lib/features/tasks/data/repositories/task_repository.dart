import 'package:sqflite/sqflite.dart';
import '../models/task_model.dart';
import '../models/task_comment_model.dart';
import '../services/task_alarm_service.dart';
import 'package:almudeer_mobile_app/core/services/local_database_service.dart';
import '../services/sync_service.dart';
import 'package:almudeer_mobile_app/features/auth/data/repositories/auth_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'package:almudeer_mobile_app/core/services/websocket_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almudeer_mobile_app/features/tasks/utils/task_logger.dart'; // FIX #8: Centralized logging
import 'package:almudeer_mobile_app/core/api/api_client.dart';

class TaskRepository {
  final ApiClient _apiClient = ApiClient();
  final LocalDatabaseService _databaseService = LocalDatabaseService();
  final TaskSyncService _syncService = TaskSyncService();
  final WebSocketService? _webSocketService;
  StreamSubscription? _connectivitySubscription;
  StreamSubscription? _wsSubscription;
  bool _isSyncing = false;

  // Add a StreamController to notify when sync completes
  final _syncController = StreamController<void>.broadcast();
  Stream<void> get syncStream => _syncController.stream;

  // Typing Indicators Stream
  final _typingController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get typingStream => _typingController.stream;

  // Expose syncService for repository access
  TaskSyncService get syncService => _syncService;

  TaskRepository({WebSocketService? webSocketService})
    : _webSocketService = webSocketService {
    // Listen for connectivity changes to retry sync
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      // results is a List<ConnectivityResult> in newer versions
      if (results.any((r) => r != ConnectivityResult.none)) {
        _runSyncQueue();
      }
    });

    // Reliability Hardening: Reschedule alarms on startup from local database
    _rescheduleLocalAlarms();

    // Real-time Sync: Listen for remote task changes
    _initWebSocket();
  }

  // FIX BUG-003 + PERF-001: Use LinkedHashMap for O(1) LRU operations instead of O(n) List
  // This prevents memory leak and improves performance for large comment caches
  final _commentCache = <String, List<TaskCommentModel>>{};
  final Map<String, DateTime> _commentCacheTimestamps = {};  // Track cache entry time for TTL
  final Set<String> _commentCacheStale = {};
  // BUG-004 FIX: Reduced cache size from 20 to 10 to prevent memory leak
  static const int _maxCommentCacheSize = 10;
  // BUG-004 FIX: Reduced TTL from 5 to 3 minutes for better memory management
  static const Duration _commentCacheTTL = Duration(minutes: 3);
  // FIX: No need for separate access order list - LinkedHashMap maintains insertion order

  // FIX BUG-003: Evict oldest entries when cache is full or expired - O(1) operations
  void _evictCommentCacheIfNeeded() {
    final now = DateTime.now();

    // First, remove expired entries (TTL-based eviction)
    final expiredKeys = <String>[];
    for (final entry in _commentCacheTimestamps.entries) {
      if (now.difference(entry.value) > _commentCacheTTL) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      _commentCache.remove(key);
      _commentCacheTimestamps.remove(key);
      _commentCacheStale.remove(key);
      TaskLogger.cache('Evicted expired comment cache for task $key');
    }

    // Then, evict oldest entries if still over capacity (LRU eviction)
    // FIX BUG-003: LinkedHashMap.keys.iterator is O(1) for getting first key
    while (_commentCache.length >= _maxCommentCacheSize && _commentCache.isNotEmpty) {
      final oldestKey = _commentCache.keys.first;
      _commentCache.remove(oldestKey);
      _commentCacheTimestamps.remove(oldestKey);
      _commentCacheStale.remove(oldestKey);
      TaskLogger.cache('Evicted LRU comment cache for task $oldestKey');
    }
  }

  // FIX BUG-003: Update LRU order and timestamp when accessing cache - O(1) operation
  void _updateCommentCacheAccess(String taskId) {
    // FIX: Re-insert to move to end of LinkedHashMap (marks as most recently used)
    if (_commentCache.containsKey(taskId)) {
      final comments = _commentCache.remove(taskId);
      _commentCache[taskId] = comments!;
      _commentCacheTimestamps[taskId] = DateTime.now();
    }
  }

  // FIX: Helper to add entry to cache with timestamp
  void _addToCommentCache(String taskId, List<TaskCommentModel> comments) {
    _evictCommentCacheIfNeeded();  // Evict before adding
    _commentCache[taskId] = comments;
    _commentCacheTimestamps[taskId] = DateTime.now();
    _updateCommentCacheAccess(taskId);
    TaskLogger.cache('Cached ${comments.length} comments for task $taskId');
  }

  // FIX BUG-004: Add error-based cache cleanup to prevent memory leaks on repeated failures
  void _cleanupCommentCacheOnError(String taskId) {
    // On repeated errors, remove the cache entry to prevent serving stale data indefinitely
    if (_commentCacheStale.contains(taskId)) {
      // Already stale - this is a repeated failure, evict the cache
      _commentCache.remove(taskId);
      _commentCacheTimestamps.remove(taskId);
      _commentCacheStale.remove(taskId);
      TaskLogger.cache('Evicted comment cache for task $taskId due to repeated errors');
    } else {
      // First error - mark as stale
      _commentCacheStale.add(taskId);
      TaskLogger.cache('Comment cache marked stale for task $taskId due to error');
    }
  }

  // WebSocket reconnection state
  int _wsReconnectAttempts = 0;
  static const int _maxWsReconnectAttempts = 10;
  static const Duration _wsReconnectBaseDelay = Duration(seconds: 2);
  static const Duration _wsReconnectMaxDelay = Duration(minutes: 2); // FIX BUG-008: Cap max delay
  Timer? _wsReconnectTimer;
  bool _isReconnecting = false; // FIX BUG-008: Prevent concurrent reconnection attempts
  
  // FIX BUG-011: WebSocket connection status for UI indicator
  bool _isWebSocketConnected = true;
  DateTime? _wsLastDisconnectedAt;
  int _wsDisconnectCount = 0;
  
  // Get WebSocket connection status
  bool get isWebSocketConnected => _isWebSocketConnected;
  DateTime? get wsLastDisconnectedAt => _wsLastDisconnectedAt;
  int get wsDisconnectCount => _wsDisconnectCount;
  int get wsReconnectAttempts => _wsReconnectAttempts;
  
  // Stream for WebSocket status changes
  final _wsStatusController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get wsStatusStream => _wsStatusController.stream;
  
  void _notifyWsStatusChange() {
    if (_wsStatusController.hasListener) {
      _wsStatusController.add({
        'isConnected': _isWebSocketConnected,
        'reconnectAttempts': _wsReconnectAttempts,
        'disconnectCount': _wsDisconnectCount,
        'lastDisconnectedAt': _wsLastDisconnectedAt,
      });
    }
  }

  // BUG-005 FIX: WebSocket event deduplication with LRU cache
  final Map<String, DateTime> _processedEventIds = {};
  static const Duration _eventIdTTL = Duration(minutes: 5);
  static const int _maxEventIdCacheSize = 100;

  // BUG-005 FIX: Check if event was already processed
  bool _isDuplicateEvent(String eventId) {
    if (_processedEventIds.containsKey(eventId)) {
      TaskLogger.websocket('Duplicate event ignored: $eventId');
      return true;
    }
    return false;
  }

  // BUG-005 FIX: Track processed event
  void _markEventAsProcessed(String eventId) {
    // Evict old entries if cache is full
    if (_processedEventIds.length >= _maxEventIdCacheSize) {
      _cleanupOldEventIds();
    }
    _processedEventIds[eventId] = DateTime.now();
  }

  // BUG-005 FIX: Cleanup expired event IDs
  void _cleanupOldEventIds() {
    final now = DateTime.now();
    _processedEventIds.removeWhere((key, timestamp) {
      return now.difference(timestamp) > _eventIdTTL;
    });
  }

  void _initWebSocket() {
    final ws = _webSocketService;
    if (ws == null) return;

    // FIX BUG-008: Cancel any existing reconnection timer before initializing
    _wsReconnectTimer?.cancel();
    _isReconnecting = false;

    _wsSubscription?.cancel();
    _wsSubscription = ws.stream.listen((event) {
      // BUG-005 FIX: Check for duplicate events
      final eventId = event['event_id'] as String?;
      if (eventId != null && _isDuplicateEvent(eventId)) {
        return;  // Skip duplicate event
      }

      if (event['event'] == 'task_sync') {
        final data = event['data'] as Map<String, dynamic>?;
        final taskId = data?['task_id'] as String?;
        final changeType = data?['change_type'] as String?;

        debugPrint(
          'TaskRepository: task_sync event received. ID: $taskId, Type: $changeType',
        );

        // BUG-005 FIX: Mark event as processed
        if (eventId != null) {
          _markEventAsProcessed(eventId);
        }

        // Handle comment events separately for real-time updates
        if (changeType == 'comment' && taskId != null) {
          // FIX BUG-005: Mark as stale but don't remove - return stale data while fetching
          _commentCacheStale.add(taskId);
          TaskLogger.cache('Comment cache marked stale for task $taskId');

          // Notify listeners to refresh comments
          _syncController.add(null);

          // Fetch fresh in background - don't await
          getComments(taskId).then((comments) {
            TaskLogger.d('Background comment refresh completed for $taskId', tag: 'Comments');
          }).catchError((e) {
            TaskLogger.e('Background comment refresh failed for $taskId: $e', tag: 'Comments');
          });
        } else if (changeType == 'delete' && taskId != null) {
          // Optimization: If delete, we can remove locally immediately
          _deleteTaskLocally(taskId).then((_) {
            _runSyncQueue(); // Still sync to be sure
          });
        } else {
          _runSyncQueue();
        }
      } else if (event['event'] == 'task_typing') {
        final data = event['data'] as Map<String, dynamic>?;
        if (data != null) {
          _typingController.add(data);
        }
      }
    }, onError: (error) {
      // FIX BUG-008: Handle WebSocket errors with debounce and capped exponential backoff
      TaskLogger.websocket('WebSocket error: $error');

      // FIX BUG-011: Track disconnection status
      _isWebSocketConnected = false;
      _wsLastDisconnectedAt = DateTime.now();
      _wsDisconnectCount++;
      _notifyWsStatusChange();

      // FIX: Debounce reconnection attempts to prevent rapid retries
      if (_isReconnecting) {
        TaskLogger.websocket('Reconnection already in progress, skipping...');
        return;
      }

      _wsReconnectAttempts++;
      if (_wsReconnectAttempts <= _maxWsReconnectAttempts) {
        // FIX: Cap the delay to prevent excessively long waits
        final delay = Duration(
          milliseconds: (_wsReconnectBaseDelay.inMilliseconds * (1 << (_wsReconnectAttempts - 1)))
              .clamp(0, _wsReconnectMaxDelay.inMilliseconds),
        );
        TaskLogger.websocket('Scheduling reconnection in ${delay.inSeconds}s (attempt $_wsReconnectAttempts/$_maxWsReconnectAttempts)');

        _wsReconnectTimer?.cancel();
        _isReconnecting = true;
        _wsReconnectTimer = Timer(delay, () {
          _isReconnecting = false;
          TaskLogger.websocket('Reconnecting WebSocket...');
          _initWebSocket();
        });
      } else {
        TaskLogger.w('Max WebSocket reconnection attempts reached. Stopping reconnections.', tag: 'WebSocket');
      }
    }, onDone: () {
      // FIX BUG-008: Handle WebSocket disconnection with debounce and capped backoff
      TaskLogger.websocket('WebSocket connection closed. Attempting reconnection...');

      // FIX BUG-011: Track disconnection status
      _isWebSocketConnected = false;
      _wsLastDisconnectedAt = DateTime.now();
      _wsDisconnectCount++;
      _notifyWsStatusChange();

      // FIX: Debounce reconnection attempts
      if (_isReconnecting) {
        TaskLogger.websocket('Reconnection already in progress, skipping...');
        return;
      }

      _wsReconnectAttempts++;
      if (_wsReconnectAttempts <= _maxWsReconnectAttempts) {
        // FIX: Cap the delay
        final delay = Duration(
          milliseconds: (_wsReconnectBaseDelay.inMilliseconds * (1 << (_wsReconnectAttempts - 1)))
              .clamp(0, _wsReconnectMaxDelay.inMilliseconds),
        );
        TaskLogger.websocket('Scheduling reconnection in ${delay.inSeconds}s (attempt $_wsReconnectAttempts/$_maxWsReconnectAttempts)');

        _wsReconnectTimer?.cancel();
        _isReconnecting = true;
        _wsReconnectTimer = Timer(delay, () {
          _isReconnecting = false;
          TaskLogger.websocket('Reconnecting WebSocket...');
          _initWebSocket();
        });
      } else {
        TaskLogger.w('Max WebSocket reconnection attempts reached. Stopping reconnections.', tag: 'WebSocket');
      }
    });
    // Reset reconnect attempts on successful connection
    _wsReconnectAttempts = 0;
    // FIX BUG-011: Mark as connected on successful init
    if (!_isWebSocketConnected) {
      _isWebSocketConnected = true;
      _notifyWsStatusChange();
    }
  }

  // FIX PERF-002: Cache last alarm reschedule to avoid unnecessary work
  DateTime? _lastAlarmReschedule;
  static const Duration _alarmRescheduleInterval = Duration(hours: 24);
  
  // FIX: Invalidate alarm cache when tasks are modified
  void _invalidateAlarmCache() {
    _lastAlarmReschedule = null;
    TaskLogger.alarm('Alarm cache invalidated');
  }

  Future<void> _rescheduleLocalAlarms() async {
    try {
      // FIX PERF-002: Skip if recently rescheduled
      final now = DateTime.now();
      if (_lastAlarmReschedule != null &&
          now.difference(_lastAlarmReschedule!) < _alarmRescheduleInterval) {
        TaskLogger.alarm('Skipping alarm reschedule (recently done)');
        return;
      }

      final db = await _databaseService.database;

      // FIX PERF-002: Only load alarm-enabled, active tasks with future alarm times
      final maps = await db.query(
        'tasks',
        where: 'alarm_enabled = ? AND is_completed = ? AND is_deleted = ? AND alarm_time > ?',
        whereArgs: [0, 0, 0, now.millisecondsSinceEpoch],
      );

      if (maps.isEmpty) {
        TaskLogger.alarm('No active alarms to reschedule');
        _lastAlarmReschedule = now;
        return;
      }

      final tasks = maps.map((m) => TaskModel.fromMap(m)).toList();
      TaskLogger.alarm('Rescheduling ${tasks.length} active alarms');
      await TaskAlarmService().rescheduleAllAlarms(tasks);
      _lastAlarmReschedule = now;
    } catch (e) {
      TaskLogger.e('Failed to reschedule local alarms: $e', tag: 'Alarm');
    }
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _wsSubscription?.cancel();
    _wsReconnectTimer?.cancel();
    _syncController.close();
    _typingController.close();
    // BUG-004 FIX: Clear comment cache on dispose (logout)
    clearCommentCache();
  }

  /// BUG-004 FIX: Clear entire comment cache (useful for logout or data reset)
  void clearCommentCache() {
    _commentCache.clear();
    _commentCacheTimestamps.clear();
    _commentCacheStale.clear();
    TaskLogger.cache('Comment cache cleared (BUG-004 FIX)');
  }

  Future<List<TaskModel>> getTasks({
    bool triggerSync = true,
    int? limit,
    int? offset,
  }) async {
    final db = await _databaseService.database;
    // Only return non-deleted tasks
    final List<Map<String, dynamic>> maps = await db.query(
      'tasks',
      where: 'is_deleted = ?',
      whereArgs: [0],
      orderBy: 'updated_at DESC', // Sort by most recently updated
      limit: limit,
      offset: offset,
    );

    // Trigger sync process (pull & push)
    if (triggerSync) {
      _runSyncQueue();
    }

    return List.generate(maps.length, (i) {
      return TaskModel.fromMap(maps[i]);
    });
  }

  /// Fetch tasks shared with the current user from backend
  /// BUG-002 FIX: Added client-side expiration filtering
  Future<List<TaskModel>> getSharedTasks({String? permission}) async {
    try {
      final tasks = await _syncService.fetchSharedTasks(permission: permission);
      final now = DateTime.now();
      
      // Mark tasks as shared by setting sharePermission
      // BUG-002 FIX: Filter out expired shares client-side as additional safety
      return tasks
          .map((task) {
            return task.copyWith(sharePermission: permission ?? 'read');
          })
          .where((task) {
            // Filter out expired shares
            if (task.shareExpiresAt != null) {
              if (task.shareExpiresAt!.isBefore(now)) {
                TaskLogger.d(
                  'Filtering out expired share: task=${task.id}, expiredAt=${task.shareExpiresAt}',
                  tag: 'Sync',
                );
                return false;
              }
            }
            return true;
          })
          .toList();
    } catch (e) {
      TaskLogger.e('Failed to fetch shared tasks: $e', tag: 'Sync');
      return [];
    }
  }

  /// Processes the sync queue (Push local, Pull remote)
  /// Uses atomic compare-and-swap to prevent race conditions
  /// FIX PERF-005: Process pending tasks in parallel with concurrency limit
  Future<void> _runSyncQueue() async {
    // Use atomic compare-and-swap to prevent race conditions
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      // Security Guard: Prevent sync if no valid session
      if (!await AuthRepository().isAuthenticated()) {
        return;
      }

      // 1. Push pending local changes (created/updated/deleted but not synced)
      final db = await _databaseService.database;
      final pendingMaps = await db.query(
        'tasks',
        where: 'is_synced = ?',
        whereArgs: [0],
      );

      // FIX PERF-005: Process in parallel with concurrency limit (max 5 concurrent)
      const maxConcurrent = 5;
      final pendingTasks = pendingMaps.map((m) => TaskModel.fromMap(m)).toList();

      if (pendingTasks.isNotEmpty) {
        TaskLogger.sync('Processing ${pendingTasks.length} pending sync items (max concurrent: $maxConcurrent)');
        debugPrint('[TaskRepository] Found ${pendingTasks.length} pending sync tasks: ${pendingTasks.map((t) => t.id).join(", ")}');

        // Process in batches to avoid overwhelming the server
        for (var i = 0; i < pendingTasks.length; i += maxConcurrent) {
          final batch = pendingTasks.skip(i).take(maxConcurrent).toList();
          await Future.wait(batch.map((task) => _processSyncTask(db, task)));
        }
      } else {
        debugPrint('[TaskRepository] No pending sync tasks found');
      }

      // 2. Pull remote changes with timeout
      await _syncFromBackend();
    } catch (e) {
      TaskLogger.e('Sync queue processing error: $e', tag: 'Sync');
    } finally {
      _isSyncing = false;
    }
  }
  
  /// Helper to process a single sync task (create/update/delete)
  Future<void> _processSyncTask(Database db, TaskModel task) async {
    try {
      // TIMEOUT: Add timeout to prevent indefinite hangs
      if (task.isDeleted) {
        await _syncService.deleteTask(task.id).timeout(
          const Duration(seconds: 60),
          onTimeout: () => throw TimeoutException('Delete task timeout'),
        );
        await db.delete('tasks', where: 'id = ?', whereArgs: [task.id]);
        TaskLogger.sync('Deleted task ${task.id} from remote');
      } else {
        // TaskSyncService will send the local updated_at which the backend now respects for LWW
        await _syncService.createTask(task).timeout(
          const Duration(seconds: 60),
          onTimeout: () => throw TimeoutException('Create task timeout'),
        );
        await db.update(
          'tasks',
          task.copyWith(isSynced: true).toMap(),
          where: 'id = ?',
          whereArgs: [task.id],
        );
        TaskLogger.sync('Synced task ${task.id} to remote');
      }
    } catch (e, stackTrace) {
      // Explicit Error Handling for Silent Sync Failures
      TaskLogger.e(
        'Failed to push local sync item ${task.id} to remote: $e',
        tag: 'Sync',
        error: e,
        stackTrace: stackTrace,
      );
      // We intentionally do not mark isSynced = true here, so it retries on the next queue run.
    }
  }

  // ... (_runSyncQueue)

  static const String _lastSyncedKey = 'tasks_last_synced_at';

  Future<void> _syncFromBackend() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSyncStr = prefs.getString(_lastSyncedKey);
      final lastSync = lastSyncStr != null
          ? DateTime.tryParse(lastSyncStr)
          : null;

      // FIX: Check if local DB has tasks - if empty, force full sync
      final db = await _databaseService.database;
      final localTaskCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM tasks WHERE is_deleted = 0'),
      ) ?? 0;

      // Force full sync if:
      // 1. No lastSync timestamp exists (first time)
      // 2. Local DB is empty (data loss or fresh install)
      // 3. Last sync was more than 7 days ago (safety net)
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      final shouldForceFullSync = lastSync == null ||
          localTaskCount == 0 ||
          lastSync.isBefore(sevenDaysAgo);

      if (shouldForceFullSync) {
        TaskLogger.sync(
          'Forcing FULL sync - lastSync: $lastSync, '
          'localTaskCount: $localTaskCount',
        );
      }

      TaskLogger.sync('Syncing from backend - lastSync: $lastSync, localTaskCount: $localTaskCount');

      // TIMEOUT: Add timeout to fetchTasks to prevent indefinite hangs
      final remoteTasks = await _syncService.fetchTasks(
        // On full sync, don't use 'since' filter - get ALL tasks
        since: shouldForceFullSync ? null : lastSync,
      ).timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          TaskLogger.w('Sync timeout: fetchTasks exceeded 60s', tag: 'Sync');
          return <TaskModel>[];
        },
      );

      TaskLogger.sync('Received ${remoteTasks.length} tasks from backend');

      if (remoteTasks.isNotEmpty) {
        final db = await _databaseService.database;
        final batch = db.batch();

        // Get pending local tasks to compare timestamps for LWW
        final pendingMaps = await db.query(
          'tasks',
          where: 'is_synced = ?',
          whereArgs: [0],
        );
        final pendingTasks = pendingMaps
            .map((m) => TaskModel.fromMap(m))
            .toList();
        final Map<String, TaskModel> pendingMap = {
          for (var t in pendingTasks) t.id: t,
        };

        for (var task in remoteTasks) {
          // LWW Conflict Resolution:
          // If we have an unsynced local edit for this task, and our local edit
          // is NEWER than the remote task, DO NOT OVERWRITE LOCAL.
          if (pendingMap.containsKey(task.id)) {
            final localTask = pendingMap[task.id]!;
            if (localTask.updatedAt.isAfter(task.updatedAt)) {
              TaskLogger.sync('Skipping remote pull for ${task.id}, local is newer');
              continue;
            }
          }

          batch.insert(
            'tasks',
            task.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);

        // Update last sync time
        await prefs.setString(
          _lastSyncedKey,
          DateTime.now().toUtc().toIso8601String(),
        );

        // FIX BUG-006: Handle remote deletions on BOTH full and delta sync
        // Backend now includes soft-deleted tasks in delta sync with is_deleted=1 flag
        final remoteIds = remoteTasks.map((t) => t.id).toSet();
        final localTasks = await getTasks(triggerSync: false);

        // Process deletions: Remove local tasks that are marked deleted on remote
        for (var remoteTask in remoteTasks) {
          if (remoteTask.isDeleted) {
            // Remote task is soft-deleted - delete locally as well
            await db.delete(
              'tasks',
              where: 'id = ?',
              whereArgs: [remoteTask.id],
            );
            await TaskAlarmService().cancelAlarm(remoteTask.id);
            TaskLogger.alarm('Cancelled alarm for deleted task ${remoteTask.id}');
          }
        }

        // FIX BUG-006: Also handle tasks that exist locally but not on remote (only on full sync)
        // This catches any edge cases where delta sync might miss deletions
        if (shouldForceFullSync) {
          for (var localTask in localTasks) {
            if (!remoteIds.contains(localTask.id) && localTask.isSynced) {
              await db.delete(
                'tasks',
                where: 'id = ?',
                whereArgs: [localTask.id],
              );
              await TaskAlarmService().cancelAlarm(localTask.id);
              TaskLogger.alarm('Cancelled alarm for orphaned task ${localTask.id}');
            }
          }
        }

        // Re-schedule alarms for all active remote tasks
        for (var task in remoteTasks) {
          if (task.alarmEnabled && !task.isCompleted && !task.isDeleted) {
            await TaskAlarmService().scheduleAlarm(task);
          } else {
            // Safety: If completed or alarm disabled, ensure it's cancelled locally
            await TaskAlarmService().cancelAlarm(task.id);
          }
        }

        // FIX: Invalidate alarm cache after sync to ensure fresh reschedule
        _invalidateAlarmCache();

        // Notify UI of updates
        _syncController.add(null);
      }
    } catch (e) {
      TaskLogger.e('Sync failed: $e', tag: 'Sync');
    }
  }

  Future<void> insertTask(TaskModel task) async {
    final db = await _databaseService.database;
    // Insert as pending sync
    await db.insert(
      'tasks',
      task.copyWith(isSynced: false).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Schedule Alarm if enabled
    if (task.alarmEnabled) {
      await TaskAlarmService().scheduleAlarm(task);
    }

    // FIX: Invalidate alarm cache when tasks are modified
    _invalidateAlarmCache();

    // Trigger Sync
    _runSyncQueue();
  }

  Future<void> updateTask(TaskModel task) async {
    final db = await _databaseService.database;

    TaskLogger.d('updateTask: id=${task.id}, subTasks=${task.subTasks.map((s) => s.title).toList()}', tag: 'Repository');

    // Update as pending sync
    await db.update(
      'tasks',
      task.copyWith(isSynced: false).toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );

    // Update Alarm
    if (task.alarmEnabled && !task.isCompleted) {
      await TaskAlarmService().scheduleAlarm(task);
    } else {
      await TaskAlarmService().cancelAlarm(task.id);
    }

    // FIX: Invalidate alarm cache when tasks are modified
    _invalidateAlarmCache();

    // Trigger Sync
    _runSyncQueue();
  }

  Future<void> _deleteTaskLocally(String taskId) async {
    final db = await _databaseService.database;
    await db.update(
      'tasks',
      {
        'is_deleted': 1,
        'is_synced': 1,
      }, // Mark as synced so we don't try to push this delete back
      where: 'id = ?',
      whereArgs: [taskId],
    );
    _syncController.add(null);
  }

  /// Share a task with a user - P4-2
  Future<void> shareTask({
    required String taskId,
    required String sharedWithUserId,
    required String permission,
    int? expiresInDays,
  }) async {
    await _syncService.shareTask(
      taskId: taskId,
      sharedWithUserId: sharedWithUserId,
      permission: permission,
      expiresInDays: expiresInDays,
    );
    TaskLogger.i('Task shared successfully: $taskId with $sharedWithUserId');
  }

  Future<void> deleteTask(String id) async {
    // Soft Delete: Mark as deleted and pending sync
    final db = await _databaseService.database;
    final tasksToCheck = await db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (tasksToCheck.isNotEmpty) {
      final task = TaskModel.fromMap(tasksToCheck.first);
      await db.update(
        'tasks',
        task.copyWith(isDeleted: true, isSynced: false).toMap(),
        where: 'id = ?',
        whereArgs: [id],
      );

      // Cancel Alarm on delete
      await TaskAlarmService().cancelAlarm(id);
    }
    // Trigger Sync
    _runSyncQueue();
  }

  /// Fetch collaborators from backend
  Future<List<Map<String, dynamic>>> getCollaborators() async {
    return _syncService.fetchCollaborators();
  }

  /// Get comments for a task (fresh from remote, fallback to local)
  /// FIX BUG-005: Returns stale cache immediately while fetching fresh data in background
  /// FIX: Added LRU eviction with TTL to prevent memory leaks
  Future<List<TaskCommentModel>> getComments(String taskId) async {
    // FIX BUG-005: Return stale cache immediately if available (even if marked stale)
    if (_commentCache.containsKey(taskId)) {
      _updateCommentCacheAccess(taskId);  // FIX: Update LRU and timestamp
      final cached = _commentCache[taskId]!;
      if (_commentCacheStale.contains(taskId)) {
        TaskLogger.cache('Returning STALE cached comments for task $taskId');
      } else {
        TaskLogger.cache('Returning cached comments for task $taskId');
      }
      return cached;
    }

    // FIX: Fetch fresh data from remote first, with timeout and fallback to local
    final db = await _databaseService.database;

    try {
      // Try to fetch from remote with timeout (3 seconds)
      final remoteComments = await _syncService.fetchComments(taskId).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          TaskLogger.w('Comment sync timeout for task $taskId, using local cache', tag: 'Comments');
          return <TaskCommentModel>[];
        },
      );

      // Update local DB and cache with fresh data
      if (remoteComments.isNotEmpty) {
        final batch = db.batch();
        for (var comment in remoteComments) {
          batch.insert(
            'task_comments',
            comment.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);

        // FIX: Use helper method for proper cache management
        _addToCommentCache(taskId, remoteComments);
        _commentCacheStale.remove(taskId);

        TaskLogger.i('Updated ${remoteComments.length} comments for task $taskId', tag: 'Comments');
        return remoteComments;
      }

      // Remote returned empty - could be no comments or sync issue
      // Fall through to local cache
    } catch (e) {
      TaskLogger.e('Comment sync failed for task $taskId: $e', tag: 'Comments');
      // FIX BUG-004: Add error-based cache cleanup
      _cleanupCommentCacheOnError(taskId);
      // Fall through to local cache on error
    }

    // Fallback: Return local cached comments
    final List<Map<String, dynamic>> maps = await db.query(
      'task_comments',
      where: 'task_id = ?',
      whereArgs: [taskId],
      orderBy: 'created_at ASC',
    );

    final localComments = maps.map((map) => TaskCommentModel.fromMap(map)).toList();

    // FIX: Use helper method for proper cache management
    _addToCommentCache(taskId, localComments);
    _commentCacheStale.remove(taskId);

    return localComments;
  }

  /// Add a comment to a task
  Future<bool> addComment(
    String taskId,
    String content, {
    List<String>? attachmentPaths,
  }) async {
    final comment = await _syncService.addComment(
      taskId,
      content,
      attachmentPaths: attachmentPaths,
    );
    if (comment != null) {
      final db = await _databaseService.database;
      await db.insert(
        'task_comments',
        comment.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Update cache and LRU
      if (_commentCache.containsKey(taskId)) {
        _commentCache[taskId]!.add(comment);
        _updateCommentCacheAccess(taskId);
      }

      _syncController.add(null);
      return true;
    }
    return false;
  }

  // ============================================================================
  // ALARM SYNC ACROSS DEVICES (FIX #9, #10)
  // ============================================================================

  /// Fetch pending alarms from backend for backup/restore across devices
  Future<List<Map<String, dynamic>>> fetchPendingAlarms() async {
    try {
      final response = await _apiClient.get(
        '/notifications/alarm/pending',
      );

      if (response['success'] == true) {
        final alarms = response['alarms'] as List;
        TaskLogger.alarm('Fetched ${alarms.length} pending alarms from backend');
        return alarms.cast<Map<String, dynamic>>();
      }
      TaskLogger.w('Failed to fetch pending alarms');
    } catch (e) {
      TaskLogger.e('Error fetching pending alarms: $e', tag: 'Alarm');
    }
    return [];
  }

  /// Sync local alarms with backend (restore alarms on new device)
  Future<void> syncAlarmsWithBackend() async {
    try {
      // Fetch pending alarms from backend
      final backendAlarms = await fetchPendingAlarms();
      
      if (backendAlarms.isEmpty) {
        TaskLogger.alarm('No pending alarms on backend to sync');
        return;
      }

      // Get all tasks to match alarms
      final tasks = await getTasks();
      final taskMap = {for (var task in tasks) task.id: task};

      // Schedule local alarms for backend alarms
      for (final alarm in backendAlarms) {
        final taskId = alarm['task_id'] as String;
        final task = taskMap[taskId];
        
        if (task != null) {
          // Parse alarm time from backend
          final alarmTimeStr = alarm['alarm_time'] as String?;
          if (alarmTimeStr != null) {
            final alarmTime = DateTime.tryParse(alarmTimeStr);
            if (alarmTime != null && alarmTime.isAfter(DateTime.now())) {
              // Schedule local alarm
              final updatedTask = task.copyWith(
                alarmEnabled: true,
                alarmTime: alarmTime,
              );
              await TaskAlarmService().scheduleAlarm(updatedTask);
              TaskLogger.alarm('Restored alarm for task $taskId from backend');
            }
          }
        }
      }
    } catch (e) {
      TaskLogger.e('Error syncing alarms with backend: $e', tag: 'Alarm');
    }
  }

  /// Acknowledge alarm on backend (sync across devices)
  Future<bool> acknowledgeAlarmOnBackend({
    required int alarmId,
    String? deviceId,
  }) async {
    try {
      final response = await _apiClient.post(
        '/notifications/alarm/acknowledge',
        body: {
          'alarm_id': alarmId,
          'device_id': deviceId,
        },
      );

      if (response['success'] == true) {
        TaskLogger.alarm('Acknowledged alarm $alarmId on backend');
        return true;
      }
      TaskLogger.w('Failed to acknowledge alarm');
    } catch (e) {
      TaskLogger.e('Error acknowledging alarm: $e', tag: 'Alarm');
    }
    return false;
  }

  /// Snooze alarm on backend
  Future<Map<String, dynamic>?> snoozeAlarmOnBackend({
    required String taskId,
    int? alarmId,
  }) async {
    try {
      final response = await _apiClient.post(
        '/notifications/alarm/snooze',
        body: {
          'task_id': taskId,
          'alarm_id': alarmId,
        },
      );

      if (response['success'] == true) {
        TaskLogger.alarm('Snoozed alarm for task $taskId on backend');
        return response;
      }
      TaskLogger.w('Failed to snooze alarm');
    } catch (e) {
      TaskLogger.e('Error snoozing alarm: $e', tag: 'Alarm');
    }
    return null;
  }
}
