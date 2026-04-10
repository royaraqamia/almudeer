import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import '../constants/colors.dart';
import '../constants/dimensions.dart';
import '../constants/shadows.dart';

/// Premium text field with floating label, character counter, and enhanced validation
///
/// Design Specifications:
/// - Height: 48px minimum (56px with floating label)
/// - Border radius: 24px (pill-shaped) or custom
/// - Border width: 1px (default), 1.5px (focused/error)
/// - Character counter with maxLength option
/// - Manual error display to avoid InputDecorator shifts
class AppTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String hintText;
  final String? labelText;
  final bool obscureText;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final TextInputAction? textInputAction;
  final Function(String)? onFieldSubmitted;
  final Function(String)? onChanged;
  final VoidCallback? onEditingComplete;
  final double? height;
  final double? maxHeight;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final bool showCharacterCounter;
  final TextAlign? textAlign;
  final bool enabled;
  final FocusNode? focusNode;
  final TextDirection? textDirection;
  final Color? backgroundColor;
  final bool showBorder;
  final bool showShadow;
  final TextAlignVertical? textAlignVertical;
  final String? errorText;
  final double? borderRadius;
  final bool readOnly;
  final VoidCallback? onTap;
  final double? lineHeight;
  final TextStyle? style;
  final TextStyle? hintStyle;
  final bool useFloatingLabel;

  // Apple HIG: Auto-capitalization controls
  final bool autocorrect;
  final bool enableSuggestions;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;
  final bool enableInteractiveSelection;

  const AppTextField({
    super.key,
    this.controller,
    required this.hintText,
    this.labelText,
    this.obscureText = false,
    this.validator,
    this.keyboardType = TextInputType.text,
    this.textInputAction,
    this.onFieldSubmitted,
    this.onChanged,
    this.onEditingComplete,
    this.height = 48,
    this.maxHeight = 96,
    this.prefixIcon,
    this.suffixIcon,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.showCharacterCounter = false,
    this.textAlign,
    this.enabled = true,
    this.focusNode,
    this.textDirection,
    this.backgroundColor,
    this.showBorder = true,
    this.showShadow = true,
    this.textAlignVertical,
    this.errorText,
    this.borderRadius,
    this.readOnly = false,
    this.onTap,
    this.lineHeight = 1.2,
    this.style,
    this.hintStyle,
    this.useFloatingLabel = false,
    // Apple HIG: Default to no autocorrect for sensitive fields
    this.autocorrect = false,
    this.enableSuggestions = false,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.autofocus = false,
    this.enableInteractiveSelection = true,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late FocusNode _focusNode;
  bool _isFocused = false;
  String? _internalErrorText;
  late TextEditingController _controller;
  int _currentLength = 0;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _currentLength = _controller.text.length;
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChange);
    _controller.addListener(_handleTextChange);
  }

  @override
  void dispose() {
    // Remove listener (controller might already be disposed by parent)
    try {
      _controller.removeListener(_handleTextChange);
    } catch (_) {
      // Controller was already disposed, ignore
    }
    // Only dispose if we created it
    if (widget.controller == null) {
      try {
        _controller.dispose();
      } catch (_) {
        // Already disposed, ignore
      }
    }
    // Clean up focus node
    if (widget.focusNode == null) {
      _focusNode.removeListener(_handleFocusChange);
      _focusNode.dispose();
    } else {
      _focusNode.removeListener(_handleFocusChange);
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Handle controller change
    if (oldWidget.controller != widget.controller) {
      // Remove listener from old controller (if not disposed)
      try {
        oldWidget.controller?.removeListener(_handleTextChange);
      } catch (_) {
        // Old controller was already disposed, ignore
      }
      // Update reference and add listener to new controller
      _controller = widget.controller ?? TextEditingController();
      _currentLength = _controller.text.length;
      _controller.addListener(_handleTextChange);
    }
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    }
  }

  void _handleTextChange() {
    // Safety check: controller might be disposed by parent
    try {
      if (mounted && _controller.text.length != _currentLength) {
        setState(() {
          _currentLength = _controller.text.length;
        });
      }
    } catch (_) {
      // Controller was disposed, ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isMultiline = (widget.maxLines == null || widget.maxLines! > 1);

    // PRESERVED: Approved 24px pill radius or custom
    final double borderRadius =
        widget.borderRadius ??
        (widget.height != null ? widget.height! / 2 : 24);

    final currentError = widget.errorText ?? _internalErrorText;
    final hasError = currentError != null;
    final showCounter = widget.showCharacterCounter && widget.maxLength != null;
    final effectiveHeight = widget.useFloatingLabel
        ? (widget.height ?? 56)
        : (widget.height ?? 48);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Floating label (if enabled)
        if (widget.useFloatingLabel && widget.labelText != null) ...[
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style:
                theme.textTheme.labelMedium?.copyWith(
                  color: hasError
                      ? AppColors.error
                      : (_isFocused
                            ? AppColors.primary
                            : (isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight)),
                  fontSize: _isFocused ? 13 : 12,
                  fontWeight: FontWeight.w500,
                ) ??
                const TextStyle(fontSize: 12),
            child: Padding(
              padding: const EdgeInsets.only(
                left: AppDimensions.spacing16,
                right: AppDimensions.spacing16,
                bottom: AppDimensions.spacing4,
              ),
              child: Text(widget.labelText!),
            ),
          ),
        ],
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter, // Grows upwards
          child: Container(
            constraints: BoxConstraints(
              minHeight: effectiveHeight,
              maxHeight: isMultiline
                  ? (widget.maxHeight ?? 96)
                  : effectiveHeight,
            ),
            decoration: ShapeDecoration(
              color:
                  widget.backgroundColor ??
                  (isDark ? AppColors.surfaceDark : AppColors.surfaceLight),
              shape: SmoothRectangleBorder(
                borderRadius: SmoothBorderRadius(
                  cornerRadius: borderRadius,
                  cornerSmoothing: 1.0,
                ),
                side: widget.showBorder
                    ? BorderSide(
                        color: hasError
                            ? AppColors.error
                            : (_isFocused
                                  ? AppColors.primary
                                  : (isDark
                                        ? Colors.white10
                                        : AppColors.borderLight)),
                        width: (_isFocused || hasError) ? 1.5 : 1.0,
                      )
                    : BorderSide.none,
              ),
              shadows: widget.showShadow
                  ? [
                      if (isDark)
                        BoxShadow(
                          color: hasError
                              ? AppColors.error.withValues(alpha: 0.1)
                              : (_isFocused
                                    ? AppColors.primary.withValues(alpha: 0.1)
                                    : Colors.black.withValues(alpha: 0.15)),
                          blurRadius: 24,
                          offset: Offset(0, (_isFocused || hasError) ? 2 : 4),
                        )
                      else
                        AppShadows.premiumShadow,
                    ]
                  : [],
            ),
            clipBehavior: Clip.antiAlias, // PRESERVED: Perfect corners logic
            child: TextFormField(
              controller: _controller,
              obscureText: widget.obscureText,
              readOnly: widget.readOnly,
              showCursor: !widget.readOnly,
              onTap: widget.onTap,
              keyboardType:
                  isMultiline && widget.keyboardType == TextInputType.text
                      ? TextInputType.multiline
                      : widget.keyboardType,
              onChanged: (value) {
                // Manual validation to avoid InputDecorator shifts
                if (widget.validator != null) {
                  final error = widget.validator!(value);
                  if (_internalErrorText != error) {
                    setState(() {
                      _internalErrorText = error;
                    });
                  }
                } else if (_internalErrorText != null) {
                  setState(() {
                    _internalErrorText = null;
                  });
                }
                widget.onChanged?.call(value);
              },
              validator: (value) {
                // ALWAYS return null to prevent InputDecorator from reserving space
                // and shifting the baseline. We handle the error UI manually.
                final error = widget.validator?.call(value);

                // Use a post-frame callback to update UI safely during validation
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _internalErrorText != error) {
                    setState(() {
                      _internalErrorText = error;
                    });
                  }
                });
                return null;
              },
              enabled: widget.enabled,
              textInputAction: isMultiline
                  ? TextInputAction.newline
                  : widget.textInputAction,
              onEditingComplete: widget.onEditingComplete,
              onFieldSubmitted: (value) {
                // Ensure validation runs on submit as well
                if (widget.validator != null) {
                  final error = widget.validator!(value);
                  if (_internalErrorText != error) {
                    setState(() {
                      _internalErrorText = error;
                    });
                  }
                }
                widget.onFieldSubmitted?.call(value);
              },
              maxLines: widget.maxLines,
              minLines: isMultiline ? 1 : widget.minLines,
              textAlign:
                  widget.textAlign ??
                  (Directionality.of(context) == TextDirection.rtl
                      ? TextAlign.right
                      : TextAlign.left),
              textDirection: Directionality.of(context),
              focusNode: _focusNode,
              // Only set textAlignVertical for multiline fields to avoid vertical caret movement issues
              textAlignVertical: isMultiline
                  ? (widget.textAlignVertical ?? TextAlignVertical.center)
                  : widget.textAlignVertical,
              style:
                  widget.style ??
                  TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: widget.lineHeight,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                    letterSpacing: -0.3, // Apple standard for text fields
                  ),
              // Apple HIG: Disable autocorrect for sensitive fields
              autocorrect: widget.autocorrect,
              enableSuggestions: widget.enableSuggestions,
              textCapitalization: widget.textCapitalization,
              inputFormatters: widget.inputFormatters,
              autofocus: widget.autofocus,
              enableInteractiveSelection: widget.enableInteractiveSelection,
              decoration: InputDecoration(
                hintText: widget.useFloatingLabel ? null : widget.hintText,
                hintStyle:
                    widget.hintStyle ??
                    TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      height: widget.lineHeight,
                      color: isDark
                          ? AppColors.textTertiaryDark
                          : AppColors.textTertiaryLight,
                      // Apple HIG: 60% opacity for placeholders
                    ),
                prefixIcon: widget.prefixIcon,
                suffixIcon: widget.suffixIcon,
                contentPadding: EdgeInsets.only(
                  left: widget.prefixIcon != null ? 12 : 24,
                  right: widget.suffixIcon != null || showCounter ? 12 : 24,
                  top: widget.useFloatingLabel ? 18 : 14,
                  bottom: widget.useFloatingLabel ? 18 : 14,
                ),
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                fillColor: Colors.transparent,
                filled: true,
              ),
            ),
          ),
        ),
        // Error message and character counter row
        if (hasError || showCounter)
          Padding(
            padding: const EdgeInsets.only(
              top: AppDimensions.spacing6,
              right: AppDimensions.spacing16,
              left: AppDimensions.spacing16,
            ),
            child: Row(
              children: [
                if (hasError) ...[
                  const Icon(
                    SolarLinearIcons.dangerCircle,
                    color: AppColors.error,
                    size: 14,
                  ),
                  const SizedBox(width: AppDimensions.spacing4),
                  Expanded(
                    child: Text(
                      currentError,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
                if (showCounter)
                  Text(
                    '$_currentLength/${widget.maxLength}',
                    style: TextStyle(
                      color: _currentLength > (widget.maxLength ?? 0)
                          ? AppColors.error
                          : (isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
