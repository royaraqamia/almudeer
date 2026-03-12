import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:hijri/hijri_calendar.dart';
import '../../models/task_model.dart';
import '../../providers/task_provider.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/dimensions.dart';
import '../../../../core/constants/animations.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../core/extensions/string_extension.dart';
import '../screens/task_edit_screen.dart';
import 'package:figma_squircle/figma_squircle.dart';
import '../../../../presentation/widgets/animated_toast.dart';

class TaskListItem extends StatefulWidget {
  final TaskModel task;
  final bool isSelectionMode;
  final bool isSelected;
  final ValueChanged<bool>? onSelectionChanged;
  final VoidCallback? onComplete;

  const TaskListItem({
    super.key,
    required this.task,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelectionChanged,
    this.onComplete,
  });

  @override
  State<TaskListItem> createState() => _TaskListItemState();
}

class _TaskListItemState extends State<TaskListItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  TaskModel get task => widget.task;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppAnimations.fast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _controller, curve: AppAnimations.interactive),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isOverdue =
        widget.task.dueDate != null &&
        widget.task.dueDate!.isBefore(DateTime.now()) &&
        !widget.task.isCompleted;

    final cardColor = theme.brightness == Brightness.dark
        ? AppColors.surfaceCardDark
        : AppColors.surfaceCardLight;

    return RepaintBoundary(
      child: GestureDetector(
        onTapDown: (_) => _controller.forward(),
        onTapUp: (_) async {
          _controller.reverse();
          Haptics.lightTap();
          if (widget.isSelectionMode) {
            widget.onSelectionChanged?.call(!widget.isSelected);
          } else {
            final provider = context.read<TaskProvider>();
            final userId = provider.currentUserId;
            final canEdit = _canUserEditTask(widget.task, userId);

            if (!canEdit) {
              AnimatedToast.error(context, 'ليس لديك صلاحية تعديل هذه المهمة');
              return;
            }

            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TaskEditScreen(task: widget.task),
              ),
            );
          }
        },
        onTapCancel: () => _controller.reverse(),
        onLongPress: () {
          Haptics.mediumTap();
          widget.onSelectionChanged?.call(true);
        },
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: SizedBox(
                height: 72,
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.paddingMedium,
                    vertical: AppDimensions.paddingSmall,
                  ),
                  decoration: ShapeDecoration(
                    color: cardColor,
                    shape: SmoothRectangleBorder(
                      borderRadius: SmoothBorderRadius(
                        cornerRadius: AppDimensions.radiusXLarge,
                        cornerSmoothing: 1.0,
                      ),
                      side: widget.isSelected
                          ? const BorderSide(color: AppColors.primary, width: 2)
                          : BorderSide.none,
                    ),
                    shadows: [
                      BoxShadow(
                        color: isDark
                            ? AppColors.shadowPrimaryDark
                            : Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Main card content - clipped
                      ClipRRect(
                        borderRadius: SmoothBorderRadius(
                          cornerRadius: AppDimensions.radiusXLarge,
                          cornerSmoothing: 1.0,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 24),
                          child: Row(
                            children: [
                              Expanded(
                                child: _buildContent(context, isOverdue),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Right-side checkbox container - positioned outside clipped area
                      Positioned(
                        right: AppDimensions.spacing12,
                        top: 0,
                        bottom: 0,
                        child: Align(child: _buildCheckbox(context)),
                      ),
                      // Selection indicator overlay - fade in/out to avoid layout shifts
                      Positioned(
                        bottom: -4,
                        left: -4,
                        child: AnimatedOpacity(
                          opacity: widget.isSelectionMode ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            padding: EdgeInsets.all(widget.isSelected ? 0 : 3),
                            decoration: BoxDecoration(
                              color: theme.scaffoldBackgroundColor,
                              shape: BoxShape.circle,
                              border: widget.isSelected
                                  ? null
                                  : Border.all(
                                      color: theme.scaffoldBackgroundColor,
                                      width: 2,
                                    ),
                            ),
                            child: widget.isSelected
                                ? const Icon(
                                    SolarBoldIcons.checkCircle,
                                    color: AppColors.success,
                                    size: 24,
                                  )
                                : Icon(
                                    SolarLinearIcons.stop,
                                    size: 14,
                                    color: isDark
                                        ? AppColors.textSecondaryDark
                                        : Colors.grey[400],
                                  ),
                          ),
                        ),
                      ),
                      // Show shared badge for tasks shared with the user
                      if (widget.task.sharePermission != null)
                        Positioned(
                          top: AppDimensions.spacing8,
                          right: 56, // Position to the left of the checkbox
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppDimensions.spacing8,
                              vertical: AppDimensions.spacing4,
                            ),
                            decoration: BoxDecoration(
                              color: _getPermissionColor(
                                widget.task.sharePermission!,
                              ).withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(
                                AppDimensions.radiusSmall,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getPermissionIcon(
                                    widget.task.sharePermission!,
                                  ),
                                  size: AppDimensions.iconSmall,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: AppDimensions.spacing4),
                                Text(
                                  _getPermissionLabel(
                                    widget.task.sharePermission!,
                                  ),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      // UX-001 FIX: Show sync pending indicator
                      if (!widget.task.isSynced)
                        Positioned(
                          top: AppDimensions.spacing8,
                          right: widget.task.sharePermission != null ? 120 : 56,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 1,
                              ),
                            ),
                            child: Tooltip(
                              message: 'Pending sync',
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.orange,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCheckbox(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: () {
        Haptics.lightTap();
        final provider = context.read<TaskProvider>();
        final previousState = widget.task.isCompleted;
        
        // Toggle the task
        provider.toggleTaskStatus(widget.task);
        widget.onComplete?.call();
        
        // UX-004 FIX: Show undo snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              previousState
                  ? 'تم إعادة فتح المهمة'
                  : 'تم إكمال المهمة',
            ),
            action: SnackBarAction(
              label: 'تراجع',
              onPressed: () {
                // Toggle back to previous state
                provider.toggleTaskStatus(widget.task);
              },
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isDark ? AppColors.textSecondaryDark : Colors.grey[400]!,
              width: 2,
            ),
          ),
          child: widget.task.isCompleted
              ? Semantics(
                  label: 'مكتملة',
                  checked: true,
                  child: const Icon(
                    SolarBoldIcons.checkCircle,
                    size: 20,
                    color: AppColors.success,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool isOverdue) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Date/time on the left (right in RTL)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.task.dueDate != null) ...[
                _buildInfoTag(
                  context,
                  SolarLinearIcons.calendar,
                  _getRelativeDate(widget.task.dueDate!),
                  isWarning: isOverdue,
                ),
              ],
              if (widget.task.alarmEnabled &&
                  widget.task.alarmTime != null) ...[
                const SizedBox(height: 2),
                _buildInfoTag(
                  context,
                  SolarLinearIcons.bellBing,
                  TimeOfDay.fromDateTime(
                    widget.task.alarmTime!,
                  ).format(context),
                  color: AppColors.primary,
                ),
              ],
              if (widget.task.recurrence != null &&
                  widget.task.recurrence!.isNotEmpty) ...[
                const SizedBox(height: 2),
                _buildInfoTag(
                  context,
                  SolarLinearIcons.refresh,
                  _getRecurrenceLabel(widget.task.recurrence!),
                ),
              ],
            ],
          ),
          const SizedBox(width: AppDimensions.spacing12),
          // Task content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.task.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    decoration: widget.task.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                    color: widget.task.isCompleted
                        ? theme.textTheme.bodySmall?.color
                        : theme.textTheme.titleMedium?.color,
                  ),
                ),
                if (widget.task.category != null) ...[
                  const SizedBox(height: 2),
                  _buildCategoryTag(context, widget.task.category!),
                ],
                if (widget.task.description != null &&
                    widget.task.description!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.task.description!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
                _buildAssignmentInfo(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getRelativeDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);
    final difference = dateOnly.difference(today).inDays;

    if (difference == 0) {
      return 'اليوم';
    } else if (difference == 1) {
      return 'غداً';
    } else if (difference == -1) {
      return 'أمس';
    } else if (difference > 1 && difference <= 7) {
      return 'بعد $difference أيام';
    } else if (difference < -1 && difference >= -7) {
      return 'منذ ${-difference} أيام';
    } else {
      HijriCalendar.setLocal('ar');
      final hijri = HijriCalendar.fromDate(date);
      return hijri.toFormat('DD , dd MMMM').toEnglishNumbers;
    }
  }

  String _getRecurrenceLabel(String recurrence) {
    switch (recurrence) {
      case 'daily':
        return 'يوميًّا';
      case 'weekly':
        return 'أسبوعيًّا';
      case 'monthly':
        return 'شهريًّا';
      default:
        return '';
    }
  }

  Widget _buildInfoTag(
    BuildContext context,
    IconData icon,
    String label, {
    bool isWarning = false,
    Color? color,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tagColor =
        color ??
        (isWarning
            ? AppColors.error
            : (isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight));

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacing6,
        vertical: 2,
      ),
      decoration: ShapeDecoration(
        color: tagColor.withValues(alpha: 0.05),
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusMedium,
            cornerSmoothing: 1.0,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: tagColor),
          const SizedBox(width: 2),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: tagColor,
              fontWeight: isWarning ? FontWeight.w600 : FontWeight.w400,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTag(BuildContext context, String category) {
    final categoryColor =
        AppColors.taskCategoryColors[category] ?? AppColors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacing6,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: categoryColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
        border: Border.all(
          color: categoryColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_getCategoryIcon(category), size: 10, color: categoryColor),
          const SizedBox(width: 2),
          Text(
            category,
            style: TextStyle(
              color: categoryColor,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'عمل':
        return SolarLinearIcons.folder;
      case 'شخصي':
        return SolarLinearIcons.user;
      case 'تسوق':
        return SolarLinearIcons.cart;
      case 'عاجل':
        return SolarLinearIcons.danger;
      case 'دراسة':
        return SolarLinearIcons.book;
      case 'صحة':
        return SolarLinearIcons.heart;
      case 'مالية':
        return SolarLinearIcons.walletMoney;
      default:
        return SolarLinearIcons.folder;
    }
  }

  Widget _buildAssignmentInfo(BuildContext context) {
    final provider = context.watch<TaskProvider>();
    final currentUser = provider.currentUserEmail;

    if (widget.task.assignedTo == null && widget.task.createdBy == null) {
      return const SizedBox.shrink();
    }

    String? displayLabel;
    IconData icon = SolarLinearIcons.user;
    Color color = AppColors.primary;

    if (widget.task.assignedTo != null &&
        widget.task.assignedTo != currentUser) {
      final collab = provider.collaborators.firstWhere(
        (c) => c['email'] == widget.task.assignedTo,
        orElse: () => {
          'email': widget.task.assignedTo,
          'name': widget.task.assignedTo,
        },
      );
      displayLabel = 'مسندة إلى: ${collab['name'] ?? collab['email']}';
    } else if (widget.task.assignedTo == currentUser &&
        widget.task.createdBy != null &&
        widget.task.createdBy != currentUser) {
      final collab = provider.collaborators.firstWhere(
        (c) => c['email'] == widget.task.createdBy,
        orElse: () => {
          'email': widget.task.createdBy,
          'name': widget.task.createdBy,
        },
      );
      displayLabel = 'بواسطة: ${collab['name'] ?? collab['email']}';
      icon = SolarLinearIcons.userHandUp;
      color = AppColors.accent;
    }

    if (displayLabel == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color.withValues(alpha: 0.7)),
          const SizedBox(width: AppDimensions.spacing4),
          Text(
            displayLabel,
            style: TextStyle(
              fontSize: 10,
              color: color.withValues(alpha: 0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getPermissionIcon(String permission) {
    switch (permission) {
      case 'edit':
        return SolarLinearIcons.pen;
      case 'admin':
        return SolarLinearIcons.userHeart;
      default:
        return SolarLinearIcons.eye;
    }
  }

  String _getPermissionLabel(String permission) {
    switch (permission) {
      case 'edit':
        return 'تعديل';
      case 'admin':
        return 'مدير';
      default:
        return 'قراءة';
    }
  }

  Color _getPermissionColor(String permission) {
    switch (permission) {
      case 'edit':
        return Colors.blue;
      case 'admin':
        return Colors.purple;
      default:
        return AppColors.primary;
    }
  }
}

bool _canUserEditTask(TaskModel task, String? userId) {
  if (userId == null) return false;

  // Owner can always edit
  if (task.createdBy == userId) return true;

  // FIX: If createdBy is null (legacy task), allow edit for all license users
  if (task.createdBy == null || task.createdBy!.isEmpty) return true;

  // FIX P4-2: Check share permission instead of old assigned_to field
  // Users with edit or admin permission can edit shared tasks
  if (task.sharePermission == 'edit' || task.sharePermission == 'admin') {
    return true;
  }

  // Fallback for backward compatibility: assigned_to with shared visibility
  if (task.assignedTo == userId && task.visibility == 'shared') {
    return true;
  }

  return false;
}
