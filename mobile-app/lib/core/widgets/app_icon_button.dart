import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import '../constants/colors.dart';
import '../constants/animations.dart';
import '../utils/haptics.dart';

/// Premium icon button with multiple variants and proper touch targets
///
/// Design Specifications:
/// - Minimum touch target: 44x44px (WCAG 2.1 AA)
/// - Default size: 48x48px
/// - Variants: filled, outlined, ghost, tonal
/// - Hover states for tablet/desktop support
/// - Press animation with scale effect
/// - Haptic feedback on tap
class AppIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double size;
  final double iconSize;
  final String? tooltip;
  final bool showBackground;
  final Color? backgroundColor;
  final Color? iconColor;
  final Color? hoverColor;
  final ButtonVariant variant;
  final bool enabled;

  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.isLoading = false,
    this.size = 48,
    this.iconSize = 24,
    this.tooltip,
    this.showBackground = true,
    this.backgroundColor,
    this.iconColor,
    this.hoverColor,
    this.variant = ButtonVariant.filled,
    this.enabled = true,
  });

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final effectiveIconColor =
        widget.iconColor ??
        (widget.enabled
            ? (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight)
            : AppColors.textTertiaryLight);

    final effectiveBgColor =
        widget.backgroundColor ??
        (widget.variant == ButtonVariant.filled
            ? (isDark ? AppColors.surfaceCardDark : AppColors.surfaceCardLight)
            : Colors.transparent);

    Widget buttonContent = GestureDetector(
      onTapDown: (_) {
        if (widget.enabled && widget.onPressed != null) {
          setState(() => _isPressed = true);
        }
      },
      onTapUp: (_) {
        if (widget.enabled && widget.onPressed != null) {
          setState(() => _isPressed = false);
          Haptics.lightTap();
          widget.onPressed?.call();
        }
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
      },
      child: AnimatedScale(
        scale: _isPressed ? 0.9 : 1.0,
        duration: AppAnimations.fast,
        child: AnimatedContainer(
          duration: AppAnimations.normal,
          width: widget.size,
          height: widget.size,
          decoration: widget.showBackground
              ? ShapeDecoration(
                  color: _isHovered && widget.enabled
                      ? (widget.hoverColor ??
                            (isDark
                                ? AppColors.hoverDark
                                : AppColors.hoverLight))
                      : effectiveBgColor,
                  shape: SmoothRectangleBorder(
                    borderRadius: SmoothBorderRadius(
                      cornerRadius: widget.size / 2,
                      cornerSmoothing: 1.0,
                    ),
                  ),
                  shadows:
                      widget.variant == ButtonVariant.filled &&
                          !isDark &&
                          widget.enabled
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                )
              : null,
          child: widget.isLoading
              ? Center(
                  child: SizedBox(
                    width: widget.iconSize,
                    height: widget.iconSize,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        effectiveIconColor,
                      ),
                    ),
                  ),
                )
              : Center(
                  child: Icon(
                    widget.icon,
                    size: widget.iconSize,
                    color: widget.enabled
                        ? effectiveIconColor
                        : effectiveIconColor.withValues(alpha: 0.5),
                  ),
                ),
        ),
      ),
    );

    // Add mouse region for hover on desktop/tablet
    if (widget.enabled && widget.onPressed != null) {
      buttonContent = MouseRegion(
        onEnter: (_) {
          setState(() => _isHovered = true);
        },
        onExit: (_) {
          setState(() => _isHovered = false);
        },
        cursor: SystemMouseCursors.click,
        child: buttonContent,
      );
    }

    // Add tooltip if provided
    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: buttonContent);
    }

    return buttonContent;
  }
}

/// Button variant types
enum ButtonVariant { filled, outlined, ghost, tonal }

/// Icon button with badge for notifications
class AppIconButtonWithBadge extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? badgeText;
  final bool showBadge;
  final Color? badgeColor;
  final double size;
  final double iconSize;

  const AppIconButtonWithBadge({
    super.key,
    required this.icon,
    this.onPressed,
    this.badgeText,
    this.showBadge = false,
    this.badgeColor,
    this.size = 48,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AppIconButton(
          icon: icon,
          onPressed: onPressed,
          size: size,
          iconSize: iconSize,
        ),
        if (showBadge)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor ?? AppColors.error,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 2),
              ),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              child: badgeText != null
                  ? Text(
                      badgeText!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    )
                  : const SizedBox(
                      width: 8,
                      height: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
            ),
          ),
      ],
    );
  }
}
