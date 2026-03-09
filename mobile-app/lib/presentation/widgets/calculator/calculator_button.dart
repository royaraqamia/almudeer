import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import '../../../core/utils/haptics.dart';

class CalculatorButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final Color? color;
  final Color? textColor;
  final bool isLarge;
  final IconData? icon;

  const CalculatorButton({
    super.key,
    required this.text,
    required this.onTap,
    this.color,
    this.textColor,
    this.isLarge = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return _CalculatorButtonContent(
      text: text,
      onTap: onTap,
      color: color,
      textColor: textColor,
      isLarge: isLarge,
      icon: icon,
    );
  }
}

class _CalculatorButtonContent extends StatefulWidget {
  final String text;
  final VoidCallback onTap;
  final Color? color;
  final Color? textColor;
  final bool isLarge;
  final IconData? icon;

  const _CalculatorButtonContent({
    required this.text,
    required this.onTap,
    this.color,
    this.textColor,
    this.isLarge = false,
    this.icon,
  });

  @override
  State<_CalculatorButtonContent> createState() =>
      _CalculatorButtonContentState();
}

class _CalculatorButtonContentState extends State<_CalculatorButtonContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.92,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Expanded(
      flex: widget.isLarge ? 2 : 1,
      child: Padding(
        padding: const EdgeInsets.all(6.0),
        child: GestureDetector(
          onTapDown: (_) => _controller.forward(),
          onTapUp: (_) => _controller.reverse(),
          onTapCancel: () => _controller.reverse(),
          onTap: () {
            Haptics.lightTap();
            widget.onTap();
          },
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Container(
              decoration: ShapeDecoration(
                color:
                    widget.color ??
                    (isDark ? Colors.grey[850] : Colors.grey[200]),
                shape: SmoothRectangleBorder(
                  borderRadius: SmoothBorderRadius(
                    cornerRadius: 20,
                    cornerSmoothing: 1.0,
                  ),
                ),
                shadows: isDark
                    ? []
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: Center(
                child: widget.icon != null
                    ? Icon(
                        widget.icon,
                        color:
                            widget.textColor ??
                            (isDark ? Colors.white : Colors.black87),
                        size: 28,
                      )
                    : Text(
                        widget.text,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color:
                              widget.textColor ??
                              (isDark ? Colors.white : Colors.black87),
                          fontFamily: 'IBM Plex Sans Arabic',
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
