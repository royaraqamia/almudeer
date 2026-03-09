import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import '../../../core/extensions/string_extension.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/colors.dart';
import '../../../features/tasks/providers/task_provider.dart';
import '../../widgets/animated_toast.dart';

class TaskBubble extends StatelessWidget {
  final Map<String, dynamic> taskData;
  final bool isOutgoing;
  final Color color;

  const TaskBubble({
    super.key,
    required this.taskData,
    required this.isOutgoing,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Robust key mapping for both local optimistic data and server response
    final title =
        taskData['title']?.toString() ??
        taskData['name']?.toString() ??
        taskData['TaskTitle']?.toString() ??
        taskData['task_title']?.toString() ??
        'مهمة';
    final description =
        taskData['description']?.toString() ??
        taskData['content']?.toString() ??
        taskData['body']?.toString() ??
        taskData['TaskDescription']?.toString() ??
        taskData['task_description']?.toString();
    final isCompleted =
        taskData['is_completed'] == true ||
        taskData['is_completed'] == 1 ||
        taskData['is_completed'] == 'true' ||
        taskData['is_completed'] == '1' ||
        taskData['completed'] == true ||
        taskData['completed'] == 1;

    DateTime? dueDate;
    if (taskData['due_date'] != null) {
      if (taskData['due_date'] is DateTime) {
        dueDate = taskData['due_date'] as DateTime;
      } else {
        dueDate = DateTime.tryParse(taskData['due_date'].toString());
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),  // Reduced from 7 for better text readability
        child: Container(
          width: 280,
          margin: const EdgeInsets.only(bottom: 4),
          decoration: ShapeDecoration(
            color: isOutgoing
                ? color.withValues(alpha: 0.15)
                : (isDark
                      ? AppColors.hoverDark
                      : AppColors.hoverLight),
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(
                cornerRadius: 16,
                cornerSmoothing: 1,
              ),
              side: BorderSide(
                color: isOutgoing
                    ? Colors.white.withValues(alpha: 0.1)
                    : (isDark
                          ? Colors.white.withValues(alpha: 0.08)  // Increased from 0.05 for better definition
                          : Colors.black.withValues(alpha: 0.08)),
                width: 0.5,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with Gradient
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      isOutgoing
                          ? Colors.white.withValues(alpha: 0.1)
                          : (isCompleted ? Colors.green : color).withValues(
                              alpha: 0.1,
                            ),
                      Colors.transparent,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: isOutgoing
                          ? Colors.white.withValues(alpha: 0.1)
                          : (isDark
                                ? Colors.white.withValues(alpha: 0.08)  // Increased from 0.05
                                : Colors.black.withValues(alpha: 0.08)),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color:
                            (isOutgoing
                                    ? Colors.white
                                    : (isCompleted ? Colors.green : color))
                                .withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isCompleted
                            ? SolarBoldIcons.checkCircle
                            : SolarBoldIcons.clipboardList,
                        size: 14,
                        color: isOutgoing
                            ? Colors.white
                            : (isCompleted ? Colors.green : color),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title.isNotEmpty ? title : 'مهمة',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: isOutgoing
                              ? Colors.white
                              : (isCompleted
                                    ? theme.colorScheme.onSurface.withValues(
                                        alpha: 0.6,
                                      )
                                    : theme.colorScheme.onSurface),
                          fontWeight: FontWeight.bold,
                          decoration: isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!isOutgoing)
                      _SaveToTasksButton(
                        title: title,
                        description: description,
                        dueDate: dueDate,
                        alarmEnabled:
                            taskData['alarm_enabled'] == true ||
                            taskData['alarm_enabled'] == 1,
                        alarmTime: taskData['alarm_time'] != null
                            ? DateTime.tryParse(
                                taskData['alarm_time'].toString(),
                              )
                            : null,
                        recurrence: taskData['recurrence']?.toString(),
                      ),
                  ],
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (description != null && description.isNotEmpty) ...[
                      Text(
                        description.safeUtf16,
                        textDirection: description.direction,
                        textAlign: description.isArabic
                            ? TextAlign.right
                            : TextAlign.left,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isOutgoing
                              ? Colors.white.withValues(alpha: 0.9)
                              : theme.textTheme.bodySmall?.color,
                          height: 1.4,
                          fontSize: 13,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (dueDate != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: (isOutgoing ? Colors.white : theme.hintColor)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              SolarLinearIcons.calendar,
                              size: 12,
                              color: isOutgoing
                                  ? Colors.white.withValues(alpha: 0.7)
                                  : theme.hintColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              DateFormat.yMMMd('ar_AE').format(dueDate),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isOutgoing
                                    ? Colors.white.withValues(alpha: 0.7)
                                    : theme.hintColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaveToTasksButton extends StatefulWidget {
  final String title;
  final String? description;
  final DateTime? dueDate;
  final bool alarmEnabled;
  final DateTime? alarmTime;
  final String? recurrence;

  const _SaveToTasksButton({
    required this.title,
    this.description,
    this.dueDate,
    this.alarmEnabled = false,
    this.alarmTime,
    this.recurrence,
  });

  @override
  State<_SaveToTasksButton> createState() => _SaveToTasksButtonState();
}

class _SaveToTasksButtonState extends State<_SaveToTasksButton> {
  bool _isSaved = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _isSaved
          ? null
          : () async {
              try {
                await context.read<TaskProvider>().addTask(
                  title: widget.title,
                  description: widget.description,
                  dueDate: widget.dueDate,
                  alarmEnabled: widget.alarmEnabled,
                  alarmTime: widget.alarmTime,
                  recurrence: widget.recurrence,
                );
                if (mounted) {
                  setState(() {
                    _isSaved = true;
                  });
                  if (context.mounted) {
                    AnimatedToast.success(context, 'تمت الإضافة لمهامي');
                  }
                }
              } catch (e) {
                if (mounted && context.mounted) {
                  AnimatedToast.error(context, 'فشل الإضافة: $e');
                }
              }
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _isSaved
              ? AppColors.success.withValues(alpha: 0.2)
              : AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isSaved ? SolarBoldIcons.checkCircle : SolarBoldIcons.addCircle,
              size: 12,
              color: _isSaved ? AppColors.success : AppColors.primary,
            ),
            const SizedBox(width: 4),
            Text(
              _isSaved ? 'تم' : 'إضافة',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: _isSaved ? AppColors.success : AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
