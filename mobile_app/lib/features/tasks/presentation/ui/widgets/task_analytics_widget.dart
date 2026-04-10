import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import '../../providers/task_provider.dart';
import 'package:almudeer_mobile_app/features/tasks/data/models/task_model.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/constants/dimensions.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';

class TaskAnalyticsWidget extends StatefulWidget {
  const TaskAnalyticsWidget({super.key});

  @override
  State<TaskAnalyticsWidget> createState() => _TaskAnalyticsWidgetState();
}

class _TaskAnalyticsWidgetState extends State<TaskAnalyticsWidget> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<TaskProvider>(
      builder: (context, provider, _) {
        final tasks = provider.tasks;
        final totalTasks = tasks.length;
        final completedTasks = tasks.where((t) => t.isCompleted).length;
        final activeTasks = totalTasks - completedTasks;
        final overdueTasks = tasks
            .where(
              (t) =>
                  !t.isCompleted &&
                  t.dueDate != null &&
                  t.dueDate!.isBefore(DateTime.now()),
            )
            .length;

        final completionRate = totalTasks > 0
            ? (completedTasks / totalTasks * 100)
            : 0.0;

        return GestureDetector(
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            padding: const EdgeInsets.all(AppDimensions.paddingMedium),
            margin: const EdgeInsets.symmetric(
              horizontal: AppDimensions.paddingMedium,
              vertical: AppDimensions.paddingSmall,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary,
                  AppColors.primary.withValues(alpha: 0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppDimensions.radiusXLarge),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
                      ),
                      child: const Icon(
                        SolarBoldIcons.chart,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: AppDimensions.spacing12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ظ…ظ„ط®طµ ط§ظ„ظ…ظ‡ط§ظ…',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '$completedTasks/$totalTasks ظ…ظƒطھظ…ظ„ط© â€¢ ${completionRate.toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        SolarLinearIcons.arrowDown,
                        color: Colors.white.withValues(alpha: 0.8),
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppDimensions.spacing16),
                
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppDimensions.radiusSmall),
                  child: LinearProgressIndicator(
                    value: completionRate / 100,
                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    minHeight: 8,
                  ),
                ),
                
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: _buildExpandedContent(
                    totalTasks,
                    activeTasks,
                    completedTasks,
                    overdueTasks,
                    tasks,
                  ),
                  crossFadeState: _isExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 300),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildExpandedContent(
    int totalTasks,
    int activeTasks,
    int completedTasks,
    int overdueTasks,
    List<TaskModel> tasks,
  ) {
    final priorityBreakdown = {
      TaskPriority.low: tasks
          .where((t) => t.priority == TaskPriority.low && !t.isCompleted)
          .length,
      TaskPriority.medium: tasks
          .where((t) => t.priority == TaskPriority.medium && !t.isCompleted)
          .length,
      TaskPriority.high: tasks
          .where((t) => t.priority == TaskPriority.high && !t.isCompleted)
          .length,
      TaskPriority.urgent: tasks
          .where((t) => t.priority == TaskPriority.urgent && !t.isCompleted)
          .length,
    };

    return Column(
      children: [
        const SizedBox(height: AppDimensions.spacing16),
        Row(
          children: [
            _buildStatBadge(
              'ط§ظ„ط¥ط¬ظ…ط§ظ„ظٹ',
              totalTasks.toString(),
              SolarLinearIcons.list,
            ),
            const SizedBox(width: AppDimensions.spacing8),
            _buildStatBadge(
              'ط§ظ„ظ†ط´ط·ط©',
              activeTasks.toString(),
              SolarLinearIcons.playCircle,
            ),
            const SizedBox(width: AppDimensions.spacing8),
            _buildStatBadge(
              'ط§ظ„ظ…طھط£ط®ط±ط©',
              overdueTasks.toString(),
              SolarLinearIcons.danger,
            ),
          ],
        ),
        const SizedBox(height: AppDimensions.spacing16),
        const Text(
          'ط§ظ„ط£ظˆظ„ظˆظٹط§طھ ط§ظ„ظ†ط´ط·ط©',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: AppDimensions.spacing8),
        Wrap(
          spacing: AppDimensions.spacing6,
          runSpacing: AppDimensions.spacing6,
          children: [
            _buildPriorityChip(
              'ظ…ظ†ط®ظپط¶ط©',
              priorityBreakdown[TaskPriority.low] ?? 0,
              AppColors.success,
            ),
            _buildPriorityChip(
              'ظ…طھظˆط³ط·ط©',
              priorityBreakdown[TaskPriority.medium] ?? 0,
              AppColors.primaryLight,
            ),
            _buildPriorityChip(
              'ط¹ط§ظ„ظٹط©',
              priorityBreakdown[TaskPriority.high] ?? 0,
              AppColors.warning,
            ),
            _buildPriorityChip(
              'ط¹ط§ط¬ظ„ط©',
              priorityBreakdown[TaskPriority.urgent] ?? 0,
              AppColors.error,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatBadge(String label, String value, IconData icon) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          // Drill-down: Filter by stat type
          Haptics.lightTap();
          // Note: Could navigate to filtered list or set provider filter
          // For now, provide haptic feedback
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: AppDimensions.spacing10,
            horizontal: AppDimensions.spacing8,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
          ),
          child: Column(
            children: [
              Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 18),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriorityChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppDimensions.spacing6,
        horizontal: AppDimensions.spacing10,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count $label',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
