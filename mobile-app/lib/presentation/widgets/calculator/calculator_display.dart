import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/animated_toast.dart';
import '../../../core/utils/haptics.dart';

class CalculatorDisplay extends StatelessWidget {
  final String expression;
  final String result;

  const CalculatorDisplay({
    super.key,
    required this.expression,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        if (result.isNotEmpty && result != 'Error') {
          Clipboard.setData(ClipboardData(text: result));
          Haptics.mediumTap();
          AnimatedToast.success(context, 'تم نسخ النتيجة');
        } else if (expression.isNotEmpty) {
          Clipboard.setData(ClipboardData(text: expression));
          Haptics.mediumTap();
          AnimatedToast.success(context, 'تم نسخ التعبير');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        alignment: Alignment.bottomRight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                style: TextStyle(
                  fontSize: expression.length > 10 ? 32 : 48,
                  fontWeight: FontWeight.w300,
                  color: isDark ? Colors.white : Colors.black87,
                  fontFamily: 'IBM Plex Sans Arabic',
                  letterSpacing: -1,
                ),
                child: Text(expression.isEmpty ? '0' : expression),
              ),
            ),
            const SizedBox(height: 8),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: result.isNotEmpty ? 1.0 : 0.0,
              child: Text(
                result == 'Error' ? 'خطأ' : result,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w400,
                  color: result == 'Error'
                      ? Colors.red
                      : (isDark ? Colors.white70 : Colors.black54),
                  fontFamily: 'IBM Plex Sans Arabic',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
