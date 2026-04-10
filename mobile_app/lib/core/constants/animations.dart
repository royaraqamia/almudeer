import 'package:flutter/material.dart';

/// Animation constants for consistent, snappy feel across the app
///
/// Motion Guidelines (Apple HIG Compliant):
/// - Minimum duration: 200ms (Apple standard, avoids jarring animations)
/// - Enter animations: 300ms, easeOutQuart
/// - Exit animations: 250ms, easeInQuart
/// - Micro-interactions: 200-250ms
/// - Complex transitions: 400-500ms
/// - Drawer/Side menus: 300-400ms (not 800ms+)
///
/// Accessibility: Respects system reduced motion preferences
/// Reference: Apple Style Guide p. 72-73
class AppAnimations {
  // Prevent instantiation
  AppAnimations._();

  // ─────────────────────────────────────────────────────────────────
  // Durations - Apple HIG Compliant (200ms minimum)
  // ─────────────────────────────────────────────────────────────────

  /// Ultra-fast for micro-interactions (ripples, highlights)
  /// Apple minimum: 200ms for perceivable, non-jarring animation
  static const Duration ultraFast = Duration(milliseconds: 200);

  /// Fast for button presses, chip selections
  /// Apple standard for interactive elements
  static const Duration fast = Duration(milliseconds: 250);

  /// Normal for most UI transitions
  /// Apple standard for standard transitions
  static const Duration normal = Duration(milliseconds: 300);

  /// Standard for page transitions, modals
  /// Apple standard for modal presentations
  static const Duration standard = Duration(milliseconds: 350);

  /// Slow for complex animations (drawer, expand/collapse)
  /// Apple standard for drawer/side menus (NOT 800ms+)
  static const Duration slow = Duration(milliseconds: 400);

  /// Extended for emphasized animations
  /// Apple standard for complex, multi-element animations
  static const Duration extended = Duration(milliseconds: 500);

  // ─────────────────────────────────────────────────────────────────
  // Curves - Apple-standard natural-feeling curves
  // Reference: Apple Style Guide p. 72
  // ─────────────────────────────────────────────────────────────────

  /// Primary curve for most animations - fast start, smooth finish
  /// Apple standard: easeOutCubic for natural deceleration
  static const Curve primary = Curves.easeOutCubic;

  /// For entering elements (fade in, slide in)
  /// Apple standard: easeOutQuart for smooth entrance
  static const Curve enter = Curves.easeOutQuart;

  /// For exiting elements (fade out, slide out)
  /// Apple standard: easeInQuart for smooth exit
  static const Curve exit = Curves.easeInQuart;

  /// For interactive elements (buttons, chips)
  /// Apple standard: fastOutSlowIn for tactile feel
  static const Curve interactive = Curves.fastOutSlowIn;

  /// For spring-like animations (bouncy, playful)
  /// Use sparingly per Apple guidelines
  static const Curve spring = Curves.elasticOut;

  /// For smooth deceleration (scrolling, settling)
  static const Curve decelerate = Curves.decelerate;

  /// For bounce effect (success animations, confirmations)
  /// Apple: Use only for positive feedback
  static const Curve bounce = Curves.bounceOut;

  // ─────────────────────────────────────────────────────────────────
  // Spring Physics - Apple-standard physics-based animations
  // Reference: Apple Style Guide p. 72
  // ─────────────────────────────────────────────────────────────────

  /// Default spring for most animations (balanced)
  /// Apple standard: mass=1, stiffness=150, damping=15
  static const SpringDescription defaultSpring = SpringDescription(
    mass: 1.0,
    stiffness: 150.0,
    damping: 15.0,
  );

  /// Stiff spring for snappy responses (buttons, toggles)
  /// Apple standard for interactive controls
  static const SpringDescription stiffSpring = SpringDescription(
    mass: 1.0,
    stiffness: 200.0,
    damping: 20.0,
  );

  /// Gentle spring for subtle animations (cards, sheets)
  /// Apple standard for surface-level elements
  static const SpringDescription gentleSpring = SpringDescription(
    mass: 1.0,
    stiffness: 100.0,
    damping: 12.0,
  );

  /// Bouncy spring for playful animations (success, celebrations)
  /// Apple: Use sparingly, only for positive feedback
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
