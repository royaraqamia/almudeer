import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import '../constants/colors.dart';
import '../constants/dimensions.dart';
import '../constants/animations.dart';
import '../utils/haptics.dart';

/// Outline button with gradient border and optional icon
///
/// Design Specifications:
/// - Height: 48px minimum (accessible touch target)
/// - Border radius: 24px (pill-shaped, matches AppGradientButton)
/// - Border width: 1.5px (gradient or solid color)
/// - Used for secondary actions (e.g., WhatsApp, Cancel)
class AppOutlineButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final Widget? leading;
  final Widget? trailing;
  final double width;
  final List<Color>? gradientColors;
  final Color? textColor;
  final double? height;
  final bool showShadow;
  final bool isFullWidth;
  final VoidCallback? onHover;

  const AppOutlineButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.leading,
    this.trailing,
    this.width = double.infinity,
    this.gradientColors,
    this.textColor,
    this.height,
    this.showShadow = false,
    this.isFullWidth = true,
    this.onHover,
  });

  @override
  State<AppOutlineButton> createState() => _AppOutlineButtonState();
}

class _AppOutlineButtonState extends State<AppOutlineButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final effectiveHeight = widget.height ?? AppDimensions.buttonHeightMedium;
    final effectiveWidth = widget.isFullWidth ? double.infinity : widget.width;

    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        widget.onHover?.call();
      },
      onExit: (_) => setState(() => _isHovered = false),
      cursor: widget.onPressed != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      child: GestureDetector(
        onTapDown: (_) {
          if (widget.onPressed != null) {
            setState(() => _isPressed = true);
          }
        },
        onTapUp: (_) {
          if (widget.onPressed != null) {
            setState(() => _isPressed = false);
            Haptics.lightTap();
            widget.onPressed?.call();
          }
        },
        onTapCancel: () {
          setState(() => _isPressed = false);
        },
        child: AnimatedScale(
          scale: _isPressed ? 0.97 : 1.0,
          duration: AppAnimations.fast,
          child: AnimatedContainer(
            duration: AppAnimations.normal,
            width: effectiveWidth,
            height: effectiveHeight,
            decoration: ShapeDecoration(
              color: _getBackgroundColor(),
              shadows: _getShadows(),
              shape: SmoothRectangleBorder(
                borderRadius: SmoothBorderRadius(
                  cornerRadius: AppDimensions.radiusButton,
                  cornerSmoothing: 1.0,
                ),
                side: BorderSide(
                  color: _getBorderColor(),
                  width: _isPressed ? 2.0 : 1.5,
                ),
              ),
            ),
            child: InkWell(
              onTap: widget.isLoading ? null : widget.onPressed,
              borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: Center(child: _buildButtonContent()),
            ),
          ),
        ),
      ),
    );
  }

  Color _getBackgroundColor() {
    if (widget.onPressed == null) {
      return Colors.transparent.withValues(alpha: 0.05);
    }
    if (_isHovered) {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      return isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.04);
    }
    return Colors.transparent;
  }

  Color _getBorderColor() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (widget.onPressed == null) {
      return isDark
          ? AppColors.textDisabledDark
          : AppColors.textDisabledLight;
    }

    // WhatsApp button specific colors
    if (widget.gradientColors != null &&
        widget.gradientColors!.first == AppColors.whatsappGreen) {
      return _isHovered
          ? AppColors.whatsappGreen.withValues(alpha: 0.8)
          : AppColors.whatsappGreen;
    }

    // Default primary color border
    return _isHovered
        ? (isDark ? AppColors.primaryLight : AppColors.primaryDark)
        : (isDark ? AppColors.primaryDark : AppColors.primary);
  }

  List<BoxShadow> _getShadows() {
    if (!widget.showShadow || widget.onPressed == null) {
      return [];
    }

    final shadowColor = widget.gradientColors?.first ?? AppColors.primary;

    if (_isHovered) {
      return [
        BoxShadow(
          color: shadowColor.withValues(alpha: 0.2),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];
    }

    return [
      BoxShadow(
        color: shadowColor.withValues(alpha: 0.1),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ];
  }

  Widget _buildButtonContent() {
    if (widget.isLoading) {
      return SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(
            widget.textColor ?? _getBorderColor(),
          ),
        ),
      );
    }

    final textColor = widget.textColor ??
        (widget.onPressed == null
            ? AppColors.textDisabledLight
            : _getBorderColor());

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.leading != null) ...[
          widget.leading!,
          const SizedBox(width: AppDimensions.spacing8),
        ] else if (widget.icon != null) ...[
          Semantics(label: widget.text, child: Icon(widget.icon, size: 20)),
          const SizedBox(width: AppDimensions.spacing8),
        ],
        Flexible(
          child: Text(
            widget.text,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (widget.trailing != null) ...[
          const SizedBox(width: AppDimensions.spacing8),
          widget.trailing!,
        ],
      ],
    );
  }
}
