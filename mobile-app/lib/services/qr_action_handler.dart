import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/utils/url_launcher_utils.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/app_config.dart';
import '../presentation/widgets/animated_toast.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

import '../presentation/widgets/premium_bottom_sheet.dart';
import 'qr_api_service.dart';

/// Callback type for saving scan history
typedef SaveScanHistoryCallback = Future<void> Function(String data, {String? type});

class QRActionHandler {
  /// Optional callback to save scan history (should be provided by provider)
  static SaveScanHistoryCallback? _onSaveHistory;

  /// Set the history save callback (call this from your provider initialization)
  static void setHistoryCallback(SaveScanHistoryCallback? callback) {
    _onSaveHistory = callback;
  }

  /// Clear the history callback (call this in dispose to prevent memory leaks)
  static void clearHistoryCallback() {
    _onSaveHistory = null;
  }

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
  static bool _isValidDeepLinkPath(String? path) {
    // Handle null or empty path
    if (path == null || path.isEmpty) {
      return false;
    }
    
    // Normalize path
    final normalizedPath = path.startsWith('/') ? path : '/$path';

    // Check against allowlist
    return _allowedDeepLinkPaths.contains(normalizedPath) ||
        _allowedDeepLinkPaths.any((allowed) => normalizedPath.startsWith('$allowed/'));
  }

  /// Handle QR code scan result
  static Future<void> handleResult(
    BuildContext context,
    String code, {
    SaveScanHistoryCallback? onSaveHistory,
  }) async {
    // Trim whitespace
    final trimmedCode = code.trim();

    if (trimmedCode.isEmpty) {
      if (context.mounted) {
        AnimatedToast.error(context, 'الرمز الممسوح فارغ');
      }
      return;
    }

    // Check if this looks like a backend QR code (64-char SHA256 hash)
    if (QrApiService.looksLikeBackendQr(trimmedCode)) {
      await _handleBackendQrCode(context, trimmedCode, onSaveHistory);
      return;
    }

    // Try to parse as URI
    final Uri? uri = Uri.tryParse(trimmedCode);

    // Determine type
    final bool isUrl = uri != null && _allowedSchemes.contains(uri.scheme);
    final bool isDeepLink = uri != null && uri.scheme == AppConfig.deepLinkScheme;
    String? scanType;

    if (isUrl) {
      scanType = 'url';
    } else if (isDeepLink) {
      scanType = 'deep_link';
    } else {
      scanType = 'text';
    }

    if (isUrl) {
      // Validate URL security
      if (!_isValidUrl(trimmedCode)) {
        if (!context.mounted) return;
        await _saveHistoryIfCallback(onSaveHistory, trimmedCode, type: scanType);
        if (context.mounted) {
          AnimatedToast.error(context, 'رابط غير صالح أو غير آمن');
        }
        return;
      }

      if (_isPotentiallyMalicious(trimmedCode)) {
        if (!context.mounted) return;
        await _saveHistoryIfCallback(onSaveHistory, trimmedCode, type: scanType);
        if (context.mounted) {
          AnimatedToast.error(context, 'هذا الرابط قد يكون ضاراً');
        }
        return;
      }

      if (context.mounted) {
        await _saveHistoryIfCallback(onSaveHistory, trimmedCode, type: scanType);
      }
      if (context.mounted) {
        await _handleUrl(context, trimmedCode);
      }
    } else if (isDeepLink) {
      // Validate deep link path (uri is guaranteed non-null here because isDeepLink checks it)
      if (!_isValidDeepLinkPath(uri.path)) {
        if (!context.mounted) return;
        await _saveHistoryIfCallback(onSaveHistory, trimmedCode, type: scanType);
        if (context.mounted) {
          AnimatedToast.error(context, 'رابط داخلي غير صالح');
        }
        return;
      }

      if (context.mounted) {
        await _saveHistoryIfCallback(onSaveHistory, trimmedCode, type: scanType);
      }
      if (context.mounted) {
        await _handleDeepLink(context, uri);
      }
    } else {
      // Handle as plain text
      if (context.mounted) {
        await _saveHistoryIfCallback(onSaveHistory, trimmedCode, type: scanType);
      }
      if (context.mounted) {
        await _handlePlainText(context, trimmedCode);
      }
    }
  }

  /// Handle backend QR code verification
  static Future<void> _handleBackendQrCode(
    BuildContext context,
    String codeHash,
    SaveScanHistoryCallback? onSaveHistory,
  ) async {
    // Show loading dialog
    if (!context.mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    try {
      // Verify with backend
      final result = await QrApiService().verifyQrCode(codeHash: codeHash);

      // Close loading dialog and check mounted before using context
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      // Save to history
      await _saveHistoryIfCallback(onSaveHistory, codeHash, type: 'qr_code');

      if (!context.mounted) return;

      if (result.isSuccess) {
        // Success - show QR code details
        _showQrVerificationSuccess(context, result);
      } else {
        // Failed verification
        AnimatedToast.error(context, result.errorMessage);
      }
    } catch (e) {
      // Close loading dialog
      if (context.mounted) {
        Navigator.of(context).pop();
      }
      if (context.mounted) {
        AnimatedToast.error(context, 'فشل التحقق من رمز QR');
      }
    }
  }

  /// Show QR verification success dialog
  static void _showQrVerificationSuccess(
    BuildContext context,
    QrVerificationResult result,
  ) {
    final qrCode = result.qrCode;
    final title = qrCode?['title'] as String? ?? 'رمز QR';
    final description = qrCode?['description'] as String? ?? '';
    final codeType = qrCode?['code_type'] as String? ?? 'custom';
    final useCount = result.useCount ?? 0;
    final maxUses = result.maxUses;

    PremiumBottomSheet.show(
      context: context,
      title: 'تم التحقق بنجاح',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // QR Code type badge
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      if (codeType.isNotEmpty)
                        Text(
                          codeType,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primary.withValues(alpha: 0.7),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Description if available
          if (description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                description,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ),

          // Usage info
          if (maxUses != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.repeat,
                    size: 20,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'الاستخدامات: $useCount / $maxUses',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 24),

          // Close button
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
  
  /// Internal helper to save history using callback
  static Future<void> _saveHistoryIfCallback(
    SaveScanHistoryCallback? callback,
    String data, {
    String? type,
  }) async {
    // Use provided callback first, then fall back to static callback
    final effectiveCallback = callback ?? _onSaveHistory;
    if (effectiveCallback != null) {
      try {
        await effectiveCallback(data, type: type);
      } catch (e) {
        // Silently fail - history save shouldn't block the main flow
        debugPrint('Failed to save scan history: $e');
      }
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
