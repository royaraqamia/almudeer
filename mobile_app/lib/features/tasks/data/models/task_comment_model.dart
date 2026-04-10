import 'dart:convert';
import 'package:equatable/equatable.dart';

class TaskCommentModel extends Equatable {
  final String id;
  final String taskId;
  final String userId;
  final String? userName;
  final String content;
  final List<Map<String, dynamic>> attachments;
  final DateTime createdAt;

  const TaskCommentModel({
    required this.id,
    required this.taskId,
    required this.userId,
    this.userName,
    required this.content,
    this.attachments = const [],
    required this.createdAt,
  });

  factory TaskCommentModel.fromMap(Map<String, dynamic> map) {
    return TaskCommentModel(
      id: map['id'],
      taskId: map['task_id'],
      userId: map['user_id'],
      userName: map['user_name'],
      content: map['content'],
      attachments: map['attachments'] != null
          ? (map['attachments'] is String
                ? List<Map<String, dynamic>>.from(
                    json.decode(map['attachments']),
                  )
                : List<Map<String, dynamic>>.from(map['attachments']))
          : const [],
      createdAt: map['created_at'] is String
          ? DateTime.parse(map['created_at'])
          : map['created_at'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'task_id': taskId,
      'user_id': userId,
      'user_name': userName,
      'content': content,
      'attachments': json.encode(attachments),
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
    id,
    taskId,
    userId,
    userName,
    content,
    attachments,
    createdAt,
  ];
}
