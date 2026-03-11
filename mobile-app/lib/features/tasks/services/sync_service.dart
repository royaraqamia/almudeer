import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/api/api_client.dart';
import '../models/task_model.dart';
import '../models/task_comment_model.dart';

class TaskSyncService {
  final ApiClient _apiClient = ApiClient();
  final String _endpoint = '/api/tasks';

  /// Fetch tasks from backend with optional pagination and delta sync
  /// FIX PERF-003: Added cursor-based pagination support for better performance
  Future<List<TaskModel>> fetchTasks({
    DateTime? since,
    int? limit,
    int? offset,
    String? cursor, // NEW: Cursor for pagination
  }) async {
    try {
      final Map<String, String> queryParams = {};
      if (since != null) {
        queryParams['since'] = since.toUtc().toIso8601String();
      }
      if (limit != null) {
        queryParams['limit'] = limit.toString();
      }
      if (offset != null) {
        queryParams['offset'] = offset.toString();
      }
      if (cursor != null) {
        queryParams['cursor'] = cursor; // NEW: Use cursor for pagination
      }
      final response = await _apiClient.get(
        '$_endpoint/',
        queryParams: queryParams.isEmpty ? null : queryParams,
      );

      // Log first task's sub_tasks for debugging
      String? firstTaskSubTasks;
      int taskCount = 0;

      final dataObj = response['data'] as List?;
      if (dataObj != null) {
        taskCount = dataObj.length;
        if (dataObj.isNotEmpty) {
          final firstMap = dataObj[0] as Map<String, dynamic>?;
          firstTaskSubTasks = firstMap?['sub_tasks']?.toString();
        }
      }

      debugPrint(
        '[TaskSyncService] fetchTasks response: $taskCount tasks, '
        'first task sub_tasks: $firstTaskSubTasks',
      );

      // Handle response format: {'data': [...]} - wrapped format
      final List<TaskModel> result = [];

      if (dataObj != null) {
        for (var e in dataObj) {
          result.add(TaskModel.fromJson(e as Map<String, dynamic>));
        }
      }
      return result;
    } catch (e) {
      debugPrint('Error fetching tasks: $e');
      // Return empty list on error during sync, or rethrow?
      // Rethrow so repository knows sync failed.
      rethrow;
    }
  }

  /// Create task on backend with proper error handling for attachments
  Future<TaskModel> createTask(TaskModel task) async {
    final attachments = task.attachments;
    final List<MapEntry<String, String>> filesToUpload = [];

    // Filter out local files that need to be uploaded
    for (var i = 0; i < attachments.length; i++) {
      final attachment = attachments[i];
      if (attachment['path'] != null && attachment['url'] == null) {
        filesToUpload.add(MapEntry('files', attachment['path']));
      }
    }

    // Prepare task_json with attachments that only have URLs (not local paths)
    // The backend will add uploaded files to the attachments list
    final taskJson = task.toJson();
    taskJson['attachments'] = attachments
        .where((a) => a['url'] != null)
        .toList();

    try {
      if (filesToUpload.isNotEmpty) {
        final response = await _apiClient.uploadMultipleFiles(
          '$_endpoint/',
          files: filesToUpload,
          fields: {'task_json': jsonEncode(taskJson)},
        );
        return TaskModel.fromJson(response);
      } else {
        // Even without files, the backend expects task_json as a form field now
        final response = await _apiClient.uploadMultipleFiles(
          '$_endpoint/',
          files: [],
          fields: {'task_json': jsonEncode(taskJson)},
        );
        return TaskModel.fromJson(response);
      }
    } on ApiException catch (e) {
      debugPrint(
        'TaskSyncService: Failed to create task - API Error: ${e.message}, StatusCode: ${e.statusCode}',
      );
      debugPrint('Task ID: ${task.id}, Title: ${task.title}');
      debugPrint(
        'Attachments count: ${attachments.length}, Files to upload: ${filesToUpload.length}',
      );
      // Re-throw with localized message
      throw _createLocalizedApiException(e, 'إضافة المهمة');
    } catch (e, st) {
      debugPrint('TaskSyncService: Failed to create task with attachments: $e');
      debugPrint('Stack trace: $st');
      // Re-throw with localized message
      throw Exception('فشل إضافة المهمة. يرجى المحاولة مرة أخرى');
    }
  }

