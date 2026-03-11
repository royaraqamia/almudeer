import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:provider/provider.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/dimensions.dart';
import '../../../core/constants/animations.dart';
import '../../../core/constants/settings_strings.dart';
import '../../providers/auth_provider.dart';
import 'widgets/subscription_plans_section.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _progressController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
  }

  void _initAnimations() {
    // Main fade-in animation
    // Apple HIG: 350ms standard duration (was 600ms)
    _fadeController = AnimationController(
      duration: AppAnimations.standard,
      vsync: this,
    );

    // Progress circle animation
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: AppAnimations.enter,
    );

    _progressAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _progressController,
        curve: AppAnimations.primary,
      ),
    );

    _fadeController.forward();
    _progressController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return '-';
    try {
      final date = DateTime.parse(dateStr);
      HijriCalendar.setLocal('en');
      final hijriDate = HijriCalendar.fromDate(date);
      return hijriDate.toFormat('dd/mm/yyyy');
    } catch (e) {
      return dateStr;
    }
  }

  double _calculateProgress(int daysRemaining, int totalDays) {
    if (totalDays == 0) return 0;
    return daysRemaining / totalDays;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final authProvider = context.watch<AuthProvider>();
    final daysRemaining = authProvider.userInfo?.daysUntilExpiry ?? 0;
    final totalDays = 365; // Assuming yearly subscription
    final progress = _calculateProgress(daysRemaining, totalDays);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(theme, isDark),
      body: Stack(
        children: [
          // Background gradient decoration
          _buildBackgroundDecoration(isDark),
          // Main content
          SafeArea(
            child: _buildContent(
              theme,
              isDark,
              authProvider,
              daysRemaining,
              progress,
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme, bool isDark) {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 2,
      backgroundColor: theme.scaffoldBackgroundColor.withValues(alpha: 0.85),
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  theme.scaffoldBackgroundColor.withValues(alpha: 0.9),
                  theme.scaffoldBackgroundColor.withValues(alpha: 0.7),
                ],
              ),
            ),
          ),
        ),
      ),
      title: Text(
        'نظام الاشتراك',
        style: theme.textTheme.titleLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          color: isDark
              ? AppColors.textPrimaryDark
              : AppColors.textPrimaryLight,
        ),
      ),
      centerTitle: true,
      leading: _buildBackButton(isDark),
    );
  }

  Widget _buildBackButton(bool isDark) {
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: ShapeDecoration(
        color: isDark
            ? AppColors.surfaceDark.withValues(alpha: 0.5)
            : AppColors.surfaceLight.withValues(alpha: 0.5),
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusFull,
            cornerSmoothing: 1.0,
          ),
        ),
      ),
      child: IconButton(
        icon: const Icon(
          SolarLinearIcons.arrowRight,
          size: 22,
          color: AppColors.primary,
        ),
        onPressed: () => Navigator.of(context).pop(),
        tooltip: 'رجوع',
      ),
    );
  }

  Widget _buildBackgroundDecoration(bool isDark) {
    return Positioned.fill(
      child: Stack(
        children: [
          // Primary gradient orb (top-right)
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
                    AppColors.primary.withValues(alpha: isDark ? 0.15 : 0.1),
                    AppColors.primary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          // Secondary gradient orb (bottom-left)
          Positioned(
            bottom: -150,
            left: -150,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.accent.withValues(alpha: isDark ? 0.12 : 0.08),
                    AppColors.accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    ThemeData theme,
    bool isDark,
    AuthProvider authProvider,
    int daysRemaining,
    double progress,
  ) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(
        left: AppDimensions.paddingMedium,
        right: AppDimensions.paddingMedium,
        top: AppDimensions.spacing24,
        bottom: AppDimensions.paddingLarge,
      ),
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Membership Status Card
            _buildMembershipCard(
              theme,
              isDark,
              authProvider,
              daysRemaining,
              progress,
            ),
            const SizedBox(height: AppDimensions.spacing24),

            // Subscription Plans
            _buildSubscriptionPlansSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildMembershipCard(
    ThemeData theme,
    bool isDark,
    AuthProvider authProvider,
    int daysRemaining,
    double progress,
  ) {
    final expiresAt = authProvider.userInfo?.expiresAt ?? '';
    final isActive = daysRemaining > 0;

    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: _fadeController,
              curve: AppAnimations.decelerate,
            ),
          ),
      child: Container(
        decoration: ShapeDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isActive
                ? [
                    AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.05),
                    AppColors.accent.withValues(alpha: isDark ? 0.15 : 0.08),
                  ]
                : [
                    AppColors.error.withValues(alpha: isDark ? 0.15 : 0.05),
                    AppColors.warning.withValues(alpha: isDark ? 0.12 : 0.04),
                  ],
          ),
          shape: SmoothRectangleBorder(
            borderRadius: SmoothBorderRadius(
              cornerRadius: AppDimensions.radiusXXLarge,
              cornerSmoothing: 1.0,
            ),
            side: BorderSide(
              color: isActive
                  ? AppColors.primary.withValues(alpha: isDark ? 0.3 : 0.15)
                  : AppColors.error.withValues(alpha: isDark ? 0.3 : 0.15),
              width: 1.5,
            ),
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Subtle shine effect
            Positioned(
              top: -50,
              right: -50,
              child: Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: isActive ? 0.1 : 0.05),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(AppDimensions.paddingLarge),
              child: Column(
                children: [
                  // Header with icon and status
                  Row(
                    children: [
                      _buildStatusIcon(isActive, isDark),
                      const SizedBox(width: AppDimensions.spacing12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isActive ? 'اشتراك نشط' : 'انتهى الاشتراك',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: isActive
                                    ? (isDark
                                          ? AppColors.textPrimaryDark
                                          : AppColors.textPrimaryLight)
                                    : AppColors.error,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              SettingsStrings.subscriptionEnds,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondaryLight,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDimensions.spacing20),

                  // Progress section
                  Row(
                    children: [
                      // Circular progress indicator
                      _buildCircularProgress(progress, isActive, isDark),
                      const SizedBox(width: AppDimensions.spacing16),
                      // Text info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatDate(expiresAt),
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 20,
                                color: isDark
                                    ? AppColors.textPrimaryDark
                                    : AppColors.textPrimaryLight,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: ShapeDecoration(
                                color:
                                    (isActive
                                            ? AppColors.success
                                            : AppColors.error)
                                        .withValues(alpha: isDark ? 0.2 : 0.1),
                                shape: SmoothRectangleBorder(
                                  borderRadius: SmoothBorderRadius(
                                    cornerRadius: AppDimensions.radiusFull,
                                    cornerSmoothing: 1.0,
                                  ),
                                ),
                              ),
                              child: Text(
                                SettingsStrings.daysRemaining.replaceAll(
                                  '@days',
                                  daysRemaining.toString(),
                                ),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isActive
                                      ? AppColors.success
                                      : AppColors.error,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(bool isActive, bool isDark) {
    return AnimatedContainer(
      duration: AppAnimations.normal,
      width: 52,
      height: 52,
      decoration: ShapeDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isActive
              ? [
                  AppColors.primary.withValues(alpha: 0.2),
                  AppColors.accent.withValues(alpha: 0.15),
                ]
              : [
                  AppColors.error.withValues(alpha: 0.2),
                  AppColors.warning.withValues(alpha: 0.15),
                ],
        ),
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: 14,
            cornerSmoothing: 1.0,
          ),
        ),
      ),
      child: Icon(
        isActive ? SolarLinearIcons.calendarMark : SolarLinearIcons.closeCircle,
        size: 26,
        color: isActive ? AppColors.primary : AppColors.error,
      ),
    );
  }

  Widget _buildCircularProgress(double progress, bool isActive, bool isDark) {
    return AnimatedBuilder(
      animation: _progressAnimation,
      builder: (context, child) {
        return SizedBox(
          width: 72,
          height: 72,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Background circle
              CustomPaint(
                size: const Size(72, 72),
                painter: _CircularProgressPainter(
                  progress: 0,
                  strokeWidth: 6,
                  color: isDark
                      ? AppColors.surfaceDark
                      : AppColors.surfaceLight,
                ),
              ),
              // Progress arc
              CustomPaint(
                size: const Size(72, 72),
                painter: _CircularProgressPainter(
                  progress: progress * _progressAnimation.value,
                  strokeWidth: 6,
                  color: isActive ? AppColors.primary : AppColors.error,
                  hasGradient: true,
                  isDark: isDark,
                ),
              ),
              // Center percentage text
              Text(
                '${(progress * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: isActive ? AppColors.primary : AppColors.error,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSubscriptionPlansSection() {
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: _fadeController,
              curve: AppAnimations.decelerate,
            ),
          ),
      child: const SubscriptionPlansSection(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Custom Painter for Circular Progress
// ─────────────────────────────────────────────────────────────────
class _CircularProgressPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color color;
  final bool hasGradient;
  final bool isDark;

  _CircularProgressPainter({
    required this.progress,
    required this.strokeWidth,
    required this.color,
    this.hasGradient = false,
    this.isDark = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background paint
    final bgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Progress paint
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    if (hasGradient) {
      progressPaint.shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: [
          AppColors.primary,
          AppColors.accent,
        ].map((c) => isDark ? c.withValues(alpha: 0.9) : c).toList(),
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    }

    // Draw background circle
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2,
      false,
      bgPaint,
    );

    // Draw progress arc
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.hasGradient != hasGradient;
  }
}
