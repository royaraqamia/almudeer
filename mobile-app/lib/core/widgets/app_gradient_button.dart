import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import '../constants/colors.dart';
import '../constants/dimensions.dart';
import '../utils/haptics.dart';

class AppGradientButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final Widget? leading;
  final Widget? trailing;
  final double width;
  final List<Color>? gradientColors;
  final Color? textColor;
  final BoxBorder? border;
  final double? height;
  final bool showShadow;
  final bool isFullWidth;
  final VoidCallback? onHover;

  const AppGradientButton({
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
    this.border,
    this.height,
    this.showShadow = false,
    this.isFullWidth = true,
    this.onHover,
  });

  /// Factory for a danger/destructive button with a red gradient
  factory AppGradientButton.danger({
    required String text,
    VoidCallback? onPressed,
    bool isLoading = false,
    IconData? icon,
    double width = double.infinity,
    bool showShadow = false,
  }) {
    return AppGradientButton(
      text: text,
      onPressed: onPressed,
      isLoading: isLoading,
      icon: icon,
      width: width,
      showShadow: showShadow,
      gradientColors: AppColors.errorGradient,
    );
  }

  /// Factory for a ghost button (no border, no background)
  factory AppGradientButton.ghost({
    required String text,
    VoidCallback? onPressed,
    IconData? icon,
    Color? textColor,
    double? height,
  }) {
    return AppGradientButton(
      text: text,
      onPressed: onPressed,
      icon: icon,
      textColor: textColor ?? AppColors.primary,
      height: height,
      gradientColors: [Colors.transparent, Colors.transparent],
      border: Border.all(color: Colors.transparent),
      showShadow: false,
    );
  }

  @override
  State<AppGradientButton> createState() => _AppGradientButtonState();
}

class _AppGradientButtonState extends State<AppGradientButton> {
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
      cursor: widget.onPressed != null ? SystemMouseCursors.click : MouseCursor.defer,
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
          duration: const Duration(milliseconds: 100),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: effectiveWidth,
            height: effectiveHeight,
            decoration: ShapeDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _getGradientColors(),
              ),
              shadows: _getShadows(),
              shape: SmoothRectangleBorder(
                borderRadius: SmoothBorderRadius(
                  cornerRadius: AppDimensions.radiusButton,
                  cornerSmoothing: 1.0,
                ),
                side: widget.border is Border ? (widget.border as Border).top : BorderSide.none,
              ),
            ),
            child: ElevatedButton(
              onPressed: widget.isLoading ? null : widget.onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: widget.textColor ?? Colors.white,
                disabledForegroundColor: (widget.textColor ?? Colors.white).withValues(alpha: 0.5),
                padding: EdgeInsets.zero,
                shape: SmoothRectangleBorder(
                  borderRadius: SmoothBorderRadius(
                    cornerRadius: AppDimensions.radiusButton,
                    cornerSmoothing: 1.0,
                  ),
                ),
                overlayColor: Colors.transparent,
              ),
              child: _buildButtonContent(),
            ),
          ),
        ),
      ),
    );
  }

  List<Color> _getGradientColors() {
    final baseColors = widget.gradientColors ?? [AppColors.primary, AppColors.accent];
    
    // Disabled state
    if (widget.onPressed == null) {
      return baseColors.map((c) => c.withValues(alpha: 0.5)).toList();
    }
    
    // Hover state - slightly brighter
    if (_isHovered) {
      return baseColors.map((c) => Color.lerp(c, Colors.white, 0.1) ?? c).toList();
    }
    
    // Single color handling
    if (baseColors.length == 1) {
      return [baseColors.first, baseColors.first];
    }
    
    return baseColors;
  }

  List<BoxShadow> _getShadows() {
    if (widget.onPressed == null || !widget.showShadow) {
      return [];
    }
    
    final shadowColor = widget.gradientColors?.first ?? AppColors.primary;
    
    // Enhanced shadow on hover
    if (_isHovered) {
      return [
        BoxShadow(
          color: shadowColor.withValues(alpha: 0.4),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];
    }
    
    return [
      BoxShadow(
        color: shadowColor.withValues(alpha: 0.3),
        blurRadius: 12,
        offset: const Offset(0, 4),
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
            widget.textColor ?? Colors.white,
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.leading != null) ...[
          widget.leading!,
          const SizedBox(width: AppDimensions.spacing8),
        ] else if (widget.icon != null) ...[
          Semantics(
            label: widget.text,
            child: Icon(widget.icon, size: 20),
          ),
          const SizedBox(width: AppDimensions.spacing8),
        ],
        Text(
          widget.text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
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
