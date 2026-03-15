import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import '../../../../../core/constants/colors.dart';
import '../../../../../core/constants/dimensions.dart';
import '../../../../../core/constants/shadows.dart';

class IntegrationCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isExpanded;
  final bool isLoading;
  final bool isDisconnecting;
  final ValueChanged<bool> onExpandChanged;
  final Widget content;

  const IntegrationCard({
    super.key,
    required this.data,
    required this.isExpanded,
    this.isLoading = false,
    this.isDisconnecting = false,
    required this.onExpandChanged,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isConnected = data['is_connected'] as bool? ?? false;
    final color = data['color'] as Color;
    final isDark = theme.brightness == Brightness.dark;
    final type = data['type'] as String?;
    final isTelegramPhone = type == 'telegram_phone';
    final shouldExpand = isExpanded || (isLoading && isTelegramPhone);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: isConnected ? 1 : 0),
      duration: const Duration(seconds: 1),
      curve: Curves.elasticOut,
      builder: (context, value, child) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          decoration: ShapeDecoration(
            color: isDark
                ? theme.cardColor
                : theme.cardColor.withValues(alpha: 0.8),
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(
                cornerRadius: AppDimensions.radiusLarge,
                cornerSmoothing: 1.0,
              ),
              side: BorderSide(
                color: isConnected
                    ? color.withValues(alpha: 0.5 + (value * 0.2))
                    : theme.dividerColor.withValues(alpha: 0.1),
                width: isConnected ? 1.5 + (value * 0.5) : 1,
              ),
            ),
            shadows: [
              if (!isDark) AppShadows.premiumShadow,
              if (!isDark && isConnected && value < 0.9)
                BoxShadow(
                  color: color.withValues(alpha: 0.1 * (1 - value)),
                  blurRadius: 20 * value,
                  spreadRadius: 10 * value,
                ),
            ],
          ),
          child: child,
        );
      },
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: isTelegramPhone && isLoading
                ? null
                : () => onExpandChanged(!isExpanded),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(AppDimensions.radiusLarge),
              topRight: const Radius.circular(AppDimensions.radiusLarge),
              bottomLeft: Radius.circular(
                shouldExpand ? 0 : AppDimensions.radiusLarge,
              ),
              bottomRight: Radius.circular(
                shouldExpand ? 0 : AppDimensions.radiusLarge,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppDimensions.paddingMedium),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    padding: const EdgeInsets.all(10),
                    decoration: ShapeDecoration(
                      gradient: LinearGradient(
                        colors: [
                          color.withValues(alpha: 0.1),
                          color.withValues(alpha: 0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: SmoothRectangleBorder(
                        borderRadius: SmoothBorderRadius(
                          cornerRadius: 16,
                          cornerSmoothing: 1.0,
                        ),
                        side: BorderSide(color: color.withValues(alpha: 0.2)),
                      ),
                    ),
                    child: Icon(data['icon'], color: color, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Flexible(
                              child: Text(
                                data['name'],
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (isConnected)
                              _buildStatusBadge(AppColors.success, 'مفعّل')
                            else if (isLoading)
                              _buildStatusBadge(color, 'جاري الربط...'),
                          ],
                        ),
                        if (data['desc'] != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            data['desc'],
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.hintColor,
                              fontSize: 12,
                              fontWeight: FontWeight.normal,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (isLoading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.primary,
                        ),
                      ),
                    )
                  else if (!isTelegramPhone)
                    AnimatedRotation(
                      duration: const Duration(milliseconds: 200),
                      turns: isExpanded ? 0.5 : 0,
                      child: Icon(
                        SolarLinearIcons.altArrowDown,
                        color: theme.hintColor,
                        size: 20,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Progress bar when loading
          if (isLoading)
            LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: color.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),

          // Expanded Content
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: shouldExpand
                ? Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isDark
                          ? theme.scaffoldBackgroundColor.withValues(alpha: 0.3)
                          : Colors.black.withValues(alpha: 0.02),
                      border: Border(
                        top: BorderSide(
                          color: theme.dividerColor.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                    child: content,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(Color color, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.1),
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: 20,
            cornerSmoothing: 1.0,
          ),
          side: BorderSide(color: color.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            text == 'مفعّل'
                ? SolarLinearIcons.checkCircle
                : SolarLinearIcons.refresh,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
