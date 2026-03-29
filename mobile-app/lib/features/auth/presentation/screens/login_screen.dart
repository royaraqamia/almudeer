import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:almudeer_mobile_app/core/utils/url_launcher_utils.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:almudeer_mobile_app/core/app/routes.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/constants/strings_ar.dart';
import 'package:almudeer_mobile_app/core/constants/dimensions.dart';
import 'package:almudeer_mobile_app/core/widgets/app_text_field.dart';
import 'package:almudeer_mobile_app/core/widgets/app_gradient_button.dart';
import 'package:almudeer_mobile_app/core/widgets/app_outline_button.dart';
import 'package:almudeer_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';

/// Login screen with license key validation
///
/// Design Principles:
/// - Visual hierarchy: Primary (Login) > Secondary (WhatsApp)
/// - Responsive: Adapts padding for small screens and landscape orientation
/// - Performance: Cached theme references, derived validation state, isolated widgets
/// - Accessibility: Proper semantics, loading states, WCAG compliant contrast
/// - Clean: Minimal background distractions for better conversion
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _licenseController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Listen to text changes for validation
    _licenseController.addListener(_onLicenseTextChanged);
  }

  @override
  void dispose() {
    _licenseController.removeListener(_onLicenseTextChanged);
    _licenseController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Update validation state when license key text changes
  void _onLicenseTextChanged() {
    // Trigger rebuild of widgets listening to controller
    setState(() {});
  }

  /// Computed property for landscape orientation
  bool get _isLandscape => MediaQuery.of(context).size.width >
      MediaQuery.of(context).size.height;

  /// Computed property for small screen detection
  bool get _isSmallScreen =>
      MediaQuery.of(context).size.height < AppDimensions.breakpointSmallHeight;

  /// Computed property for vertical padding based on screen state
  double get _screenVerticalPadding {
    if (_isLandscape) {
      return AppDimensions.paddingLarge;
    }
    return _isSmallScreen
        ? AppDimensions.loginScreenTopPaddingSmall
        : AppDimensions.loginScreenTopPaddingLarge;
  }

  /// Computed property for header margin based on screen state
  double get _headerMargin {
    if (_isLandscape) {
      return AppDimensions.spacing32;
    }
    return _isSmallScreen
        ? AppDimensions.loginScreenHeaderMarginSmall
        : AppDimensions.loginScreenHeaderMarginLarge;
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.login(_licenseController.text);

    if (!mounted) return;

    if (success) {
      // Haptic feedback on successful login
      Haptics.mediumTap();
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.dashboard, (route) => false);
    }
  }

  void _openWhatsApp() async {
    final message = Uri.encodeComponent(
      'ط§ظ„ط³ظژظ‘ظ„ط§ظ… ط¹ظ„ظٹظƒظ…طŒ ط£ط±ط؛ط¨ ظپظٹ ط§ظ„ط­طµظˆظ„ ط¹ظ„ظ‰ ظ…ظپطھط§ط­ ط§ط´طھط±ط§ظƒ ظ„طھط·ط¨ظٹظ‚ ط§ظ„ظ…ط¯ظٹط±.',
    );
    final whatsappUrl = 'https://wa.me/+963966478904?text=$message';
    await AppLauncher.launchSafeUrl(context, whatsappUrl);
  }

  /// Build the background - simplified to solid color for performance
  /// The subtle gradient was nearly imperceptible (4% alpha) and removed
  Widget _buildBackground(BuildContext context) {
    final theme = Theme.of(context);
    // Solid background color matching theme
    return Container(color: theme.scaffoldBackgroundColor);
  }

  /// Build the header section with logo and app name
  Widget _buildHeader() {
    final theme = Theme.of(context);
    return Column(
      children: [
        // Vertical spacing - documented: centers content on larger screens
        SizedBox(height: _headerMargin),
        // Header - RTL-safe logo implementation
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo with semantic label
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
        // Vertical spacing - documented: balances header with content below
        SizedBox(height: _headerMargin),
      ],
    );
  }

  /// Build feedback section (error messages and rate limit warnings)
  Widget _buildFeedbackSection({
    required AuthProvider auth,
    required bool isDark,
  }) {
    final hasError = auth.errorMessage != null;
    final isRateLimited = auth.isRateLimited;

    if (!hasError && !isRateLimited) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        if (hasError) ...[
          _ErrorMessageBanner(
            message: auth.errorMessage!,
            isDark: isDark,
          ),
          // Spacing between error and rate limit - documented: visual separation
          const SizedBox(height: AppDimensions.loginErrorMarginTop),
        ],
        if (isRateLimited) ...[
          _RateLimitBanner(isDark: isDark),
          // Spacing after feedback section before button
          const SizedBox(height: AppDimensions.loginErrorMarginTop),
        ],
      ],
    );
  }

  /// Build login card with validation state
  Widget _buildLoginCard(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        final cardHorizontalPadding = _isSmallScreen
            ? AppDimensions.loginCardHorizontalPaddingSmall
            : AppDimensions.loginCardHorizontalPaddingLarge;
        final cardVerticalPadding = _isSmallScreen
            ? AppDimensions.loginCardPaddingSmall
            : AppDimensions.loginCardPaddingLarge;

        return Container(
          width: double.infinity,
          constraints: const BoxConstraints(
            maxWidth: AppDimensions.loginCardMaxWidth,
          ),
          decoration: ShapeDecoration(
            color: theme.cardColor,
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(
                cornerRadius: AppDimensions.radiusLoginCard,
                cornerSmoothing: 1.0,
              ),
              side: BorderSide(
                color: isDark ? AppColors.borderDark : AppColors.borderLight,
                width: 1.0,
              ),
            ),
            shadows: [
              BoxShadow(
                color: isDark
                    ? AppColors.shadowPrimaryDark
                    : AppColors.shadowPrimaryLight,
                blurRadius: 24,
                offset: const Offset(0, 8),
                spreadRadius: 0,
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: cardHorizontalPadding,
              vertical: cardVerticalPadding,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  // Icon with gradient background - cached with RepaintBoundary
                  RepaintBoundary(
                    child: Container(
                      width: AppDimensions.loginIconContainerSize,
                      height: AppDimensions.loginIconContainerSize,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            theme.colorScheme.primary,
                            theme.colorScheme.secondary,
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        SolarLinearIcons.key,
                        color: Colors.white,
                        size: AppDimensions.loginIconSize,
                      ),
                    ),
                  ),
                  // Spacing after icon - documented: visual breathing room
                  const SizedBox(height: AppDimensions.loginIconMarginTop),

                  // Title
                  Text(
                    AppStrings.loginTitle,
                    style: TextStyle(
                      fontSize: AppDimensions.loginTitleSize,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                      color: theme.textTheme.headlineSmall?.color,
                    ),
                  ),
                  // Spacing after title
                  const SizedBox(height: AppDimensions.loginTitleMarginTop),
                  Text(
                    AppStrings.loginSubtitle,
                    style: TextStyle(
                      fontSize: AppDimensions.loginSubtitleSize,
                      letterSpacing: -0.2,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                  // Spacing after subtitle before input field
                  const SizedBox(height: AppDimensions.loginFieldMarginTop),

                  // License Key Input - Extracted to separate widget
                  _LicenseKeyTextField(
                    controller: _licenseController,
                    focusNode: _focusNode,
                    auth: auth,
                    onClearError: () => auth.clearError(),
                  ),
                  // Spacing after input field before feedback section
                  const SizedBox(height: AppDimensions.loginButtonMarginTop),

                  // Error Message and Rate Limit Warning - consolidated
                  _buildFeedbackSection(auth: auth, isDark: isDark),

                  // Login Button (Primary Action)
                  // Validate license format on every controller change
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _licenseController,
                    builder: (context, value, _) {
                      final text = value.text.trim().toUpperCase();
                      final isValid = auth.validateLicenseFormat(text);
                      return AppGradientButton(
                        text: auth.isLoading
                            ? AppStrings.loggingIn
                            : AppStrings.loginButton,
                        onPressed: (auth.isRateLimited || !isValid)
                            ? null
                            : _handleLogin,
                        isLoading: auth.isLoading,
                        gradientColors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.secondary,
                        ],
                        showShadow: true,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Build the "Or" divider section
  Widget _buildOrDivider() {
    return const Column(
      children: [
        // Spacing before divider - documented: visual separation
        SizedBox(height: AppDimensions.spacing24),
        _OrDivider(),
        // Spacing after divider before WhatsApp button
        SizedBox(height: AppDimensions.whatsappDividerMarginTop),
      ],
    );
  }

  /// Build WhatsApp button section
  Widget _buildWhatsAppButton() {
    return Column(
      children: [
        // WhatsApp Button (Secondary Action - Outline Style)
        AppOutlineButton(
          text: AppStrings.getKeyViaWhatsApp,
          onPressed: _openWhatsApp,
          gradientColors: const [
            AppColors.whatsappGreen,
            AppColors.whatsappGreen,
          ],
          showShadow: false,
          trailing: SvgPicture.asset(
            'assets/icons/whatsapp.svg',
            width: AppDimensions.whatsappIconSize,
            height: AppDimensions.whatsappIconSize,
            colorFilter: const ColorFilter.mode(
              AppColors.whatsappGreen,
              BlendMode.srcIn,
            ),
          ),
        ),
        // Spacing after WhatsApp button - documented: bottom margin
        const SizedBox(height: AppDimensions.loginWhatsAppMarginTop),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      // Dismiss keyboard on tap outside using TapRegion instead of GestureDetector
      onTapOutside: (_) => _focusNode.unfocus(),
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Stack(
          children: [
            // Simplified Background - Solid color for performance
            _buildBackground(context),

            SafeArea(
              child: SingleChildScrollView(
                // Dismiss keyboard on scroll
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.symmetric(
                  horizontal: _isSmallScreen
                      ? AppDimensions.paddingMedium
                      : AppDimensions.paddingLarge,
                  vertical: _screenVerticalPadding,
                ),
                child: Column(
                  children: [
                    // Header section
                    _buildHeader(),

                    // Login Card with validation state
                    _buildLoginCard(context),

                    // Add vertical space in landscape mode for centering
                    // Documented: 48px for visual centering in landscape orientation
                    if (_isLandscape)
                      const SizedBox(height: AppDimensions.spacing48),

                    // Or Divider section
                    _buildOrDivider(),

                    // WhatsApp Button section
                    _buildWhatsAppButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Text formatter to convert input to uppercase
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

/// Isolated license key text field widget
///
/// Extracted to avoid full-screen rebuilds when typing or showing clear button
class _LicenseKeyTextField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final AuthProvider auth;
  final VoidCallback onClearError;

  const _LicenseKeyTextField({
    required this.controller,
    required this.focusNode,
    required this.auth,
    required this.onClearError,
  });

  @override
  State<_LicenseKeyTextField> createState() => _LicenseKeyTextFieldState();
}

class _LicenseKeyTextFieldState extends State<_LicenseKeyTextField> {
  bool _showClearButton = false;
  bool _hasClipboardText = false;

  @override
  void initState() {
    super.initState();
    _updateClearButtonState(widget.controller.text);
    _checkClipboard();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    _updateClearButtonState(widget.controller.text);
    _checkClipboard();
    widget.onClearError();
  }

  void _updateClearButtonState(String value) {
    final showClear = value.isNotEmpty;
    if (showClear != _showClearButton) {
      setState(() {
        _showClearButton = showClear;
      });
    }
  }

  /// Check clipboard for paste functionality
  Future<void> _checkClipboard() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final hasText = clipboardData?.text != null &&
        clipboardData!.text!.trim().isNotEmpty;
    if (hasText != _hasClipboardText) {
      setState(() {
        _hasClipboardText = hasText;
      });
    }
  }

  /// Paste from clipboard
  Future<void> _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboardData?.text != null) {
      widget.controller.text = clipboardData!.text!.trim().toUpperCase();
      widget.onClearError();
      widget.focusNode.requestFocus();
      Haptics.lightTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            right: AppDimensions.spacing4,
            bottom: AppDimensions.spacing8,
          ),
          child: Text(
            AppStrings.licenseKeyLabel,
            style: TextStyle(
              fontSize: AppDimensions.loginLabelSize,
              fontWeight: FontWeight.w500,
              color: theme.textTheme.labelLarge?.color,
            ),
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
          autofocus: widget.auth.accounts.isEmpty,
          maxLines: 1, // Single-line field to prevent vertical caret movement issues
          suffixIcon: _buildSuffixIcon(theme),
          onChanged: (_) {
            // Update validation state via parent's listener
          },
          onFieldSubmitted: (_) {
            widget.focusNode.unfocus();
          },
          validator: (value) {
            if (value == null || value.isEmpty) {
              return AppStrings.errorLicenseRequired;
            }
            return null;
          },
        ),
        // Format hint - shown when input is non-empty but invalid
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.controller,
          builder: (context, value, _) {
            final text = value.text.trim().toUpperCase();
            final hasText = text.isNotEmpty;
            final isValid = widget.auth.validateLicenseFormat(text);
            if (hasText && !isValid) {
              return Padding(
                padding: const EdgeInsets.only(
                  top: AppDimensions.spacing8,
                  right: AppDimensions.spacing4,
                ),
                child: Text(
                  AppStrings.licenseKeyFormatHint,
                  style: TextStyle(
                    fontSize: AppDimensions.loginHintSize,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }

  /// Build suffix icon with clear and paste buttons
  Widget? _buildSuffixIcon(ThemeData theme) {
    if (_showClearButton) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Paste button (shown when clipboard has text and field is not empty)
          if (_hasClipboardText)
            IconButton(
              icon: const Icon(
                SolarLinearIcons.clipboard,
                size: 20,
              ),
              onPressed: _pasteFromClipboard,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              color: theme.colorScheme.primary,
              tooltip: AppStrings.pasteFromClipboard,
            ),
          // Clear button
          IconButton(
            icon: const Icon(
              SolarLinearIcons.closeCircle,
              size: 20,
            ),
            onPressed: () {
              widget.controller.clear();
              widget.onClearError();
              _showClearButton = false;
              widget.focusNode.requestFocus();
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            color: theme.textTheme.bodySmall?.color,
            tooltip: AppStrings.clear,
          ),
        ],
      );
    } else if (_hasClipboardText) {
      // Show only paste button when field is empty but clipboard has text
      return IconButton(
        icon: const Icon(
          SolarLinearIcons.clipboard,
          size: 20,
        ),
        onPressed: _pasteFromClipboard,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        color: theme.colorScheme.primary,
        tooltip: AppStrings.pasteFromClipboard,
      );
    }
    return null;
  }
}

/// Error message banner with improved visibility and contrast
class _ErrorMessageBanner extends StatelessWidget {
  final String message;
  final bool isDark;

  const _ErrorMessageBanner({
    required this.message,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    // Use high-contrast colors for better accessibility
    // Fixed: Consistent alpha values for both light and dark mode
    final errorColor = isDark ? AppColors.errorDark : AppColors.error;
    final backgroundColor = isDark
        ? AppColors.errorDark.withValues(alpha: 0.20)
        : AppColors.errorLight.withValues(alpha: 0.20);
    final borderColor = isDark
        ? AppColors.errorDark.withValues(alpha: 0.6)
        : AppColors.error.withValues(alpha: 0.4);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimensions.errorPadding),
      decoration: ShapeDecoration(
        color: backgroundColor,
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusLarge,
            cornerSmoothing: 1.0,
          ),
          side: BorderSide(
            color: borderColor,
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            SolarLinearIcons.dangerCircle,
            color: errorColor,
            size: AppDimensions.errorIconSize,
          ),
          const SizedBox(width: AppDimensions.errorIconMarginEnd),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: errorColor,
                fontSize: AppDimensions.loginErrorSize,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rate limit warning banner
class _RateLimitBanner extends StatelessWidget {
  final bool isDark;

  const _RateLimitBanner({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final warningColor =
        isDark ? AppColors.warningDark : AppColors.warning;
    final backgroundColor = isDark
        ? AppColors.warningDark.withValues(alpha: 0.20)
        : AppColors.warningLight.withValues(alpha: 0.20);
    final borderColor = isDark
        ? AppColors.warningDark.withValues(alpha: 0.6)
        : AppColors.warning.withValues(alpha: 0.4);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimensions.errorPadding),
      decoration: ShapeDecoration(
        color: backgroundColor,
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusLarge,
            cornerSmoothing: 1.0,
          ),
          side: BorderSide(
            color: borderColor,
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            SolarLinearIcons.infoCircle,
            color: warningColor,
            size: AppDimensions.errorIconSize,
          ),
          const SizedBox(width: AppDimensions.errorIconMarginEnd),
          Expanded(
            child: Text(
              AppStrings.rateLimitWarning,
              style: TextStyle(
                color: warningColor,
                fontSize: AppDimensions.loginErrorSize,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reusable "Or" divider component
class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Divider(
            color: theme.dividerColor.withValues(alpha: 0.5),
            thickness: 1,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacing16,
          ),
          child: Text(
            AppStrings.or,
            style: TextStyle(
              fontSize: AppDimensions.loginHintSize,
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
        ),
        Expanded(
          child: Divider(
            color: theme.dividerColor.withValues(alpha: 0.5),
            thickness: 1,
          ),
        ),
      ],
    );
  }
}
