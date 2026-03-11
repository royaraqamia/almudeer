import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/dimensions.dart';
import '../../../../core/constants/animations.dart';
import '../../../../core/constants/settings_strings.dart';
import '../../../providers/auth_provider.dart';

class SubscriptionPlansSection extends StatefulWidget {
  const SubscriptionPlansSection({super.key});

  @override
  State<SubscriptionPlansSection> createState() =>
      _SubscriptionPlansSectionState();
}

class _SubscriptionPlansSectionState extends State<SubscriptionPlansSection>
    with SingleTickerProviderStateMixin {
  bool isYearly = true;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  
  // Loading state for subscription action
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: AppAnimations.interactive),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final prefersReducedMotion = AppAnimations.prefersReducedMotion(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimensions.paddingLarge),
      decoration: ShapeDecoration(
        color: isDark ? const Color(0xFF101928) : AppColors.surfaceLight,
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusXXLarge,
            cornerSmoothing: 1.0,
          ),
          side: BorderSide(
            color: isDark ? const Color(0xFF1D2939) : AppColors.borderLight,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Plan Selector Toggle
          _buildPlanToggle(isDark, prefersReducedMotion),
          const SizedBox(height: AppDimensions.spacing32),

          // Price Display
          _buildPriceDisplay(isDark),
          const SizedBox(height: AppDimensions.spacing24),

          // Features List
          _buildFeaturesList(isDark),
          const SizedBox(height: AppDimensions.spacing24),

          // Subscribe Button
          _buildSubscribeButton(isDark, prefersReducedMotion),
        ],
      ),
    );
  }

  Widget _buildPlanToggle(bool isDark, bool prefersReducedMotion) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          height: 52,
          padding: const EdgeInsets.all(4),
          decoration: ShapeDecoration(
            color: isDark ? const Color(0xFF0B101A) : Colors.grey.shade200,
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(
                cornerRadius: AppDimensions.radiusFull,
                cornerSmoothing: 1.0,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildToggleButton(
                  title: 'شهري',
                  isSelected: !isYearly,
                  onTap: () {
                    if (!isYearly) return;
                    _controller.forward().then((_) => _controller.reverse());
                    setState(() => isYearly = false);
                  },
                ),
              ),
              Expanded(
                child: _buildToggleButton(
                  title: 'سنوي',
                  isSelected: isYearly,
                  onTap: () {
                    if (isYearly) return;
                    _controller.forward().then((_) => _controller.reverse());
                    setState(() => isYearly = true);
                  },
                  icon: const Icon(SolarLinearIcons.stars, size: 15),
                ),
              ),
            ],
          ),
        ),
        if (isYearly)
          Positioned(
            top: -8,
            left: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: ShapeDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                ),
                shape: SmoothRectangleBorder(
                  borderRadius: SmoothBorderRadius(
                    cornerRadius: AppDimensions.radiusFull,
                    cornerSmoothing: 1.0,
                  ),
                ),
                shadows: [
                  BoxShadow(
                    color: AppColors.success.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(SolarLinearIcons.tag, size: 12, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'وفر 25%',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildToggleButton({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
    Widget? icon,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppAnimations.standard,
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          shape: SmoothRectangleBorder(
            borderRadius: SmoothBorderRadius(
              cornerRadius: AppDimensions.radiusFull,
              cornerSmoothing: 1.0,
            ),
          ),
          shadows: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              IconTheme(
                data: IconThemeData(
                  color: isSelected
                      ? Colors.white
                      : AppColors.textTertiaryLight,
                  size: 15,
                ),
                child: icon,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              title,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : (isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight),
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceDisplay(bool isDark) {
    final price = isYearly ? '90' : '10';
    final period = isYearly ? 'سنة' : 'شهر';

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '\$',
              style: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
                fontSize: 24,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
            const SizedBox(width: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) {
                return ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              child: Text(
                price,
                key: ValueKey(isYearly),
                style: TextStyle(
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimaryLight,
                  fontSize: 64,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: -2,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              ' / $period',
              style: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (isYearly) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: ShapeDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              shape: SmoothRectangleBorder(
                borderRadius: SmoothBorderRadius(
                  cornerRadius: AppDimensions.radiusFull,
                  cornerSmoothing: 1.0,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '7.5\$/شهر',
                  style: TextStyle(
                    color: Color(0xFF10B981),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '•',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textTertiaryDark
                        : AppColors.textTertiaryLight,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '120\$/سنة',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textTertiaryDark
                        : AppColors.textTertiaryLight,
                    decoration: TextDecoration.lineThrough,
                    decorationThickness: 1.5,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFeaturesList(bool isDark) {
    final features = [
      {'icon': SolarLinearIcons.checkCircle, 'text': 'جميع الميزات الأساسية'},
      {
        'icon': SolarLinearIcons.usersGroupTwoRounded,
        'text': 'عدد غير محدود من المستخدمين',
      },
      {'icon': SolarLinearIcons.clockCircle, 'text': 'دعم فني على مدار الساعة'},
      {'icon': SolarLinearIcons.cloud, 'text': 'تحديثات مجانية مستمرة'},
    ];

    return Column(
      children: [
        ...features.asMap().entries.map((entry) {
          final index = entry.key;
          final feature = entry.value;
          return Padding(
            padding: EdgeInsets.only(
              bottom: index < features.length - 1 ? 12 : 0,
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: ShapeDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    shape: SmoothRectangleBorder(
                      borderRadius: SmoothBorderRadius(
                        cornerRadius: 6,
                        cornerSmoothing: 1.0,
                      ),
                    ),
                  ),
                  child: Icon(
                    feature['icon'] as IconData,
                    size: 14,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  feature['text'] as String,
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSubscribeButton(bool isDark, bool prefersReducedMotion) {
    final authProvider = context.watch<AuthProvider>();
    final isSubscribed = (authProvider.userInfo?.daysUntilExpiry ?? 0) > 0;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        width: double.infinity,
        height: AppDimensions.buttonHeightLarge,
        decoration: ShapeDecoration(
          gradient: LinearGradient(
            colors: isSubscribed
                ? [AppColors.surfaceCardDark, AppColors.surfaceDark]
                : [AppColors.primary, AppColors.primaryDark],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          shape: SmoothRectangleBorder(
            borderRadius: SmoothBorderRadius(
              cornerRadius: AppDimensions.radiusButton,
              cornerSmoothing: 1.0,
            ),
          ),
          shadows: isSubscribed
              ? null
              : [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isSubscribed ? null : _handleSubscribe,
            borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!isSubscribed && !_isLoading) ...[
                    const Icon(
                      SolarLinearIcons.wallet,
                      size: 20,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (_isLoading) ...[
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Text(
                    isSubscribed
                        ? SettingsStrings.subscriptionActive
                        : SettingsStrings.subscribeNow,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
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

  /// Handle subscription action
  Future<void> _handleSubscribe() async {
    setState(() => _isLoading = true);

    try {
      // For now, just simulate a loading state
      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;

      // Example: Navigate to payment screen or show payment options dialog
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isYearly 
                ? 'سيتم توجيهك للدفع السنوي (90\$)' 
                : 'سيتم توجيهك للدفع الشهري (10\$/شهر)'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(
                cornerRadius: AppDimensions.radiusMedium,
                cornerSmoothing: 1.0,
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: SmoothRectangleBorder(
            borderRadius: SmoothBorderRadius(
              cornerRadius: AppDimensions.radiusMedium,
              cornerSmoothing: 1.0,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
