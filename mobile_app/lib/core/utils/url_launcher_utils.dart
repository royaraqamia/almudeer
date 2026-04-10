import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/ad_blocker_service.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/animated_toast.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/custom_dialog.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

class AppLauncher {
  AppLauncher._();

  static final PornBlockerService _adBlocker = PornBlockerService();

  /// Launches a URL after verifying it's safe (not adult content)
  static Future<void> launchSafeUrl(
    BuildContext context,
    String urlString,
  ) async {
    if (urlString.isEmpty) return;

    final url = urlString.trim();

    // Check for adult content
    if (_adBlocker.isAdultContent(url)) {
      _showBlockedDialog(context);
      return;
    }

    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          AnimatedToast.error(context, 'ظ„ط§ ظٹظ…ظƒظ† ظپطھط­ ظ‡ط°ط§ ط§ظ„ط±ط§ط¨ط·');
        }
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
      if (context.mounted) {
        AnimatedToast.error(context, 'ط­ط¯ط« ط®ط·ط£ ط£ط«ظ†ط§ط، ظپطھط­ ط§ظ„ط±ط§ط¨ط·');
      }
    }
  }

  static void _showBlockedDialog(BuildContext context) {
    CustomDialog.show(
      context,
      title: 'ظ…ط­طھظˆظ‰ ظ…ط­ط¸ظˆط±',
      type: DialogType.warning,
      message:
          'طھظ… ط­ط¸ط± ط§ظ„ظˆطµظˆظ„ ط¥ظ„ظ‰ ظ‡ط°ط§ ط§ظ„ظ…ظˆظ‚ط¹ ظ„ط£ظ†ظ‡ ظٹط­طھظˆظٹ ط¹ظ„ظ‰ ظ…ط­طھظˆظ‰ ط؛ظٹط± ظ„ط§ط¦ظ‚. ظٹط±ط¬ظ‰ ط§ظ„ط§ظ„طھط²ط§ظ… ط¨ط³ظٹط§ط³ط© ط§ظ„ط§ط³طھط®ط¯ط§ظ… ط§ظ„ط¢ظ…ظ†.',
      icon: SolarBoldIcons.shieldWarning,
      color: Colors.red,
      confirmText: 'ط­ط³ظ†ظ‹ط§',
    );
  }
}
