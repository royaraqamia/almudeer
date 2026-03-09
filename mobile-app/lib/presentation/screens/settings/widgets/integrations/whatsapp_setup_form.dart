import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/constants/dimensions.dart';
import '../../../../../core/utils/haptics.dart';
import '../../../../../core/widgets/app_gradient_button.dart';
import '../../../../../core/widgets/app_text_field.dart';

class WhatsappSetupForm extends StatelessWidget {
  final int setupStep;
  final TextEditingController phoneIdController;
  final TextEditingController tokenController;
  final ValueChanged<int> onStepChange;
  final VoidCallback onSave;

  const WhatsappSetupForm({
    super.key,
    required this.setupStep,
    required this.phoneIdController,
    required this.tokenController,
    required this.onStepChange,
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
          // Step Indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildStepIndicator(1, setupStep >= 1, theme),
              Container(
                width: 60,
                height: 2,
                decoration: ShapeDecoration(
                  color: setupStep >= 2 ? AppColors.primary : theme.dividerColor,
                  shape: SmoothRectangleBorder(
                    borderRadius: SmoothBorderRadius(
                      cornerRadius: 1,
                      cornerSmoothing: 1.0,
                    ),
                  ),
                ),
              ),
              _buildStepIndicator(2, setupStep >= 2, theme),
            ],
          ),

          const SizedBox(height: AppDimensions.spacing24),

          // Step Content
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: setupStep == 1
                ? _buildWhatsAppStep1(context, theme)
                : _buildWhatsAppStep2(context, theme),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(int step, bool isActive, ThemeData theme) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isActive ? AppColors.primary : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: isActive ? AppColors.primary : theme.dividerColor,
          width: 2,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: Center(
        child: Text(
          '$step',
          style: TextStyle(
            color: isActive ? Colors.white : theme.hintColor,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildWhatsAppStep1(BuildContext context, ThemeData theme) {
    return Column(
      key: const ValueKey(1),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Instructions
        Container(
          padding: const EdgeInsets.all(AppDimensions.paddingMedium),
          decoration: ShapeDecoration(
            color: AppColors.whatsappGreen.withValues(alpha: 0.05),
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(
                cornerRadius: AppDimensions.radiusXLarge,
                cornerSmoothing: 1.0,
              ),
              side: BorderSide(
                color: AppColors.whatsappGreen.withValues(alpha: 0.1),
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
                      'الخطوة 1: الحصول على الـ Phone Number ID',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0F172A),
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.spacing16),
              _buildWhatsAppInstruction(
                '1. افتح الـ Meta Business Manager',
                null,
                theme,
              ),
              _buildWhatsAppInstruction(
                '2. انتقل إلى الـ WhatsApp Accounts',
                null,
                theme,
              ),
              _buildWhatsAppInstruction(
                '3. اختر رقم الهاتف الخاص بك',
                null,
                theme,
              ),
              _buildWhatsAppInstruction(
                '4. انسخ الـ Phone Number ID',
                null,
                theme,
              ),
            ],
          ),
        ),

        const SizedBox(height: AppDimensions.spacing24),

        // Phone Number ID Input
        Text(
          '* Phone Number ID',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
          textAlign: TextAlign.right,
        ),
        const SizedBox(height: AppDimensions.spacing8),
        AppTextField(
          controller: phoneIdController,
          textAlign: TextAlign.left,
          keyboardType: TextInputType.number,
          hintText: '123456789012345',
          onChanged: (_) => onStepChange(setupStep),
        ),
        const SizedBox(height: AppDimensions.spacing24),

        // Next Button
        SizedBox(
          width: double.infinity,
          child: AppGradientButton(
            onPressed: !RegExp(r'^\d{15}$').hasMatch(phoneIdController.text.trim())
                ? null
                : () {
                    Haptics.lightTap();
                    onStepChange(setupStep + 1);
                  },
            text: 'التَّالي',
            gradientColors: [
              AppColors.primary,
              AppColors.primaryDark,
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWhatsAppStep2(BuildContext context, ThemeData theme) {
    return Column(
      key: const ValueKey(2),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Instructions
        Container(
          padding: const EdgeInsets.all(AppDimensions.paddingMedium),
          decoration: ShapeDecoration(
            color: AppColors.whatsappGreen.withValues(alpha: 0.05),
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(
                cornerRadius: AppDimensions.radiusXLarge,
                cornerSmoothing: 1.0,
              ),
              side: BorderSide(
                color: AppColors.whatsappGreen.withValues(alpha: 0.1),
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
                      'الخطوة 2: الحصول على الـ Access Token',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0F172A),
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.spacing16),
              _buildWhatsAppInstruction(
                '1. في الـ Meta Business Manager، انتقل إلى الـ System Users',
                null,
                theme,
              ),
              _buildWhatsAppInstruction(
                '2. أنشِئ مستخدِم نظام جديد',
                null,
                theme,
              ),
              _buildWhatsAppInstruction(
                '3. امنحه صلاحيَّات الـ WhatsApp Business',
                null,
                theme,
              ),
              _buildWhatsAppInstruction(
                '4. أنشِئ توكن جديد وانسخه',
                null,
                theme,
              ),
            ],
          ),
        ),

        const SizedBox(height: AppDimensions.spacing24),

        // Access Token Input
        Text(
          '* Access Token',
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
          onChanged: (_) => onStepChange(setupStep),
          prefixIcon: Icon(
            SolarLinearIcons.eyeClosed,
            color: theme.hintColor,
            size: AppDimensions.iconLarge,
          ),
        ),

        const SizedBox(height: AppDimensions.spacing24),

        // Buttons
        Row(
          children: [
            Expanded(
              child: AppGradientButton(
                onPressed: () {
                  Haptics.lightTap();
                  onStepChange(1);
                },
                text: 'السَّابق',
                textColor: theme.textTheme.bodyMedium?.color,
              ),
            ),
            const SizedBox(width: AppDimensions.spacing12),
            Expanded(
              flex: 2,
              child: AppGradientButton(
                onPressed: tokenController.text.trim().length < 50
                    ? null
                    : () {
                        Haptics.lightTap();
                        onSave();
                      },
                text: 'ربط',
                gradientColors: [
                  AppColors.primary,
                  AppColors.primaryDark,
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWhatsAppInstruction(
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
            Text(
              highlight,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
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
