import 'dart:convert';
import 'package:flutter/foundation.dart';

enum TaskPriority { low, medium, high, urgent }

extension TaskPriorityExtension on TaskPriority {
  String get label {
    switch (this) {
      case TaskPriority.low:
        return 'منخفضة';
      case TaskPriority.medium:
        return 'متوسطة';
      case TaskPriority.high:
        return 'عالية';
      case TaskPriority.urgent:
        return 'عاجلة';
    }
  }

  int get colorValue {
    switch (this) {
      case TaskPriority.low:
        return 0xFF6B7280;
      case TaskPriority.medium:
        return 0xFF2563EB;
      case TaskPriority.high:
        return 0xFFF59E0B;
      case TaskPriority.urgent:
        return 0xFFEF4444;
    }
  }
}

class SubTaskModel {
  final String id;
  final String title;
  final bool isCompleted;

  SubTaskModel({
    required this.id,
    required this.title,
    this.isCompleted = false,
  });

  SubTaskModel copyWith({String? id, String? title, bool? isCompleted}) {
    return SubTaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'title': title, 'is_completed': isCompleted};
  }

  factory SubTaskModel.fromMap(Map<String, dynamic> map) {
    return SubTaskModel(
      id: map['id'],
      title: map['title'],
      isCompleted: map['is_completed'] ?? false,
    );
  }
}

class TaskModel {
  final String id;
  final String title;
  final String? description;
  final bool isCompleted;
  final DateTime? dueDate;
  final bool alarmEnabled;
  final DateTime? alarmTime;
  final String? recurrence;
  final List<SubTaskModel> subTasks;
  final String? category;
  final double orderIndex;
  final String? createdBy;
  final String? assignedTo;
  final List<Map<String, dynamic>> attachments;
  final DateTime createdAt;
  final DateTime updatedAt;
  final TaskPriority priority;

  final String visibility; // 'shared' or 'private'
  // P4-2: Sharing support
  final String? sharePermission; // 'read', 'edit', 'admin' - for tasks shared with user
  final DateTime? shareExpiresAt; // Expiration time for shared access (BUG-002 FIX)

