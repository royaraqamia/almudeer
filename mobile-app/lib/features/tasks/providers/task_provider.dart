import 'package:flutter/material.dart';
import 'dart:async';
import 'package:uuid/uuid.dart';
import '../models/task_model.dart';
import '../models/task_comment_model.dart';
import '../repositories/task_repository.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../core/services/websocket_service.dart';
import '../services/task_alarm_service.dart';

enum TaskFilter { all, today, upcoming, completed }

class TaskProvider extends ChangeNotifier {
  final TaskRepository _repository;
  final AuthRepository _authRepository = AuthRepository();
  final WebSocketService? _webSocketService;

  StreamSubscription? _syncSubscription;
  StreamSubscription? _typingSubscription;

  // Error state for UI feedback
  String? _lastError;
  DateTime? _lastErrorTime; // ignore: unused_field

  // FIX: Sync failure state for UI indicator
  bool _hasSyncFailure = false;
  DateTime? _lastSyncFailureTime;
  String? _lastSyncFailureReason;

  // Retry state
  int _retryCount = 0;
  static const int _maxRetries = 3;

  // Typing state: task_id -> {user_id -> user_name}
  final Map<String, Map<String, String>> _taskTypingUsers = {};
  final Map<String, Timer?> _typingTimers = {};

  // FIX: Debounce for rapid toggle to prevent race conditions
  static const Duration _toggleDebounceMs = Duration(milliseconds: 500);
  static const Duration _togglePendingTTL = Duration(seconds: 5);
  final Map<String, DateTime?> _pendingToggles = {};

  // FIX: Cleanup for pending toggles to prevent memory leak
  void _cleanupPendingToggles() {
    final now = DateTime.now();
    _pendingToggles.removeWhere((key, timestamp) {
      return timestamp != null && now.difference(timestamp) > _togglePendingTTL;
    });
  }

  // Error getter
  String? get lastError => _lastError;
  bool get hasError => _lastError != null;

  // FIX: Sync failure getters for UI indicator
  bool get hasSyncFailure => _hasSyncFailure;
  DateTime? get lastSyncFailureTime => _lastSyncFailureTime;
  String? get lastSyncFailureReason => _lastSyncFailureReason;

  void _setError(String error) {
    _lastError = error;
    _lastErrorTime = DateTime.now();
    _retryCount = 0;
    notifyListeners();
  }

  void _clearError() {
    _lastError = null;
    _lastErrorTime = null;
    _retryCount = 0;
  }

  // FIX: Track sync failures for UI indicator
  void _trackSyncFailure(String reason) {
    _hasSyncFailure = true;
    _lastSyncFailureTime = DateTime.now();
    _lastSyncFailureReason = reason;
    debugPrint('TaskProvider: Sync failure tracked - $reason');
    notifyListeners();
  }

  void _clearSyncFailure() {
    if (_hasSyncFailure) {
      _hasSyncFailure = false;
      _lastSyncFailureTime = null;
      _lastSyncFailureReason = null;
      notifyListeners();
    }
  }

  bool get canRetry => _retryCount < _maxRetries;

  Future<void> retryLastOperation() async {
    if (!canRetry) {
      _setError('Maximum retries exceeded');
      return;
    }
    _retryCount++;
    _clearError();
    await loadTasks(triggerSync: true);
  }

  TaskProvider({TaskRepository? repository, WebSocketService? webSocketService})
    : _repository =
          repository ?? TaskRepository(webSocketService: webSocketService),
      _webSocketService = webSocketService {
    _syncSubscription = _repository.syncStream.listen((_) {
      loadTasks(triggerSync: false);
    });
    _typingSubscription = _repository.typingStream.listen((data) {
      _handleTypingEvent(data);
    });

    // Listen for WebSocket share events
    _webSocketService?.stream.listen((event) {
      final eventType = event['event'] as String?;
      if (eventType == 'task_shared') {
        debugPrint('[TaskProvider] Received task_shared event, refreshing tasks');
        // Refresh tasks to show the newly shared task
        loadTasks(triggerSync: false);
      }
    });

    loadCurrentUser();

    // Register callback for Interactive Notification Actions (e.g., Mark as Completed from notification)
    TaskAlarmService.setActionCallback((taskId, action) {
      if (action == TaskAlarmService.actionComplete) {
        final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
        if (taskIndex != -1) {
          toggleTaskStatus(_tasks[taskIndex]);
        }
      }
    });
  }

