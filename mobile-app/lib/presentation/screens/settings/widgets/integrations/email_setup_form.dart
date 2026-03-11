import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/constants/dimensions.dart';
import '../../../../../core/utils/haptics.dart';
import '../../../../../core/widgets/app_gradient_button.dart';

class EmailSetupForm extends StatelessWidget {
  final VoidCallback onSave;

  const EmailSetupForm({super.key, required this.onSave});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppDimensions.paddingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Info card
          Container(
            padding: const EdgeInsets.all(AppDimensions.paddingMedium),
            decoration: ShapeDecoration(
              color: AppColors.emailRed.withValues(alpha: 0.05),
              shape: SmoothRectangleBorder(
                borderRadius: SmoothBorderRadius(
                  cornerRadius: AppDimensions.radiusXLarge,
                  cornerSmoothing: 1.0,
                ),
                side: BorderSide(
                  color: AppColors.emailRed.withValues(alpha: 0.1),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.emailRed.withValues(alpha: 0.2),
                        AppColors.emailRed.withValues(alpha: 0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(
                      AppDimensions.radiusMedium,
                    ),
                  ),
                  child: const Icon(
                    SolarLinearIcons.letter,
                    size: 20,
                    color: AppColors.emailRed,
                  ),
                ),
                const SizedBox(width: AppDimensions.spacing12),
                Expanded(
                  child: Text(
                    'يتم ربط البريد الإلكتروني عبر تسجيل الدخول بحسابك في Google (OAuth 2.0)، بدون الحاجة لإدخال كلمة المرور داخل النظام.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      height: 1.5,
                      color: theme.hintColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppDimensions.spacing24),

          // Connect button
          SizedBox(
            width: double.infinity,
            child: AppGradientButton(
              onPressed: () {
                Haptics.lightTap();
                onSave();
              },
              text: 'ربط حساب Gmail',
              gradientColors: const [AppColors.primary, AppColors.primaryDark],
            ),
          ),
        ],
      ),
    );
  }
}
