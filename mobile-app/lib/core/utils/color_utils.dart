import 'dart:math';
import 'package:flutter/material.dart';
import '../constants/colors.dart';

/// Utility functions for color operations and accessibility
///
/// Provides helper methods for:
/// - Color blending and mixing
/// - Contrast ratio calculation (WCAG 2.1)
/// - Accessibility validation
/// - Dynamic color generation
class ColorUtils {
  // Prevent instantiation
  ColorUtils._();

  // ─────────────────────────────────────────────────────────────────
  // WCAG Contrast Ratio Calculation
  // ─────────────────────────────────────────────────────────────────

  /// Calculate relative luminance of a color (WCAG 2.1)
  /// https://www.w3.org/WAI/GL/wiki/Relative_luminance
  static double relativeLuminance(Color color) {
    final r = _linearize(color.r);
    final g = _linearize(color.g);
    final b = _linearize(color.b);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  /// Calculate contrast ratio between two colors (WCAG 2.1)
  /// Returns ratio between 1.0 (same color) and 21.0 (max contrast)
  static double contrastRatio(Color color1, Color color2) {
    final l1 = relativeLuminance(color1);
    final l2 = relativeLuminance(color2);
    final lighter = max(l1, l2);
    final darker = min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Check if color pair meets WCAG 2.1 AA standard
  /// - Normal text: 4.5:1 minimum
  /// - Large text (18px+ or 14px+ bold): 3:1 minimum
  static bool meetsWCAGAA(Color foreground, Color background, {bool isLargeText = false}) {
    final ratio = contrastRatio(foreground, background);
    final minimum = isLargeText ? 3.0 : 4.5;
    return ratio >= minimum;
  }

  /// Check if color pair meets WCAG 2.1 AAA standard
  /// - Normal text: 7:1 minimum
  /// - Large text (18px+ or 14px+ bold): 4.5:1 minimum
  static bool meetsWCGAAA(Color foreground, Color background, {bool isLargeText = false}) {
    final ratio = contrastRatio(foreground, background);
    final minimum = isLargeText ? 4.5 : 7.0;
    return ratio >= minimum;
  }

  /// Linearize sRGB color channel for luminance calculation
  static double _linearize(double channel) {
    return channel <= 0.03928
        ? channel / 12.92
        : pow((channel + 0.055) / 1.055, 2.4).toDouble();
  }

  // ─────────────────────────────────────────────────────────────────
  // Color Blending & Mixing
  // ─────────────────────────────────────────────────────────────────

  /// Mix two colors with a given weight
  /// [weight] ranges from 0.0 (100% color1) to 1.0 (100% color2)
  static Color mix(Color color1, Color color2, double weight) {
    final w = weight.clamp(0.0, 1.0);
    return Color.fromRGBO(
      (color1.r * (1 - w) + color2.r * w).round().clamp(0, 255),
      (color1.g * (1 - w) + color2.g * w).round().clamp(0, 255),
      (color1.b * (1 - w) + color2.b * w).round().clamp(0, 255),
      1.0,
    );
  }

  /// Create a lighter version of a color by mixing with white
  static Color lighten(Color color, [double amount = 0.1]) {
    return mix(color, Colors.white, amount.clamp(0.0, 1.0));
  }

  /// Create a darker version of a color by mixing with black
  static Color darken(Color color, [double amount = 0.1]) {
    return mix(color, Colors.black, amount.clamp(0.0, 1.0));
  }

  /// Adjust color opacity/alpha
  static Color withAlpha(Color color, double alpha) {
    return color.withValues(alpha: alpha.clamp(0.0, 1.0));
  }

  // ─────────────────────────────────────────────────────────────────
  // Accessibility Helpers
  // ─────────────────────────────────────────────────────────────────

  /// Get appropriate text color (black or white) for a given background
  /// Uses WCAG AA 4.5:1 contrast ratio as threshold
  static Color getContrastingTextColor(Color backgroundColor) {
    final lightContrast = contrastRatio(Colors.white, backgroundColor);
    final darkContrast = contrastRatio(Colors.black, backgroundColor);
    return lightContrast > darkContrast ? Colors.white : Colors.black;
  }

  /// Get accessible text color from app colors for light theme backgrounds
  static Color getTextForLightBackground() => AppColors.textPrimaryLight;

  /// Get accessible text color for dark theme backgrounds
  static Color getTextForDarkBackground() => AppColors.textPrimaryDark;

  // ─────────────────────────────────────────────────────────────────
  // Semantic Color Helpers
  // ─────────────────────────────────────────────────────────────────

  /// Get color for intent type
  static Color getIntentColor(String intent) {
    return AppColors.intentColors[intent] ?? AppColors.info;
  }

  /// Get color for urgency level
  static Color getUrgencyColor(String urgency) {
    return AppColors.urgencyColors[urgency] ?? AppColors.info;
  }

  /// Get color for sentiment
  static Color getSentimentColor(String sentiment) {
    return AppColors.sentimentColors[sentiment] ?? AppColors.info;
  }

  /// Get color for task category
  static Color getTaskCategoryColor(String category) {
    return AppColors.taskCategoryColors[category] ?? AppColors.info;
  }

  // ─────────────────────────────────────────────────────────────────
  // Chart Color Helpers
  // ─────────────────────────────────────────────────────────────────

  /// Get chart color by index (light mode)
  static Color getChartColorLight(int index) {
    final colors = [
      AppColors.chartLight1,
      AppColors.chartLight2,
      AppColors.chartLight3,
      AppColors.chartLight4,
      AppColors.chartLight5,
    ];
    return colors[index % colors.length];
  }

  /// Get chart color by index (dark mode)
  static Color getChartColorDark(int index) {
    final colors = [
      AppColors.chartDark1,
      AppColors.chartDark2,
      AppColors.chartDark3,
      AppColors.chartDark4,
      AppColors.chartDark5,
    ];
    return colors[index % colors.length];
  }

  // ─────────────────────────────────────────────────────────────────
  // Gradient Helpers
  // ─────────────────────────────────────────────────────────────────

  /// Create a gradient from AppColors brand gradient
  static LinearGradient getBrandGradient({bool isDark = false}) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [AppColors.primaryLight, AppColors.primary]
          : [AppColors.brandGradientStart, AppColors.brandGradientEnd],
    );
  }

