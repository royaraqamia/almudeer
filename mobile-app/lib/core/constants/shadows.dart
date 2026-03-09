import 'package:flutter/material.dart';
import 'colors.dart';

/// Centralized shadow constants for the application
///
/// Shadow Guidelines (Apple/Stripe-style layered shadows):
/// - Light mode: Multi-layer shadows for depth perception
/// - Dark mode: Subtle single-layer shadows (light travels differently)
/// - All shadows use low opacity for premium feel
/// - Brand-colored shadows for enhanced premium feel
class AppShadows {
  AppShadows._();

  /// Premium drop shadow: Single layer for dark mode
  /// X:0, Y:4, Blur:48, Color:000000 5%
  static final BoxShadow premiumShadow = BoxShadow(
    color: AppColors.shadowPrimaryDark,
    offset: const Offset(0, 4),
    blurRadius: 48,
  );

  /// Layered shadow system for light mode (Apple/Stripe style)
  /// Creates depth perception through multiple shadow layers
  static List<BoxShadow> get layeredShadow => [
        // Layer 1: Close, subtle shadow for edge definition
        BoxShadow(
          color: AppColors.shadowPrimaryLight,
          offset: const Offset(0, 1),
          blurRadius: 2,
        ),
        // Layer 2: Mid-range shadow for depth
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          offset: const Offset(0, 4),
          blurRadius: 8,
        ),
        // Layer 3: Far shadow for elevation
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          offset: const Offset(0, 16),
          blurRadius: 24,
        ),
      ];

  /// Small shadow for subtle elevation (chips, small cards)
  static List<BoxShadow> get shadowSmall => [
        BoxShadow(
          color: AppColors.shadowPrimaryLight,
          offset: const Offset(0, 1),
          blurRadius: 2,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          offset: const Offset(0, 4),
          blurRadius: 8,
        ),
      ];

  /// Medium shadow for standard cards and buttons
  static List<BoxShadow> get shadowMedium => layeredShadow;

  /// Large shadow for modals, bottom sheets, and floating elements
  static List<BoxShadow> get shadowLarge => [
        BoxShadow(
          color: AppColors.shadowPrimaryLight,
          offset: const Offset(0, 2),
          blurRadius: 4,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          offset: const Offset(0, 8),
          blurRadius: 16,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.16),
          offset: const Offset(0, 24),
          blurRadius: 48,
        ),
      ];

  /// Colored shadow for brand elements (buttons, CTAs)
  static BoxShadow coloredShadow(Color color, {double alpha = 0.3}) => BoxShadow(
        color: color.withValues(alpha: alpha),
        blurRadius: 12,
        offset: const Offset(0, 4),
      );

  /// Inner shadow effect for inset elements
  static BoxShadow get innerShadow => BoxShadow(
        color: Colors.black.withValues(alpha: 0.1),
        offset: const Offset(0, 2),
        blurRadius: 4,
        spreadRadius: -2,
      );
}
