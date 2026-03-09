import 'package:flutter/material.dart';

/// Animation constants for consistent, snappy feel across the app
///
/// Motion Guidelines:
/// - Enter animations: 300ms, easeOutQuart
/// - Exit animations: 200ms, easeInQuart
/// - Micro-interactions: 100-150ms
/// - Complex transitions: 400-500ms
///
/// Accessibility: Respects system reduced motion preferences
class AppAnimations {
  // Prevent instantiation
  AppAnimations._();

  // ─────────────────────────────────────────────────────────────────
  // Durations - Optimized for "instant" feel
  // ─────────────────────────────────────────────────────────────────

  /// Ultra-fast for micro-interactions (ripples, highlights)
  static const Duration ultraFast = Duration(milliseconds: 50);

  /// Fast for button presses, chip selections
  static const Duration fast = Duration(milliseconds: 100);

  /// Normal for most UI transitions
  static const Duration normal = Duration(milliseconds: 150);

  /// Standard for page transitions, modals
  static const Duration standard = Duration(milliseconds: 200);

  /// Slow for complex animations (drawer, expand/collapse)
  static const Duration slow = Duration(milliseconds: 250);

  /// Extended for emphasized animations
  static const Duration extended = Duration(milliseconds: 300);

  // ─────────────────────────────────────────────────────────────────
  // Curves - Snappy, natural-feeling curves
  // ─────────────────────────────────────────────────────────────────

  /// Primary curve for most animations - fast start, smooth finish
  static const Curve primary = Curves.easeOutCubic;

  /// For entering elements (fade in, slide in)
  static const Curve enter = Curves.easeOutQuart;

  /// For exiting elements (fade out, slide out)
  static const Curve exit = Curves.easeInQuart;

  /// For interactive elements (buttons, chips)
  static const Curve interactive = Curves.fastOutSlowIn;

  /// For spring-like animations
  static const Curve spring = Curves.elasticOut;

  /// For smooth deceleration
  static const Curve decelerate = Curves.decelerate;

  /// For bounce effect (success animations)
  static const Curve bounce = Curves.bounceOut;

  // ─────────────────────────────────────────────────────────────────
  // Spring Physics - For physics-based animations
  // ─────────────────────────────────────────────────────────────────

  /// Default spring for most animations (balanced)
  static const SpringDescription defaultSpring = SpringDescription(
    mass: 1.0,
    stiffness: 150.0,
    damping: 15.0,
  );

  /// Stiff spring for snappy responses (buttons, toggles)
  static const SpringDescription stiffSpring = SpringDescription(
    mass: 1.0,
    stiffness: 200.0,
    damping: 20.0,
  );

  /// Gentle spring for subtle animations (cards, sheets)
  static const SpringDescription gentleSpring = SpringDescription(
    mass: 1.0,
    stiffness: 100.0,
    damping: 12.0,
  );

  /// Bouncy spring for playful animations
  static const SpringDescription bouncySpring = SpringDescription(
    mass: 1.0,
    stiffness: 180.0,
    damping: 8.0,
  );

  // ─────────────────────────────────────────────────────────────────
  // Accessibility: Reduced Motion Support
  // ─────────────────────────────────────────────────────────────────

  /// Check if user prefers reduced motion (system setting)
  static bool prefersReducedMotion(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.disableAnimations ||
        mediaQuery.accessibleNavigation;
  }

  /// Get duration respecting reduced motion preference
  static Duration getDuration(BuildContext context, Duration normalDuration) {
    if (prefersReducedMotion(context)) {
      return Duration.zero;
    }
    return normalDuration;
  }

  /// Get curve respecting reduced motion preference
  static Curve getCurve(BuildContext context, Curve normalCurve) {
    if (prefersReducedMotion(context)) {
      return Curves.linear;
    }
    return normalCurve;
  }

  /// Get spring description respecting reduced motion preference
  static SpringDescription getSpring(
    BuildContext context,
    SpringDescription normalSpring,
  ) {
    if (prefersReducedMotion(context)) {
      return const SpringDescription(
        mass: 1.0,
        stiffness: 1000.0,
        damping: 50.0,
      ); // Near-instant, no bounce
    }
    return normalSpring;
  }

  // ─────────────────────────────────────────────────────────────────
  // Page Transition Builders
  // ─────────────────────────────────────────────────────────────────

  /// Fade + Slide transition for page navigation
  static Widget fadeSlideTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Respect reduced motion preference
    if (prefersReducedMotion(context)) {
      return FadeTransition(
        opacity: animation,
        child: child,
      );
    }

    const begin = Offset(0.03, 0.0); // Subtle horizontal slide
    const end = Offset.zero;
    final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: enter));

    return FadeTransition(
      opacity: animation.drive(CurveTween(curve: enter)),
      child: SlideTransition(position: animation.drive(tween), child: child),
    );
  }

  /// Fade-only transition for modals and dialogs
  static Widget fadeTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: animation.drive(CurveTween(curve: prefersReducedMotion(context) ? Curves.linear : enter)),
      child: child,
    );
  }

  /// Scale + Fade for popups and action sheets
  static Widget scaleTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (prefersReducedMotion(context)) {
      return FadeTransition(
        opacity: animation,
        child: child,
      );
    }

    return ScaleTransition(
      scale: animation.drive(
        Tween(begin: 0.95, end: 1.0).chain(CurveTween(curve: enter)),
      ),
      child: FadeTransition(
        opacity: animation.drive(CurveTween(curve: enter)),
        child: child,
      ),
    );
  }

  /// Spring scale transition for playful popups
  static Widget springScaleTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (prefersReducedMotion(context)) {
      return FadeTransition(
        opacity: animation,
        child: child,
      );
    }

    return ScaleTransition(
      scale: animation.drive(
        Tween(begin: 0.8, end: 1.0).chain(CurveTween(curve: spring)),
      ),
      child: FadeTransition(
        opacity: animation.drive(CurveTween(curve: enter)),
        child: child,
      ),
    );
  }
}

/// Custom page route with optimized transitions
class FastPageRoute<T> extends PageRouteBuilder<T> {
  FastPageRoute({required WidgetBuilder builder, super.settings})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionDuration: AppAnimations.standard,
        reverseTransitionDuration: AppAnimations.normal,
        transitionsBuilder: AppAnimations.fadeSlideTransition,
      );
}

/// Fade-only page route for special transitions
class FadePageRoute<T> extends PageRouteBuilder<T> {
  FadePageRoute({required WidgetBuilder builder, super.settings})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionDuration: AppAnimations.normal,
        reverseTransitionDuration: AppAnimations.fast,
        transitionsBuilder: AppAnimations.fadeTransition,
      );
}

/// Spring page route for playful transitions
class SpringPageRoute<T> extends PageRouteBuilder<T> {
  SpringPageRoute({required WidgetBuilder builder, super.settings})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionDuration: AppAnimations.extended,
        reverseTransitionDuration: AppAnimations.standard,
        transitionsBuilder: AppAnimations.springScaleTransition,
      );
}
