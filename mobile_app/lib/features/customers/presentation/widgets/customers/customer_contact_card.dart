import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:almudeer_mobile_app/core/utils/url_launcher_utils.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/constants/dimensions.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/common_widgets.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/animated_toast.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';

class CustomerContactCard extends StatelessWidget {
  final Map<String, dynamic> customer;

  const CustomerContactCard({super.key, required this.customer});

  bool _isValidPhoneNumber(String phone) {
    // Remove all non-digit characters
    final digitsOnly = phone.replaceAll(RegExp(r'[^0-9]'), '');
    // Valid phone numbers typically have 10-15 digits (E.164 standard)
    // Minimum 10 digits for international numbers with country code
    return digitsOnly.length >= 10 && digitsOnly.length <= 15;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = customer['phone'] as String?;
    final username = customer['username'] as String?;

    if (phone == null && username == null) {
      return PremiumCard(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'ظ„ط§ طھظˆط¬ط¯ ظ…ط¹ظ„ظˆظ…ط§طھ ط§طھطµط§ظ„',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.hintColor,
              ),
            ),
          ),
        ),
      );
    }

    return PremiumCard(
      child: Column(
        children: [
          if (username != null)
            _buildPremiumContactRow(
              context,
              theme,
              icon: SolarLinearIcons.userId,
              iconColor: AppColors.primary,
              value: username,
              label: 'ظ…ظڈط¹ط±ظ‘ظگظپ ط§ظ„ظ…ظڈط¯ظٹط±',
              onTap: () =>
                  _copyToClipboard(context, username, 'ظ…ظڈط¹ط±ظ‘ظگظپ ط§ظ„ظ…ظڈط¯ظٹط±'),
              onCopy: () =>
                  _copyToClipboard(context, username, 'ظ…ظڈط¹ط±ظ‘ظگظپ ط§ظ„ظ…ظڈط¯ظٹط±'),
            ),
          if (username != null && phone != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Divider(
                color: theme.dividerColor.withValues(alpha: 0.5),
                height: 1,
              ),
            ),
          if (phone != null)
            _buildPremiumContactRow(
              context,
              theme,
              icon: SolarLinearIcons.phone,
              iconColor: AppColors.success,
              value: phone,
              label: 'ط±ظ‚ظ… ط§ظ„ظ‡ط§طھظپ',
              onTap: () => _launchUri(context, 'tel:$phone'),
              onCopy: () => _copyToClipboard(context, phone, 'ط±ظ‚ظ… ط§ظ„ظ‡ط§طھظپ'),
            ),

          if (phone != null) ...[
            if (customer['has_whatsapp'] == true ||
                customer['has_whatsapp'] == 1 ||
                _isValidPhoneNumber(phone)) ...[
              const SizedBox(height: 8),
              Divider(
                color: theme.dividerColor.withValues(alpha: 0.5),
                height: 1,
              ),
              const SizedBox(height: 8),
              _buildActionRow(
                context,
                theme,
                label: 'ظ…ط±ط§ط³ظ„ط© ط¹ط¨ط± ظˆط§طھط³ط§ط¨',
                icon: SvgPicture.asset(
                  'assets/icons/whatsapp.svg',
                  width: 24,
                  height: 24,
                  colorFilter: const ColorFilter.mode(
                    Color(0xFF25D366),
                    BlendMode.srcIn,
                  ),
                ),
                color: const Color(0xFF25D366),
                onTap: () => _launchUri(
                  context,
                  'https://wa.me/${phone.replaceAll(RegExp(r'[^0-9]'), '')}',
                ),
                semanticsLabel: 'ظ…ط±ط§ط³ظ„ط© ط¹ط¨ط± ظˆط§طھط³ط§ط¨',
              ),
            ],
            if (customer['has_telegram'] == true ||
                customer['has_telegram'] == 1 ||
                _isValidPhoneNumber(phone)) ...[
              if (customer['has_whatsapp'] != true &&
                  customer['has_whatsapp'] != 1 &&
                  !_isValidPhoneNumber(phone)) ...[
                const SizedBox(height: 8),
                Divider(
                  color: theme.dividerColor.withValues(alpha: 0.5),
                  height: 1,
                ),
                const SizedBox(height: 8),
              ],
              _buildActionRow(
                context,
                theme,
                label: 'ظ…ط±ط§ط³ظ„ط© ط¹ط¨ط± طھظٹظ„ظٹط¬ط±ط§ظ…',
                icon: const Icon(
                  SolarLinearIcons.plain,
                  color: Color(0xFF0088CC),
                  size: 24,
                ),
                color: const Color(0xFF0088CC),
                onTap: () {
                  _launchUri(
                    context,
                    'https://t.me/+${phone.replaceAll(RegExp(r'[^0-9]'), '')}',
                  );
                },
                semanticsLabel: 'ظ…ط±ط§ط³ظ„ط© ط¹ط¨ط± طھظٹظ„ظٹط¬ط±ط§ظ…',
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildPremiumContactRow(
    BuildContext context,
    ThemeData theme, {
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
    required VoidCallback onTap,
    required VoidCallback onCopy,
  }) {
    return InkWell(
      onTap: () {
        Haptics.lightTap();
        onTap();
      },
      onLongPress: () {
        Haptics.mediumTap();
        onCopy();
      },
      borderRadius: BorderRadius.circular(12),
      focusColor: AppColors.primary.withValues(alpha: 0.12),
      hoverColor: AppColors.primary.withValues(alpha: 0.04),
      highlightColor: AppColors.primary.withValues(alpha: 0.08),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    iconColor.withValues(alpha: 0.15),
                    iconColor.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 24, color: iconColor),
            ),
            const SizedBox(width: AppDimensions.spacing12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Semantics(
              label: 'ظ†ط³ط®',
              button: true,
              child: SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                  icon: Icon(
                    SolarLinearIcons.copy,
                    size: 24,
                    color: theme.hintColor,
                  ),
                  onPressed: onCopy,
                  tooltip: 'ظ†ط³ط®',
                  padding: const EdgeInsets.all(12),
                  style: IconButton.styleFrom(
                    focusColor: AppColors.primary.withValues(alpha: 0.12),
                    hoverColor: AppColors.primary.withValues(alpha: 0.04),
                    highlightColor: AppColors.primary.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchUri(BuildContext context, String uriString) async {
    if (!context.mounted) return;

    try {
      await AppLauncher.launchSafeUrl(context, uriString);
    } catch (e) {
      debugPrint('Error launching URL: $e');
      if (!context.mounted) return;
      AnimatedToast.error(context, 'ظپط´ظ„ ظپطھط­ ط§ظ„ط±ط§ط¨ط·');
    }
  }

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    Haptics.lightTap();
    AnimatedToast.success(context, 'طھظ… ظ†ط³ط® $label');
  }

  Widget _buildActionRow(
    BuildContext context,
    ThemeData theme, {
    required String label,
    required Widget icon,
    required Color color,
    required VoidCallback onTap,
    String? semanticsLabel,
  }) {
    return Semantics(
      label: semanticsLabel ?? label,
      button: true,
      child: InkWell(
        onTap: () {
          Haptics.mediumTap();
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        focusColor: color.withValues(alpha: 0.12),
        hoverColor: color.withValues(alpha: 0.04),
        highlightColor: color.withValues(alpha: 0.08),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: icon,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: color.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
