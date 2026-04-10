import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';

class PremiumFAB extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget icon;
  final String? label;
  final String? heroTag;
  final List<Color>? gradientColors;
  final bool standalone;

  const PremiumFAB({
    super.key,
    required this.onPressed,
    required this.icon,
    this.label,
    this.heroTag,
    this.gradientColors,
    this.standalone = false,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: gradientColors ?? [AppColors.primary, AppColors.primaryDark],
    );

    Widget content;
    if (label != null) {
      // ... (existing label logic)
      content = Container(
        height: 56,
        decoration: ShapeDecoration(
          gradient: gradient,
          shape: SmoothRectangleBorder(
            borderRadius: SmoothBorderRadius(
              cornerRadius: 28,
              cornerSmoothing: 1.0,
            ),
          ),
          shadows: [
            if (Theme.of(context).brightness != Brightness.dark)
              BoxShadow(
                color: (gradientColors?.first ?? AppColors.primary).withValues(
                  alpha: 0.3,
                ),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: SmoothBorderRadius(
              cornerRadius: 28,
              cornerSmoothing: 1.0,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon,
                  const SizedBox(width: 8),
                  Text(
                    label!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      content = Container(
        width: 56,
        height: 56,
        decoration: standalone
            ? null
            : BoxDecoration(
                gradient: gradient,
                shape: BoxShape.circle,
                boxShadow: [
                  if (Theme.of(context).brightness != Brightness.dark)
                    BoxShadow(
                      color: (gradientColors?.first ?? AppColors.primary)
                          .withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                ],
              ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: Center(child: icon),
          ),
        ),
      );
    }

    if (heroTag != null) {
      return Hero(
        tag: heroTag!,
        child: Material(type: MaterialType.transparency, child: content),
      );
    }
    return content;
  }
}
