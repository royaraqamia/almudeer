import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';

/// A small indicator for Almudeer account holders
class AlmudeerIndicator extends StatelessWidget {
  final double size;
  final Color? color;

  const AlmudeerIndicator({super.key, this.size = 14, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: (color ?? AppColors.primary).withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Tooltip(
        message: 'ط­ط³ط§ط¨ ط§ظ„ظ…ط¯ظٹط± ظ…ظڈظپط¹ظ‘ظژظ„',
        child: SvgPicture.asset(
          'assets/icons/library.svg',
          width: size,
          height: size,
          colorFilter: ColorFilter.mode(
            color ?? AppColors.primary,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}
