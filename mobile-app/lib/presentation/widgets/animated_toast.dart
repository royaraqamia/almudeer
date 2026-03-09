import 'dart:collection';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import '../../core/constants/animations.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/dimensions.dart';
import '../../core/utils/haptics.dart';

/// Toast type for styling
enum ToastType { success, error, info, warning }

/// Toast message data structure
class ToastMessage {
  final String message;
  final ToastType type;
  final Duration duration;
  final bool hapticFeedback;

  const ToastMessage({
    required this.message,
    required this.type,
    this.duration = const Duration(seconds: 3),
    this.hapticFeedback = true,
  });
}

/// Custom animated toast with smooth enter/exit animations and queue support
///
/// Design Specifications:
/// - Position: Top centered with safe area
/// - Radius: 16px
/// - Timer: Circular progress with close button
/// - Types: success, error, warning, info
/// - Queue: Maximum 3 toasts, FIFO processing
class AnimatedToast {
  static final Queue<ToastMessage> _toastQueue = Queue();
  static OverlayEntry? _currentToast;
  static bool _isShowing = false;

  /// Show a toast with smooth animations
  static void show(
    BuildContext context, {
    required String message,
    ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 3),
    bool hapticFeedback = true,
  }) {
    final toast = ToastMessage(
      message: message,
      type: type,
      duration: duration,
      hapticFeedback: hapticFeedback,
    );

    _toastQueue.add(toast);
    _processQueue(context);
  }

  static void _processQueue(BuildContext context) {
    if (_isShowing || _toastQueue.isEmpty) return;

    _isShowing = true;
    final toast = _toastQueue.removeFirst();

    // Dismiss any existing toast
    _currentToast?.remove();
    _currentToast = null;

    // Haptic feedback
    if (toast.hapticFeedback) {
      switch (toast.type) {
        case ToastType.success:
          Haptics.lightTap();
          break;
        case ToastType.error:
          Haptics.heavyTap();
          break;
        case ToastType.warning:
          Haptics.mediumTap();
          break;
        case ToastType.info:
          Haptics.selection();
          break;
      }
    }

    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => _AnimatedToastWidget(
        message: toast.message,
        type: toast.type,
        duration: toast.duration,
        onDismiss: () {
          entry.remove();
          _currentToast = null;
          _isShowing = false;
          // Process next toast after a small delay
          Future.delayed(const Duration(milliseconds: 100), () {
            if (context.mounted && _toastQueue.isNotEmpty) {
              _processQueue(context);
            }
          });
        },
      ),
    );

    _currentToast = entry;
    overlay.insert(entry);
  }

  /// Show success toast
  static void success(BuildContext context, String message) {
    show(context, message: message, type: ToastType.success);
  }

  /// Show error toast
  static void error(BuildContext context, String message) {
    show(context, message: message, type: ToastType.error);
  }

  /// Show info toast
  static void info(BuildContext context, String message) {
    show(context, message: message, type: ToastType.info);
  }

  /// Show warning toast
  static void warning(BuildContext context, String message) {
    show(context, message: message, type: ToastType.warning);
  }

  /// Dismiss current toast
  static void dismiss() {
    _currentToast?.remove();
    _currentToast = null;
    _isShowing = false;
  }

  /// Clear all queued toasts
  static void clearQueue() {
    _toastQueue.clear();
  }

  /// Get current queue length
  static int get queueLength => _toastQueue.length;
}

class _AnimatedToastWidget extends StatefulWidget {
  final String message;
  final ToastType type;
  final VoidCallback onDismiss;
  final Duration duration;

  const _AnimatedToastWidget({
    required this.message,
    required this.type,
    required this.onDismiss,
    required this.duration,
  });

  @override
  State<_AnimatedToastWidget> createState() => _AnimatedToastWidgetState();
}

class _AnimatedToastWidgetState extends State<_AnimatedToastWidget>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _timerController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: AppAnimations.normal,
      reverseDuration: AppAnimations.fast,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: AppAnimations.enter,
      reverseCurve: AppAnimations.exit,
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _controller,
            curve: AppAnimations.enter,
            reverseCurve: AppAnimations.exit,
          ),
        );

    // Initialize timer controller
    _timerController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _timerController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _dismiss();
      }
    });

    // Start entrance animation
    _controller.forward();

    // Start timer animation
    _timerController.forward();
  }

  void _dismiss() async {
    _timerController.stop(); // Stop timer if manually dismissed
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    _timerController.dispose();
    super.dispose();
  }

  Color get _backgroundColor {
    switch (widget.type) {
      case ToastType.success:
        return AppColors.success;
      case ToastType.error:
        return AppColors.error;
      case ToastType.warning:
        return const Color(0xFFF59E0B);
      case ToastType.info:
        return AppColors.primary;
    }
  }

  IconData get _icon {
    switch (widget.type) {
      case ToastType.success:
        return SolarLinearIcons.checkCircle;
      case ToastType.error:
        return SolarLinearIcons.dangerCircle;
      case ToastType.warning:
        return SolarLinearIcons.infoCircle;
      case ToastType.info:
        return SolarLinearIcons.infoCircle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _dismiss,
              onHorizontalDragEnd: (_) => _dismiss(),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppDimensions.radiusXLarge),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimensions.spacing16,
                      vertical: AppDimensions.spacing16,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.surfaceDark
                          : _backgroundColor.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(
                        AppDimensions.radiusXLarge,
                      ),
                      border: Border.all(
                        color: isDark
                            ? _backgroundColor.withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.2),
                        width: 1,
                      ),
                      boxShadow: [
                        if (!isDark)
                          BoxShadow(
                            color: _backgroundColor.withValues(alpha: 0.2),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(_icon, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: AppDimensions.spacing14),
                        Expanded(
                          child: Text(
                            widget.message,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppDimensions.spacing8),
                        // Circular Timer with Close Button
                        // Touch target: 44x44px minimum (WCAG 2.1 AA)
                        GestureDetector(
                          onTap: _dismiss,
                          child: Semantics(
                            label: 'إغلاق',
                            child: SizedBox(
                              width: AppDimensions.touchTargetMin,
                              height: AppDimensions.touchTargetMin,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  AnimatedBuilder(
                                    animation: _timerController,
                                    builder: (context, child) {
                                      return SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: CircularProgressIndicator(
                                          value: 1.0 - _timerController.value,
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation(
                                            Colors.white.withValues(alpha: 0.5),
                                          ),
                                          backgroundColor: Colors.white
                                              .withValues(alpha: 0.1),
                                        ),
                                      );
                                    },
                                  ),
                                  Icon(
                                    SolarLinearIcons.closeCircle,
                                    color: Colors.white.withValues(alpha: 0.9),
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
