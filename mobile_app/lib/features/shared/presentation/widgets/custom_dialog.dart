import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:almudeer_mobile_app/core/widgets/app_text_field.dart';
import 'package:almudeer_mobile_app/core/widgets/app_gradient_button.dart';
import 'premium_bottom_sheet.dart';

enum DialogType { success, error, warning, info, confirm, input }

class CustomDialog extends StatefulWidget {
  final String title;
  final String? message;
  final DialogType type;
  final String? confirmText;
  final String? cancelText;
  final VoidCallback? onConfirm;
  final Function(String)? onConfirmInput;
  final VoidCallback? onCancel;
  final Widget? content;
  final IconData? icon;
  final Color? color;
  final bool isLoading;

  const CustomDialog({
    super.key,
    required this.title,
    this.message,
    this.type = DialogType.info,
    this.confirmText,
    this.cancelText,
    this.onConfirm,
    this.onConfirmInput,
    this.onCancel,
    this.content,
    this.icon,
    this.color,
    this.isLoading = false,
  });

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    String? message,
    DialogType type = DialogType.info,
    String? confirmText,
    String? cancelText,
    VoidCallback? onConfirm,
    Function(String)? onConfirmInput,
    VoidCallback? onCancel,
    Widget? content,
    IconData? icon,
    Color? color,
    bool isLoading = false,
    bool barrierDismissible = true,
  }) {
    // We convert showDialog to PremiumBottomSheet.show
    return PremiumBottomSheet.show<T>(
      context: context,
      isDismissible: barrierDismissible,
      padding: EdgeInsets.zero, // We handle padding inside CustomDialog
      child: CustomDialog(
        title: title,
        message: message,
        type: type,
        confirmText: confirmText,
        cancelText: cancelText,
        onConfirm: onConfirm,
        onConfirmInput: onConfirmInput,
        onCancel: onCancel,
        content: content,
        icon: icon,
        color: color,
        isLoading: isLoading,
      ),
    );
  }

  @override
  State<CustomDialog> createState() => _CustomDialogState();
}

class _CustomDialogState extends State<CustomDialog> {
  final TextEditingController _inputController = TextEditingController();

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Text(
                  widget.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 17, // Apple standard: 17pt (was 20)
                    fontWeight: FontWeight.w600, // Semibold (was bold)
                    letterSpacing: -0.5, // Apple standard for titles
                  ),
                  textAlign: TextAlign.center,
                ),
                // Message rendering removed to comply with bottom sheet standards
              ],
            ),
          ),
          if (widget.type == DialogType.input) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: AppTextField(
                controller: _inputController,
                textAlign: TextAlign.center,
                hintText: 'ط£ط¯ط®ظگظ„ ط§ظ„ط¨ظٹط§ظ†ط§طھ ظ‡ظ†ط§',
              ),
            ),
          ],
          if (widget.content != null) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: widget.content!,
            ),
          ],
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Row(
              children: [
                if (widget.onCancel != null || widget.cancelText != null) ...[
                  Expanded(
                    child: TextButton(
                      onPressed: widget.isLoading
                          ? null
                          : () {
                              if (widget.onCancel != null) {
                                widget.onCancel!();
                              } else {
                                Navigator.pop(context, false);
                              }
                            },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: SmoothRectangleBorder(
                          borderRadius: SmoothBorderRadius(
                            cornerRadius: 16,
                            cornerSmoothing: 1.0,
                          ),
                        ),
                      ),
                      child: Text(
                        widget.cancelText ?? 'ط¥ظ„ط؛ط§ط،',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black54,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: widget.type == DialogType.error
                      ? AppGradientButton.danger(
                          text: widget.confirmText ?? 'ط­ط³ظ†ظ‹ط§',
                          isLoading: widget.isLoading,
                          onPressed: () {
                            if (widget.type == DialogType.input) {
                              if (widget.onConfirmInput != null) {
                                widget.onConfirmInput!(_inputController.text);
                                Navigator.pop(context, true);
                              } else {
                                Navigator.pop(context, _inputController.text);
                              }
                            } else {
                              if (widget.onConfirm != null) {
                                widget.onConfirm!();
                              } else {
                                Navigator.pop(context, true);
                              }
                            }
                          },
                        )
                      : AppGradientButton(
                          text: widget.confirmText ?? 'ط­ط³ظ†ظ‹ط§',
                          isLoading: widget.isLoading,
                          gradientColors: widget.type == DialogType.warning
                              ? [
                                  const Color(0xFFF59E0B),
                                  const Color(0xFFD97706),
                                ]
                              : null,
                          onPressed: () {
                            if (widget.type == DialogType.input) {
                              if (widget.onConfirmInput != null) {
                                widget.onConfirmInput!(_inputController.text);
                                Navigator.pop(context, true);
                              } else {
                                Navigator.pop(context, _inputController.text);
                              }
                            } else {
                              if (widget.onConfirm != null) {
                                widget.onConfirm!();
                              } else {
                                Navigator.pop(context, true);
                              }
                            }
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
