import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import '../../../core/constants/colors.dart';
import '../../../core/extensions/string_extension.dart';
import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';

/// Reply preview widget shown above input when replying
class ReplyPreview extends StatelessWidget {
  final String senderName;
  final String messageBody;
  final bool isOutgoing; // Added to distinguish user's own messages
  final List<Map<String, dynamic>>?
  attachments; // Added to show media thumbnails
  final VoidCallback onCancel;

  const ReplyPreview({
    super.key,
    required this.senderName,
    required this.messageBody,
    required this.isOutgoing,
    this.attachments,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final Widget? thumbnailWidget = _buildThumbnail(theme, isDark);
    
    // Get caption from first attachment with caption
    final caption = attachments?.firstWhere(
      (a) => a['caption'] != null && a['caption'].toString().isNotEmpty,
      orElse: () => {},
    )['caption'] as String?;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: ShapeDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        shape: SmoothRectangleBorder(
          borderRadius: const SmoothBorderRadius.vertical(
            top: SmoothRadius(cornerRadius: 16, cornerSmoothing: 1.0),
          ),
          side: BorderSide(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isOutgoing ? 'أنت' : senderName.safeUtf16,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                // Show caption if available, otherwise show message body
                Text(
                  (caption ?? messageBody).safeUtf16,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.2),
                ),
              ],
            ),
          ),
          if (thumbnailWidget != null) ...[
            const SizedBox(width: 8),
            thumbnailWidget,
            const SizedBox(width: 8),
          ],
          Semantics(
            label: 'إلغاء الرَّد',
            button: true,
            child: SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  onCancel();
                },
                icon: const Icon(SolarLinearIcons.closeCircle),
                padding: const EdgeInsets.all(12),
                iconSize: 20,
                color: theme.hintColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildThumbnail(ThemeData theme, bool isDark) {
    if (attachments == null || attachments!.isEmpty) return null;

    final att = attachments!.firstWhere(
      (a) =>
          _isImageType(a['type'], a['mime_type']) ||
          _isVideoType(a['type'], a['mime_type']),
      orElse: () => {},
    );

    if (att.isEmpty) return null;

    final url = (att['url'] as String?)?.toFullUrl;
    final data = att['data'] as String? ?? att['base64'] as String?;
    final localPath = att['path'] as String?;

    ImageProvider? imageProvider;
    if (data != null) {
      imageProvider = MemoryImage(base64Decode(data));
    } else if (localPath != null) {
      imageProvider = FileImage(File(localPath));
    } else if (url != null) {
      imageProvider = CachedNetworkImageProvider(url);
    }

    if (imageProvider == null) return null;

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black12,
        borderRadius: BorderRadius.circular(8),
        image: DecorationImage(image: imageProvider, fit: BoxFit.cover),
      ),
      child: _isVideoType(att['type'], att['mime_type'])
          ? const Center(
              child: Icon(
                SolarBoldIcons.playCircle,
                color: Colors.white,
                size: 24,
              ),
            )
          : null,
    );
  }

  bool _isImageType(String? type, String? mime) {
    if (type == 'image' || type == 'sticker') return true;
    if (mime != null && mime.startsWith('image/')) return true;
    return false;
  }

  bool _isVideoType(String? type, String? mime) {
    if (type == 'video') return true;
    if (mime != null && mime.startsWith('video/')) return true;
    return false;
  }
}