  void _handleTypingEvent(Map<String, dynamic> data) {
    final taskId = data['task_id'] as String?;
    final userId = data['user_id'] as String?;
    final userName = data['user_name'] as String?;
    final isTyping = data['is_typing'] as bool? ?? false;

    if (taskId == null || userId == null || userName == null) return;

    // Check if it's us (approximate check using email as id for now)
    if (userId == _currentUserEmail) return;

    if (!_taskTypingUsers.containsKey(taskId)) {
      _taskTypingUsers[taskId] = {};
    }

    if (isTyping) {
      _taskTypingUsers[taskId]![userId] = userName;

      // Reset timer to clear
      final timerKey = '${taskId}_$userId';
      _typingTimers[timerKey]?.cancel();
      _typingTimers[timerKey] = Timer(const Duration(seconds: 6), () {
        _taskTypingUsers[taskId]?.remove(userId);
        notifyListeners();
      });
    } else {
      _taskTypingUsers[taskId]?.remove(userId);
      final timerKey = '${taskId}_$userId';
      _typingTimers[timerKey]?.cancel();
    }

    notifyListeners();
  }

  Map<String, String> getTypingUsers(String taskId) =>
      _taskTypingUsers[taskId] ?? {};

  List<TaskModel> _tasks = [];
  List<Map<String, dynamic>> _collaborators = [];
  String? _currentUserEmail;
  String? _currentUserId; // Backend user_id (from JWT)
  bool _isLoading = false;
  TaskFilter _filter = TaskFilter.today;
  String _searchQuery = '';
  bool _isDisposed = false;
  int _loadGeneration = 0;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  static const int _pageSize = 50;

  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;

  List<TaskModel> get tasks => _tasks;
  List<Map<String, dynamic>> get collaborators => _collaborators;
  String? get currentUserEmail => _currentUserEmail;
  String? get currentUserId => _currentUserId; // Backend user_id
  bool get isLoading => _isLoading;
  TaskFilter get filter => _filter;
  TaskRepository get repository => _repository;
  String get searchQuery => _searchQuery;

  // FIX PERF-004: Enhanced cache with selective invalidation
  List<TaskModel>? _cachedFilteredTasks;
  TaskFilter? _cachedFilter;
  String? _cachedSearchQuery;
  int? _cachedTasksHash;
  DateTime? _cacheTimestamp;
  static const Duration _cacheValidity = Duration(milliseconds: 100);

  // Filtered tasks based on current filter selection and search query
  // FIX PERF-004: Enhanced memoization with selective re-computation
  List<TaskModel> get filteredTasks {
    // Quick check: if no tasks, return empty
    if (_tasks.isEmpty) {
      _cachedFilteredTasks = [];
      return _cachedFilteredTasks!;
    }

    // Check if cache is still valid (within validity window)
    final now = DateTime.now();
    final cacheValid = _cachedFilteredTasks != null &&
        _cacheTimestamp != null &&
        now.difference(_cacheTimestamp!) < _cacheValidity &&
        _cachedFilter == _filter &&
        _cachedSearchQuery == _searchQuery &&
        _cachedTasksHash == _tasks.length;

    if (cacheValid) {
      return _cachedFilteredTasks!;
    }

    // FIX PERF-004: Only recompute if filter/search changed or tasks were modified
    final needsRecompute = _cachedFilter != _filter ||
        _cachedSearchQuery != _searchQuery ||
        _cachedTasksHash != _tasks.length;

    if (needsRecompute) {
      _cachedFilteredTasks = _computeFilteredTasks();
      _cachedFilter = _filter;
      _cachedSearchQuery = _searchQuery;
      _cachedTasksHash = _tasks.length;
      _cacheTimestamp = now;
    }

    return _cachedFilteredTasks!;
  }

