import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:provider/provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:almudeer_mobile_app/core/app/routes.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/constants/strings_ar.dart';
import 'package:almudeer_mobile_app/core/constants/dimensions.dart';
import 'package:almudeer_mobile_app/core/widgets/app_text_field.dart';
import 'package:almudeer_mobile_app/core/widgets/app_gradient_button.dart';
import 'package:almudeer_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';

/// Login screen with email/password authentication
///
/// Users authenticate using email and password only.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFormKey = GlobalKey<FormState>();
  final _focusNode = FocusNode();
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleEmailLogin() async {
    if (!_emailFormKey.currentState!.validate()) return;

    // P2-14 FIX: Sanitize email input - trim and strip non-printable characters
    final sanitizedEmail = _emailController.text
        .trim()
        .replaceAll(RegExp(r'[\x00-\x1F\x7F-\x9F]'), '');

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.loginWithEmail(
      sanitizedEmail,
      _passwordController.text,
    );

    if (!mounted) return;

    if (success) {
      Haptics.mediumTap();
      Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.dashboard, (route) => false);
    } else if (authProvider.state == AuthState.pendingApproval) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.waitingForApproval,
        arguments: {'email': _emailController.text.trim()},
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isLandscape = MediaQuery.of(context).size.width > MediaQuery.of(context).size.height;
    final isSmallScreen = MediaQuery.of(context).size.height < AppDimensions.breakpointSmallHeight;
    final topPadding = isLandscape
        ? AppDimensions.paddingLarge
        : (isSmallScreen ? AppDimensions.loginScreenTopPaddingSmall : AppDimensions.loginScreenTopPaddingLarge);
    final headerMargin = isLandscape
        ? AppDimensions.spacing32
        : (isSmallScreen ? AppDimensions.loginScreenHeaderMarginSmall : AppDimensions.loginScreenHeaderMarginLarge);

    return TapRegion(
      onTapOutside: (_) => _focusNode.unfocus(),
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.symmetric(
              horizontal: isSmallScreen ? AppDimensions.paddingMedium : AppDimensions.paddingLarge,
              vertical: topPadding,
            ),
            child: Column(
              children: [
                // Header
                SizedBox(height: headerMargin),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      label: AppStrings.appName,
                      child: Image.asset(
                        'assets/images/transparent-logo.png',
                        height: AppDimensions.headerLogoHeight,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: AppDimensions.headerLogoMarginEnd),
                    Text(
                      AppStrings.appName,
                      style: TextStyle(
                        fontSize: AppDimensions.headerTitleSize,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: headerMargin),

                // Login Card
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: AppDimensions.loginCardMaxWidth),
                  decoration: ShapeDecoration(
                    color: theme.cardColor,
                    shape: SmoothRectangleBorder(
                      borderRadius: SmoothBorderRadius(
                        cornerRadius: AppDimensions.radiusLoginCard,
                        cornerSmoothing: 1.0,
                      ),
                      side: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight, width: 1.0),
                    ),
                    shadows: [
                      BoxShadow(
                        color: isDark ? AppColors.shadowPrimaryDark : AppColors.shadowPrimaryLight,
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? AppDimensions.loginCardHorizontalPaddingSmall : AppDimensions.loginCardHorizontalPaddingLarge,
                      vertical: isSmallScreen ? AppDimensions.loginCardPaddingSmall : AppDimensions.loginCardPaddingLarge,
                    ),
                    child: Column(
                      children: [
                        // Icon
                        RepaintBoundary(
                          child: Container(
                            width: AppDimensions.loginIconContainerSize,
                            height: AppDimensions.loginIconContainerSize,
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
                        const SizedBox(height: AppDimensions.loginIconMarginTop),

                        // Title
                        Text(
                          'تسجيل الدخول',
                          style: TextStyle(
                            fontSize: AppDimensions.loginTitleSize,
                            fontWeight: FontWeight.bold,
                            color: theme.textTheme.headlineSmall?.color,
                          ),
                        ),
                        const SizedBox(height: AppDimensions.spacing8),
                        Text(
                          'أدخل بريدك الإلكتروني وكلمة المرور',
                          style: TextStyle(
                            fontSize: AppDimensions.loginSubtitleSize,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                        const SizedBox(height: AppDimensions.spacing24),

                        // Email Login Form
                        _buildEmailLoginForm(theme),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppDimensions.spacing24),

                // Links
                TextButton(
                  onPressed: () => Navigator.of(context).pushNamed(AppRoutes.forgotPassword),
                  child: Text(
                    'نسيت كلمة المرور؟',
                    style: TextStyle(color: theme.colorScheme.primary, fontSize: 14),
                  ),
                ),
                const SizedBox(height: AppDimensions.spacing8),
                TextButton(
                  onPressed: () => Navigator.of(context).pushNamed(AppRoutes.signup),
                  child: Text(
                    'ليس لديك حساب؟ إنشاء حساب جديد',
                    style: TextStyle(color: theme.colorScheme.primary, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: AppDimensions.spacing24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailLoginForm(ThemeData theme) {
    return Form(
      key: _emailFormKey,
      child: Column(
        children: [
          // Email Input
          Semantics(
            label: 'البريد الإلكتروني',
            child: AppTextField(
              controller: _emailController,
              focusNode: _focusNode,
              hintText: 'user@example.com',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              enableSuggestions: false,
              maxLines: 1,
              validator: (value) {
                if (value == null || value.isEmpty) return 'البريد الإلكتروني مطلوب';
                final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
                if (!emailRegex.hasMatch(value)) return 'بريد إلكتروني غير صالح';
                return null;
              },
            ),
          ),
          const SizedBox(height: AppDimensions.spacing16),

          // Password Input
          Semantics(
            label: 'كلمة المرور',
            child: AppTextField(
              controller: _passwordController,
              focusNode: _focusNode,
              hintText: 'كلمة المرور',
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              enableInteractiveSelection: false, // P1-8 FIX: Prevent text selection/copy
              obscureText: !_showPassword,
              maxLines: 1,
              suffixIcon: IconButton(
                icon: Icon(_showPassword ? SolarLinearIcons.eye : SolarLinearIcons.eyeClosed, size: 20),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'كلمة المرور مطلوبة';
                return null;
              },
            ),
          ),
          const SizedBox(height: AppDimensions.spacing24),

          // Error message
          Consumer<AuthProvider>(
            builder: (context, auth, _) {
              if (auth.errorMessage == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: AppDimensions.spacing16),
                child: Text(
                  auth.errorMessage!,
                  style: const TextStyle(color: AppColors.error, fontSize: 13, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              );
            },
          ),

          // Login Button
          Consumer<AuthProvider>(
            builder: (context, auth, _) {
              return AppGradientButton(
                text: auth.isLoading ? 'جاري الدخول...' : AppStrings.loginButton,
                onPressed: auth.isLoading ? null : _handleEmailLogin,
                isLoading: auth.isLoading,
                gradientColors: [theme.colorScheme.primary, theme.colorScheme.secondary],
                showShadow: true,
              );
            },
          ),
        ],
      ),
    );
  }
}
