import 'package:flutter/material.dart';
import '../widgets/custom_dialog.dart';

class LoadingOverlay extends StatelessWidget {
  final Widget child;
  final bool isLoading;
  final String? message;
  final Color? color;
  final Color? textColor;

  const LoadingOverlay({
    super.key,
    required this.child,
    required this.isLoading,
    this.message,
    this.color,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Container(
            color: (color ?? Colors.black).withValues(alpha: 0.7),
            width: double.infinity,
            height: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
                if (message != null) ...[
                  const SizedBox(height: 24),
                  Material(
                    color: Colors.transparent,
                    child: Text(
                      message!,
                      style: TextStyle(
                        color: textColor ?? Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// Static helper to show a global blocking overlay using CustomDialog
  /// Returns a function to dismiss the overlay
  static Future<void> show({required BuildContext context, String? message}) {
    return CustomDialog.show(
      context,
      title: message ?? 'جاري التحميل...',
      type: DialogType.info,
      isLoading: true,
      barrierDismissible: false,
    );
  }
}
