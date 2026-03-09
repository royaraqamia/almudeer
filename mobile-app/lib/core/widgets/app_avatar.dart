import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import '../constants/colors.dart';
import '../extensions/string_extension.dart';

class AppAvatar extends StatelessWidget {
  final String? imageUrl;
  final String? initials;
  final double radius;
  final Color? fallbackColor;
  final TextStyle? textStyle;
  final BoxBorder? border;
  final Widget? overlay;
  final Widget? child;
  final List<Color>? customGradient;

  const AppAvatar({
    super.key,
    this.imageUrl,
    this.initials,
    this.radius = 24,
    this.fallbackColor,
    this.textStyle,
    this.border,
    this.overlay,
    this.child,
    this.customGradient,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final gradient =
        customGradient ??
        (isDark ? AppColors.avatarGradientDark : AppColors.avatarGradientLight);

    // Convert relative server paths to full URLs
    final fullImageUrl = imageUrl?.toFullUrl;

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: border,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(
            child:
                child ??
                (fullImageUrl != null && fullImageUrl.isNotEmpty
                    ? ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: fullImageUrl,
                          width: radius * 2,
                          height: radius * 2,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => _buildPlaceholder(isDark),
                          errorWidget: (_, _, _) => _buildPlaceholder(isDark),
                        ),
                      )
                    : _buildPlaceholder(isDark)),
          ),
          ?overlay,
        ],
      ),
    );
  }

  Widget _buildPlaceholder(bool isDark) {
    if (initials != null && initials!.isNotEmpty) {
      return Text(
        initials!,
        style:
            textStyle ??
            TextStyle(
              color: AppColors.accent,
              fontWeight: FontWeight.bold,
              fontSize: radius * 0.75,
            ),
      );
    }

    return Icon(SolarLinearIcons.user, color: AppColors.accent, size: radius);
  }
}