  /// Create localized exception from API error
  Exception _createLocalizedApiException(ApiException e, String operation) {
    // Default localized messages based on status code
    if (e.statusCode == 400) {
      // Try to extract message from ApiException
      if (e.message.isNotEmpty) {
        return Exception(e.message);
      }
      return Exception('بيانات $operation غير صحيحة');
    } else if (e.statusCode == 401) {
      return Exception('غير مصرح لك بـ $operation');
    } else if (e.statusCode == 403) {
      return Exception('ليس لديك صلاحية $operation');
    } else if (e.statusCode == 404) {
      return Exception('$operation غير موجودة');
    } else if (e.statusCode == 409) {
      return Exception('حدث تعارض أثناء $operation. يرجى المحاولة مرة أخرى');
    } else if (e.statusCode == 413) {
      return Exception('حجم الملف يتجاوز الحد المسموح');
    }
    // Default message with error code for debugging
    return Exception(
      'فشل $operation (${e.statusCode ?? 0}). يرجى المحاولة مرة أخرى',
    );
  }

  /// Update task on backend with proper error handling for attachments
  Future<TaskModel> updateTask(TaskModel task) async {
    final attachments = task.attachments;
    final List<MapEntry<String, String>> filesToUpload = [];

    for (var i = 0; i < attachments.length; i++) {
      final attachment = attachments[i];
      if (attachment['path'] != null && attachment['url'] == null) {
        filesToUpload.add(MapEntry('files', attachment['path']));
      }
    }

    // Prepare task_json with attachments that only have URLs (not local paths)
    // The backend will add uploaded files to the attachments list
    final taskJson = task.toJson();
    taskJson['attachments'] = attachments
        .where((a) => a['url'] != null)
        .toList();

    debugPrint(
      '[TaskSyncService] updateTask: id=${task.id}, subTasks=${task.subTasks.map((s) => s.title).toList()}, '
      'taskJson[sub_tasks]=${taskJson['sub_tasks']}',
    );

    try {
      // Upload with PUT method for update endpoint
      final response = await _apiClient.uploadMultipleFiles(
        '$_endpoint/${task.id}',
        method: 'PUT',
        files: filesToUpload,
        fields: {'task_json': jsonEncode(taskJson)},
      );
      debugPrint(
        '[TaskSyncService] updateTask response: id=${task.id}, '
        'responseSubTasks=${response['sub_tasks']}',
      );
      return TaskModel.fromJson(response);
    } on ApiException catch (e) {
      debugPrint(
        'TaskSyncService: Failed to update task - API Error: ${e.message}, StatusCode: ${e.statusCode}',
      );
      throw _createLocalizedApiException(e, 'تحديث المهمة');
    } catch (e) {
      debugPrint('TaskSyncService: Failed to update task with attachments: $e');
      throw Exception('فشل تحديث المهمة. يرجى المحاولة مرة أخرى');
    }
  }

  /// Delete task from backend
  Future<void> deleteTask(String taskId) async {
    await _apiClient.delete('$_endpoint/$taskId');
  }

  /// Share a task with a user - P4-2
  /// FIX BUG #2: Add proper error handling with localized messages
  Future<Map<String, dynamic>> shareTask({
    required String taskId,
    required String sharedWithUserId,
    required String permission,
    int? expiresInDays,
  }) async {
    try {
      final response = await _apiClient.post(
        '$_endpoint/$taskId/share',
        body: {
          'shared_with_user_id': sharedWithUserId,
          'permission': permission,
          'expires_in_days': expiresInDays,
        },
      );

      // Check for backend error response
      if (response['success'] != true) {
        final detail = response['detail'];
        final errorMessage =
            detail?['message_ar'] ??
            detail?['message_en'] ??
            'فشل مشاركة المهمة';
        throw Exception(errorMessage);
      }

      return response;
    } on ApiException catch (e) {
      debugPrint('[SyncService] Share task API error: $e');
      // Handle specific HTTP status codes
      if (e.statusCode == 403) {
        throw Exception('ليس لديك صلاحية مشاركة هذه المهمة');
      } else if (e.statusCode == 404) {
        throw Exception('المهمة غير موجودة');
      } else if (e.statusCode == 400) {
        throw Exception(e.message);
      }
      rethrow;
    } catch (e) {
      debugPrint('[SyncService] Share task failed: $e');
      if (e is Exception) {
        rethrow;
      }
      throw Exception('حدث خطأ غير متوقع أثناء مشاركة المهمة');
    }
  }

