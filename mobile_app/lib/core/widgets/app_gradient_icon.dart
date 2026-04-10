import 'package:flutter/material.dart';
import '../constants/colors.dart';

class AppGradientIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final bool isEnabled;
  final List<Color>? gradientColors;

  const AppGradientIcon({
    super.key,
    required this.icon,
    this.size = 24,
    this.isEnabled = true,
    this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    final colors = (gradientColors ?? [AppColors.primary, AppColors.accent]);
    final effectiveColors = isEnabled
        ? colors
        : colors.map((c) => c.withValues(alpha: 0.5)).toList();

    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: effectiveColors,
        ).createShader(bounds);
      },
      blendMode: BlendMode.srcIn,
      child: Icon(
        icon,
        size: size,
        color: Colors.white, // Base color for the gradient mask
      ),
    );
  }
}
