import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/app_config.dart';
import '../widgets/animated_toast.dart';

/// QR Code Generator Widget with validation and accessibility
class QRGenerator extends StatelessWidget {
  final String data;
  final double size;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final String? semanticLabel;

  /// Maximum data length for QR codes (practical limit for good scannability)
  static const int maxDataLength = AppConfig.maxQrDataLength;

  QRGenerator({
    super.key,
    required this.data,
    this.size = 200,
    this.backgroundColor,
    this.foregroundColor,
    this.semanticLabel,
  }) {
    // Input validation with assertions for debug mode
    assert(data.isNotEmpty, 'QR code data cannot be empty');
    assert(
      data.length <= maxDataLength,
      'QR code data exceeds maximum length of $maxDataLength characters',
    );
    assert(size > 0 && size <= 1000, 'Size must be between 0 and 1000');
  }

  /// Check if data is valid for QR generation
  static bool isValidData(String data) {
    if (data.isEmpty) return false;
    if (data.length > maxDataLength) return false;
    return true;
  }

  /// Get appropriate error correction level based on data size
  /// Always use High (H) error correction for best durability and scannability
  static int _getErrorCorrectionLevel(String data) {
    // Use high error correction (30%) for all cases
    // This provides the best durability against damage and better scannability
    return QrErrorCorrectLevel.H;
  }

  @override
  Widget build(BuildContext context) {
    // Validate data before rendering
    if (!isValidData(data)) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.error_outline,
          color: Colors.red,
          size: 48,
        ),
      );
    }

    // Generate QR code with error handling
    try {
      return Semantics(
        label: semanticLabel ?? 'رمز QR يحتوي على: $data',
        image: true,
        child: RepaintBoundary(
          child: QrImageView(
            data: data,
            version: QrVersions.auto,
            size: size,
            backgroundColor: backgroundColor ?? Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: AppColors.primary,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: AppColors.primary,
            ),
            // Use high error correction for better scannability
            errorCorrectionLevel: _getErrorCorrectionLevel(data),
          ),
        ),
      );
    } catch (e) {
      // Handle QR generation errors (e.g., invalid characters)
      debugPrint('QR generation failed: $e');
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.amber,
              size: 32,
            ),
            SizedBox(height: 4),
            Text(
              'فشل إنشاء QR',
              style: TextStyle(
                color: Colors.amber,
                fontSize: 10,
              ),
            ),
          ],
        ),
      );
    }
  }
}

/// Bottom sheet for displaying and sharing QR codes
class QRGeneratorBottomSheet {
  /// Show QR code in a bottom sheet with share functionality
  static void show(
    BuildContext context, {
    required String title,
    required String data,
    double size = 200,
    String? subtitle,
    List<Widget>? extraActions,
  }) {
    // Validate data before showing
    if (!QRGenerator.isValidData(data)) {
      AnimatedToast.error(context, 'بيانات الرمز غير صالحة');
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _QRBottomSheetContent(
        title: title,
        data: data,
        size: size,
        subtitle: subtitle,
        extraActions: extraActions,
      ),
    );
  }
}

/// Internal widget for QR bottom sheet content
class _QRBottomSheetContent extends StatefulWidget {
  final String title;
  final String data;
  final double size;
  final String? subtitle;
  final List<Widget>? extraActions;

  const _QRBottomSheetContent({
    required this.title,
    required this.data,
    required this.size,
    this.subtitle,
    this.extraActions,
  });

  @override
  State<_QRBottomSheetContent> createState() => _QRBottomSheetContentState();
}

class _QRBottomSheetContentState extends State<_QRBottomSheetContent> {
  bool _isSharing = false;
  bool _showFullData = false;

  /// Share QR code using SharePlus
  Future<void> _shareQrCode() async {
    if (_isSharing) return;

    setState(() {
      _isSharing = true;
    });

    try {
      // Share as text using SharePlus
      await SharePlus.instance.share(
        ShareParams(
          text: widget.data,
          subject: widget.title,
        ),
      );
    } on PlatformException catch (e) {
      // Handle platform-specific sharing errors
      debugPrint('Share failed: ${e.code} - ${e.message}');
      if (mounted) {
        AnimatedToast.error(context, 'فشل المشاركة');
      }
    } catch (e) {
      debugPrint('Share failed: $e');
      if (mounted) {
        AnimatedToast.error(context, 'فشل المشاركة: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSharing = false;
        });
      }
    }
  }

  /// Copy data to clipboard
  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: widget.data));
    AnimatedToast.info(context, 'تم النسخ إلى الحافظة');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Title
          Text(
            widget.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),

          // Subtitle if provided
          if (widget.subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              widget.subtitle!,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).hintColor,
              ),
            ),
          ],

          const SizedBox(height: 24),

          // QR Code with white background for better contrast
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: QRGenerator(
              data: widget.data,
              size: widget.size,
              semanticLabel: '${widget.title}: رمز QR',
            ),
          ),

          const SizedBox(height: 16),

          // Data preview with expand option
          if (widget.data.length > 50)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  AnimatedCrossFade(
                    firstChild: Text(
                      widget.data,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).hintColor,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    secondChild: Container(
                      constraints: const BoxConstraints(maxHeight: 150),
                      child: SingleChildScrollView(
                        child: Text(
                          widget.data,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).hintColor,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    crossFadeState: _showFullData
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 200),
                  ),
                  if (widget.data.length > 100)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _showFullData = !_showFullData;
                        });
                      },
                      child: Text(
                        _showFullData ? 'إخفاء' : 'عرض البيانات الكاملة',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),

          const SizedBox(height: 24),

          // Action buttons
          Row(
            children: [
              // Copy button
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _copyToClipboard,
                  icon: const Icon(Icons.copy),
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

              // Share button
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isSharing ? null : _shareQrCode,
                  icon: _isSharing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.share),
                  label: Text(_isSharing ? 'جاري...' : 'مشاركة'),
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

          // Extra custom actions if provided
          if (widget.extraActions != null && widget.extraActions!.isNotEmpty)
            Column(
              children: widget.extraActions!,
            ),

          // Bottom padding for safe area
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}
