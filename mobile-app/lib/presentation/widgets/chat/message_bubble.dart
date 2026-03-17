import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:intl/intl.dart';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/colors.dart';
import '../../../data/models/inbox_message.dart';
import '../../providers/conversation_detail_provider.dart';
import '../../screens/inbox/image_viewer_screen.dart';
import '../../utils/chat_grouping_helper.dart';
import '../../screens/customers/customer_detail_screen.dart';
import 'audio_file_bubble.dart';
import 'file_message_bubble.dart';
import 'video_message_bubble.dart';
import 'voice_message_bubble.dart';
import 'note_bubble.dart';
import 'task_bubble.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/extensions/string_extension.dart';
import '../../../core/services/media_cache_manager.dart';
import 'mention_text.dart';
import 'caption_text.dart';

/// Premium message bubble with glassmorphism and RTL-correct alignment
class MessageBubble extends StatefulWidget {
  final InboxMessage message;
  final Color channelColor;
  final MessageGroupPosition position;
  final Function(int?, String?)? onReplyTap;
  final bool isHighlighted;

  const MessageBubble({
    super.key,
    required this.message,
    required this.channelColor,
    this.position = MessageGroupPosition.single,
    this.onReplyTap,
    required this.displayName,
    this.isHighlighted = false,
  });

  final String displayName;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  final GlobalKey _bubbleKey = GlobalKey();

  // Drag-to-select state
  bool _isDragSelecting = false;
  bool _isInDragSelectMode = false;

