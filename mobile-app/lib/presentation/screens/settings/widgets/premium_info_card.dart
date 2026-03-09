import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import '../../../../core/constants/colors.dart';
import '../../../widgets/common_widgets.dart';

class PremiumInfoCard extends StatelessWidget {
  final String label;
  final String value;
  final String? badge;
  final Color? badgeColor;
  final IconData? icon;

  const PremiumInfoCard({
    super.key,
    required this.label,
    required this.value,
    this.badge,
    this.badgeColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: theme.hintColor),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (badge != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: ShapeDecoration(
                color: (badgeColor ?? AppColors.primary).withValues(
                  alpha: 0.12,
                ),
                shape: SmoothRectangleBorder(
                  borderRadius: SmoothBorderRadius(
                    cornerRadius: 12,
                    cornerSmoothing: 1.0,
                  ),
                ),
              ),
              child: Text(
                badge!,
                style: TextStyle(
                  fontSize: 10,
                  color: badgeColor ?? AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
