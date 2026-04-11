import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:provider/provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:almudeer_mobile_app/core/app/routes.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/constants/dimensions.dart';
import 'package:almudeer_mobile_app/core/widgets/app_text_field.dart';
import 'package:almudeer_mobile_app/core/widgets/app_gradient_button.dart';
import 'package:almudeer_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';
import 'package:almudeer_mobile_app/core/utils/validators.dart';

/// Reset Password screen
///
/// Flow:
/// 1. Receives reset token via route arguments
/// 2. User enters new password + confirm password
/// 3. Calls /api/auth/reset-password
/// 4. On success: navigates to login
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.token});

  final String token;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _focusNode = FocusNode();
  bool _showPassword = false;
  bool _showConfirm = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleResetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    // Sanitize token to prevent control character injection
    final sanitizedToken = widget.token.trim();
    final success = await authProvider.resetPassword(sanitizedToken, _passwordController.text);

    if (!mounted) return;

    if (success) {
      Haptics.mediumTap();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إعادة تعيين كلمة المرور بنجاح. يمكنك تسجيل الدخول الآن'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
      Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return TapRegion(
      onTapOutside: (_) => _focusNode.unfocus(),
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(SolarLinearIcons.arrowLeft, color: theme.colorScheme.primary),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingLarge),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppDimensions.spacing24),

                  // Icon
                  RepaintBoundary(
                    child: Container(
                      width: 80,
                      height: 80,
                      margin: const EdgeInsets.only(bottom: AppDimensions.spacing24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFF093FB),
                            Color(0xFFF5576C),
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF093FB).withValues(alpha: 0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(SolarLinearIcons.key, color: Colors.white, size: 40),
                    ),
                  ),

                  // Title
                  Text(
                    'إعادة تعيين كلمة المرور',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: theme.textTheme.headlineSmall?.color,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacing8),
                  Text(
                    'أنشئ كلمة مرور جديدة لحسابك',
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacing32),

                  // New Password
                  Text(
                    'كلمة المرور الجديدة',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: theme.textTheme.labelLarge?.color,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacing8),
                  AppTextField(
                    controller: _passwordController,
                    focusNode: _focusNode,
                    hintText: 'كلمة مرور قوية',
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                    obscureText: !_showPassword,
                    enableInteractiveSelection: false, // P1-8 FIX
                    maxLines: 1,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPassword ? SolarLinearIcons.eye : SolarLinearIcons.eyeClosed,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'كلمة المرور مطلوبة';
                      final result = Validators.validatePassword(value);
                      return result.errorMessage;
                    },
                  ),
                  const SizedBox(height: AppDimensions.spacing16),

                  // Confirm Password
                  Text(
                    'تأكيد كلمة المرور',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: theme.textTheme.labelLarge?.color,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacing8),
                  AppTextField(
                    controller: _confirmController,
                    focusNode: _focusNode,
                    hintText: 'أعد كتابة كلمة المرور',
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    enableSuggestions: false,
                    obscureText: !_showConfirm,
                    enableInteractiveSelection: false, // P1-8 FIX
                    maxLines: 1,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showConfirm ? SolarLinearIcons.eye : SolarLinearIcons.eyeClosed,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _showConfirm = !_showConfirm),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'تأكيد كلمة المرور مطلوب';
                      final result = Validators.validatePasswordConfirmation(value, _passwordController.text);
                      return result.errorMessage;
                    },
                  ),
                  const SizedBox(height: AppDimensions.spacing8),
                  Text(
                    'يجب أن تحتوي على 8 أحرف، حرف كبير وصغير، رقم، ورمز خاص',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacing32),

                  // Error Message
                  Consumer<AuthProvider>(
                    builder: (context, auth, _) {
                      if (auth.errorMessage == null) return const SizedBox.shrink();
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: AppDimensions.spacing16),
                        decoration: ShapeDecoration(
                          color: isDark
                              ? AppColors.errorDark.withValues(alpha: 0.20)
                              : AppColors.errorLight.withValues(alpha: 0.20),
                          shape: SmoothRectangleBorder(
                            borderRadius: SmoothBorderRadius(cornerRadius: 12, cornerSmoothing: 1.0),
                            side: BorderSide(
                              color: isDark
                                  ? AppColors.errorDark.withValues(alpha: 0.6)
                                  : AppColors.error.withValues(alpha: 0.4),
                              width: 1.0,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(SolarLinearIcons.dangerCircle, color: isDark ? AppColors.errorDark : AppColors.error, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                auth.errorMessage!,
                                style: TextStyle(
                                  color: isDark ? AppColors.errorDark : AppColors.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  // Reset Button
                  Consumer<AuthProvider>(
                    builder: (context, auth, _) {
                      return AppGradientButton(
                        text: auth.isLoading ? 'جاري إعادة التعيين...' : 'إعادة تعيين كلمة المرور',
                        onPressed: auth.isLoading ? null : _handleResetPassword,
                        isLoading: auth.isLoading,
                        gradientColors: const [
                          Color(0xFFF093FB),
                          Color(0xFFF5576C),
                        ],
                        showShadow: true,
                      );
                    },
                  ),
                  const SizedBox(height: AppDimensions.spacing24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