  SmoothBorderRadius _getBorderRadius(bool isOutgoing) {
    return SmoothBorderRadius.only(
      topLeft: SmoothRadius(
        cornerRadius:
            !isOutgoing &&
                (widget.position == MessageGroupPosition.middle ||
                    widget.position == MessageGroupPosition.bottom)
            ? 6
            : 20,
        cornerSmoothing: 1.0,
      ),
      topRight: SmoothRadius(
        cornerRadius:
            isOutgoing &&
                (widget.position == MessageGroupPosition.middle ||
                    widget.position == MessageGroupPosition.bottom)
            ? 6
            : 20,
        cornerSmoothing: 1.0,
      ),
      bottomRight: SmoothRadius(
        cornerRadius: isOutgoing
            ? (widget.position == MessageGroupPosition.top ||
                      widget.position == MessageGroupPosition.middle
                  ? 20
                  : 4)
            : 20,
        cornerSmoothing: 1.0,
      ),
      bottomLeft: SmoothRadius(
        cornerRadius: !isOutgoing
            ? (widget.position == MessageGroupPosition.top ||
                      widget.position == MessageGroupPosition.middle
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

  bool _isVideoType(String? type, String? mime) {
    return type == 'video' || mime?.startsWith('video/') == true;
  }

  bool _isVoiceType(String? type, String? mime) {
    return type == 'voice' ||
        (type != 'audio' && mime?.startsWith('audio/') == true);
  }

  bool _isNoteType(Map<String, dynamic> a) {
    final type = a['type']?.toString().toLowerCase();
    return type == 'note' || type == 'shared_note';
  }

  bool _isTaskType(Map<String, dynamic> a) {
    final type = a['type']?.toString().toLowerCase();
    return type == 'task' || type == 'shared_task';
  }

  bool _isOtherFileType(Map<String, dynamic> a) {
    final type = a['type'] as String?;
    final mime = a['mime_type'] as String?;
    if (_isImageType(type, mime)) return false;
    if (_isVideoType(type, mime)) return false;
    if (_isVoiceType(type, mime)) return false;
    if (type == 'audio') return false;
    if (_isNoteType(a)) return false;
    if (_isTaskType(a)) return false;
    return true;
  }

  Widget _buildReplyContext(ThemeData theme) {
    String senderName = widget.message.replyToSenderName?.safeUtf16 ?? '';

    // Standardize sender naming: ONLY 'أنا' should be 'أنت' (You)
    if (senderName == 'أنا') {
      senderName = 'أنت';
    }

    // Safety fallback for legacy data or missing name
    if (senderName.isEmpty) {
      if (widget.message.isOutgoing) {
        // You are replying -> most likely to the peer
        senderName = widget.displayName;
      } else {
        // Peer is replying -> most likely to you
        senderName = 'أنت';
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: () {
          if (widget.message.replyToId != null ||
              widget.message.replyToPlatformId != null) {
            Haptics.lightTap();
            widget.onReplyTap?.call(
              widget.message.replyToId,
              widget.message.replyToPlatformId,
            );
          }
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: ShapeDecoration(
            color: widget.message.isOutgoing
                ? Colors.black.withValues(
                    alpha: 0.15,
                  ) // Darker inset for primary colored bubbles
                : (theme.brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.05)),
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(
                cornerRadius: 8,
                cornerSmoothing: 1.0,
              ),
              side: BorderSide.none,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 3,
                height: 32,
                decoration: BoxDecoration(
                  color: widget.channelColor.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      senderName,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: widget.message.isOutgoing
                            ? Colors.white.withValues(alpha: 0.9)
                            : widget.channelColor,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (widget.message.replyToBody ??
                              widget.message.replyToBodyPreview ??
                              '')
                          .safeUtf16,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: widget.message.isOutgoing
                            ? Colors.white.withValues(alpha: 0.85)
                            : (theme.textTheme.bodySmall?.color ??
                                      (theme.brightness == Brightness.dark
                                          ? Colors.white70
                                          : Colors.black54))
                                  .withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOutgoing = widget.message.isOutgoing;
    final provider = context.read<ConversationDetailProvider>();
    final isRtl = Directionality.of(context) == ui.TextDirection.rtl;
    final isDark = theme.brightness == Brightness.dark;
    final isSelected = context.select<ConversationDetailProvider, bool>(
      (p) => p.isMessageSelected(widget.message.id),
    );
    final isSelectionMode = context.select<ConversationDetailProvider, bool>(
      (p) => p.isSelectionMode,
    );

    if (widget.message.isDeleted) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      key: _bubbleKey,
      behavior: HitTestBehavior.deferToChild,
      onTap: isSelectionMode
          ? () {
              provider.toggleMessageSelection(widget.message.id);
            }
          : null,
      onLongPressStart: (_) {
        // Instant selection on long-press - no delay, no reaction overlay
        Haptics.lightTap();
        provider.toggleMessageSelection(widget.message.id);
      },
      onPanStart: (_) {
        // Start drag selection
        _isDragSelecting = true;
        provider.toggleMessageSelection(widget.message.id);
      },
      onPanUpdate: (details) {
        // Handle drag selection
        if (!_isDragSelecting) return;

        // Use a small debounce to avoid too many rapid selections
        if (!_isInDragSelectMode) {
          _isInDragSelectMode = true;
          Future.delayed(const Duration(milliseconds: 100), () {
            _isInDragSelectMode = false;
          });
          provider.toggleMessageSelection(widget.message.id);
        }
      },
      onPanEnd: (_) {
        _isDragSelecting = false;
      },
      child: Container(
        color: widget.isHighlighted
            ? (isDark
                  ? AppColors.primary.withValues(
                      alpha: 0.2,
                    ) // More visible in dark mode
                  : AppColors.primary.withValues(alpha: 0.1))
            : (isSelected ? AppColors.primary.withValues(alpha: 0.1) : null),
        padding: EdgeInsets.only(
          top:
              widget.position == MessageGroupPosition.top ||
                  widget.position == MessageGroupPosition.middle
              ? 2
              : 6,
          bottom:
              widget.position == MessageGroupPosition.bottom ||
                  widget.position == MessageGroupPosition.middle
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
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
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
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(
                          sigmaX: isOutgoing
                              ? 0
                              : 4, // Reduced from 7 for better text readability
                          sigmaY: isOutgoing ? 0 : 4,
                        ),
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
                                          .withValues(
                                            alpha: 0.08,
                                          ), // Increased from 0.05 for better definition
                                width: widget.message.channel == 'saved'
                                    ? 1.5
                                    : 0.5,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Forwarded Indicator
                              if (widget.message.isForwarded)
                                _buildForwardedIndicator(theme, isOutgoing),

                              // Reply Context
                              if (widget.message.replyToBody != null ||
                                  widget.message.replyToBodyPreview != null)
                                _buildReplyContext(theme),

                              // Attachments
                              if (widget.message.attachments != null) ...[
                                ...widget.message.attachments!
                                    .where((a) {
                                      final res = _isImageType(
                                        a['type'],
                                        a['mime_type'],
                                      );
                                      return res;
                                    })
                                    .map(
                                      (att) =>
                                          _buildImageAttachment(context, att),
                                    ),
                                ...widget.message.attachments!
                                    .where(
                                      (a) => _isVideoType(
                                        a['type'],
                                        a['mime_type'],
                                      ),
                                    )
                                    .map(
                                      (att) => VideoMessageBubble(
                                        attachment: att,
                                        isOutgoing: isOutgoing,
                                        color: widget.channelColor,
                                      ),
                                    ),

                                ...widget.message.attachments!
                                    .where((a) => a['type'] == 'audio')
                                    .map(
                                      (att) => AudioFileBubble(
                                        attachment: att,
                                        isOutgoing: isOutgoing,
                                        color: widget.channelColor,
                                      ),
                                    ),

                                ...widget.message.attachments!
                                    .where((a) => _isNoteType(a))
                                    .map(
                                      (att) => NoteBubble(
                                        noteData: att,
                                        isOutgoing: isOutgoing,
                                        color: widget.channelColor,
                                      ),
                                    ),

                                ...widget.message.attachments!
                                    .where((a) => _isTaskType(a))
                                    .map(
                                      (att) => TaskBubble(
                                        taskData: att,
                                        isOutgoing: isOutgoing,
                                        color: widget.channelColor,
                                      ),
                                    ),
                              ],

                              if (widget.message.attachments?.any(
                                    (a) =>
                                        _isVoiceType(a['type'], a['mime_type']),
                                  ) ??
                                  false)
                                VoiceMessageBubble(
                                  message: widget.message,
                                  isOutgoing: isOutgoing,
                                  color: widget.channelColor,
                                ),

                              if (widget.message.attachments != null)
                                ...widget.message.attachments!
                                    .where((a) => _isOtherFileType(a))
                                    .map(
                                      (att) => FileMessageBubble(
                                        attachment: att,
                                        isOutgoing: isOutgoing,
                                        color: widget.channelColor,
                                      ),
                                    ),

                              if (widget.message.body.isNotEmpty)
                                MentionText(
                                  text: widget.message.body.safeUtf16,
                                  mentions: widget.message.mentions,
                                  textDirection: widget.message.body.direction,
                                  textAlign: widget.message.body.isArabic
                                      ? TextAlign.right
                                      : TextAlign.left,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontSize: 15,
                                    height: 1.5,
                                    letterSpacing: 0.2,
                                    color: isOutgoing
                                        ? Colors.white
                                        : theme.textTheme.bodyMedium?.color,
                                  ),
                                  mentionStyle: TextStyle(
                                    color: isOutgoing
                                        ? Colors.white.withValues(alpha: 0.9)
                                        : AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.underline,
                                    decorationColor: isOutgoing
                                        ? Colors.white.withValues(alpha: 0.9)
                                        : AppColors.primary,
                                  ),
                                  onMentionTap: (username) {
                                    // Navigate to customer detail screen
                                    _navigateToCustomerDetail(context, username);
                                  },
                                  onUrlTap: (url) async {
                                    // Open URL in browser
                                    final uri = Uri.parse(url);
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                                    }
                                  },
                                ),

                              const SizedBox(height: 6),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _formatTime(
                                      widget.message.effectiveTimestamp,
                                    ),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: isOutgoing
                                          ? Colors.white.withValues(alpha: 0.7)
                                          : theme.hintColor,
                                      fontSize: 11,
                                    ),
                                  ),
                                  // Edited indicator
                                  if (widget.message.isEdited) ...[
                                    const SizedBox(width: 4),
                                    Text(
                                      'مُعدّلة',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: isOutgoing
                                                ? Colors.white.withValues(
                                                    alpha: 0.5,
                                                  )
                                                : theme.hintColor,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                          ),
                                    ),
                                  ],
                                  // Pending sync indicator for edits
                                  if (widget.message.sendStatus == MessageSendStatus.sending) ...[
                                    const SizedBox(width: 4),
                                    SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          isOutgoing
                                              ? Colors.white.withValues(alpha: 0.7)
                                              : theme.colorScheme.secondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (isOutgoing) ...[
                                    const SizedBox(width: 6),
                                    _buildDeliveryStatus(theme, isOutgoing),
                                  ],
                                  // Reply indicator for messages with replies
                                  _buildReplyIndicator(theme, isOutgoing),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (isOutgoing == isRtl) const SizedBox(width: 50),
          ],
        ),
      ),
    );
  }

  bool _isImageCached = false;
  bool _isDownloadingImage = false;
  int _imageDownloadedBytes = 0;
  int _imageTotalBytes = 0;

  @override
  void initState() {
    super.initState();
    _checkImageCache();
  }

  Future<void> _checkImageCache() async {
    final atts = widget.message.attachments;
    if (atts == null || atts.isEmpty) return;

    final imageAtt = atts.firstWhere(
      (a) => _isImageType(a['type'], a['mime_type']),
      orElse: () => {},
    );

    if (imageAtt.isNotEmpty) {
      // 1. Check for local path (Optimistic/Local Send)
      if (imageAtt['path'] != null) {
        if (mounted) {
          setState(() {
            _isImageCached = true;
          });
        }
        return;
      }

      // 2. Check for URL cache
      final url = (imageAtt['url'] as String?)?.toFullUrl;
      if (url != null) {
        final cached = await MediaCacheManager().isImageCached(url);
        if (mounted) {
          setState(() {
            _isImageCached = cached;
          });
        }
      }
    }
  }

  Future<void> _downloadImage(String url) async {
    setState(() {
      _isDownloadingImage = true;
    });

    try {
      await MediaCacheManager().downloadFile(
        url,
        onProgressBytes: (received, total) {
          if (mounted) {
            setState(() {
              _imageDownloadedBytes = received;
              _imageTotalBytes = total;
            });
          }
        },
      );
      if (mounted) {
        setState(() {
          _isImageCached = true;
          _isDownloadingImage = false;
          _imageDownloadedBytes = 0;
          _imageTotalBytes = 0;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloadingImage = false;
          _imageDownloadedBytes = 0;
          _imageTotalBytes = 0;
        });
      }
    }
  }

  Widget _buildImageAttachment(BuildContext context, Map<String, dynamic> att) {
    final url = (att['url'] as String?)?.toFullUrl;
    final data = att['data'] as String? ?? att['base64'] as String?;
    final localPath = att['path'] as String?;
    final caption = att['caption'] as String?;

    if (data == null && url == null && localPath == null) {
      return const SizedBox.shrink();
    }

    final heroTag = 'image_${widget.message.id}_${att.hashCode}';
    final imageBytes = data != null ? base64Decode(data) : null;

    // Use imageBytes directly if available (local data)
    final bool isLocal =
        imageBytes != null || _isImageCached || localPath != null;

    // Image Provider Source: Bytes -> Local File -> Network
    ImageProvider? imageProvider;
    if (imageBytes != null) {
      imageProvider = MemoryImage(imageBytes);
    } else if (localPath != null) {
      imageProvider = FileImage(File(localPath));
    } else if (url != null) {
      imageProvider = CachedNetworkImageProvider(url);
    }

    if (!isLocal && url != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          onTap: _isDownloadingImage ? null : () => _downloadImage(url),
          child: Container(
            height: 150,
            width: 200,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    (widget.message.isOutgoing
                            ? Colors.white
                            : Theme.of(context).primaryColor)
                        .withValues(alpha: 0.2),
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_isDownloadingImage)
                  _buildImageDownloadProgress()
                else
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        SolarLinearIcons.download,
                        color: widget.message.isOutgoing
                            ? Colors.white.withValues(alpha: 0.7)
                            : Theme.of(context).primaryColor,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'عرض الصُّورة',
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.message.isOutgoing
                              ? Colors.white.withValues(alpha: 0.7)
                              : Theme.of(context).primaryColor,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ImageViewerScreen(
                    imageData: imageBytes,
                    imageUrl: url,
                    heroTag: heroTag,
                    caption: caption,
                  ),
                ),
              );
            },
            child: Hero(
              tag: heroTag,
              child: ClipRRect(
                borderRadius: caption != null && caption.isNotEmpty
                    ? const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                      )
                    : BorderRadius.circular(12),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: isLocal && imageProvider != null
                      ? Image(
                          image: imageProvider,
                          fit: BoxFit.cover,
                          frameBuilder:
                              (context, child, frame, wasSynchronouslyLoaded) {
                                if (wasSynchronouslyLoaded) return child;
                                return AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  child: frame == null
                                      ? Shimmer.fromColors(
                                          baseColor: Colors.grey[300]!,
                                          highlightColor: Colors.grey[100]!,
                                          child: Container(
                                            height: 150,
                                            width: 200,
                                            color: Colors.white,
                                          ),
                                        )
                                      : child,
                                );
                              },
                          errorBuilder: (_, error, stackTrace) =>
                              _buildImageError(context),
                        )
                      : (url != null
                            ? CachedNetworkImage(
                                imageUrl: url,
                                fit: BoxFit.cover,
                                memCacheHeight: 400, // Optimization
                                placeholder: (context, url) => Shimmer.fromColors(
                                  baseColor: Colors.grey[300]!,
                                  highlightColor: Colors.grey[100]!,
                                  child: Container(
                                    height: 150,
                                    width: 200,
                                    color: Colors.white,
                                  ),
                                ),
                                errorWidget: (_, url, error) =>
                                    _buildImageError(context),
                              )
                            : _buildImageError(context)),
                ),
              ),
            ),
          ),
          // Caption
          if (caption != null && caption.isNotEmpty)
            CaptionText(
              caption: caption,
              isOutgoing: widget.message.isOutgoing,
              theme: Theme.of(context),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImageDownloadProgress() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final percentage = _imageTotalBytes > 0
        ? (_imageDownloadedBytes / _imageTotalBytes * 100)
        : 0;
    final progress = _imageTotalBytes > 0
        ? (_imageDownloadedBytes / _imageTotalBytes)
        : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 3,
                  color: widget.message.isOutgoing
                      ? Colors.white
                      : AppColors.primary,
                  backgroundColor: isDark ? Colors.white24 : Colors.black12,
                ),
              ),
              Text(
                '${percentage.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: widget.message.isOutgoing
                      ? Colors.white
                      : AppColors.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_formatBytesSmall(_imageDownloadedBytes)}/${_formatBytesSmall(_imageTotalBytes)}',
          style: TextStyle(
            fontSize: 8,
            color: widget.message.isOutgoing
                ? Colors.white70
                : Theme.of(context).hintColor,
          ),
        ),
      ],
    );
  }

  Widget _buildImageError(BuildContext context) {
    return Container(
      height: 100,
      width: 150,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            SolarLinearIcons.dangerCircle,
            color: Colors.grey[500],
            size: 32,
          ),
          const SizedBox(height: 4),
          Text(
            'فشل التَّحميل',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryStatus(ThemeData theme, bool isOutgoing) {
    if (widget.message.sendStatus == MessageSendStatus.failed) {
      return Semantics(
        label: 'فشل الإرسال',
        child: const Icon(
          SolarLinearIcons.dangerCircle,
          size: 20,
          color: AppColors.error,
        ),
      );
    }

    // CRITICAL FIX: Define isOutgoing at the top to avoid reference errors
    final isOutgoing = widget.message.isOutgoing;
    final statusColor = isOutgoing
        ? Colors.white.withValues(alpha: 0.7)
        : theme.hintColor;

    // Show upload progress for messages with attachments
    if (widget.message.isUploading &&
        widget.message.attachments != null &&
        widget.message.attachments!.isNotEmpty) {
      final progress = widget.message.uploadProgress ?? 0.0;
      final percentage = (progress * 100).toStringAsFixed(0);
      final uploadedBytes = widget.message.uploadedBytes ?? 0;
      final totalBytes = widget.message.totalUploadBytes ?? 0;

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2,
                    color: isOutgoing ? Colors.white : AppColors.primary,
                    backgroundColor: isOutgoing
                        ? Colors.white24
                        : AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$percentage%',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: isOutgoing ? Colors.white : AppColors.primary,
            ),
          ),
          if (totalBytes > 0)
            Text(
              '${_formatBytesSmall(uploadedBytes)}/${_formatBytesSmall(totalBytes)}',
              style: TextStyle(
                fontSize: 7,
                color: isOutgoing ? Colors.white70 : theme.hintColor,
              ),
            ),
        ],
      );
    }

    if (widget.message.sendStatus == MessageSendStatus.sending) {
      return Semantics(
        label: 'جاري الإرسال',
        child: Icon(
          SolarLinearIcons.clockCircle,
          size: 16,
          color: statusColor.withValues(alpha: 0.5),
        ),
      );
    }

    // Almudeer channel: Show detailed delivery status (read/delivered/sent)
    final isAlmudeer = widget.message.channel.toLowerCase() == 'almudeer';
    // CRITICAL FIX: Normalize deliveryStatus and status for comparison
    final deliveryStatus =
        (widget.message.deliveryStatus ?? widget.message.status).toLowerCase();
    final mainStatus = widget.message.status.toLowerCase();

    if (isAlmudeer && isOutgoing) {
      // Almudeer-specific status indicators with double-check icons
      // Priority: read > delivered > sent > pending
      if (deliveryStatus == 'read') {
        // Read: SVG icon with lighter blue color
        return Semantics(
          label: 'مقروءة',
          child: SvgPicture.asset(
            'assets/icons/check-read.svg',
            width: 20,
            height: 20,
            colorFilter: ColorFilter.mode(
              Colors.white.withValues(alpha: 1),
              BlendMode.srcIn,
            ),
          ),
        );
      } else if (deliveryStatus == 'delivered') {
        // Delivered: SVG icon with light gray color for contrast on blue bubble
        return Semantics(
          label: 'تمَّ التسليم',
          child: SvgPicture.asset(
            'assets/icons/check-read.svg',
            width: 20,
            height: 20,
            colorFilter: ColorFilter.mode(
              Colors.white.withValues(alpha: 0.5),
              BlendMode.srcIn,
            ),
          ),
        );
      } else if (deliveryStatus == 'sent' ||
          mainStatus == 'sent' ||
          mainStatus == 'approved' ||
          mainStatus == 'auto_replied') {
        // Sent: Single check with white 50% opacity
        return Semantics(
          label: 'تمَّ الإرسال',
          child: Icon(
            SolarBoldIcons.check,
            size: 16,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        );
      } else {
        // Pending/Waiting: Clock with white 50% opacity
        return Semantics(
          label: 'قيد الانتظار',
          child: Icon(
            SolarLinearIcons.clockCircle,
            size: 16,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        );
      }
    } else if (isOutgoing) {
      // Non-Almudeer channels: Legacy behavior
      if (mainStatus == 'sent' ||
          mainStatus == 'approved' ||
          mainStatus == 'auto_replied' ||
          deliveryStatus == 'sent' ||
          deliveryStatus == 'delivered' ||
          deliveryStatus == 'read') {
        return Semantics(
          label: 'تمَّ الإرسال',
          child: Icon(SolarBoldIcons.checkCircle, size: 16, color: statusColor),
        );
      } else {
        return Semantics(
          label: 'قيد الانتظار',
          child: Icon(
            SolarLinearIcons.clockCircle,
            size: 16,
            color: statusColor,
          ),
        );
      }
    } else {
      // Incoming messages: No status indicator
      return const SizedBox.shrink();
    }
  }

  Widget _buildReplyIndicator(ThemeData theme, bool isOutgoing) {
    final replyCount = widget.message.replyCount;
    if (replyCount == 0) {
      return const SizedBox.shrink();
    }

    return Semantics(
      label: 'لديها $replyCount ردود',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 4),
          Icon(
            SolarLinearIcons.reply,
            size: 14,
            color: isOutgoing
                ? Colors.white.withValues(alpha: 0.7)
                : theme.hintColor.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 2),
          Text(
            '$replyCount',
            style: theme.textTheme.labelSmall?.copyWith(
              color: isOutgoing
                  ? Colors.white.withValues(alpha: 0.7)
                  : theme.hintColor.withValues(alpha: 0.7),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _formatBytesSmall(int bytes) {
    if (bytes <= 0) return '0B';
    const suffixes = ['B', 'K', 'M', 'G', 'T'];
    double dBytes = bytes.toDouble();
    int iSafety = 0;
    while (dBytes >= 1024 && iSafety < suffixes.length - 1) {
      dBytes /= 1024;
      iSafety++;
    }
    return '${dBytes.toStringAsFixed(iSafety == 0 ? 0 : 1)}${suffixes[iSafety]}';
  }

  String _formatTime(String dateStr) {
    try {
      var date = DateTime.parse(dateStr);
      if (!dateStr.endsWith('Z') && !dateStr.contains('+')) {
        date = DateTime.utc(
          date.year,
          date.month,
          date.day,
          date.hour,
          date.minute,
          date.second,
        );
      }
      return DateFormat.jm('ar_AE').format(date.toLocal()).toEnglishNumbers;
    } catch (e) {
      return '';
    }
  }

  /// Navigate to customer detail screen when a @username mention is tapped
  void _navigateToCustomerDetail(BuildContext context, String username) {
    Haptics.lightTap();
    // Navigate using the existing CustomerDetailScreen with username-based customer data
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CustomerDetailScreen(
          customer: {
            'username': username,
            'name': username,
            'is_almudeer_user': true,
            'is_online': false,
          },
        ),
      ),
    );
  }

  Widget _buildForwardedIndicator(ThemeData theme, bool isOutgoing) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            SolarLinearIcons.forward,
            size: 14,
            color: isOutgoing
                ? Colors.white.withValues(alpha: 0.7)
                : theme.hintColor.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 4),
          Text(
            'تمَّ مشاركتها',
            style: theme.textTheme.labelSmall?.copyWith(
              color: isOutgoing
                  ? Colors.white.withValues(alpha: 0.7)
                  : theme.hintColor.withValues(alpha: 0.7),
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