  TaskModel({
    required this.id,
    required this.title,
    this.description,
    this.isCompleted = false,
    this.dueDate,
    this.alarmEnabled = false,
    this.alarmTime,
    this.recurrence,
    this.subTasks = const [],
    this.category,
    this.orderIndex = 0.0,
    this.createdBy,
    this.assignedTo,
    this.attachments = const [],
    this.visibility = 'shared',
    this.priority = TaskPriority.medium,
    this.sharePermission,
    this.shareExpiresAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isSynced = true,
    this.isDeleted = false,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final bool isSynced;
  final bool isDeleted;

  TaskModel copyWith({
    String? id,
    String? title,
    String? description,
    bool? isCompleted,
    DateTime? dueDate,
    bool? alarmEnabled,
    DateTime? alarmTime,
    String? recurrence,
    List<SubTaskModel>? subTasks,
    String? category,
    double? orderIndex,
    String? createdBy,
    String? assignedTo,
    List<Map<String, dynamic>>? attachments,
    String? visibility,
    TaskPriority? priority,
    String? sharePermission,
    DateTime? shareExpiresAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isSynced,
    bool? isDeleted,
  }) {
    return TaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      isCompleted: isCompleted ?? this.isCompleted,
      dueDate: dueDate ?? this.dueDate,
      alarmEnabled: alarmEnabled ?? this.alarmEnabled,
      alarmTime: alarmTime ?? this.alarmTime,
      recurrence: recurrence ?? this.recurrence,
      subTasks: subTasks ?? this.subTasks,
      category: category ?? this.category,
      orderIndex: orderIndex ?? this.orderIndex,
      createdBy: createdBy ?? this.createdBy,
      assignedTo: assignedTo ?? this.assignedTo,
      attachments: attachments ?? this.attachments,
      visibility: visibility ?? this.visibility,
      priority: priority ?? this.priority,
      sharePermission: sharePermission ?? this.sharePermission,
      shareExpiresAt: shareExpiresAt ?? this.shareExpiresAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'is_completed': isCompleted ? 1 : 0,
      'due_date': dueDate?.millisecondsSinceEpoch,
      'alarm_enabled': alarmEnabled ? 1 : 0,
      'alarm_time': alarmTime?.millisecondsSinceEpoch,
      'recurrence': recurrence,
      'sub_tasks': subTasks.isEmpty
          ? null
          : jsonEncode(subTasks.map((s) => s.toMap()).toList()),
      'category': category,
      'order_index': orderIndex,
      'created_by': createdBy,
      'assigned_to': assignedTo,
      'attachments': attachments.isEmpty ? null : jsonEncode(attachments),
      'visibility': visibility,
      'priority': priority.index,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'is_synced': isSynced ? 1 : 0,
      'is_deleted': isDeleted ? 1 : 0,
      // P4-2: Share permission
      'share_permission': sharePermission,
      // BUG-002 FIX: Share expiration
      'share_expires_at': shareExpiresAt?.millisecondsSinceEpoch,
    };
  }

  factory TaskModel.fromMap(Map<String, dynamic> map) {
    List<SubTaskModel> parsedSubTasks = [];
    if (map['sub_tasks'] != null && map['sub_tasks'] is String) {
      try {
        final List<dynamic> decoded = jsonDecode(map['sub_tasks']);
        parsedSubTasks = decoded
            .map((s) => SubTaskModel.fromMap(s as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('Error decoding subtasks: $e');
      }
    }

    List<Map<String, dynamic>> parsedAttachments = [];
    if (map['attachments'] != null && map['attachments'] is String) {
      try {
        final List<dynamic> decoded = jsonDecode(map['attachments']);
        parsedAttachments = decoded
            .map((s) => Map<String, dynamic>.from(s))
            .toList();
      } catch (e) {
        debugPrint('Error decoding attachments: $e');
      }
    }

    return TaskModel(
      id: map['id'],
      title: map['title'],
      description: map['description'],
      isCompleted: (map['is_completed'] ?? 0) == 1,
      dueDate: map['due_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['due_date'])
          : null,
      alarmEnabled: (map['alarm_enabled'] ?? 0) == 1,
      alarmTime: map['alarm_time'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['alarm_time'])
          : null,
      recurrence: map['recurrence'],
      subTasks: parsedSubTasks,
      category: map['category'],
      orderIndex: (map['order_index'] ?? 0.0).toDouble(),
      createdBy: map['created_by'],
      assignedTo: map['assigned_to'],
      attachments: parsedAttachments,
      visibility: map['visibility'] ?? 'shared',
      // FIX: Use _parsePriority which has proper bounds checking
      priority: _parsePriority(map['priority']),
      // P4-2: Share permission - backend returns 'share_permission'
      sharePermission: map['share_permission'],
      // BUG-002 FIX: Share expiration
      shareExpiresAt: map['share_expires_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['share_expires_at'])
          : null,
      createdAt: map['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['created_at'])
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'])
          : null,
      isSynced: (map['is_synced'] ?? 1) == 1,
      isDeleted: (map['is_deleted'] ?? 0) == 1,
    );
  }

  // API Serialization - FIX BUG-003: Send priority as string name, not index
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'is_completed': isCompleted,
      'due_date': dueDate?.toIso8601String(),
      'alarm_enabled': alarmEnabled,
      'alarm_time': alarmTime?.toIso8601String(),
      'recurrence': recurrence,
      'sub_tasks': subTasks.map((s) => s.toMap()).toList(),
      'category': category,
      'order_index': orderIndex,
      'created_by': createdBy,
      'assigned_to': assignedTo,
      'attachments': attachments,
      'visibility': visibility,
      'priority': priority.name,  // FIX: Send as string ('low', 'medium', 'high', 'urgent')
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    // P4-2 FIX: Backend may return JSON strings instead of parsed lists
    // Parse sub_tasks
    List? subTasksList;
    final subTasksData = json['sub_tasks'];
    if (subTasksData is String) {
      // Parse JSON string to list
      try {
        final parsed = jsonDecode(subTasksData);
        if (parsed is List) {
          subTasksList = parsed;
        }
      } catch (e) {
        debugPrint('Failed to parse sub_tasks JSON: $e');
      }
    } else if (subTasksData is List) {
      subTasksList = subTasksData;
    }

    // Parse attachments
    List? attachmentsList;
    final attachmentsData = json['attachments'];
    if (attachmentsData is String) {
      // Parse JSON string to list
      try {
        final parsed = jsonDecode(attachmentsData);
        if (parsed is List) {
          attachmentsList = parsed;
        }
      } catch (e) {
        debugPrint('Failed to parse attachments JSON: $e');
      }
    } else if (attachmentsData is List) {
      attachmentsList = attachmentsData;
    }

    return TaskModel(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      isCompleted: json['is_completed'] ?? false,
      dueDate: json['due_date'] != null
          ? DateTime.tryParse(json['due_date'])
          : null,
      alarmEnabled: json['alarm_enabled'] ?? false,
      alarmTime: json['alarm_time'] != null
          ? DateTime.tryParse(json['alarm_time'])
          : null,
      recurrence: json['recurrence'],
      subTasks: subTasksList
          ?.whereType<Map<String, dynamic>>()
          .map((s) => SubTaskModel.fromMap(s))
          .toList() ??
      [],
      category: json['category'],
      orderIndex: (json['order_index'] ?? 0.0).toDouble(),
      createdBy: json['created_by'],
      assignedTo: json['assigned_to'],
      attachments: attachmentsList
          ?.whereType<Map<String, dynamic>>()
          .map((s) => Map<String, dynamic>.from(s))
          .toList() ??
      [],
      visibility: json['visibility'] ?? 'shared',
      // FIX BUG-003: Handle both string and int priority formats
      priority: _parsePriority(json['priority']),
      // P4-2: Share permission - backend returns 'share_permission'
      sharePermission: json['share_permission'],
      // BUG-002 FIX: Share expiration
      shareExpiresAt: json['share_expires_at'] != null
          ? DateTime.tryParse(json['share_expires_at'])
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'])
          : null,
    );
  }
  
  // FIX BUG-003: Helper to parse priority from both string and int formats
  static TaskPriority _parsePriority(dynamic priority) {
    if (priority is String) {
      // Backend format: 'low', 'medium', 'high', 'urgent'
      return TaskPriority.values.firstWhere(
        (p) => p.name == priority,
        orElse: () => TaskPriority.medium,
      );
    } else if (priority is int) {
      // Legacy mobile format: 0, 1, 2, 3
      if (priority >= 0 && priority < TaskPriority.values.length) {
        return TaskPriority.values[priority];
      }
      // FIX: Log warning for invalid priority value
      debugPrint('TaskModel: Invalid priority int value: $priority, expected 0-3, defaulting to medium');
    } else if (priority != null) {
      // Log for unexpected types
      debugPrint('TaskModel: Unexpected priority type: ${priority.runtimeType}, value: $priority, defaulting to medium');
    }
    return TaskPriority.medium;  // Default
  }

  /// Check if task is overdue (not completed and due date is in the past)
  bool get isOverdue {
    if (isCompleted || dueDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    return due.isBefore(today);
  }
}
