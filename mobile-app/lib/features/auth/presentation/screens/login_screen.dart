import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:almudeer_mobile_app/core/app/routes.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/constants/strings_ar.dart';
import 'package:almudeer_mobile_app/core/constants/dimensions.dart';
import 'package:almudeer_mobile_app/core/widgets/app_text_field.dart';
import 'package:almudeer_mobile_app/core/widgets/app_gradient_button.dart';
import 'package:almudeer_mobile_app/core/widgets/app_outline_button.dart';
import 'package:almudeer_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';

/// Login screen supporting BOTH email/password AND license key login
///
/// Default tab: Email/Password login
/// Second tab: License key login (backward compatibility for existing users)
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _licenseController = TextEditingController();
  final _emailFormKey = GlobalKey<FormState>();
  final _licenseFormKey = GlobalKey<FormState>();
  final _focusNode = FocusNode();
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChange);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChange);
    _tabController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _licenseController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTabChange() {
    _focusNode.unfocus();
    setState(() {});
  }

  Future<void> _handleEmailLogin() async {
    if (!_emailFormKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.loginWithEmail(
      _emailController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;

    if (success) {
      Haptics.mediumTap();
      Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.dashboard, (route) => false);
    } else if (authProvider.state == AuthState.pendingApproval) {
      // Navigate to waiting for approval screen
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.waitingForApproval,
        arguments: {'email': _emailController.text.trim()},
        (route) => false,
      );
    }
  }

  Future<void> _handleLicenseLogin() async {
    if (!_licenseFormKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.login(_licenseController.text);

    if (!mounted) return;

    if (success) {
      Haptics.mediumTap();
      Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.dashboard, (route) => false);
    }
  }

  void _openWhatsApp() async {
    final message = Uri.encodeComponent('السلام عليكم، أرغب في الحصول على مفتاح اشتراك لتطبيق المدير.');
    final whatsappUrl = 'https://wa.me/+963966478904?text=$message';
    final uri = Uri.parse(whatsappUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
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
    final headerMargin = isLandscape ? AppDimensions.spacing32 : (isSmallScreen ? AppDimensions.loginScreenHeaderMarginSmall : AppDimensions.loginScreenHeaderMarginLarge);

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
                            child: Icon(
                              _tabController.index == 0 ? SolarLinearIcons.user : SolarLinearIcons.key,
                              color: Colors.white,
                              size: AppDimensions.loginIconSize,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppDimensions.loginIconMarginTop),

                        // Title
                        Text(
                          _tabController.index == 0 ? 'تسجيل الدخول' : 'تسجيل الدخول بالمفتاح',
                          style: TextStyle(
                            fontSize: AppDimensions.loginTitleSize,
                            fontWeight: FontWeight.bold,
                            color: theme.textTheme.headlineSmall?.color,
                          ),
                        ),
                        const SizedBox(height: AppDimensions.spacing8),
                        Text(
                          _tabController.index == 0 ? 'أدخل بريدك الإلكتروني وكلمة المرور' : 'أدخل مفتاح الاشتراك للمتابعة',
                          style: TextStyle(
                            fontSize: AppDimensions.loginSubtitleSize,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                        const SizedBox(height: AppDimensions.spacing24),

                        // Tab Bar
                        Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: TabBar(
                            controller: _tabController,
                            indicator: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            indicatorSize: TabBarIndicatorSize.tab,
                            labelColor: Colors.white,
                            unselectedLabelColor: theme.textTheme.bodySmall?.color,
                            dividerColor: Colors.transparent,
                            tabs: const [
                              Tab(text: 'البريد الإلكتروني'),
                              Tab(text: 'مفتاح الاشتراك'),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppDimensions.spacing24),

                        // Tab Views
                        SizedBox(
                          height: _tabController.index == 0 ? 300 : 250,
                          child: TabBarView(
                            controller: _tabController,
                            children: [_buildEmailLoginTab(theme), _buildLicenseKeyTab(theme)],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppDimensions.spacing24),

                // Links
                if (_tabController.index == 0) ...[
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
                ] else ...[
                  AppOutlineButton(
                    text: AppStrings.getKeyViaWhatsApp,
                    onPressed: _openWhatsApp,
                    gradientColors: const [AppColors.whatsappGreen, AppColors.whatsappGreen],
                    showShadow: false,
                    trailing: SvgPicture.asset(
                      'assets/icons/whatsapp.svg',
                      width: AppDimensions.whatsappIconSize,
                      height: AppDimensions.whatsappIconSize,
                      colorFilter: const ColorFilter.mode(AppColors.whatsappGreen, BlendMode.srcIn),
                    ),
                  ),
                ],
                const SizedBox(height: AppDimensions.spacing24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailLoginTab(ThemeData theme) {
    return Form(
      key: _emailFormKey,
      child: Column(
        children: [
          // Email Input
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
              if (value == null || value.isEmpty) return 'البريد الإلكتروني مطلوب';
              final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
              if (!emailRegex.hasMatch(value)) return 'بريد إلكتروني غير صالح';
              return null;
            },
          ),
          const SizedBox(height: AppDimensions.spacing16),

          // Password Input
          AppTextField(
            controller: _passwordController,
            focusNode: _focusNode,
            hintText: 'كلمة المرور',
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
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
          const Spacer(),

          // Error message
          Consumer<AuthProvider>(
            builder: (context, auth, _) {
              if (auth.errorMessage == null || _tabController.index != 0) return const SizedBox.shrink();
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

  Widget _buildLicenseKeyTab(ThemeData theme) {
    return Form(
      key: _licenseFormKey,
      child: Column(
        children: [
          // License Key Input
          _LicenseKeyTextField(
            controller: _licenseController,
            focusNode: _focusNode,
          ),
          const Spacer(),

          // Error message
          Consumer<AuthProvider>(
            builder: (context, auth, _) {
              if (auth.errorMessage == null || _tabController.index != 1) return const SizedBox.shrink();
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
                onPressed: auth.isLoading ? null : _handleLicenseLogin,
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

// Keep the existing _LicenseKeyTextField from the original file
class _LicenseKeyTextField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  const _LicenseKeyTextField({required this.controller, required this.focusNode});

  @override
  State<_LicenseKeyTextField> createState() => _LicenseKeyTextFieldState();
}

class _LicenseKeyTextFieldState extends State<_LicenseKeyTextField> {
  bool _showClearButton = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final showClear = widget.controller.text.isNotEmpty;
    if (showClear != _showClearButton) {
      setState(() => _showClearButton = showClear);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: AppDimensions.spacing4, bottom: AppDimensions.spacing8),
          child: Text(
            AppStrings.licenseKeyLabel,
            style: TextStyle(fontSize: AppDimensions.loginLabelSize, fontWeight: FontWeight.w500, color: theme.textTheme.labelLarge?.color),
          ),
        ),
        AppTextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          hintText: AppStrings.licenseKeyPlaceholder,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [UpperCaseTextFormatter()],
          maxLines: 1,
          suffixIcon: _showClearButton
              ? IconButton(
                  icon: const Icon(SolarLinearIcons.closeCircle, size: 20),
                  onPressed: () => widget.controller.clear(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: theme.textTheme.bodySmall?.color,
                )
              : null,
          validator: (value) {
            if (value == null || value.isEmpty) return AppStrings.errorLicenseRequired;
            return null;
          },
        ),
      ],
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