  /// Create error gradient
  static LinearGradient getErrorGradient() {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: AppColors.errorGradient,
    );
  }

  /// Create avatar gradient
  static LinearGradient getAvatarGradient({required bool isDark}) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? AppColors.avatarGradientDark
          : AppColors.avatarGradientLight,
    );
  }

  /// Create background gradient
  static LinearGradient getBackgroundGradient({required bool isDark}) {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? AppColors.backgroundGradientDark
          : AppColors.backgroundGradientLight,
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // State Color Helpers
  // ─────────────────────────────────────────────────────────────────

  /// Get disabled color variant
  static Color getDisabledColor({required bool isDark}) {
    return isDark ? AppColors.disabledDark : AppColors.disabledLight;
  }

  /// Get disabled background color
  static Color getDisabledBackgroundColor({required bool isDark}) {
    return isDark ? AppColors.disabledBackgroundDark : AppColors.disabledBackgroundLight;
  }

  /// Get hover color overlay
  static Color getHoverColor({required bool isDark}) {
    return isDark ? AppColors.hoverDark : AppColors.hoverLight;
  }

  /// Get focus ring color
  static Color getFocusRingColor({required bool isDark}) {
    return isDark ? AppColors.focusRingDark : AppColors.focusRingLight;
  }

  /// Get scrim color for modals/overlays
  static Color getScrimColor({required bool isDark}) {
    return isDark ? AppColors.scrimDark : AppColors.scrimLight;
  }

  /// Get shimmer colors for loading states
  static List<Color> getShimmerColors({required bool isDark}) {
    return isDark
        ? [AppColors.shimmerBaseDark, AppColors.shimmerHighlightDark]
        : [AppColors.shimmerBaseLight, AppColors.shimmerHighlightLight];
  }

  // ─────────────────────────────────────────────────────────────────
  // Badge Color Helpers
  // ─────────────────────────────────────────────────────────────────

  /// Get badge color for new items
  static Color getBadgeNewColor() => AppColors.badgeNew;

  /// Get badge color for unread items
  static Color getBadgeUnreadColor() => AppColors.badgeUnread;

  /// Get badge color for updates
  static Color getBadgeUpdateColor() => AppColors.badgeUpdate;

  // ─────────────────────────────────────────────────────────────────
  // Shadow Helpers
  // ─────────────────────────────────────────────────────────────────

  /// Get premium shadow color for light mode
  static Color getShadowColorLight() => AppColors.shadowPrimaryLight;

  /// Get shadow color for dark mode
  static Color getShadowColorDark() => AppColors.shadowPrimaryDark;

  /// Create a box shadow with brand-colored shadow
  static BoxShadow createPremiumShadow({
    required bool isDark,
    double blurRadius = 20,
    Offset offset = const Offset(0, 4),
    double spreadRadius = 0,
  }) {
    return BoxShadow(
      color: isDark ? getShadowColorDark() : getShadowColorLight(),
      blurRadius: blurRadius,
      offset: offset,
      spreadRadius: spreadRadius,
    );
  }
}