  /// Fetch tasks shared with the current user - P4-2
  Future<List<TaskModel>> fetchSharedTasks({String? permission}) async {
    try {
      final Map<String, String> queryParams = {};
      if (permission != null) {
        queryParams['permission'] = permission;
      }

      final response = await _apiClient.get(
        '$_endpoint/shared-with-me',
        queryParams: queryParams.isEmpty ? null : queryParams,
      );

      debugPrint('[SyncService] fetchSharedTasks response: $response');

      // Extract tasks list from response
      dynamic tasksData;
      if (response.containsKey('tasks')) {
        tasksData = response['tasks'];
      } else if (response.containsKey('data')) {
        tasksData = response['data'];
      } else {
        tasksData = null;
      }

      if (tasksData == null || tasksData is! List) {
        debugPrint('[SyncService] No tasks found in response');
        return [];
      }

      debugPrint('[SyncService] Processing ${tasksData.length} tasks');
      if (tasksData.isNotEmpty) {
        debugPrint('[SyncService] First task: ${tasksData.first}');
        debugPrint(
          '[SyncService] First task sub_tasks type: ${(tasksData.first as Map)['sub_tasks']?.runtimeType}',
        );
        debugPrint(
          '[SyncService] First task attachments type: ${(tasksData.first as Map)['attachments']?.runtimeType}',
        );
      }

      return tasksData
          .whereType<Map<String, dynamic>>()
          .map((e) => TaskModel.fromJson(e))
          .toList();
    } catch (e, stackTrace) {
      debugPrint('Error fetching shared tasks: $e');
      debugPrint('Stack trace: $stackTrace');
      return [];
    }
  }

  /// Fetch all collaborators (users under same license)
  Future<List<Map<String, dynamic>>> fetchCollaborators() async {
    try {
      final response = await _apiClient.get('$_endpoint/collaborators');
      // Handle wrapped list format: {'data': [...]}
      if (response.containsKey('data') && response['data'] is List) {
        return List<Map<String, dynamic>>.from(response['data'] as List);
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching collaborators: $e');
      return [];
    }
  }

  Future<List<TaskCommentModel>> fetchComments(String taskId) async {
    try {
      final response = await _apiClient.get('$_endpoint/$taskId/comments');
      // Handle wrapped list format: {'data': [...]}
      if (response.containsKey('data') && response['data'] is List) {
        return (response['data'] as List)
            .map(
              (json) => TaskCommentModel.fromMap(json as Map<String, dynamic>),
            )
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching task comments: $e');
      return [];
    }
  }

  Future<TaskCommentModel?> addComment(
    String taskId,
    String content, {
    List<String>? attachmentPaths,
  }) async {
    try {
      final List<MapEntry<String, String>> filesToUpload = [];
      if (attachmentPaths != null) {
        for (final path in attachmentPaths) {
          filesToUpload.add(MapEntry('files', path));
        }
      }

      final response = await _apiClient.uploadMultipleFiles(
        '$_endpoint/$taskId/comments',
        files: filesToUpload,
        fields: {
          'comment_json': jsonEncode({'content': content}),
        },
      );

      // Backend returns the created comment directly or wrapped?
      // Based on routes/tasks.py it returns the result of add_task_comment
      // which is the comment dict.
      // ApiClient might wrap it if it's a list, but for dict it returns as is.

      return TaskCommentModel.fromMap(response);
    } catch (e) {
      debugPrint('Error adding task comment: $e');
      return null;
    }
  }

  Future<void> setTypingStatus(String taskId, bool isTyping) async {
    try {
      await _apiClient.post(
        '$_endpoint/$taskId/typing',
        body: {'is_typing': isTyping},
      );
    } catch (e) {
      debugPrint('Error sending task typing status: $e');
    }
  }
}
