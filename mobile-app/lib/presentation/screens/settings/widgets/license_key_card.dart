import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:provider/provider.dart';

import '../../../../core/utils/haptics.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/animated_toast.dart';
import '../../../widgets/common_widgets.dart';

class LicenseKeyCard extends StatefulWidget {
  const LicenseKeyCard({super.key});

  @override
  State<LicenseKeyCard> createState() => _LicenseKeyCardState();
}

class _LicenseKeyCardState extends State<LicenseKeyCard> {
  bool _isVisible = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authProvider = context.watch<AuthProvider>();
    final licenseKey =
        authProvider.userInfo?.licenseKey ?? '••••••••-••••-••••';

    return PremiumCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: ShapeDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              shape: SmoothRectangleBorder(
                borderRadius: SmoothBorderRadius(
                  cornerRadius: 11,
                  cornerSmoothing: 1.0,
                ),
              ),
            ),
            child: Icon(
              SolarLinearIcons.key,
              color: theme.colorScheme.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isVisible ? licenseKey : '••••••••-••••-••••',
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontSize: 16,
                letterSpacing: 2,
                color: theme.textTheme.bodyLarge?.color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Visibility Toggle
          GestureDetector(
            onTap: () {
              Haptics.lightTap();
              setState(() {
                _isVisible = !_isVisible;
              });
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: ShapeDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                shape: SmoothRectangleBorder(
                  borderRadius: SmoothBorderRadius(
                    cornerRadius: 10,
                    cornerSmoothing: 1.0,
                  ),
                ),
              ),
              child: Center(
                child: Icon(
                  _isVisible
                      ? SolarLinearIcons.eyeClosed
                      : SolarLinearIcons.eye,
                  color: theme.hintColor,
                  size: 24,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              final actualKey = authProvider.userInfo?.licenseKey;
              if (actualKey != null && actualKey.isNotEmpty) {
                Clipboard.setData(ClipboardData(text: actualKey));
                Haptics.lightTap();
                AnimatedToast.success(context, 'تم نسخ مفتاح الاشتراك');
              } else {
                AnimatedToast.error(
                  context,
                  'عذرًا، لم يتم العثور على المفتاح',
                );
              }
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: ShapeDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                shape: SmoothRectangleBorder(
                  borderRadius: SmoothBorderRadius(
                    cornerRadius: 10,
                    cornerSmoothing: 1.0,
                  ),
                ),
              ),
              child: Center(
                child: SvgPicture.asset(
                  'assets/icons/copy.svg',
                  width: 24,
                  height: 24,
                  colorFilter: ColorFilter.mode(
                    theme.hintColor,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
