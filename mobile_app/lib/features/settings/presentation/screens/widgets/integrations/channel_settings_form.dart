import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';

import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/constants/dimensions.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';
import 'package:almudeer_mobile_app/core/widgets/app_gradient_button.dart';

class ChannelSettingsForm extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isLoading;
  final bool isDisconnecting;
  final VoidCallback onDisconnect;
  final ValueChanged<String> onUpdateSettings;

  const ChannelSettingsForm({
    super.key,
    required this.data,
    required this.isLoading,
    required this.isDisconnecting,
    required this.onDisconnect,
    required this.onUpdateSettings,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = data['type'] as String;
    final displayName = data['display_name'] ?? '';
    final color = data['color'] as Color;

    return Padding(
      padding: const EdgeInsets.all(AppDimensions.paddingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Disconnect button
          AppGradientButton(
            onPressed: isDisconnecting ? null : onDisconnect,
            isLoading: isDisconnecting,
            text: 'ط¥ظ„ط؛ط§ط، ط§ظ„ط±ط¨ط·',
            textColor: AppColors.error,
          ),
          const SizedBox(height: AppDimensions.spacing20),

          // Connected account info
          Text(
            type == 'whatsapp' || type.startsWith('telegram')
                ? 'ط§ظ„ط±ظ‚ظ… ط§ظ„ظ…طھطµظ„'
                : 'ط§ظ„ط¨ط±ظٹط¯ ط§ظ„ط¥ظ„ظƒطھط±ظˆظ†ظٹ',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppDimensions.spacing8),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.paddingMedium,
              vertical: AppDimensions.spacing14,
            ),
            decoration: ShapeDecoration(
              color: theme.cardColor.withValues(alpha: 0.5),
              shape: SmoothRectangleBorder(
                borderRadius: SmoothBorderRadius(
                  cornerRadius: AppDimensions.radiusLarge,
                  cornerSmoothing: 1.0,
                ),
                side: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.5),
                ),
              ),
              shadows: [
                if (theme.brightness == Brightness.light)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
              ],
            ),
            child: Row(
              children: [
                Icon(data['icon'], size: 20, color: color),
                const SizedBox(width: AppDimensions.spacing12),
                Expanded(
                  child: Text(
                    displayName,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                    textAlign: TextAlign.left,
                    textDirection: TextDirection.ltr,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.spacing24),

          // Save settings button
          AppGradientButton(
            onPressed: isLoading
                ? null
                : () {
                    Haptics.lightTap();
                    onUpdateSettings(type);
                  },
            isLoading: isLoading,
            text: 'ط­ظپط¸ ط§ظ„ط¥ط¹ط¯ط§ط¯ط§طھ',
            gradientColors: const [AppColors.primary, AppColors.primaryDark],
          ),
        ],
      ),
    );
  }
}
