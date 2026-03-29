import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:intl/intl.dart';

import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/features/tasks/data/models/task_comment_model.dart';
import 'package:almudeer_mobile_app/core/extensions/string_extension.dart';

/// Comment bubble widget styled like conversation message bubbles
class CommentBubble extends StatelessWidget {
  final TaskCommentModel comment;
  final bool isOutgoing;
  final CommentGroupPosition position;

  const CommentBubble({
    super.key,
    required this.comment,
    required this.isOutgoing,
    this.position = CommentGroupPosition.single,
  });

  SmoothBorderRadius _getBorderRadius(bool isOutgoing) {
    return SmoothBorderRadius.only(
      topLeft: SmoothRadius(
        cornerRadius:
            !isOutgoing &&
                (position == CommentGroupPosition.middle ||
                    position == CommentGroupPosition.bottom)
            ? 6
            : 20,
        cornerSmoothing: 1.0,
      ),
      topRight: SmoothRadius(
        cornerRadius:
            isOutgoing &&
                (position == CommentGroupPosition.middle ||
                    position == CommentGroupPosition.bottom)
            ? 6
            : 20,
        cornerSmoothing: 1.0,
      ),
      bottomRight: SmoothRadius(
        cornerRadius: isOutgoing
            ? (position == CommentGroupPosition.top ||
                      position == CommentGroupPosition.middle
                  ? 20
                  : 4)
            : 20,
        cornerSmoothing: 1.0,
      ),
      bottomLeft: SmoothRadius(
        cornerRadius: !isOutgoing
            ? (position == CommentGroupPosition.top ||
                      position == CommentGroupPosition.middle
                  ? 20
                  : 4)
            : 20,
        cornerSmoothing: 1.0,
      ),
    );
  }

  bool _isImageType(String? type, String? mime) {
    return type == 'image' ||
        type == 'photo' ||
        mime?.startsWith('image/') == true;
  }

  String _formatTime(DateTime dateTime) {
    return DateFormat('HH:mm', 'ar_AE').format(dateTime).toEnglishNumbers;
  }

  String _formatDate(DateTime dateTime) {
    final now = DateTime.now();
    final isToday = dateTime.year == now.year &&
        dateTime.month == now.month &&
        dateTime.day == now.day;

    if (isToday) {
      return _formatTime(dateTime);
    }

    final isYesterday = dateTime.year == now.year &&
        dateTime.month == now.month &&
        dateTime.day == now.day - 1;

    if (isYesterday) {
      return 'ط£ظ…ط³';
    }

    return DateFormat('MM/dd/yyyy').format(dateTime).toEnglishNumbers;
  }

  Widget _buildImageAttachment(
    BuildContext context,
    Map<String, dynamic> att,
    ThemeData theme,
    bool isOutgoing,
  ) {
    final url = att['url'] as String?;
    final data = att['data'] as String? ?? att['base64'] as String?;
    final localPath = att['path'] as String?;

    if (data == null && url == null && localPath == null) {
      return const SizedBox.shrink();
    }

    final imageBytes = data != null ? base64Decode(data) : null;

    ImageProvider? imageProvider;
    if (imageBytes != null) {
      imageProvider = MemoryImage(imageBytes);
    } else if (localPath != null) {
      imageProvider = FileImage(File(localPath));
    } else if (url != null) {
      imageProvider = CachedNetworkImageProvider(url);
    }

    if (imageProvider == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOutgoing
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.black.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image(
          image: imageProvider,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Center(
                child: Icon(
                  SolarLinearIcons.gallery,
                  color: theme.hintColor,
                  size: 32,
                ),
              ),
            );
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isOutgoing ? Colors.white : AppColors.primary,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Check if text direction is RTL (Arabic/Hebrew) - TextDirection.rtl has index 1
    final direction = Directionality.of(context);
    final isRtl = direction.index == 1;  // TextDirection.rtl.index == 1

    return Padding(
      padding: EdgeInsets.only(
        top: position == CommentGroupPosition.top ||
                position == CommentGroupPosition.middle
            ? 2
            : 6,
        bottom: position == CommentGroupPosition.bottom ||
                position == CommentGroupPosition.middle
            ? 2
            : 6,
      ),
      child: Row(
        mainAxisAlignment: isOutgoing
            ? (isRtl ? MainAxisAlignment.start : MainAxisAlignment.end)
            : (isRtl ? MainAxisAlignment.end : MainAxisAlignment.start),
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isOutgoing != isRtl) const SizedBox(width: 50),
          Flexible(
            child: Container(
              decoration: ShapeDecoration(
                shape: SmoothRectangleBorder(
                  borderRadius: _getBorderRadius(isOutgoing),
                ),
                shadows: [
                  if (!isDark)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                ],
              ),
              child: ClipRRect(
                borderRadius: _getBorderRadius(isOutgoing),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: ShapeDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isOutgoing
                          ? [
                              AppColors.primary,
                              AppColors.primary.withValues(alpha: 0.85),
                            ]
                          : [
                              isDark
                                  ? Colors.white.withValues(alpha: 0.12)
                                  : Colors.white.withValues(alpha: 0.7),
                              isDark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : Colors.white.withValues(alpha: 0.4),
                            ],
                    ),
                    shape: SmoothRectangleBorder(
                      borderRadius: _getBorderRadius(isOutgoing),
                      side: BorderSide(
                        color: isOutgoing
                            ? Colors.white.withValues(alpha: 0.1)
                            : (isDark ? Colors.white : Colors.black)
                                  .withValues(alpha: 0.05),
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // User name for incoming comments
                      if (!isOutgoing && comment.userName != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            comment.userName!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),

                      // Attachments
                      if (comment.attachments.isNotEmpty) ...[
                        ...comment.attachments
                            .where((a) => _isImageType(
                                  a['type'] as String?,
                                  a['mime_type'] as String?,
                                ))
                            .map((att) => _buildImageAttachment(
                                  context,
                                  att,
                                  theme,
                                  isOutgoing,
                                )),
                      ],

                      // Comment content
                      if (comment.content.isNotEmpty)
                        Text(
                          comment.content.safeUtf16,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 15,
                            height: 1.5,
                            letterSpacing: 0.2,
                            color: isOutgoing
                                ? Colors.white
                                : theme.textTheme.bodyMedium?.color,
                          ),
                        ),

                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatDate(comment.createdAt),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isOutgoing
                                  ? Colors.white.withValues(alpha: 0.7)
                                  : theme.hintColor,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isOutgoing == isRtl) const SizedBox(width: 50),
        ],
      ),
    );
  }
}

/// Position of a comment within a group (for border radius adjustments)
enum CommentGroupPosition {
  single,
  top,
  middle,
  bottom,
}
