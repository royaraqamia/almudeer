import 'package:flutter/material.dart';
import 'package:almudeer_mobile_app/core/utils/url_launcher_utils.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:provider/provider.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/constants/animations.dart';
import 'package:almudeer_mobile_app/core/app/routes.dart';
import 'package:almudeer_mobile_app/features/users/data/models/user_info.dart';
import 'package:almudeer_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'animated_toast.dart';
import 'premium_bottom_sheet.dart';

import 'package:almudeer_mobile_app/core/utils/haptics.dart';

import 'package:almudeer_mobile_app/core/widgets/app_text_field.dart';
import 'package:almudeer_mobile_app/core/widgets/app_gradient_button.dart';
import 'package:almudeer_mobile_app/core/widgets/app_avatar.dart';

class CustomDrawer extends StatefulWidget {
  final int currentIndex;
  final Function(int) onIndexChanged;
  const CustomDrawer({
    super.key,
    required this.currentIndex,
    required this.onIndexChanged,
  });

  @override
  State<CustomDrawer> createState() => _CustomDrawerState();
}

class _CustomDrawerState extends State<CustomDrawer>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  bool _isAccountsExpanded = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration:
          AppAnimations.slow, // Apple standard: 400ms for drawer (was 800ms)
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  bool _isAddingAccount = false;

  void _showAddAccountSheet(BuildContext context) {
    Haptics.selection();
    final controller = TextEditingController();
    final authProvider = context.read<AuthProvider>();

    PremiumBottomSheet.show(
      context: context,
      title: 'ط¥ط¶ط§ظپط© ط­ط³ط§ط¨ ط¬ط¯ظٹط¯',
      child: StatefulBuilder(
        builder: (context, setSheetState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextField(
                controller: controller,
                hintText: 'MUDEER-XXXXXXXX-XXXXXXXX-XXXXXXXX',
                enabled: !_isAddingAccount,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setSheetState(() {}),
              ),
              const SizedBox(height: 32),
              AppGradientButton(
                onPressed:
                    controller.text.trim().isEmpty ||
                        !context.read<AuthProvider>().validateLicenseFormat(
                          controller.text,
                        ) ||
                        _isAddingAccount
                    ? null
                    : () async {
                        if (!context.read<AuthProvider>().validateLicenseFormat(
                          controller.text,
                        )) {
                          return;
                        }
                        Haptics.mediumTap();

                        setSheetState(() => _isAddingAccount = true);

                        try {
                          final success = await authProvider.addAccount(
                            controller.text,
                          );
                          if (success && context.mounted) {
                            Navigator.pop(context);
                            AnimatedToast.success(
                              context,
                              'طھظ…ظ‘ظژ ط¥ط¶ط§ظپط© ط§ظ„ط­ط³ط§ط¨ ط¨ظ†ط¬ط§ط­',
                            );
                            setState(() => _isAccountsExpanded = false);
                          } else if (context.mounted) {
                            AnimatedToast.error(
                              context,
                              authProvider.errorMessage ?? 'ظپط´ظ„ ط¥ط¶ط§ظپط© ط§ظ„ط­ط³ط§ط¨',
                            );
                          }
                        } finally {
                          if (context.mounted) {
                            setSheetState(() => _isAddingAccount = false);
                          }
                        }
                      },
                text: 'ط¥ط¶ط§ظپط©',
                isLoading: _isAddingAccount,
                gradientColors: const [Color(0xFF2563EB), Color(0xFF0891B2)],
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.userInfo;
    final allAccounts = authProvider.accounts;

    return Drawer(
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Container(
            decoration: ShapeDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.surfaceDark
                  : theme.scaffoldBackgroundColor,
              shape: SmoothRectangleBorder(
                borderRadius: SmoothBorderRadius(
                  cornerRadius: 28,
                  cornerSmoothing: 1.0,
                ),
                side: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              shadows: [
                if (Theme.of(context).brightness != Brightness.dark)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 40,
                    offset: const Offset(0, 10),
                  ),
              ],
            ),
            child: ClipSmoothRect(
              radius: SmoothBorderRadius(
                cornerRadius: 28,
                cornerSmoothing: 1.0,
              ),
              child: Column(
                children: [
                  _buildPremiumHeader(context, currentUser, allAccounts),
                  Expanded(
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      children: [
                        _buildStaggeredItem(
                          index: 0,
                          child: _buildAccountsAccordion(
                            context,
                            authProvider,
                            allAccounts,
                            currentUser,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          child: Divider(
                            height: 1,
                            thickness: 0.5,
                            color: theme.dividerColor.withValues(alpha: 0.1),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._buildMainMenuItems(context),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStaggeredItem({required int index, required Widget child}) {
    final animation = CurvedAnimation(
      parent: _animationController,
      curve: Interval(
        (index * 0.1).clamp(0.0, 1.0),
        ((index * 0.1) + 0.4).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - animation.value)),
          child: Opacity(opacity: animation.value, child: child),
        );
      },
      child: child,
    );
  }

  Widget _buildPremiumHeader(
    BuildContext context,
    UserInfo? currentUser,
    List<UserInfo> allAccounts,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(color: Colors.transparent),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [Spacer()]),
              const SizedBox(height: 24),
              if (currentUser?.username != null &&
                  currentUser!.username!.isNotEmpty)
                Text(
                  currentUser.username!,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
              Text(
                currentUser?.fullName ?? 'ط§ظ„ظ…ط¯ظٹط±',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimaryLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountsAccordion(
    BuildContext context,
    AuthProvider authProvider,
    List<UserInfo> allAccounts,
    UserInfo? currentUser,
  ) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const PageStorageKey('accounts_expansion'),
        initiallyExpanded: _isAccountsExpanded,
        onExpansionChanged: (val) {
          Haptics.selection();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _isAccountsExpanded = val);
            }
          });
        },
        leading: _buildIconContainer(
          SolarLinearIcons.usersGroupTwoRounded,
          AppColors.primary,
        ),
        title: const Text(
          'طھط¨ط¯ظٹظ„ ط§ظ„ط­ط³ط§ط¨',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.normal, fontSize: 16),
        ),
        trailing: AnimatedRotation(
          turns: _isAccountsExpanded ? 0.5 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: const Icon(
            SolarLinearIcons.altArrowDown,
            color: AppColors.primary,
            size: 24,
          ),
        ),
        iconColor: AppColors.primary,
        children: [
          ...allAccounts.map(
            (account) => _buildAccountItem(
              account,
              authProvider,
              isActive: account.licenseKey == currentUser?.licenseKey,
            ),
          ),
          _buildAddAccountItem(context),
        ],
      ),
    );
  }

  Widget _buildAccountItem(
    UserInfo account,
    AuthProvider authProvider, {
    bool isActive = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 32, bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          onTap: () async {
            Haptics.mediumTap();
            if (!isActive) {
              // Close drawer first
              Navigator.pop(context);

              // Switch account (this triggers provider resets)
              await authProvider.switchAccount(account);

              // Navigate to dashboard root, clearing all navigation stack
              // This ensures all screens are fresh with new account data
              if (mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil(
                  AppRoutes.dashboard,
                  (route) => false,
                );
              }
            }
          },
          dense: true,
          horizontalTitleGap: 8,
          hoverColor: AppColors.primary.withValues(alpha: 0.05),
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              AppAvatar(
                radius: 16,
                imageUrl: account.profileImageUrl,
                initials: account.fullName.isNotEmpty
                    ? account.fullName[0]
                    : null,
              ),
              if (isActive)
                Positioned(
                  left: -2,
                  bottom: -2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      SolarBoldIcons.checkCircle,
                      color: AppColors.success,
                      size: 16,
                    ),
                  ),
                ),
            ],
          ),
          title: Text(
            account.fullName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 16,
              color: isActive ? AppColors.primary : null,
            ),
          ),
          shape: SmoothRectangleBorder(
            borderRadius: SmoothBorderRadius(
              cornerRadius: 16,
              cornerSmoothing: 1.0,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddAccountItem(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 32, bottom: 12),
      child: ListTile(
        onTap: () => _showAddAccountSheet(context),
        dense: true,
        leading: const Icon(
          SolarLinearIcons.addSquare,
          color: AppColors.success,
          size: 24,
        ),
        title: const Text(
          'ط¥ط¶ط§ظپط© ط­ط³ط§ط¨ ط¬ط¯ظٹط¯',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.normal,
            fontSize: 16,
            color: AppColors.success,
          ),
        ),
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: 16,
            cornerSmoothing: 1.0,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMainMenuItems(BuildContext context) {
    final List<Map<String, dynamic>> items = [
      {
        'icon': SolarLinearIcons.starFallMinimalistic,
        'label': 'ظ†ط¸ط§ظ… ط§ظ„ط§ط´طھط±ط§ظƒ',
        'onTap': () => Navigator.of(context).pushNamed(AppRoutes.subscription),
      },
      {
        'icon': SolarLinearIcons.chatRoundLine,
        'label': 'طھظˆط§طµظ„ ظ…ط¹ظ†ط§',
        'onTap': () async {
          Haptics.lightTap();
          await AppLauncher.launchSafeUrl(
            context,
            'https://wa.me/+963968478904',
          );
        },
      },
      {
        'icon': SolarLinearIcons.settingsMinimalistic,
        'label': 'ط§ظ„ط¥ط¹ط¯ط§ط¯ط§طھ',
        'onTap': () {
          Navigator.pop(context);
          Navigator.of(context).pushNamed(AppRoutes.settingsRoute);
        },
      },
    ];

    return items
        .asMap()
        .entries
        .map(
          (entry) => _buildStaggeredItem(
            index: entry.key + 1,
            child: _buildDrawerItem(
              icon: entry.value['icon'],
              label: entry.value['label'],
              index: entry.value['index'],
              onTap: entry.value['onTap'],
            ),
          ),
        )
        .toList();
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    int? index,
    bool isLoading = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = index != null && widget.currentIndex == index;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Haptics.selection();
            onTap();
          },
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: ShapeDecoration(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.08)
                  : Colors.transparent,
              shape: SmoothRectangleBorder(
                borderRadius: SmoothBorderRadius(
                  cornerRadius: 20,
                  cornerSmoothing: 1.0,
                ),
                side: BorderSide(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.1)
                      : Colors.transparent,
                ),
              ),
            ),
            child: Row(
              children: [
                _buildIconContainer(
                  icon,
                  isSelected
                      ? AppColors.primary
                      : (isDark
                            ? AppColors.textSecondaryDark
                            : Colors.grey[600]!),
                  isSelected: isSelected,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.normal,
                      fontSize: 16,
                      color: isSelected
                          ? AppColors.primary
                          : (isDark
                                ? AppColors.textPrimaryDark
                                : Colors.grey[800]),
                    ),
                  ),
                ),
                if (isSelected) ...[
                  const Spacer(),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
                if (isLoading) ...[
                  const Spacer(),
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(AppColors.primary),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconContainer(
    IconData icon,
    Color color, {
    bool isSelected = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: ShapeDecoration(
        color: isSelected
            ? color.withValues(alpha: 0.12)
            : color.withValues(alpha: 0.06),
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: 14,
            cornerSmoothing: 1.0,
          ),
        ),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }
}
