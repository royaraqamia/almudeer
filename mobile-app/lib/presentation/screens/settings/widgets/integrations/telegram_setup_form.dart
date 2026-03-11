import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/constants/dimensions.dart';
import '../../../../../core/utils/haptics.dart';
import '../../../../../core/widgets/app_gradient_button.dart';
import '../../../../../core/widgets/app_text_field.dart';

class TelegramSetupForm extends StatelessWidget {
  final TextEditingController tokenController;
  final VoidCallback onSave;

  const TelegramSetupForm({
    super.key,
    required this.tokenController,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppDimensions.paddingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Instructions Card
          Container(
            padding: const EdgeInsets.all(AppDimensions.paddingMedium),
            decoration: ShapeDecoration(
              color: AppColors.telegramBlue.withValues(alpha: 0.05),
              shape: SmoothRectangleBorder(
                borderRadius: SmoothBorderRadius(
                  cornerRadius: AppDimensions.radiusXLarge,
                  cornerSmoothing: 1.0,
                ),
                side: BorderSide(
                  color: AppColors.telegramBlue.withValues(alpha: 0.1),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Text(
                        'كيفيَّة إنشاء بوت تيليجرام',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.telegramBlue,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppDimensions.spacing8),
                    const Icon(
                      SolarLinearIcons.questionCircle,
                      size: 18,
                      color: AppColors.telegramBlue,
                    ),
                  ],
                ),
                const SizedBox(height: AppDimensions.spacing16),
                _buildInstructionStep(
                  '1. افتح تيليجرام وابحث عن BotFather@',
                  null,
                  theme,
                ),
                _buildInstructionStep('2. أرسل الأمر newbot/', null, theme),
                _buildInstructionStep(
                  '3. اختر اسمًا ومعرِّفًا للبوت',
                  null,
                  theme,
                ),
                _buildInstructionStep(
                  '4. انسخ التُّوكن الذي ستحصل عليه',
                  null,
                  theme,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppDimensions.spacing24),

          // Token Input
          Text(
            'توكن البوت',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: AppDimensions.spacing8),
          AppTextField(
            controller: tokenController,
            obscureText: true,
            textAlign: TextAlign.left,
            hintText: '••••••••••••••••••••••••••••••••',
            onChanged: (val) {
              // The parent manages state
            },
            prefixIcon: Icon(
              SolarLinearIcons.eyeClosed,
              color: theme.hintColor,
              size: AppDimensions.iconLarge,
            ),
          ),

          const SizedBox(height: AppDimensions.spacing24),

          // Save Button
          SizedBox(
            width: double.infinity,
            child: AppGradientButton(
              onPressed:
                  !RegExp(
                    r'^\d+:[A-Za-z0-9_-]+$',
                  ).hasMatch(tokenController.text.trim())
                  ? null
                  : () {
                      Haptics.lightTap();
                      onSave();
                    },
              text: 'ربط',
              gradientColors: const [AppColors.primary, AppColors.primaryDark],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionStep(
    String text,
    String? highlight,
    ThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimensions.spacing8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          if (highlight != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.spacing8,
                vertical: AppDimensions.spacing4,
              ),
              decoration: ShapeDecoration(
                color: Colors.white,
                shape: SmoothRectangleBorder(
                  borderRadius: SmoothBorderRadius(
                    cornerRadius: AppDimensions.radiusSmall,
                    cornerSmoothing: 1.0,
                  ),
                  side: BorderSide(color: theme.dividerColor),
                ),
              ),
              child: Text(
                highlight,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: AppColors.telegramBlue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: AppDimensions.spacing4),
          ],
          Flexible(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.normal,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
