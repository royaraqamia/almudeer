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

/// Sign Up screen with email, password, and full name validation
///
/// Flow:
/// 1. User enters full name, email, password
/// 2. Validates all fields
/// 3. Calls /api/auth/signup
/// 4. Navigates to OTP verification screen
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _focusNode = FocusNode();
  bool _showPassword = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.signUp(
      _emailController.text.trim(),
      _passwordController.text,
      _fullNameController.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      Haptics.mediumTap();
      // Navigate to OTP verification
      Navigator.of(context).pushNamed(
        AppRoutes.otpVerification,
        arguments: {'email': _emailController.text.trim()},
      );
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
            icon: Icon(
              SolarLinearIcons.arrowLeft,
              color: theme.colorScheme.primary,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.paddingLarge,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppDimensions.spacing24),

                  // Icon
                  RepaintBoundary(
                    child: Container(
                      width: AppDimensions.loginIconContainerSize,
                      height: AppDimensions.loginIconContainerSize,
                      margin: const EdgeInsets.only(bottom: AppDimensions.spacing24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
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
                      child: const Icon(
                        SolarLinearIcons.user,
                        color: Colors.white,
                        size: AppDimensions.loginIconSize,
                      ),
                    ),
                  ),

                  // Title
                  Text(
                    'إنشاء حساب جديد',
                    style: TextStyle(
                      fontSize: AppDimensions.loginTitleSize,
                      fontWeight: FontWeight.bold,
                      color: theme.textTheme.headlineSmall?.color,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacing8),
                  Text(
                    'أدخل بريدك الإلكتروني لإنشاء حساب',
                    style: TextStyle(
                      fontSize: AppDimensions.loginSubtitleSize,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacing32),

                  // Full Name Input
                  Text(
                    'الاسم الكامل',
                    style: TextStyle(
                      fontSize: AppDimensions.loginLabelSize,
                      fontWeight: FontWeight.w500,
                      color: theme.textTheme.labelLarge?.color,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacing8),
                  AppTextField(
                    controller: _fullNameController,
                    focusNode: _focusNode,
                    hintText: 'الاسم الكامل',
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLines: 1,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'الاسم الكامل مطلوب';
                      }
                      if (value.trim().length < 2) {
                        return 'الاسم يجب أن يكون حرفين على الأقل';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppDimensions.spacing16),

                  // Email Input
                  Text(
                    'البريد الإلكتروني',
                    style: TextStyle(
                      fontSize: AppDimensions.loginLabelSize,
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
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLines: 1,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'البريد الإلكتروني مطلوب';
                      }
                      final emailRegex = RegExp(
                        r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
                      );
                      if (!emailRegex.hasMatch(value)) {
                        return 'بريد إلكتروني غير صالح';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppDimensions.spacing16),

                  // Password Input
                  Text(
                    'كلمة المرور',
                    style: TextStyle(
                      fontSize: AppDimensions.loginLabelSize,
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
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    enableSuggestions: false,
                    obscureText: !_showPassword,
                    maxLines: 1,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPassword
                            ? SolarLinearIcons.eye
                            : SolarLinearIcons.eyeClosed,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _showPassword = !_showPassword;
                        });
                      },
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'كلمة المرور مطلوبة';
                      }
                      if (value.length < 8) {
                        return 'كلمة المرور يجب أن تكون 8 أحرف على الأقل';
                      }
                      if (!RegExp(r'[A-Z]').hasMatch(value)) {
                        return 'يجب أن تحتوي على حرف كبير واحد على الأقل';
                      }
                      if (!RegExp(r'[a-z]').hasMatch(value)) {
                        return 'يجب أن تحتوي على حرف صغير واحد على الأقل';
                      }
                      if (!RegExp(r'\d').hasMatch(value)) {
                        return 'يجب أن تحتوي على رقم واحد على الأقل';
                      }
                      if (!RegExp(r"""[!@#\$%^&*(),.?":{}|<>_\-+=\[\]\\;'`~]""").hasMatch(value)) {
                        return 'يجب أن تحتوي على رمز خاص واحد على الأقل';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppDimensions.spacing8),
                  Text(
                    'يجب أن تحتوي على 8 أحرف، حرف كبير وصغير، رقم، ورمز خاص',
                    style: TextStyle(
                      fontSize: AppDimensions.loginHintSize,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacing32),

                  // Error Message
                  Consumer<AuthProvider>(
                    builder: (context, auth, _) {
                      if (auth.errorMessage == null) {
                        return const SizedBox.shrink();
                      }
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppDimensions.errorPadding),
                        margin: const EdgeInsets.only(bottom: AppDimensions.spacing16),
                        decoration: ShapeDecoration(
                          color: isDark
                              ? AppColors.errorDark.withValues(alpha: 0.20)
                              : AppColors.errorLight.withValues(alpha: 0.20),
                          shape: SmoothRectangleBorder(
                            borderRadius: SmoothBorderRadius(
                              cornerRadius: AppDimensions.radiusLarge,
                              cornerSmoothing: 1.0,
                            ),
                            side: BorderSide(
                              color: isDark
                                  ? AppColors.errorDark.withValues(alpha: 0.6)
                                  : AppColors.error.withValues(alpha: 0.4),
                              width: 1.0,
                            ),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              SolarLinearIcons.dangerCircle,
                              color: isDark ? AppColors.errorDark : AppColors.error,
                              size: AppDimensions.errorIconSize,
                            ),
                            const SizedBox(width: AppDimensions.errorIconMarginEnd),
                            Expanded(
                              child: Text(
                                auth.errorMessage!,
                                style: TextStyle(
                                  color: isDark ? AppColors.errorDark : AppColors.error,
                                  fontSize: AppDimensions.loginErrorSize,
                                  fontWeight: FontWeight.w600,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  // Sign Up Button
                  Consumer<AuthProvider>(
                    builder: (context, auth, _) {
                      return AppGradientButton(
                        text: auth.isLoading ? 'جاري الإنشاء...' : 'إنشاء حساب',
                        onPressed: auth.isLoading ? null : _handleSignUp,
                        isLoading: auth.isLoading,
                        gradientColors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.secondary,
                        ],
                        showShadow: true,
                      );
                    },
                  ),
                  const SizedBox(height: AppDimensions.spacing16),

                  // Already have account? Login
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'لديك حساب بالفعل؟ تسجيل الدخول',
                        style: TextStyle(
                          fontSize: AppDimensions.loginHintSize,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
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
