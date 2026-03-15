import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import '../constants/colors.dart';
import '../constants/dimensions.dart';

/// Shimmer loading skeleton for account cards
///
/// Used during initial load of saved accounts to indicate
/// content is being fetched. Shows placeholder for 3-4 accounts.
class AccountCardShimmer extends StatefulWidget {
  final int count;

  const AccountCardShimmer({
    super.key,
    this.count = 3,
  });

  @override
  State<AccountCardShimmer> createState() => _AccountCardShimmerState();
}

class _AccountCardShimmerState extends State<AccountCardShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.repeat();
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label shimmer
        Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 12),
          child: _ShimmerContainer(
            animation: _animation,
            width: 120,
            height: 18,
            isDark: isDark,
          ),
        ),
        // Account card shimmers
        ...List.generate(
          widget.count,
          (index) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildShimmerCard(isDark),
          ),
        ),
      ],
    );
  }

  Widget _buildShimmerCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacing16,
        vertical: AppDimensions.spacing12,
      ),
      decoration: ShapeDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusXLarge,
            cornerSmoothing: 1.0,
          ),
          side: BorderSide(
            color: isDark ? Colors.white10 : AppColors.borderLight.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          // Avatar shimmer
          _ShimmerContainer(
            animation: _animation,
            width: 40,
            height: 40,
            isCircle: true,
            isDark: isDark,
          ),
          const SizedBox(width: 12),
          // Text shimmers
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ShimmerContainer(
                  animation: _animation,
                  width: 140,
                  height: 16,
                  isDark: isDark,
                ),
                const SizedBox(height: 6),
                _ShimmerContainer(
                  animation: _animation,
                  width: 80,
                  height: 14,
                  isDark: isDark,
                ),
              ],
            ),
          ),
          // Arrow shimmer
          _ShimmerContainer(
            animation: _animation,
            width: 20,
            height: 20,
            isDark: isDark,
          ),
        ],
      ),
    );
  }
}

/// Internal shimmer container widget
class _ShimmerContainer extends StatelessWidget {
  final Animation<double> animation;
  final double width;
  final double height;
  final bool isCircle;
  final bool isDark;

  const _ShimmerContainer({
    required this.animation,
    required this.width,
    required this.height,
    required this.isDark,
    this.isCircle = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: isCircle ? null : BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment(animation.value, 0),
              end: Alignment(animation.value + 1, 0),
              colors: isDark
                  ? [
                      AppColors.shimmerBaseDark,
                      AppColors.shimmerHighlightDark,
                      AppColors.shimmerBaseDark,
                    ]
                  : [
                      AppColors.shimmerBaseLight,
                      AppColors.shimmerHighlightLight,
                      AppColors.shimmerBaseLight,
                    ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}