  // FIX PERF-004: Extract filtering logic to separate method
  List<TaskModel> _computeFilteredTasks() {
    List<TaskModel> filtered = _tasks;

    // 1. Apply Search
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered
          .where(
            (t) =>
                t.title.toLowerCase().contains(query) ||
                (t.description?.toLowerCase().contains(query) ?? false),
          )
          .toList();
    }

    // 2. Apply Category Filter - use early returns for efficiency
    switch (_filter) {
      case TaskFilter.today:
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        filtered = filtered.where((t) {
          if (t.isCompleted) return false;
          if (t.dueDate == null) return true;
          final due = DateTime(
            t.dueDate!.year,
            t.dueDate!.month,
            t.dueDate!.day,
          );
          return due.isAtSameMomentAs(today) || due.isBefore(today);
        }).toList();
        break;
      case TaskFilter.upcoming:
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        filtered = filtered.where((t) {
          if (t.isCompleted) return false;
          if (t.dueDate == null) return false;
          final due = DateTime(
            t.dueDate!.year,
            t.dueDate!.month,
            t.dueDate!.day,
          );
          return due.isAfter(today);
        }).toList();
        break;
      case TaskFilter.completed:
        filtered = filtered.where((t) => t.isCompleted).toList();
        break;
      case TaskFilter.all:
        // No filtering needed
        break;
    }

