import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/animated_toast.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';

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

    // Check if result is an error message (any of the Arabic error strings)
    final isError = result == 'ط®ط·ط£' || 
                    result == 'ط؛ظٹط± ظ…ط¹ط±ظ‘ظپ' || 
                    result == 'طµظٹط؛ط© ط؛ظٹط± طµط­ظٹط­ط©' || 
                    result == 'طھط¹ط¨ظٹط± ط؛ظٹط± طµط­ظٹط­' ||
                    result == 'Error';

    return GestureDetector(
      onTap: () {
        if (result.isNotEmpty && !isError) {
          Clipboard.setData(ClipboardData(text: result));
          Haptics.mediumTap();
          AnimatedToast.success(context, 'طھظ… ظ†ط³ط® ط§ظ„ظ†طھظٹط¬ط©');
        } else if (expression.isNotEmpty) {
          Clipboard.setData(ClipboardData(text: expression));
          Haptics.mediumTap();
          AnimatedToast.success(context, 'طھظ… ظ†ط³ط® ط§ظ„طھط¹ط¨ظٹط±');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        alignment: Alignment.bottomRight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableHeight = constraints.maxHeight;
            final needsSmallText = availableHeight < 100;

            return Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      style: TextStyle(
                        fontSize: needsSmallText
                            ? 24
                            : expression.length > 10
                                ? 32
                                : 48,
                        fontWeight: FontWeight.w300,
                        color: isDark ? Colors.white : Colors.black87,
                        fontFamily: 'IBM Plex Sans Arabic',
                        letterSpacing: -1,
                        height: 1.2,
                      ),
                      child: Text(
                        expression.isEmpty ? '0' : expression,
                        maxLines: needsSmallText ? 2 : null,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: needsSmallText ? 4 : 8),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: result.isNotEmpty ? 1.0 : 0.0,
                  child: Text(
                    isError ? 'ط®ط·ط£' : result,
                    style: TextStyle(
                      fontSize: needsSmallText ? 20 : 28,
                      fontWeight: FontWeight.w400,
                      color: isError
                          ? Colors.red
                          : (isDark ? Colors.white70 : Colors.black54),
                      fontFamily: 'IBM Plex Sans Arabic',
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
