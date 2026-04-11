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

/// Forgot Password screen
///
/// Flow:
/// 1. User enters email
/// 2. Calls /api/auth/forgot-password
/// 3. Shows success message instructing user to check email
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _focusNode = FocusNode();
  bool _emailSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSendResetLink() async {
    if (!_formKey.currentState!.validate()) return;

    final sanitizedEmail = Validators.sanitizeInput(_emailController.text);
    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.forgotPassword(sanitizedEmail);

    if (!mounted) return;

    if (success) {
      Haptics.mediumTap();
      setState(() => _emailSent = true);
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

                  if (!_emailSent) ...[
                    // Icon
                    RepaintBoundary(
                      child: Container(
                        width: 80,
                        height: 80,
                        margin: const EdgeInsets.only(bottom: AppDimensions.spacing24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary.withValues(alpha: 0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(SolarLinearIcons.lock, color: Colors.white, size: 40),
                      ),
                    ),

                    // Title
                    Text(
                      'نسيت كلمة المرور؟',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.headlineSmall?.color,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacing8),
                    Text(
                      'أدخل بريدك الإلكتروني وسنرسل لك رابطاً لإعادة تعيين كلمة المرور',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.textTheme.bodySmall?.color,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacing32),

                    // Email Input
                    Text(
                      'البريد الإلكتروني',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: theme.textTheme.labelLarge?.color,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacing8),
                    AppTextField(
                      controller: _emailController,
                      focusNode: _focusNode,
                      hintText: 'user@example.com',
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      enableSuggestions: false,
                      maxLines: 1,
                      validator: (value) {
                        final result = Validators.validateEmail(value);
                        return result.errorMessage;
                      },
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

                    // Send Reset Link Button
                    Consumer<AuthProvider>(
                      builder: (context, auth, _) {
                        return AppGradientButton(
                          text: auth.isLoading ? 'جاري الإرسال...' : 'إرسال رابط إعادة التعيين',
                          onPressed: auth.isLoading ? null : _handleSendResetLink,
                          isLoading: auth.isLoading,
                          gradientColors: [theme.colorScheme.primary, theme.colorScheme.secondary],
                          showShadow: true,
                        );
                      },
                    ),
                  ] else ...[
                    // Success State
                    const SizedBox(height: AppDimensions.spacing32),
                    RepaintBoundary(
                      child: Container(
                        width: 80,
                        height: 80,
                        margin: const EdgeInsets.only(bottom: AppDimensions.spacing24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.green.shade400, Colors.green.shade600],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withValues(alpha: 0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(SolarLinearIcons.check, color: Colors.white, size: 40),
                      ),
                    ),

                    Text(
                      'تحقق من بريدك الإلكتروني',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.headlineSmall?.color,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacing16),
                    Text(
                      'إذا كان ${_emailController.text.trim()} مسجلاً لدينا، ستتلقى رابط إعادة تعيين كلمة المرور خلال دقائق.\n\n'
                      'تأكد من فحص مجلد البريد العشوائي.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.textTheme.bodySmall?.color,
                        height: 1.7,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacing32),

                    // Back to Login Button
                    AppGradientButton(
                      text: 'العودة لتسجيل الدخول',
                      onPressed: () {
                        Navigator.of(context).pushNamedAndRemoveUntil(
                          AppRoutes.login,
                          (route) => false,
                        );
                      },
                      gradientColors: [theme.colorScheme.primary, theme.colorScheme.secondary],
                      showShadow: true,
                    ),
                    const SizedBox(height: AppDimensions.spacing16),

                    // Resend link
                    Center(
                      child: TextButton(
                        onPressed: () {
                          setState(() => _emailSent = false);
                        },
                        child: Text(
                          'لم تستلم الرابط؟ إعادة الإرسال',
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
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
