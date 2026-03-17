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
  final Duration fadeInDuration;
  final Duration fadeOutDuration;
  final VoidCallback? onImageLoading;
  final VoidCallback? onImageSuccess;
  final VoidCallback? onImageError;
  final String? semanticsLabel;

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
    this.fadeInDuration = const Duration(milliseconds: 300),
    this.fadeOutDuration = const Duration(milliseconds: 300),
    this.onImageLoading,
    this.onImageSuccess,
    this.onImageError,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final gradient =
        customGradient ??
        (isDark ? AppColors.avatarGradientDark : AppColors.avatarGradientLight);

    // Convert relative server paths to full URLs
    final fullImageUrl = imageUrl?.toFullUrl;

    final avatarWidget = Container(
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
                (fullImageUrl?.isNotEmpty == true
                    ? ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: fullImageUrl!,
                          width: radius * 2,
                          height: radius * 2,
                          fit: BoxFit.cover,
                          fadeInDuration: fadeInDuration,
                          fadeOutDuration: fadeOutDuration,
                          placeholder: (context, url) {
                            onImageLoading?.call();
                            return _buildPlaceholder(isDark);
                          },
                          errorWidget: (context, url, error) {
                            onImageError?.call();
                            return _buildPlaceholder(isDark);
                          },
                          imageBuilder: (context, imageProvider) {
                            onImageSuccess?.call();
                            return Container(
                              width: radius * 2,
                              height: radius * 2,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                image: DecorationImage(
                                  image: imageProvider,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            );
                          },
                        ),
                      )
                    : _buildPlaceholder(isDark)),
          ),
          // ignore: use_null_aware_elements
          if (overlay != null) overlay!,
        ],
      ),
    );

    // Wrap with Semantics for accessibility
    if (semanticsLabel?.isNotEmpty == true) {
      return Semantics(
        label: semanticsLabel!,
        image: true,
        child: avatarWidget,
      );
    }

    return avatarWidget;
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
