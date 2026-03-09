import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/utils/url_launcher_utils.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../app/routes.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/strings_ar.dart';
import '../../../core/constants/dimensions.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_gradient_button.dart';
import '../../providers/auth_provider.dart';
import '../../../data/models/user_info.dart';
import '../../widgets/custom_dialog.dart';
import '../../../core/extensions/string_extension.dart';

/// Login screen with license key validation
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _licenseController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isValidFormat = false; // Real-time format validation state

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _licenseController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.login(_licenseController.text);

    if (!mounted) return;

    if (success) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.dashboard, (route) => false);
    }
  }

  void _openWhatsApp() async {
    final message = Uri.encodeComponent(
      'السَّلام عليكم، أرغب في الحصول على مفتاح اشتراك لتطبيق المدير.',
    );
    final whatsappUrl = 'https://wa.me/+963968478904?text=$message';
    await AppLauncher.launchSafeUrl(context, whatsappUrl);
  }

  Future<void> _switchToAccount(UserInfo account) async {
    final authProvider = context.read<AuthProvider>();
    await authProvider.switchAccount(account);

    if (!mounted) return;

    if (authProvider.isAuthenticated) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.dashboard, (route) => false);
    }
  }

  void _showRemoveAccountDialog(UserInfo account) {
    CustomDialog.show(
      context,
      title: AppStrings.removeAccount,
      message: AppStrings.confirmRemoveAccount,
      type: DialogType.warning,
      confirmText: AppStrings.removeAccount,
      cancelText: 'إلغاء',
      onConfirm: () {
        context.read<AuthProvider>().removeAccount(account);
      },
    );
  }

  Widget _buildSavedAccountsList(List<UserInfo> accounts, String? currentKey) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 12),
          child: Text(
            AppStrings.savedAccounts,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).textTheme.labelLarge?.color,
            ),
          ),
        ),
        ...accounts.map(
          (account) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _AccountCard(
              account: account,
              isActive:
                  account.licenseKey?.toUpperCase().trim() ==
                  currentKey?.toUpperCase().trim(),
              onTap: () => _switchToAccount(account),
              onRemove: () => _showRemoveAccountDialog(account),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Dynamic Background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.04),
                  Theme.of(context).scaffoldBackgroundColor,
                  Theme.of(
                    context,
                  ).colorScheme.secondary.withValues(alpha: 0.03),
                ],
              ),
            ),
          ),

          // Abstract Background Shapes (Blurred)
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Theme.of(
                      context,
                    ).colorScheme.secondary.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.paddingLarge,
                vertical: AppDimensions.paddingMedium,
              ),
              child: Column(
                children: [
                  SizedBox(height: size.height * 0.05),
                  // Header
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/images/transparent-logo.png',
                        height: 32,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        AppStrings.appName,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: size.height * 0.06),

                  // Saved Accounts List
                  Consumer<AuthProvider>(
                    builder: (context, auth, _) {
                      if (auth.accounts.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return _buildSavedAccountsList(
                        auth.accounts,
                        auth.userInfo?.licenseKey,
                      );
                    },
                  ),

                  // Login Card
                  Container(
                    width: double.infinity,
                    decoration: ShapeDecoration(
                      color: Theme.of(context).cardColor,
                      shape: SmoothRectangleBorder(
                        borderRadius: SmoothBorderRadius(
                          cornerRadius: 32,
                          cornerSmoothing: 1.0,
                        ),
                        side: BorderSide(
                          color: Theme.of(
                            context,
                          ).dividerColor.withValues(alpha: 0.5),
                        ),
                      ),
                      shadows: [
                        BoxShadow(
                          color: Theme.of(
                            context,
                          ).shadowColor.withValues(alpha: 0.1),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 36,
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            // Icon
                            Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Theme.of(context).colorScheme.primary,
                                    Theme.of(context).colorScheme.secondary,
                                  ],
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Theme.of(context).colorScheme.primary
                                        .withValues(alpha: 0.3),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                  const BoxShadow(
                                    color: Colors.transparent,
                                    blurRadius: 0,
                                    spreadRadius: -4,
                                    offset: Offset(-2, -2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                SolarLinearIcons.key,
                                color: Colors.white,
                                size: 42,
                              ),
                            ),
                            const SizedBox(height: 28),

                            // Title
                            Text(
                              AppStrings.loginTitle,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(
                                  context,
                                ).textTheme.headlineSmall?.color,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'أدخِل مفتاح الاشتراك للمتابعة', // Subtitle
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.color,
                              ),
                            ),
                            const SizedBox(height: 32),

                            // License Key Input
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                    right: 4,
                                    bottom: 8,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        AppStrings.licenseKeyLabel,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Theme.of(
                                            context,
                                          ).textTheme.labelLarge?.color,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                AppTextField(
                                  controller: _licenseController,
                                  hintText: 'MUDEER-XXXXXXXX-XXXXXXXX-XXXXXXXX',
                                  keyboardType: TextInputType.text,
                                  textInputAction: TextInputAction.done,
                                  onChanged: (value) {
                                    final auth = context.read<AuthProvider>();
                                    auth.clearError();
                                    setState(() {
                                      _isValidFormat = auth
                                          .validateLicenseFormat(value);
                                    });
                                  },
                                  onFieldSubmitted: (_) => _handleLogin(),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return AppStrings.errorLicenseRequired;
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Error Message
                            Consumer<AuthProvider>(
                              builder: (context, auth, _) {
                                if (auth.errorMessage == null) {
                                  return const SizedBox.shrink();
                                }
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: ShapeDecoration(
                                    color: AppColors.error.withValues(
                                      alpha: 0.05,
                                    ),
                                    shape: SmoothRectangleBorder(
                                      borderRadius: SmoothBorderRadius(
                                        cornerRadius: 16,
                                        cornerSmoothing: 1.0,
                                      ),
                                      side: BorderSide(
                                        color: AppColors.error.withValues(
                                          alpha: 0.2,
                                        ),
                                      ),
                                    ),
                                    shadows: [
                                      BoxShadow(
                                        color: AppColors.error.withValues(
                                          alpha: 0.05,
                                        ),
                                        blurRadius: 20,
                                        spreadRadius: 0,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: AppColors.error.withValues(
                                            alpha: 0.1,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          SolarLinearIcons.dangerCircle,
                                          color: AppColors.error,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'خطأ في تسجيل الدُّخول',
                                              style: TextStyle(
                                                color: AppColors.error,
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              auth.errorMessage!,
                                              style: TextStyle(
                                                color: AppColors.error
                                                    .withValues(alpha: 0.8),
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                                height: 1.4,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 32),

                            Consumer<AuthProvider>(
                              builder: (context, auth, _) {
                                return AppGradientButton(
                                  text: auth.isLoading
                                      ? AppStrings.loggingIn
                                      : AppStrings.loginButton,
                                  onPressed:
                                      (auth.isRateLimited || !_isValidFormat)
                                      ? null
                                      : _handleLogin,
                                  isLoading: auth.isLoading,
                                  gradientColors: [
                                    Theme.of(context).colorScheme.primary,
                                    Theme.of(context).colorScheme.secondary,
                                  ],
                                  showShadow: true,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: AppDimensions.spacing32),

                  AppGradientButton(
                    text: AppStrings.getKeyViaWhatsApp,
                    onPressed: _openWhatsApp,
                    gradientColors: const [
                      AppColors.whatsappGreen,
                      AppColors.whatsappGreen,
                    ],
                    showShadow: true,
                    trailing: SvgPicture.asset(
                      'assets/icons/whatsapp.svg',
                      width: 20,
                      height: 20,
                      colorFilter: const ColorFilter.mode(
                        Colors.white,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),

                  const SizedBox(height: AppDimensions.spacing48),
                ],
              ),
            ),
          ),
        ],
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

/// Account card widget for saved accounts list
class _AccountCard extends StatelessWidget {
  final UserInfo account;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _AccountCard({
    required this.account,
    required this.isActive,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '${account.fullName}, ${account.username != null ? "@${account.username}" : ""}',
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isActive ? null : onTap,
          onLongPress: onRemove,
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusXLarge,
            cornerSmoothing: 1.0,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.spacing16,
              vertical: AppDimensions.spacing12,
            ),
            decoration: BoxDecoration(
              color: isActive
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                  : Theme.of(context).cardColor,
              borderRadius: SmoothBorderRadius(
                cornerRadius: AppDimensions.radiusXLarge,
                cornerSmoothing: 1.0,
              ),
              border: Border.all(
                color: isActive
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.3)
                    : Theme.of(context).dividerColor.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  backgroundImage: account.profileImageUrl != null
                      ? NetworkImage(account.profileImageUrl!.toFullUrl)
                      : null,
                  child: account.profileImageUrl == null
                      ? Text(
                          account.fullName.isNotEmpty
                              ? account.fullName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.fullName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (account.username != null)
                        Text(
                          '@${account.username}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                    ],
                  ),
                ),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 14,
                    ),
                  )
                else
                  Icon(
                    SolarLinearIcons.arrowRight,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
