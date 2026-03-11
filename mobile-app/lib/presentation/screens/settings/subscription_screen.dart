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
import '../../../data/models/user_info.dart';
import '../../providers/auth_provider.dart';
import 'widgets/subscription_plans_section.dart';

/// Apple HIG: Progress indicators should complete in 1-2 seconds
const Duration _progressAnimationDuration = Duration(milliseconds: 1400);

/// Maximum subscription duration in days (10 years)
const int _maxSubscriptionDays = 3650;

/// Default subscription duration in days (1 year)
const int _defaultSubscriptionDays = 365;

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
  late bool _prefersReducedMotion;

  // Cache for formatted dates to avoid redundant Hijri conversions
  final Map<String, String> _dateCache = {};

  @override
  void initState() {
    super.initState();
    _prefersReducedMotion = AppAnimations.prefersReducedMotion(context);
    _initAnimations();
  }

  void _initAnimations() {
    // Main fade-in animation
    // Apple HIG: 350ms standard duration
    final fadeDuration = _prefersReducedMotion
        ? Duration.zero
        : AppAnimations.standard;
    _fadeController = AnimationController(
      duration: fadeDuration,
      vsync: this,
    );

    // Progress circle animation
    final progressDuration = _prefersReducedMotion
        ? Duration.zero
        : _progressAnimationDuration;
    _progressController = AnimationController(
      duration: progressDuration,
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: _prefersReducedMotion ? Curves.linear : AppAnimations.enter,
    );

    _progressAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _progressController,
        curve: _prefersReducedMotion ? Curves.linear : AppAnimations.primary,
      ),
    );

    // Start animations after first frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fadeController.forward();
      _progressController.forward();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _progressController.dispose();
    _dateCache.clear();
    super.dispose();
  }

  /// Format date using Hijri calendar with caching
  ///
  /// Uses Arabic locale for Hijri conversion regardless of app language
  /// as per Islamic calendar standards.
  String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return '-';

    // Check cache first
    final cached = _dateCache[dateStr];
    if (cached != null) return cached;

    try {
      final date = DateTime.parse(dateStr);
      HijriCalendar.setLocal('ar');
      final hijriDate = HijriCalendar.fromDate(date);
      final formatted = hijriDate.toFormat('dd MMMM yyyy');

      // Cache the result
      _dateCache[dateStr] = formatted;
      return formatted;
    } catch (e) {
      debugPrint('[SubscriptionScreen] Date parse error: $e, input: $dateStr');
      return dateStr;
    }
  }

  double _calculateProgress(int daysRemaining, int totalDays) {
    if (totalDays == 0) return 0;
    return (daysRemaining / totalDays).clamp(0.0, 1.0);
  }

  /// Calculate total subscription duration in days
  ///
  /// Uses createdAt and expiresAt to determine the subscription period.
  /// Falls back to 365 days if dates are unavailable.
  int _calculateTotalSubscriptionDays(UserInfo userInfo) {
    try {
      final createdAt = userInfo.createdAt;
      final expiresAt = userInfo.expiresAt;
      if (createdAt != null &&
          createdAt.isNotEmpty &&
          expiresAt.isNotEmpty) {
        final startDate = DateTime.parse(createdAt);
        final endDate = DateTime.parse(expiresAt);
        final totalDays = endDate.difference(startDate).inDays;
        // Sanity check: should be between 1 and max subscription days
        if (totalDays > 0 && totalDays <= _maxSubscriptionDays) {
          return totalDays;
        }
      }
    } catch (e) {
      debugPrint('[SubscriptionScreen] Error calculating total days: $e');
    }
    // Default to 365 days (yearly subscription)
    return _defaultSubscriptionDays;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final authProvider = context.watch<AuthProvider>();

    // Show loading state while user info is being fetched
    if (authProvider.isLoading || authProvider.userInfo == null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: _buildAppBar(theme, isDark),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Check for error state
    if (authProvider.errorMessage != null && authProvider.userInfo == null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: _buildAppBar(theme, isDark),
        body: _buildErrorState(theme, authProvider.errorMessage!),
      );
    }

    // Safe to access userInfo after null check
    final userInfo = authProvider.userInfo!;
    final daysRemaining = userInfo.daysUntilExpiry;
    final totalDays = _calculateTotalSubscriptionDays(userInfo);
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
              userInfo,
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
        SettingsStrings.subscriptionSystem,
        semanticsLabel: 'Subscription System',
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
      child: Semantics(
        label: SettingsStrings.back,
        child: IconButton(
          icon: const Icon(
            SolarLinearIcons.arrowRight,
            size: 22,
            color: AppColors.primary,
          ),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: SettingsStrings.back,
        ),
      ),
    );
  }

  Widget _buildBackgroundDecoration(bool isDark) {
    return Stack(
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
                  AppColors.primary.withValues(alpha: 0.0),
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
                  AppColors.accent.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(ThemeData theme, String errorMessage) {
    final isDark = theme.brightness == Brightness.dark;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.paddingLarge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              SolarLinearIcons.closeCircle,
              size: 64,
              color: AppColors.error,
            ),
            const SizedBox(height: AppDimensions.spacing24),
            Text(
              SettingsStrings.loadingError,
              style: theme.textTheme.titleMedium?.copyWith(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppDimensions.spacing12),
            Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
            const SizedBox(height: AppDimensions.spacing32),
            ElevatedButton.icon(
              onPressed: () {
                context.read<AuthProvider>().init();
              },
              icon: const Icon(SolarLinearIcons.refresh),
              label: const Text(SettingsStrings.retry),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.spacing32,
                  vertical: AppDimensions.spacing12,
                ),
                shape: SmoothRectangleBorder(
                  borderRadius: SmoothBorderRadius(
                    cornerRadius: AppDimensions.radiusButton,
                    cornerSmoothing: 1.0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    ThemeData theme,
    bool isDark,
    AuthProvider authProvider,
    int daysRemaining,
    double progress,
    UserInfo userInfo,
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
              userInfo,
            ),
            const SizedBox(height: AppDimensions.spacing24),

            // Subscription Plans with error boundary
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
    UserInfo userInfo,
  ) {
    final expiresAt = userInfo.expiresAt;
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
                            Semantics(
                              label: isActive
                                  ? SettingsStrings.activeSubscriptionSemantics
                                  : SettingsStrings.expiredSubscriptionSemantics,
                              child: Text(
                                isActive
                                    ? SettingsStrings.activeSubscription
                                    : SettingsStrings.expiredSubscription,
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
                            Semantics(
                              label: '${SettingsStrings.expiresOn} ${_formatDate(expiresAt)}',
                              child: Text(
                                _formatDate(expiresAt),
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 20,
                                  color: isDark
                                      ? AppColors.textPrimaryDark
                                      : AppColors.textPrimaryLight,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Semantics(
                              label: SettingsStrings.daysRemainingSemantics
                                  .replaceAll('@days', daysRemaining.toString()),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: ShapeDecoration(
                                  color: (isActive
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
                                  SettingsStrings.daysRemainingLabel
                                      .replaceAll('@days', daysRemaining.toString()),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isActive
                                        ? AppColors.success
                                        : AppColors.error,
                                    fontWeight: FontWeight.w700,
                                  ),
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
      width: AppDimensions.statusIconSize,
      height: AppDimensions.statusIconSize,
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
        isActive
            ? SolarLinearIcons.calendarMark
            : SolarLinearIcons.closeCircle,
        size: 26,
        color: isActive ? AppColors.primary : AppColors.error,
      ),
    );
  }

  Widget _buildCircularProgress(double progress, bool isActive, bool isDark) {
    final progressPercent = (progress * 100).toInt();
    return AnimatedBuilder(
      animation: _progressAnimation,
      builder: (context, child) {
        return SizedBox(
          width: AppDimensions.circularProgressSize,
          height: AppDimensions.circularProgressSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Background circle
              CustomPaint(
                size: const Size.square(AppDimensions.circularProgressSize),
                painter: _CircularProgressPainter(
                  progress: 0,
                  strokeWidth: AppDimensions.progressStrokeWidth,
                  color: isDark
                      ? AppColors.surfaceDark
                      : AppColors.surfaceLight,
                ),
              ),
              // Progress arc
              CustomPaint(
                size: const Size.square(AppDimensions.circularProgressSize),
                painter: _CircularProgressPainter(
                  progress: progress * _progressAnimation.value,
                  strokeWidth: AppDimensions.progressStrokeWidth,
                  color: isActive ? AppColors.primary : AppColors.error,
                  hasGradient: true,
                  isDark: isDark,
                ),
              ),
              // Center percentage text
              Text(
                '$progressPercent%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: isActive ? AppColors.primary : AppColors.error,
                ),
              ),
              // Semantics wrapper for accessibility
              Positioned.fill(
                child: Semantics(
                  label: SettingsStrings.subscriptionProgressSemantics
                      .replaceAll('@percent', progressPercent.toString()),
                  excludeSemantics: true,
                  child: const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSubscriptionPlansSection() {
    // Wrap in error boundary to prevent entire screen crash
    return ErrorBoundary(
      errorWidget: (error, stackTrace) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppDimensions.paddingLarge),
          decoration: ShapeDecoration(
            color: AppColors.error.withValues(alpha: 0.1),
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(
                cornerRadius: AppDimensions.radiusXXLarge,
                cornerSmoothing: 1.0,
              ),
            ),
          ),
          child: const Column(
            children: [
              Icon(
                SolarLinearIcons.closeCircle,
                size: 48,
                color: AppColors.error,
              ),
              SizedBox(height: AppDimensions.spacing16),
              Text(
                SettingsStrings.loadingError,
                style: TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        );
      },
      child: const SubscriptionPlansSection(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Error Boundary Widget
// ─────────────────────────────────────────────────────────────────

/// A widget that catches errors in its child subtree and displays an error widget
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(Object error, StackTrace stackTrace) errorWidget;

  const ErrorBoundary({
    super.key,
    required this.child,
    required this.errorWidget,
  });

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  Object? _error;
  StackTrace? _stackTrace;

  @override
  void initState() {
    super.initState();
    _error = null;
    _stackTrace = null;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null || _stackTrace != null) {
      return widget.errorWidget(_error!, _stackTrace!);
    }
    return _ErrorBoundaryScope(
      onError: _handleError,
      child: widget.child,
    );
  }

  void _handleError(Object error, StackTrace stackTrace) {
    if (mounted) {
      setState(() {
        _error = error;
        _stackTrace = stackTrace;
      });
    }
  }
}

class _ErrorBoundaryScope extends InheritedWidget {
  final void Function(Object error, StackTrace stackTrace) onError;

  const _ErrorBoundaryScope({
    required super.child,
    required this.onError,
  });

  @override
  bool updateShouldNotify(covariant _ErrorBoundaryScope oldWidget) =>
      onError != oldWidget.onError;
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
        endAngle: math.pi * 2,
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
    // Only repaint when progress or color changes
    // isDark and hasGradient rarely change, so we exclude them
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
