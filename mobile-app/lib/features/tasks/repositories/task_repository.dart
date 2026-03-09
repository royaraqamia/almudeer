import 'package:sqflite/sqflite.dart';
import '../models/task_model.dart';
import '../models/task_comment_model.dart';
import '../services/task_alarm_service.dart';
import '../../../core/services/local_database_service.dart';
import '../services/sync_service.dart';
import '../../../data/repositories/auth_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import '../../../core/services/websocket_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TaskRepository {
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

  // Comment cache for real-time updates - FIX: Add max size and LRU tracking
  final Map<String, List<TaskCommentModel>> _commentCache = {};
  final Set<String> _commentCacheStale = {};
  static const int _maxCommentCacheSize = 20;  // FIX: Limit cache size to prevent memory leak
  final List<String> _commentCacheAccessOrder = [];  // LRU tracking

  // FIX: Evict oldest entries when cache is full
  void _evictCommentCacheIfNeeded() {
    while (_commentCache.length >= _maxCommentCacheSize && _commentCacheAccessOrder.isNotEmpty) {
      final oldestKey = _commentCacheAccessOrder.removeAt(0);
      _commentCache.remove(oldestKey);
      _commentCacheStale.remove(oldestKey);
      debugPrint('TaskRepository: Evicted comment cache for task $oldestKey');
    }
  }

  // FIX: Update LRU order when accessing cache
  void _updateCommentCacheAccess(String taskId) {
    _commentCacheAccessOrder.remove(taskId);
    _commentCacheAccessOrder.add(taskId);
  }

  void _initWebSocket() {
    final ws = _webSocketService;
    if (ws == null) return;
    _wsSubscription?.cancel();
    _wsSubscription = ws.stream.listen((event) {
      if (event['event'] == 'task_sync') {
        final data = event['data'] as Map<String, dynamic>?;
        final taskId = data?['task_id'] as String?;
        final changeType = data?['change_type'] as String?;

        debugPrint(
          'TaskRepository: task_sync event received. ID: $taskId, Type: $changeType',
        );

        // Handle comment events separately for real-time updates
        if (changeType == 'comment' && taskId != null) {
          // FIX BUG-005: Mark as stale but don't remove - return stale data while fetching
          _commentCacheStale.add(taskId);
          debugPrint('TaskRepository: Comment cache marked stale for task $taskId');

          // Notify listeners to refresh comments
          _syncController.add(null);

          // Fetch fresh in background - don't await
          getComments(taskId).then((comments) {
            debugPrint('TaskRepository: Background comment refresh completed for $taskId');
          }).catchError((e) {
            debugPrint('TaskRepository: Background comment refresh failed for $taskId: $e');
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
    });
  }

  // FIX PERF-002: Cache last alarm reschedule to avoid unnecessary work
  DateTime? _lastAlarmReschedule;
  static const Duration _alarmRescheduleInterval = Duration(hours: 24);

  Future<void> _rescheduleLocalAlarms() async {
    try {
      // FIX PERF-002: Skip if recently rescheduled
      final now = DateTime.now();
      if (_lastAlarmReschedule != null &&
          now.difference(_lastAlarmReschedule!) < _alarmRescheduleInterval) {
        debugPrint('TaskRepository: Skipping alarm reschedule (recently done)');
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
        debugPrint('TaskRepository: No active alarms to reschedule');
        _lastAlarmReschedule = now;
        return;
      }
      
      final tasks = maps.map((m) => TaskModel.fromMap(m)).toList();
      debugPrint('TaskRepository: Rescheduling ${tasks.length} active alarms');
      await TaskAlarmService().rescheduleAllAlarms(tasks);
      _lastAlarmReschedule = now;
    } catch (e) {
      debugPrint('TaskRepository: Failed to reschedule local alarms: $e');
    }
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _wsSubscription?.cancel();
    _syncController.close();
    _typingController.close();
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
  Future<List<TaskModel>> getSharedTasks({String? permission}) async {
    try {
      final tasks = await _syncService.fetchSharedTasks(permission: permission);
      // Mark tasks as shared by setting sharePermission
      return tasks.map((task) {
        return task.copyWith(sharePermission: permission ?? 'read');
      }).toList();
    } catch (e) {
      debugPrint('[TaskRepository] Failed to fetch shared tasks: $e');
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
        debugPrint('TaskRepository: Processing ${pendingTasks.length} pending sync items (max concurrent: $maxConcurrent)');
        
        // Process in batches to avoid overwhelming the server
        for (var i = 0; i < pendingTasks.length; i += maxConcurrent) {
          final batch = pendingTasks.skip(i).take(maxConcurrent).toList();
          await Future.wait(batch.map((task) => _processSyncTask(db, task)));
        }
      }

      // 2. Pull remote changes with timeout
      await _syncFromBackend();
    } catch (e) {
      debugPrint('Sync queue processing error: $e');
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
          const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException('Delete task timeout'),
        );
        await db.delete('tasks', where: 'id = ?', whereArgs: [task.id]);
        debugPrint('TaskRepository: Deleted task ${task.id} from remote');
      } else {
        // TaskSyncService will send the local updated_at which the backend now respects for LWW
        await _syncService.createTask(task).timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException('Create task timeout'),
        );
        await db.update(
          'tasks',
          task.copyWith(isSynced: true).toMap(),
          where: 'id = ?',
          whereArgs: [task.id],
        );
        debugPrint('TaskRepository: Synced task ${task.id} to remote');
      }
    } catch (e, stackTrace) {
      // Explicit Error Handling for Silent Sync Failures
      debugPrint(
        'CRITICAL: Failed to push local sync item ${task.id} to remote: $e',
      );
      debugPrint('Stack trace: $stackTrace');
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
        debugPrint(
          'TaskRepository: Forcing FULL sync - lastSync: $lastSync, '
          'localTaskCount: $localTaskCount, sevenDaysAgo: $sevenDaysAgo',
        );
      }

      debugPrint('TaskRepository: Syncing from backend - lastSync: $lastSync, '
          'localTaskCount: $localTaskCount, forceFullSync: $shouldForceFullSync');

      // TIMEOUT: Add timeout to fetchTasks to prevent indefinite hangs
      final remoteTasks = await _syncService.fetchTasks(
        // On full sync, don't use 'since' filter - get ALL tasks
        since: shouldForceFullSync ? null : lastSync,
      ).timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          debugPrint('Sync timeout: fetchTasks exceeded 60s');
          return <TaskModel>[];
        },
      );

      debugPrint(
        'TaskRepository: Received ${remoteTasks.length} tasks from backend, '
        'first task subTasks: ${remoteTasks.isNotEmpty ? remoteTasks.first.subTasks.map((s) => s.title).toList() : "N/A"}',
      );

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
              debugPrint(
                'LWW Sync: Skipping remote pull for ${task.id}, local is newer.',
              );
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

        // Reliability Hardening: Handle remote deletions and Re-schedule alarms
        // FIX: Only check for deletions on FULL sync (when since=null)
        // On delta sync, missing tasks are just unchanged, not deleted
        if (shouldForceFullSync) {
          final remoteIds = remoteTasks.map((t) => t.id).toSet();
          final localTasks = await getTasks(triggerSync: false);

          // Delete local tasks that no longer exist on remote (only on full sync)
          for (var localTask in localTasks) {
            if (!remoteIds.contains(localTask.id) && localTask.isSynced) {
              await db.delete(
                'tasks',
                where: 'id = ?',
                whereArgs: [localTask.id],
              );
              await TaskAlarmService().cancelAlarm(localTask.id);
              debugPrint(
                'TaskRepository: Cancelled alarm for deleted task ${localTask.id}',
              );
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

        // Notify UI of updates
        _syncController.add(null);
      }
    } catch (e) {
      debugPrint('Sync failed: $e');
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

    // Trigger Sync
    _runSyncQueue();
  }

  Future<void> updateTask(TaskModel task) async {
    final db = await _databaseService.database;
    
    debugPrint(
      '[TaskRepository] updateTask: id=${task.id}, subTasks=${task.subTasks.map((s) => s.title).toList()}',
    );
    
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
    debugPrint('Task shared successfully: $taskId with $sharedWithUserId');
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
  /// FIX: Added LRU eviction to prevent memory leaks
  Future<List<TaskCommentModel>> getComments(String taskId) async {
    // FIX BUG-005: Return stale cache immediately if available (even if marked stale)
    if (_commentCache.containsKey(taskId)) {
      _updateCommentCacheAccess(taskId);  // FIX: Update LRU
      final cached = _commentCache[taskId]!;
      if (_commentCacheStale.contains(taskId)) {
        debugPrint('TaskRepository: Returning STALE cached comments for task $taskId (background refresh in progress)');
      } else {
        debugPrint('TaskRepository: Returning cached comments for task $taskId');
      }
      return cached;
    }

    // FIX: Evict old entries if needed before adding new one
    _evictCommentCacheIfNeeded();

    // FIX: Fetch fresh data from remote first, with timeout and fallback to local
    final db = await _databaseService.database;

    try {
      // Try to fetch from remote with timeout (3 seconds)
      final remoteComments = await _syncService.fetchComments(taskId).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('Comment sync timeout for task $taskId, using local cache');
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

        // Update cache, clear stale flag, and update LRU
        _commentCache[taskId] = remoteComments;
        _commentCacheStale.remove(taskId);
        _updateCommentCacheAccess(taskId);

        debugPrint('Updated ${remoteComments.length} comments for task $taskId');
        return remoteComments;
      }

      // Remote returned empty - could be no comments or sync issue
      // Fall through to local cache
    } catch (e) {
      debugPrint('Comment sync failed for task $taskId: $e');
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

    // Cache the local comments, clear stale flag, and update LRU
    _commentCache[taskId] = localComments;
    _commentCacheStale.remove(taskId);
    _updateCommentCacheAccess(taskId);

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
}
