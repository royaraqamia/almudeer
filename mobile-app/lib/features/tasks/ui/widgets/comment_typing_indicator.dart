import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/constants/animations.dart';

/// Typing indicator widget with animated dots
class CommentTypingIndicator extends StatefulWidget {
  final Color? color;
  final String userName;

  const CommentTypingIndicator({
    super.key,
    this.color,
    required this.userName,
  });

  @override
  State<CommentTypingIndicator> createState() => _CommentTypingIndicatorState();
}

class _CommentTypingIndicatorState extends State<CommentTypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppAnimations.standard, // Apple standard: 350ms (was 600ms)
    );
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppColors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.userName} يكتب...',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(width: 8),
          _buildTypingDots(color),
        ],
      ),
    );
  }

  Widget _buildTypingDots(Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDot(color, 0),
        const SizedBox(width: 2),
        _buildDot(color, 200),
        const SizedBox(width: 2),
        _buildDot(color, 400),
      ],
    );
  }

  Widget _buildDot(Color color, int delay) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: color.withValues(
              alpha: 0.3 + 0.7 * _controller.value,
            ),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