    return filtered;
  }

  // Specific Getters for Dashboard/Home
  List<TaskModel> get todayTasks => _tasks.where((t) {
    if (t.isCompleted) return false;
    if (t.dueDate == null) return true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
    return due.isAtSameMomentAs(today) || due.isBefore(today);
  }).toList();

  int get activeTaskCount => _tasks.where((t) => !t.isCompleted).length;
  int get completedTaskCount => _tasks.where((t) => t.isCompleted).length;

  void setFilter(TaskFilter filter) {
    _filter = filter;
    notifyListeners();
  }

  // Selection Mode
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};

  bool get isSelectionMode => _isSelectionMode;
  Set<String> get selectedIds => _selectedIds;
  int get selectedCount => _selectedIds.length;

  void toggleSelection(String id) {
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
      if (_selectedIds.isEmpty) {
        _isSelectionMode = false;
      }
    } else {
      _selectedIds.add(id);
      _isSelectionMode = true;
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedIds.clear();
    _isSelectionMode = false;
    notifyListeners();
  }

  Future<List<TaskModel>> bulkDelete() async {
    if (_selectedIds.isEmpty) return [];

    try {
      final idsToDelete = _selectedIds.toList();
      
      // Save removed tasks for potential undo
      final removedTasks = <TaskModel>[];
      for (final id in idsToDelete) {
        final task = _tasks.firstWhere((t) => t.id == id, orElse: () => TaskModel(id: '', title: ''));
        if (task.id.isNotEmpty) {
          removedTasks.add(task);
        }
      }

      // Optimistic removal
      _tasks.removeWhere((t) => _selectedIds.contains(t.id));
      clearSelection();

      // Perform deletion
      for (final id in idsToDelete) {
        await _repository.deleteTask(id);
      }

      // Final refresh to ensure sync
      loadTasks(triggerSync: true);
      
      return removedTasks;
    } catch (e) {
      debugPrint("Error in bulk delete: $e");
      loadTasks(triggerSync: true);
      return [];
    }
  }

  /// Undo bulk deletion
  Future<void> undoBulkDelete(List<TaskModel> tasks) async {
    for (final task in tasks) {
      final updatedTask = task.copyWith(isDeleted: false, isSynced: false);
      _tasks.add(updatedTask);
      try {
        await _repository.updateTask(updatedTask);
      } catch (e) {
        debugPrint("Error undoing bulk delete: $e");
      }
    }
    _sortTasks();
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// Get search results for global search
  List<TaskModel> get searchResults => filteredTasks;

  Future<void> loadTasks({bool triggerSync = true}) async {
    _isLoading = true;
    _loadGeneration++;
    final currentGeneration = _loadGeneration;
    _hasMore = true;
    _clearError();
    notifyListeners();

    try {
      final tasks = await _repository.getTasks(
        triggerSync: triggerSync,
        limit: _pageSize,
        offset: 0,
      );

      debugPrint(
        '[TaskProvider] loadTasks: loaded ${tasks.length} tasks, '
        'first task subTasks: ${tasks.isNotEmpty ? tasks.first.subTasks.map((s) => s.title).toList() : "N/A"}',
      );

      // Fetch shared tasks and merge them
      final sharedTasks = await _repository.getSharedTasks();
      debugPrint('[TaskProvider] Fetched ${sharedTasks.length} shared tasks');

      // Merge owned and shared tasks
      final allTasks = _mergeAndDeduplicateTasks(tasks, sharedTasks);

      if (currentGeneration != _loadGeneration) return;

      _tasks = allTasks;
      _sortTasks();
      _isLoading = false;

      if (allTasks.length < _pageSize) {
        _hasMore = false;
      }

      if (triggerSync || currentGeneration == 1) {
        TaskAlarmService().rescheduleAllAlarms(allTasks);
        loadCollaborators();
      }

      // FIX: Clear sync failure on successful load
      _clearSyncFailure();
    } catch (e) {
      debugPrint("Error loading tasks: $e");
      _isLoading = false;
      
      // FIX: Track sync failure for UI indicator
      _trackSyncFailure(e.toString());
      
      // Don't show error for offline - just keep showing cached data
      if (_tasks.isEmpty) {
        // Show empty state instead of error for offline scenarios
      }
      notifyListeners();
    }
  }

  Future<void> loadMoreTasks() async {
    if (_isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    notifyListeners();

    try {
      final additionalTasks = await _repository.getTasks(
        triggerSync: false,
        limit: _pageSize,
        offset: _tasks.length,
      );

      if (additionalTasks.isEmpty) {
        _hasMore = false;
      } else {
        _tasks.addAll(additionalTasks);
        _sortTasks();
        if (additionalTasks.length < _pageSize) {
          _hasMore = false;
        }
      }
    } catch (e) {
      debugPrint("Error loading more tasks: $e");
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> loadCurrentUser() async {
    try {
      final userInfo = await _authRepository.getUserInfo();
      _currentUserEmail =
          userInfo.username ?? userInfo.licenseKey?.substring(0, 20);
      _currentUserId = userInfo.licenseId?.toString(); // Backend uses license_id as user_id (JWT sub claim)
      notifyListeners();
    } catch (e) {
      debugPrint("Error loading current user: $e");
    }
  }

  Future<void> loadCollaborators() async {
    try {
      final collaborators = await _repository.getCollaborators();
      _collaborators = collaborators;
      notifyListeners();
    } catch (e) {
      debugPrint("Error loading collaborators: $e");
    }
  }

  Future<void> addTask({
    required String title,
    String? description,
    DateTime? dueDate,
    bool alarmEnabled = false,
    DateTime? alarmTime,
    String? recurrence,
    List<SubTaskModel> subTasks = const [],
    String? category,
    String? assignedTo,
    List<Map<String, dynamic>> attachments = const [],
    String visibility = 'shared',
    TaskPriority priority = TaskPriority.medium,
  }) async {
    final newTask = TaskModel(
      id: const Uuid().v4(),
      title: title,
      description: description,
      dueDate: dueDate,
      alarmEnabled: alarmEnabled,
      alarmTime: alarmTime,
      recurrence: recurrence,
      subTasks: subTasks,
      category: category,
      assignedTo: assignedTo,
      attachments: attachments,
      visibility: visibility,
      priority: priority,
      isCompleted: false,
      isSynced: false,
      createdBy: _currentUserId,
    );

    // Optimistic UI: Add to local list immediately
    _tasks.insert(0, newTask);
    _sortTasks();
    notifyListeners();

    try {
      await _repository.insertTask(newTask);

      // Schedule Alarm
      if (newTask.alarmEnabled) {
        await TaskAlarmService().scheduleAlarm(newTask);
      }
    } catch (e) {
      debugPrint("Error adding task: $e");
      // Rollback on failure
      _tasks.removeWhere((t) => t.id == newTask.id);
      _setError('فشل إضافة المهمة. يرجى المحاولة مرة أخرى');
      notifyListeners();
    }
  }

  Future<void> toggleTaskStatus(TaskModel task) async {
    // FIX: Debounce rapid toggles to prevent race conditions
    final now = DateTime.now();
    final lastToggle = _pendingToggles[task.id];
    if (lastToggle != null && now.difference(lastToggle) < _toggleDebounceMs) {
      debugPrint('toggleTaskStatus: Debouncing rapid toggle for task ${task.id}');
      return;
    }
    _pendingToggles[task.id] = now;

    final isNowCompleted = !task.isCompleted;
    final updatedTask = task.copyWith(
      isCompleted: isNowCompleted,
      isSynced: false,
      updatedAt: DateTime.now(),
    );

    // Optimistic UI: Update local list immediately
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index != -1) {
      _tasks[index] = updatedTask;
      _sortTasks();
      notifyListeners();
    }

    try {
      await _repository.updateTask(updatedTask);

      // Handle Alarm State Change
      if (updatedTask.isCompleted) {
        await TaskAlarmService().cancelAlarm(updatedTask.id);

        // Recurrence is now handled by the backend spawning a new task clone upon completion.
        // We do not bump the local task anymore to preserve history.
      } else if (updatedTask.alarmEnabled) {
        await TaskAlarmService().scheduleAlarm(updatedTask);
      }
    } catch (e) {
      debugPrint("Error toggling task status: $e");
      _setError('فشل تحديث حالة المهمة. يرجى المحاولة مرة أخرى');
      await loadTasks(triggerSync: false);
    } finally {
      // FIX: Cleanup old pending toggles to prevent memory leak
      _cleanupPendingToggles();
    }
  }

  Future<TaskModel?> deleteTask(String id, {bool showUndo = false}) async {
    // Optimistic UI: Remove from local list immediately
    TaskModel? removedTask;
    try {
      removedTask = _tasks.firstWhere((t) => t.id == id);
    } catch (_) {
      return null; // Task not found
    }

    _tasks.removeWhere((t) => t.id == id);
    notifyListeners();

    try {
      await TaskAlarmService().cancelAlarm(id);
      await _repository.deleteTask(id);

      // Return the removed task for potential undo
      return removedTask;
    } catch (e) {
      debugPrint("Error deleting task: $e");
      _setError('فشل حذف المهمة. يرجى المحاولة مرة أخرى');
      // Rollback
      _tasks.add(removedTask);
      _sortTasks();
      notifyListeners();
      return null;
    }
  }

  /// Undo a task deletion
  Future<void> undoDeleteTask(TaskModel task) async {
    // Restore the task
    final updatedTask = task.copyWith(isDeleted: false, isSynced: false);
    _tasks.add(updatedTask);
    _sortTasks();
    notifyListeners();
    
    try {
      await _repository.updateTask(updatedTask);
    } catch (e) {
      debugPrint("Error undoing delete: $e");
      // Remove again if restore fails
      _tasks.removeWhere((t) => t.id == task.id);
      notifyListeners();
    }
  }

  Future<void> updateTask(TaskModel task) async {
    final updatedTask = task.copyWith(
      isSynced: false,
      updatedAt: DateTime.now(),
    );

    debugPrint(
      '[TaskProvider] updateTask: id=${task.id}, subTasks=${task.subTasks.map((s) => s.title).toList()}',
    );

    // Optimistic UI
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index != -1) {
      _tasks[index] = updatedTask;
      _sortTasks();
      notifyListeners();
    }

    try {
      await _repository.updateTask(updatedTask);
      debugPrint('[TaskProvider] updateTask repository call completed');

      // Update Alarm
      if (updatedTask.alarmEnabled && !updatedTask.isCompleted) {
        await TaskAlarmService().scheduleAlarm(updatedTask);
      } else {
        await TaskAlarmService().cancelAlarm(updatedTask.id);
      }
    } catch (e) {
      debugPrint("Error updating task: $e");
      _setError('فشل تحديث المهمة. يرجى المحاولة مرة أخرى');
      await loadTasks(triggerSync: false);
    }
  }

  /// Share a task with a user (by username) - P4-2
  Future<void> shareTask({
    required String taskId,
    required String sharedWithUserId,
    required String permission,
    int? expiresInDays,
  }) async {
    try {
      await _repository.shareTask(
        taskId: taskId,
        sharedWithUserId: sharedWithUserId,
        permission: permission,
        expiresInDays: expiresInDays,
      );
    } catch (e) {
      debugPrint("Error sharing task: $e");
      rethrow;
    }
  }

  /// Assign a task to a user (by username) - DEPRECATED: Use shareTask instead
  @Deprecated('Use shareTask instead')
  Future<void> assignTask(String taskId, String username) async {
    debugPrint('assignTask is deprecated, use shareTask instead');
    // For backward compatibility, call shareTask with edit permission
    await shareTask(
      taskId: taskId,
      sharedWithUserId: username,
      permission: 'edit',
    );
  }


  Future<void> reorderTasks(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;

    // Adjust newIndex if moving downwards
    int effectiveNewIndex = newIndex;
    if (oldIndex < newIndex) {
      effectiveNewIndex -= 1;
    }

    if (oldIndex == effectiveNewIndex) return;

    final List<TaskModel> filtered = List.from(filteredTasks);
    
    // FIX: Validate indices are within bounds
    if (oldIndex < 0 || oldIndex >= filtered.length) {
      debugPrint('reorderTasks: Invalid oldIndex $oldIndex, list length: ${filtered.length}');
      return;
    }
    
    final TaskModel movedTask = filtered.removeAt(oldIndex);
    filtered.insert(effectiveNewIndex, movedTask);

    double newOrderIndex;

    if (filtered.length <= 1) {
      newOrderIndex = 0.0;
    } else if (effectiveNewIndex == 0) {
      // Moving to start - FIX: bounds check
      if (filtered.length > 1) {
        newOrderIndex = filtered[1].orderIndex - 1.0;
      } else {
        newOrderIndex = 0.0;
      }
    } else if (effectiveNewIndex == filtered.length - 1) {
      // Moving to end - FIX: bounds check
      newOrderIndex = filtered[effectiveNewIndex - 1].orderIndex + 1.0;
    } else {
      // Moving between two items - FIX: bounds check
      double prevIndex = filtered[effectiveNewIndex - 1].orderIndex;
      double nextIndex = (effectiveNewIndex + 1 < filtered.length) 
          ? filtered[effectiveNewIndex + 1].orderIndex 
          : prevIndex + 2.0;
      newOrderIndex = (prevIndex + nextIndex) / 2.0;
    }

    final updatedTask = movedTask.copyWith(orderIndex: newOrderIndex);

    // Update local main list
    final mainIndex = _tasks.indexWhere((task) => task.id == updatedTask.id);
    if (mainIndex != -1) {
      _tasks[mainIndex] = updatedTask;
    }

    _sortTasks();
    notifyListeners();

    // Persist only the moved task
    try {
      await _repository.updateTask(updatedTask);
    } catch (e) {
      debugPrint("Error persisting reorder: $e");
      // Rollback if needed or just reload
      await loadTasks(triggerSync: false);
    }
  }

  /// Merge owned and shared tasks, removing duplicates
  /// Owned tasks take precedence, shared tasks are marked with sharePermission
  /// FIX BUG #4: Properly preserve sharePermission from backend response
  List<TaskModel> _mergeAndDeduplicateTasks(
    List<TaskModel> ownedTasks,
    List<TaskModel> sharedTasks,
  ) {
    final Map<String, TaskModel> tasksMap = {};

    // Add owned tasks first (they take precedence)
    for (final task in ownedTasks) {
      tasksMap[task.id] = task;
    }

    // Add shared tasks that aren't already owned
    for (final task in sharedTasks) {
      if (!tasksMap.containsKey(task.id)) {
        // FIX BUG #4: Preserve the actual sharePermission from backend
        // Don't default to 'read' if backend explicitly returns null
        // Backend returns share_permission only for shared tasks (not owned)
        final effectivePermission = task.sharePermission;
        
        // Only set sharePermission if backend provided it
        // This ensures we don't incorrectly mark tasks
        if (effectivePermission != null) {
          tasksMap[task.id] = task.copyWith(sharePermission: effectivePermission);
        } else {
          // If backend didn't provide sharePermission, this might be an edge case
          // Log for debugging and default to 'read' for safety
          debugPrint(
            '[TaskProvider] Shared task ${task.id} has no sharePermission, '
            'defaulting to read'
          );
          tasksMap[task.id] = task.copyWith(sharePermission: 'read');
        }
      }
    }

    return tasksMap.values.toList();
  }

  void _sortTasks() {
    _tasks.sort((a, b) {
      if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;

      // Secondary sort: orderIndex
      if (a.orderIndex != b.orderIndex) {
        return a.orderIndex.compareTo(b.orderIndex);
      }

      // Tertiary sort: due date (nulls last)
      if (a.dueDate != b.dueDate) {
        if (a.dueDate == null) return 1;
        if (b.dueDate == null) return -1;
        return a.dueDate!.compareTo(b.dueDate!);
      }

      // Final fallback: newest first
      return b.createdAt.compareTo(a.createdAt);
    });
  }

  /// Get comments for a task
  Future<List<TaskCommentModel>> getComments(String taskId) async {
    return _repository.getComments(taskId);
  }

  /// Add a comment to a task
  Future<bool> addComment(
    String taskId,
    String content, {
    List<String>? attachmentPaths,
  }) async {
    final success = await _repository.addComment(
      taskId,
      content,
      attachmentPaths: attachmentPaths,
    );
    if (success) {
      await getComments(taskId);
    }
    return success;
  }

  bool? _lastTypingStatus;
  void setTypingStatus(String taskId, bool isTyping) {
    if (_lastTypingStatus == isTyping) return;
    _lastTypingStatus = isTyping;

    _repository.syncService
        .setTypingStatus(taskId, isTyping)
        .catchError((e) => debugPrint('Error sending task typing status: $e'));
  }

  /// Reset state (for account switching)
  void reset() {
    // Cancel subscriptions to prevent stale events
    _syncSubscription?.cancel();
    _syncSubscription = null;
    _typingSubscription?.cancel();
    _typingSubscription = null;

    _loadGeneration++;
    _tasks = [];
    _isLoading = false;
    _filter = TaskFilter.today;
    _searchQuery = '';
    _lastError = null;
    _selectedIds.clear();
    _taskTypingUsers.clear();
    _typingTimers.forEach((_, timer) => timer?.cancel());
    _typingTimers.clear();
    _pendingToggles.clear();
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;

    // Clear all collections to prevent memory leaks
    _tasks.clear();
    _collaborators.clear();
    _selectedIds.clear();
    _taskTypingUsers.clear();
    _cachedFilteredTasks = null;

    // Proper cleanup order: dispose repository first, then cancel subscriptions
    // This ensures no events are emitted to cancelled subscriptions
    try {
      _repository.dispose();
    } catch (e) {
      debugPrint('TaskProvider: Error disposing repository: $e');
    }

    _syncSubscription?.cancel();
    _typingSubscription?.cancel();

    // Cancel all typing timers
    for (var timer in _typingTimers.values) {
      timer?.cancel();
    }
    _typingTimers.clear();

    // Clear pending toggles
    _pendingToggles.clear();

    // Clear current user data
    _currentUserEmail = null;
    _currentUserId = null;

    super.dispose();
  }
}
