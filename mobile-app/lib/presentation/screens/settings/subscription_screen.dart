import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:provider/provider.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/dimensions.dart';
import '../../../core/constants/settings_strings.dart';
import '../../../data/models/user_info.dart';
import '../../providers/auth_provider.dart';
import 'widgets/subscription_plans_section.dart';
import '../../../core/extensions/string_extension.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  // Cache for formatted dates to avoid redundant Hijri conversions
  final Map<String, String> _dateCache = {};

  @override
  void dispose() {
    _dateCache.clear();
    super.dispose();
  }

  /// Format date using Hijri calendar with caching
  ///
  /// Uses Arabic locale for Hijri conversion with English numbers.
  String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return '-';

    // Check cache first
    final cached = _dateCache[dateStr];
    if (cached != null) return cached;

    try {
      final date = DateTime.parse(dateStr);
      HijriCalendar.setLocal('ar');
      final hijriDate = HijriCalendar.fromDate(date);
      final formatted = hijriDate.toFormat('dd MMMM yyyy').toEnglishNumbers;

      // Cache the result
      _dateCache[dateStr] = formatted;
      return formatted;
    } catch (e) {
      debugPrint('[SubscriptionScreen] Date parse error: $e, input: $dateStr');
      return dateStr;
    }
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

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(theme, isDark),
      body: Stack(
        children: [
          // Main content
          SafeArea(
            child: _buildContent(
              theme,
              isDark,
              authProvider,
              daysRemaining,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Membership Status Card
          _buildMembershipCard(
            theme,
            isDark,
            authProvider,
            daysRemaining,
            userInfo,
          ),
          const SizedBox(height: AppDimensions.spacing24),

          // Subscription Plans with error boundary
          _buildSubscriptionPlansSection(),
        ],
      ),
    );
  }

  Widget _buildMembershipCard(
    ThemeData theme,
    bool isDark,
    AuthProvider authProvider,
    int daysRemaining,
    UserInfo userInfo,
  ) {
    final expiresAt = userInfo.expiresAt;
    final isActive = daysRemaining > 0;

    return Container(
        width: double.infinity,
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
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.paddingLarge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Expiry date and remaining days
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    SettingsStrings.subscriptionEnds,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
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
                  const SizedBox(height: 8),
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
            ],
          ),
        ),
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
