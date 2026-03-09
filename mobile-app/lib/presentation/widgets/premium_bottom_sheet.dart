import 'dart:math';
import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/dimensions.dart';
import '../../core/utils/haptics.dart';

/// Premium bottom sheet with glassmorphic effects, drag gestures, and snap points
///
/// Design Specifications:
/// - Radius: 24px (top corners)
/// - Handle: 40x5px drag indicator
/// - Snap points: 0.25, 0.5, 1.0 (optional)
/// - Max height: 85% viewport (configurable)
/// - Glassmorphism with backdrop blur
/// - Drag-to-dismiss with velocity detection
class PremiumBottomSheet extends StatefulWidget {
  final Widget child;
  final String? title;
  final List<Widget>? actions;
  final bool showHandle;
  final bool showCloseButton;
  final EdgeInsetsGeometry? padding;
  final double? maxHeight;
  final bool isDismissible;
  final bool enableDrag;
  final List<double>? snapPoints;
  final VoidCallback? onDismiss;

  const PremiumBottomSheet({
    super.key,
    required this.child,
    this.title,
    this.actions,
    this.showHandle = true,
    this.showCloseButton = false,
    this.padding,
    this.maxHeight,
    this.isDismissible = true,
    this.enableDrag = true,
    this.snapPoints,
    this.onDismiss,
  });

  /// Static method to show the premium bottom sheet
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    List<Widget>? actions,
    bool showHandle = true,
    bool showCloseButton = false,
    EdgeInsetsGeometry? padding,
    double? maxHeight,
    bool isDismissible = true,
    bool enableDrag = true,
    bool isScrollControlled = true,
    Color? barrierColor,
    List<double>? snapPoints,
    VoidCallback? onDismiss,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      isScrollControlled: isScrollControlled,
      backgroundColor: Colors.transparent,
      barrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.5),
      elevation: 0,
      builder: (context) => PremiumBottomSheet(
        title: title,
        actions: actions,
        showHandle: showHandle,
        showCloseButton: showCloseButton,
        padding: padding,
        maxHeight: maxHeight,
        isDismissible: isDismissible,
        enableDrag: enableDrag,
        snapPoints: snapPoints,
        onDismiss: onDismiss,
        child: child,
      ),
    );
  }

  @override
  State<PremiumBottomSheet> createState() => _PremiumBottomSheetState();
}

class _PremiumBottomSheetState extends State<PremiumBottomSheet> {
  double _dragExtent = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final availableHeight = screenHeight - bottomInset - safeAreaBottom - 100;
    final contentHeight = min(
      widget.maxHeight ?? screenHeight * 0.85,
      availableHeight,
    );

    return GestureDetector(
      onVerticalDragStart: widget.enableDrag ? _onDragStart : null,
      onVerticalDragUpdate: widget.enableDrag ? _onDragUpdate : null,
      onVerticalDragEnd: widget.enableDrag ? _onDragEnd : null,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppDimensions.spacing16,
          right: AppDimensions.spacing16,
          bottom: bottomInset > 0
              ? bottomInset + AppDimensions.spacing16
              : safeAreaBottom + AppDimensions.spacing16,
        ),
        child: Material(
          color: Colors.transparent,
          child: AnimatedBuilder(
            animation: Listenable.merge([Listenable.merge([])]),
            builder: (context, _) {
              return Transform.translate(
                offset: Offset(0, _dragExtent),
                child: ClipSmoothRect(
                  radius: SmoothBorderRadius(
                    cornerRadius: AppDimensions.radiusXXLarge,
                    cornerSmoothing: 1.0,
                  ),
                  child: Container(
                    constraints: BoxConstraints(maxHeight: contentHeight),
                    decoration: ShapeDecoration(
                      color: isDark ? AppColors.surfaceDark : Colors.white,
                      shape: SmoothRectangleBorder(
                        borderRadius: SmoothBorderRadius(
                          cornerRadius: AppDimensions.radiusXXLarge,
                          cornerSmoothing: 1.0,
                        ),
                        side: BorderSide(
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.1),
                          width: 1.0,
                        ),
                      ),
                      shadows: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.3 : 0.15,
                          ),
                          blurRadius: 48,
                          offset: const Offset(0, -8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.showHandle) _buildHandle(context),
                        if (widget.title != null) _buildHeader(context, theme),
                        Flexible(
                          child: Padding(
                            padding:
                                widget.padding ??
                                const EdgeInsets.all(
                                  AppDimensions.paddingLarge,
                                ),
                            child: widget.child,
                          ),
                        ),
                        if (widget.actions != null &&
                            widget.actions!.isNotEmpty)
                          _buildActions(context, theme),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _onDragStart(DragStartDetails details) {
    Haptics.selection();
    setState(() {
      // _isDragging = true;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragExtent += details.delta.dy;
      // Limit drag to 100px downward
      _dragExtent = max(-100, min(100, _dragExtent));
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    final dismissThreshold = 100.0;

    // Dismiss on downward swipe with sufficient velocity
    if (velocity > 500 || _dragExtent > dismissThreshold) {
      Haptics.lightTap();
      widget.onDismiss?.call();
      Navigator.pop(context);
    } else {
      // Snap back to original position
      setState(() {
        _dragExtent = 0;
        // _isDragging = false;
      });
    }
  }

  Widget _buildHandle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 12, bottom: 8),
        width: 40,
        height: 5,
        decoration: ShapeDecoration(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.2),
          shape: SmoothRectangleBorder(
            borderRadius: SmoothBorderRadius(
              cornerRadius: AppDimensions.radiusFull,
              cornerSmoothing: 1.0,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.title!,
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (widget.showCloseButton)
            Semantics(
              label: 'إغلاق',
              child: GestureDetector(
                onTap: () {
                  Haptics.lightTap();
                  widget.onDismiss?.call();
                  Navigator.pop(context);
                },
                child: Container(
                  width: AppDimensions.touchTargetMin,
                  height: AppDimensions.touchTargetMin,
                  decoration: BoxDecoration(
                    color: (Theme.of(context).brightness == Brightness.dark)
                        ? AppColors.hoverDark
                        : AppColors.hoverLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    SolarLinearIcons.closeCircle,
                    size: 20,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: widget.actions!.map((action) {
          return Padding(
            padding: const EdgeInsets.only(left: 12),
            child: action,
          );
        }).toList(),
      ),
    );
  }
}
