import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/utils/url_launcher_utils.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/app_config.dart';
import '../presentation/widgets/animated_toast.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

import '../presentation/widgets/premium_bottom_sheet.dart';

class QRActionHandler {
  /// Allowed URL schemes (allowlist approach for security)
  static const List<String> _allowedSchemes = ['http', 'https'];

  /// Allowed deep link paths to prevent unauthorized navigation
  static const List<String> _allowedDeepLinkPaths = [
    '/qr-scanner',
    '/login',
    '/settings',
    '/subscription',
    '/inbox',
    '/customers',
    '/tasks',
    '/library',
  ];

  /// Dangerous URL schemes that should never be allowed
  static const List<String> _blockedSchemes = [
    'javascript',
    'data',
    'blob',
    'file',
    'ftp',
    'ws',
    'wss',
    'vbscript',
    'intent',
  ];

  /// Additional malicious patterns to detect
  static const List<String> _maliciousPatterns = [
    'cryptocurrency',
    'wallet',
    'bitcoin',
    'eth:',
    '0x', // Ethereum address pattern
  ];

  /// Validate URL using allowlist approach
  static bool _isValidUrl(String url) {
    // Check length first
    if (url.length > AppConfig.maxQrUrlLength) {
      return false;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    // Use allowlist instead of blocklist for schemes
    if (!_allowedSchemes.contains(uri.scheme)) {
      return false;
    }

    // Check for blocked schemes embedded in URL
    final lowerUrl = url.toLowerCase();
    for (final blocked in _blockedSchemes) {
      if (lowerUrl.contains('$blocked:')) {
        return false;
      }
    }

    return true;
  }

  /// Check for potentially malicious content
  static bool _isPotentiallyMalicious(String url) {
    final lowerUrl = url.toLowerCase();

    // Check blocked schemes
    for (final scheme in _blockedSchemes) {
      if (lowerUrl.startsWith('$scheme:')) {
        return true;
      }
    }

    // Check malicious patterns
    for (final pattern in _maliciousPatterns) {
      if (lowerUrl.contains(pattern)) {
        return true;
      }
    }

    // Check for IDN homograph attacks (simplified check)
    if (url.contains('xn--')) {
      // Punycode detected - could be legitimate or malicious
      // For now, we allow it but could be blocked in high-security mode
    }

    return false;
  }

  /// Validate deep link path against allowlist
  static bool _isValidDeepLinkPath(String path) {
    // Normalize path
    final normalizedPath = path.startsWith('/') ? path : '/$path';

    // Check against allowlist
    return _allowedDeepLinkPaths.contains(normalizedPath) ||
        _allowedDeepLinkPaths.any((allowed) => normalizedPath.startsWith('$allowed/'));
  }

  /// Handle QR code scan result
  static Future<void> handleResult(BuildContext context, String code) async {
    // Trim whitespace
    final trimmedCode = code.trim();

    if (trimmedCode.isEmpty) {
      AnimatedToast.error(context, 'الرمز الممسوح فارغ');
      return;
    }

    // Try to parse as URI
    final Uri? uri = Uri.tryParse(trimmedCode);

    // Determine type
    final bool isUrl = uri != null && _allowedSchemes.contains(uri.scheme);
    final bool isDeepLink = uri != null && uri.scheme == AppConfig.deepLinkScheme;

    if (isUrl) {
      // Validate URL security
      if (!_isValidUrl(trimmedCode)) {
        AnimatedToast.error(context, 'رابط غير صالح أو غير آمن');
        return;
      }

      if (_isPotentiallyMalicious(trimmedCode)) {
        AnimatedToast.error(context, 'هذا الرابط قد يكون ضاراً');
        return;
      }

      await _handleUrl(context, trimmedCode);
    } else if (isDeepLink) {
      // Validate deep link path (uri is guaranteed non-null here because isDeepLink checks it)
      if (!_isValidDeepLinkPath(uri.path)) {
        AnimatedToast.error(context, 'رابط داخلي غير صالح');
        return;
      }

      await _handleDeepLink(context, uri);
    } else {
      // Handle as plain text
      await _handlePlainText(context, trimmedCode);
    }
  }

  /// Handle HTTP/HTTPS URLs
  static Future<void> _handleUrl(BuildContext context, String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return;

    PremiumBottomSheet.show(
      context: context,
      title: 'رابط خارجي',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // URL preview with better truncation
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.grey.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              url,
              style: const TextStyle(fontSize: 14, color: AppColors.primary),
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 24),
          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: url));
                    Navigator.pop(context);
                    AnimatedToast.success(context, 'تم نسخ الرابط');
                  },
                  icon: const Icon(SolarLinearIcons.copy),
                  label: const Text('نسخ'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await AppLauncher.launchSafeUrl(context, url);
                  },
                  icon: const Icon(SolarLinearIcons.linkRound),
                  label: const Text('فتح الرابط'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Handle app deep links with validated navigation
  static Future<void> _handleDeepLink(BuildContext context, Uri uri) async {
    // Get the destination description
    final String destinationDescription = uri.path.isNotEmpty
        ? uri.path
        : 'الصفحة الرئيسية';

    PremiumBottomSheet.show(
      context: context,
      title: 'رابط داخلي',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Show where user will be directed
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  SolarLinearIcons.mapArrowSquare,
                  color: AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'الوجهة',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        destinationDescription,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Navigate button with validation
          ElevatedButton.icon(
            onPressed: () {
              // Double-check path validation before navigation
              if (!_isValidDeepLinkPath(uri.path)) {
                Navigator.pop(context);
                AnimatedToast.error(context, 'الرابط غير صالح');
                return;
              }

              Navigator.pop(context);

              // Use pushNamed with error handling
              try {
                Navigator.of(context).pushNamed(uri.path);
              } catch (e) {
                if (context.mounted) {
                  AnimatedToast.error(context, 'فشل الانتقال للصفحة');
                }
              }
            },
            icon: const Icon(SolarLinearIcons.arrowRight),
            label: const Text('الانتقال'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          // Cancel button
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  /// Handle plain text QR codes
  static Future<void> _handlePlainText(BuildContext context, String text) async {
    // Determine if text looks like it might be a malformed URL
    final bool looksLikeUrl = text.startsWith('http') ||
        text.startsWith('www.') ||
        text.contains('://');

    PremiumBottomSheet.show(
      context: context,
      title: looksLikeUrl ? 'نص ممسوح (رابط غير صالح)' : 'نص ممسوح',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Warning if it looks like a malformed URL
          if (looksLikeUrl)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.amber.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.amber,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'يبدو أن هذا رابط غير صالح. تأكد من صحة الرمز.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (looksLikeUrl) const SizedBox(height: 16),
          // Text preview with scroll for long content
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.grey.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              child: Text(
                text,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Copy button
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(context);
              AnimatedToast.success(context, 'تم نسخ النص');
            },
            icon: const Icon(SolarLinearIcons.copy),
            label: const Text('نسخ'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
