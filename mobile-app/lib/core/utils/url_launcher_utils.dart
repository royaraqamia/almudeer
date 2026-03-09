import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/ad_blocker_service.dart';
import '../../presentation/widgets/animated_toast.dart';
import '../../presentation/widgets/custom_dialog.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

class AppLauncher {
  AppLauncher._();

  static final AdBlockerService _adBlocker = AdBlockerService();

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
          AnimatedToast.error(context, 'لا يمكن فتح هذا الرابط');
        }
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
      if (context.mounted) {
        AnimatedToast.error(context, 'حدث خطأ أثناء فتح الرابط');
      }
    }
  }

  static void _showBlockedDialog(BuildContext context) {
    CustomDialog.show(
      context,
      title: 'محتوى محظور',
      type: DialogType.warning,
      message:
          'تم حظر الوصول إلى هذا الموقع لأنه يحتوي على محتوى غير لائق. يرجى الالتزام بسياسة الاستخدام الآمن.',
      icon: SolarBoldIcons.shieldWarning,
      color: Colors.red,
      confirmText: 'حسنًا',
    );
  }
}
