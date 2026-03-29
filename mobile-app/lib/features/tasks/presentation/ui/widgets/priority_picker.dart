import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:almudeer_mobile_app/features/tasks/data/models/task_model.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/constants/dimensions.dart';
import 'package:almudeer_mobile_app/core/constants/animations.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';

/// Premium priority picker with proper touch targets and haptic feedback
///
/// Design Specifications:
/// - Minimum touch target: 44x44px (WCAG 2.1 AA)
/// - Haptic feedback on selection
/// - Smooth animations with proper easing
/// - Theme-aware colors
class PriorityPicker extends StatelessWidget {
  final TaskPriority selectedPriority;
  final ValueChanged<TaskPriority> onPriorityChanged;

  const PriorityPicker({
    super.key,
    required this.selectedPriority,
    required this.onPriorityChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ط§ظ„ط£ظˆظ„ظˆظٹط©',
          style: theme.textTheme.labelLarge?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppDimensions.spacing8),
        Row(
          children: TaskPriority.values.map((priority) {
            final isSelected = priority == selectedPriority;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.spacing6,
                ),
                child: _PriorityChip(
                  priority: priority,
                  isSelected: isSelected,
                  onTap: () {
                    Haptics.lightTap();
                    onPriorityChanged(priority);
                  },
                  isDark: isDark,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _PriorityChip extends StatefulWidget {
  final TaskPriority priority;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDark;

  const _PriorityChip({
    required this.priority,
    required this.isSelected,
    required this.onTap,
    required this.isDark,
  });

  @override
  State<_PriorityChip> createState() => _PriorityChipState();
}

class _PriorityChipState extends State<_PriorityChip> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final priorityColor = Color(widget.priority.colorValue);

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: AppAnimations.normal,
          constraints: const BoxConstraints(
            minWidth: AppDimensions.touchTargetMin,
            minHeight: AppDimensions.touchTargetMin,
          ),
          padding: const EdgeInsets.symmetric(
            vertical: AppDimensions.spacing12,
            horizontal: AppDimensions.spacing8,
          ),
          decoration: ShapeDecoration(
            color: widget.isSelected
                ? priorityColor.withValues(alpha: 0.15)
                : (widget.isDark
                      ? AppColors.surfaceCardDark
                      : AppColors.surfaceCardLight),
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(
                cornerRadius: AppDimensions.radiusLarge,
                cornerSmoothing: 1.0,
              ),
              side: BorderSide(
                color: widget.isSelected ? priorityColor : Colors.transparent,
                width: 2,
              ),
            ),
            shadows: widget.isSelected
                ? [
                    BoxShadow(
                      color: priorityColor.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Semantics(
            selected: widget.isSelected,
            label: widget.priority.label,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: AppAnimations.normal,
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: priorityColor,
                    shape: BoxShape.circle,
                    boxShadow: widget.isSelected
                        ? [
                            BoxShadow(
                              color: priorityColor.withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : [],
                  ),
                ),
                const SizedBox(height: AppDimensions.spacing4),
                Text(
                  widget.priority.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: widget.isSelected
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: widget.isSelected
                        ? priorityColor
                        : (widget.isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PriorityIndicator extends StatelessWidget {
  final TaskPriority priority;
  final double size;

  const PriorityIndicator({super.key, required this.priority, this.size = 8});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Color(priority.colorValue),
        shape: BoxShape.circle,
      ),
    );
  }
}
