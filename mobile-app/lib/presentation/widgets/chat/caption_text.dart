import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import '../../../core/constants/colors.dart';
import '../../../core/extensions/string_extension.dart';
import '../animated_toast.dart';

/// Reusable caption display widget with truncation, expand/collapse, and copy functionality
class CaptionText extends StatefulWidget {
  final String caption;
  final bool isOutgoing;
  final ThemeData theme;
  final int maxLength;
  final BorderRadius? borderRadius;

  const CaptionText({
    super.key,
    required this.caption,
    required this.isOutgoing,
    required this.theme,
    this.maxLength = 150,
    this.borderRadius,
  });

  @override
  State<CaptionText> createState() => _CaptionTextState();
}

class _CaptionTextState extends State<CaptionText> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final isLongCaption = widget.caption.length > widget.maxLength;
    final displayText = isLongCaption && !_isExpanded
        ? '${widget.caption.substring(0, widget.maxLength)}...'
        : widget.caption;

    return Semantics(
      label: 'التعليق: ${widget.caption}',
      child: GestureDetector(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: widget.caption));
          if (context.mounted) {
            AnimatedToast.success(context, 'تم نسخ التعليق');
          }
        },
        onTap: isLongCaption ? () {
          setState(() {
            _isExpanded = !_isExpanded;
          });
        } : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isOutgoing
                ? Colors.white.withValues(alpha: 0.15)
                : (widget.theme.brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.03)),
            borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayText,
                style: widget.theme.textTheme.bodySmall?.copyWith(
                  color: widget.isOutgoing
                      ? Colors.white.withValues(alpha: 0.9)
                      : null,
                  fontSize: 13,
                  height: 1.4,
                ),
                textDirection: widget.caption.isArabic
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                textAlign: widget.caption.isArabic
                    ? TextAlign.right
                    : TextAlign.left,
              ),
              if (isLongCaption) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: widget.caption.isArabic
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isExpanded = !_isExpanded;
                        });
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isExpanded ? 'أقل' : 'المزيد',
                            style: widget.theme.textTheme.labelSmall?.copyWith(
                              color: widget.isOutgoing
                                  ? Colors.white.withValues(alpha: 0.7)
                                  : AppColors.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            _isExpanded
                                ? SolarLinearIcons.arrowUp
                                : SolarLinearIcons.arrowDown,
                            size: 12,
                            color: widget.isOutgoing
                                ? Colors.white.withValues(alpha: 0.7)
                                : AppColors.primary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(${widget.caption.length} حرف)',
                      style: widget.theme.textTheme.labelSmall?.copyWith(
                        color: widget.isOutgoing
                            ? Colors.white.withValues(alpha: 0.5)
                            : widget.theme.hintColor.withValues(alpha: 0.5),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
