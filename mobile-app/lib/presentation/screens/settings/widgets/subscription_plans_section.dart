import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/dimensions.dart';

class SubscriptionPlansSection extends StatefulWidget {
  const SubscriptionPlansSection({super.key});

  @override
  State<SubscriptionPlansSection> createState() =>
      _SubscriptionPlansSectionState();
}

class _SubscriptionPlansSectionState extends State<SubscriptionPlansSection> {
  bool isYearly = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimensions.paddingLarge),
      decoration: ShapeDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  AppColors.surfaceDark,
                  AppColors.cardDark,
                ]
              : [
                  AppColors.surfaceLight,
                  AppColors.secondarySystemBackground,
                ],
        ),
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusXXLarge,
            cornerSmoothing: 1.0,
          ),
        ),
      ),
      child: Column(
        children: [
          // Plan Selector Toggle
          _buildPlanToggle(isDark),
          const SizedBox(height: AppDimensions.spacing32),

          // Price Display
          _buildPriceDisplay(isDark),
        ],
      ),
    );
  }

  Widget _buildPlanToggle(bool isDark) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          height: 52,
          padding: const EdgeInsets.all(4),
          decoration: ShapeDecoration(
            color: isDark
                ? AppColors.systemBackgroundDark.withValues(alpha: 0.5)
                : Colors.grey.shade200,
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(
                cornerRadius: AppDimensions.radiusFull,
                cornerSmoothing: 1.0,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildToggleButton(
                  title: 'شهري',
                  isSelected: !isYearly,
                  onTap: () {
                    if (!isYearly) return;
                    setState(() => isYearly = false);
                  },
                ),
              ),
              Expanded(
                child: _buildToggleButton(
                  title: 'سنوي',
                  isSelected: isYearly,
                  onTap: () {
                    if (isYearly) return;
                    setState(() => isYearly = true);
                  },
                  icon: const Icon(SolarLinearIcons.stars, size: 15),
                ),
              ),
            ],
          ),
        ),
        if (isYearly)
          Positioned(
            top: -8,
            left: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: ShapeDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                ),
                shape: SmoothRectangleBorder(
                  borderRadius: SmoothBorderRadius(
                    cornerRadius: AppDimensions.radiusFull,
                    cornerSmoothing: 1.0,
                  ),
                ),
                shadows: [
                  BoxShadow(
                    color: AppColors.success.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(SolarLinearIcons.tag, size: 12, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'وفر 25%',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildToggleButton({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
    Widget? icon,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          shape: SmoothRectangleBorder(
            borderRadius: SmoothBorderRadius(
              cornerRadius: AppDimensions.radiusFull,
              cornerSmoothing: 1.0,
            ),
          ),
          shadows: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              IconTheme(
                data: IconThemeData(
                  color: isSelected
                      ? Colors.white
                      : AppColors.textTertiaryLight,
                  size: 15,
                ),
                child: icon,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              title,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : (isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight),
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceDisplay(bool isDark) {
    final price = isYearly ? '90' : '10';
    final period = isYearly ? 'سنة' : 'شهر';

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '\$',
              style: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
                fontSize: 24,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
            const SizedBox(width: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) {
                return ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              child: Text(
                price,
                key: ValueKey(isYearly),
                style: TextStyle(
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimaryLight,
                  fontSize: 64,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: -2,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              ' / $period',
              style: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (isYearly) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: ShapeDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              shape: SmoothRectangleBorder(
                borderRadius: SmoothBorderRadius(
                  cornerRadius: AppDimensions.radiusFull,
                  cornerSmoothing: 1.0,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '7.5\$/شهر',
                  style: TextStyle(
                    color: Color(0xFF10B981),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '•',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textTertiaryDark
                        : AppColors.textTertiaryLight,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '120\$/سنة',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textTertiaryDark
                        : AppColors.textTertiaryLight,
                    decoration: TextDecoration.lineThrough,
                    decorationThickness: 1.5,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
