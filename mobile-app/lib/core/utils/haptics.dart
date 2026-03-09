import 'package:flutter/services.dart';

/// Haptic feedback utilities for native-feeling interactions
class Haptics {
  // Prevent instantiation
  Haptics._();

  /// Light tap feedback - for buttons, chips, list items
  static void lightTap() {
    HapticFeedback.lightImpact();
  }

  /// Medium tap feedback - for important actions
  static void mediumTap() {
    HapticFeedback.mediumImpact();
  }

  /// Heavy tap feedback - for destructive actions, confirmations
  static void heavyTap() {
    HapticFeedback.heavyImpact();
  }

  /// Selection feedback - for toggles, switches, radio buttons
  static void selection() {
    HapticFeedback.selectionClick();
  }

  /// Vibrate feedback - for errors, warnings
  static void vibrate() {
    HapticFeedback.vibrate();
  }
}
