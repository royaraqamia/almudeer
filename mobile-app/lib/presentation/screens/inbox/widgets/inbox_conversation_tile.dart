import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart' as intl;
import 'package:hijri/hijri_calendar.dart';
import 'package:provider/provider.dart';

import 'package:solar_icon_pack/solar_icon_pack.dart';
import '../../../../core/constants/animations.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/dimensions.dart';
import '../../../../core/widgets/app_avatar.dart';

import '../../../../data/models/conversation.dart';
import '../../../../core/extensions/string_extension.dart';
import '../../../providers/customers_provider.dart';

/// Premium conversation tile with glassmorphism and accessibility
///
/// Features:
/// - Long-press selection mode with haptic feedback
/// - Typing indicator with animated dots
/// - Channel-specific branding (WhatsApp, Telegram, Almudeer)
/// - Hijri calendar date formatting
/// - Full accessibility support (Semantics, 44px touch targets, focus indicators)
class InboxConversationTile extends StatefulWidget {
  final Conversation conversation;
  final VoidCallback onTap;
  final VoidCallback? onApprove;
  final bool isLast;
  final bool isSelectionMode;
  final bool isSelected;
  final ValueChanged<bool>? onSelectionChanged;
  final bool canSelectSavedMessages;
  final VoidCallback? onDelete;
  final VoidCallback? onArchive;
  final VoidCallback? onPin;
  final VoidCallback? onMarkUnread;
  final bool isTyping;
  final Function(int conversationId)? onDeleteWithUndo;
  final String? draftText;

  const InboxConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
    this.onApprove,
    this.onDelete,
    this.onArchive,
    this.onPin,
    this.onMarkUnread,
    this.isLast = false,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelectionChanged,
    this.canSelectSavedMessages = false,
    this.isTyping = false,
    this.onDeleteWithUndo,
    this.draftText,
  });

  @override
  State<InboxConversationTile> createState() => _InboxConversationTileState();
}

class _InboxConversationTileState extends State<InboxConversationTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppAnimations.fast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _controller, curve: AppAnimations.interactive),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _channelColor {
    switch (widget.conversation.channel.toLowerCase()) {
      case 'whatsapp':
        return AppColors.whatsappGreen;
      case 'telegram':
      case 'telegram_bot':
        return AppColors.telegramBlue;
      case 'almudeer':
      case 'saved':
        return AppColors.primary;
      default:
        return AppColors.primary;
    }
  }

  IconData get _channelIcon {
    switch (widget.conversation.channel.toLowerCase()) {
      case 'whatsapp':
        return SolarLinearIcons.chatRound;
      case 'telegram':
      case 'telegram_bot':
        return SolarLinearIcons.plain;
      case 'almudeer':
        return SolarBoldIcons.chatLine;
      case 'saved':
        return SolarLinearIcons.bookmark;
      default:
        return SolarLinearIcons.chatRoundDots;
    }
  }

  /// Check if message preview has attachments
  bool get _hasAttachments {
    final preview = widget.conversation.displayPreview;
    return preview.startsWith('📎') ||
        preview.startsWith('صورة') ||
        preview.startsWith('فيديو') ||
        preview.startsWith('ملف') ||
        preview.startsWith('صوتي');
  }

  /// Check if conversation has a draft
  bool get _hasDraft => widget.draftText != null &&
                        widget.draftText!.isNotEmpty &&
                        widget.conversation.senderContact != null &&
                        widget.conversation.senderContact != '__saved_messages__';

  /// Get the preview text to display (draft or regular message preview)
  String get _previewText {
    if (_hasDraft) {
      return widget.draftText!;
    }
    return widget.conversation.displayPreview;
  }

  /// Get the color for regular message preview text
  Color? _getPreviewColor(ThemeData theme, bool hasUnread) {
    if (widget.conversation.messageCount == 0) {
      return AppColors.primary;
    }
    if (hasUnread) {
      return theme.textTheme.bodyMedium?.color;
    }
    return theme.hintColor;
  }

  /// Build draft text with colored prefix
  Widget _buildDraftText(ThemeData theme, bool hasUnread) {
    final draftText = widget.draftText ?? '';
    final prefix = 'مسودَّة: ';
    final previewColor = _getPreviewColor(theme, hasUnread);
    final prefixColor = theme.hintColor.withValues(alpha: 0.7);

    // Always use RTL direction to keep the Arabic prefix "مسودَّة: " on the right
    // This ensures the prefix stays at the start for both English and Arabic drafts
    return RichText(
      text: TextSpan(
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.normal,
          height: 1.5,
        ),
        children: [
          TextSpan(
            text: prefix,
            style: TextStyle(
              color: prefixColor,
              fontWeight: FontWeight.normal,
              fontStyle: FontStyle.normal,
            ),
          ),
          TextSpan(
            text: draftText,
            style: TextStyle(
              color: previewColor,
              fontWeight: FontWeight.normal,
              fontStyle: FontStyle.normal,
            ),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      textDirection: TextDirection.rtl,
    );
  }

  /// Build typing indicator with animated dots
  Widget _buildTypingIndicator(ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTypingDot(theme, 0),
        const SizedBox(width: AppDimensions.spacing4),
        _buildTypingDot(theme, 1),
        const SizedBox(width: AppDimensions.spacing4),
        _buildTypingDot(theme, 2),
      ],
    );
  }

  Widget _buildTypingDot(ThemeData theme, int index) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 400),
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, index.isEven ? value * 3 : -value * 3),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: theme.hintColor.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUnread = widget.conversation.hasUnread;
    final isPinned = widget.conversation.isPinned;

    // Wrap with Semantics for accessibility
    return Semantics(
      label:
          '${widget.conversation.displayName}، ${widget.conversation.channelDisplayName}، ${widget.conversation.displayPreview}${hasUnread ? '، ${widget.conversation.unreadCount} رسائل غير مقروءة' : ''}${isPinned ? '، مثبتة' : ''}',
      button: true,
      child: _buildTileContent(context, theme),
    );
  }

  /// Build the actual tile content
  Widget _buildTileContent(BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final hasUnread = widget.conversation.hasUnread;
    final isSavedMessages =
        widget.conversation.senderContact == '__saved_messages__';
    final isPinned = widget.conversation.isPinned;

    return InkWell(
      onTap: () {
        if (widget.isSelectionMode) {
          if (isSavedMessages && !widget.canSelectSavedMessages) return;
          widget.onSelectionChanged?.call(!widget.isSelected);
        } else {
          widget.onTap();
        }
      },
      onLongPress: () {
        if (!widget.isSelectionMode) {
          if (isSavedMessages && !widget.canSelectSavedMessages) return;
          widget.onSelectionChanged?.call(true);
        }
      },
      onTapDown: (_) => !widget.isSelectionMode ? _controller.forward() : null,
      onTapUp: (_) => !widget.isSelectionMode ? _controller.reverse() : null,
      onTapCancel: () => !widget.isSelectionMode ? _controller.reverse() : null,
      // Focus indicators for keyboard accessibility
      focusColor: AppColors.primary.withValues(alpha: 0.12),
      hoverColor: AppColors.primary.withValues(alpha: 0.04),
      highlightColor: AppColors.primary.withValues(alpha: 0.08),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              color: widget.isSelected
                  ? AppColors.primary.withValues(alpha: 0.025)
                  : null,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimensions.paddingMedium,
                      vertical: AppDimensions.spacing12,
                    ),
                    // Minimum touch target height of 48dp for accessibility
                    constraints: const BoxConstraints(
                      minHeight: AppDimensions.touchTargetComfortable,
                    ),
                    decoration: BoxDecoration(
                      gradient: isSavedMessages
                          ? LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: isDark
                                  ? [
                                      AppColors.primary.withValues(alpha: 0.15),
                                      AppColors.primary.withValues(alpha: 0.05),
                                      Colors.transparent,
                                    ]
                                  : [
                                      AppColors.primary.withValues(alpha: 0.08),
                                      AppColors.primary.withValues(alpha: 0.03),
                                      Colors.transparent,
                                    ],
                            )
                          : null,
                      color: !isSavedMessages && hasUnread
                          ? (isDark
                                ? AppColors.primary.withValues(alpha: 0.05)
                                : AppColors.primary.withValues(alpha: 0.03))
                          : Colors.transparent,
                    ),
                    child: Row(
                      children: [
                        // Avatar with gradient ring for unread + channel icon
                        _buildAvatar(theme, hasUnread),
                        const SizedBox(width: AppDimensions.spacing12),
                        // Content
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  // Name with pin indicator
                                  Expanded(
                                    child: Consumer<CustomersProvider>(
                                      builder: (context, customersProvider, _) {
                                        final customer = customersProvider
                                            .getCustomerByContact(
                                              widget.conversation.senderContact,
                                            );
                                        final displayName =
                                            (customer != null &&
                                                customer.name != null &&
                                                customer.name!.isNotEmpty)
                                            ? customer.name!
                                            : widget.conversation.displayName;
                                        return Text(
                                          displayName,
                                          textDirection: displayName.direction,
                                          textAlign: TextAlign.right,
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: isSavedMessages
                                                    ? AppColors.primary
                                                    : null,
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        );
                                      },
                                    ),
                                  ),
                                  // Pin indicator
                                  if (isPinned) ...[
                                    const SizedBox(
                                      width: AppDimensions.spacing4,
                                    ),
                                    Icon(
                                      SolarBoldIcons.pin,
                                      size: AppDimensions.iconMedium,
                                      color: AppColors.primary.withValues(
                                        alpha: 0.7,
                                      ),
                                    ),
                                  ],
                                ],
                              ),

                              if (_previewText.isNotEmpty)
                                Row(
                                  children: [
                                    // Attachment indicator (only for non-draft messages)
                                    if (_hasAttachments &&
                                        !widget.isTyping &&
                                        !_hasDraft) ...[
                                      Icon(
                                        SolarLinearIcons.paperclip,
                                        size: AppDimensions.iconSmall,
                                        color: theme.hintColor.withValues(
                                          alpha: 0.7,
                                        ),
                                      ),
                                      const SizedBox(
                                        width: AppDimensions.spacing4,
                                      ),
                                    ],
                                    // Draft indicator icon
                                    if (_hasDraft) ...[
                                      Icon(
                                        SolarLinearIcons.pen,
                                        size: AppDimensions.iconSmall,
                                        color: theme.hintColor.withValues(
                                          alpha: 0.7,
                                        ),
                                      ),
                                      const SizedBox(
                                        width: AppDimensions.spacing4,
                                      ),
                                    ],
                                    // Preview text or typing indicator
                                    Expanded(
                                      child: widget.isTyping
                                          ? _buildTypingIndicator(theme)
                                          : _hasDraft
                                              ? _buildDraftText(theme, hasUnread)
                                              : Text(
                                                  _previewText,
                                                  textDirection: _previewText.direction,
                                                  textAlign: TextAlign.right,
                                                  style: theme.textTheme.bodyMedium?.copyWith(
                                                    fontWeight: FontWeight.normal,
                                                    color: _getPreviewColor(theme, hasUnread),
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppDimensions.spacing8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (!isSavedMessages)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Delivery status indicator for Almudeer channel
                                  if (widget.conversation.channel
                                              .toLowerCase() ==
                                          'almudeer' &&
                                      widget.conversation.isOutgoing) ...[
                                    _buildDeliveryStatusIndicator(theme),
                                    const SizedBox(
                                      width: AppDimensions.spacing4,
                                    ),
                                  ],
                                  // Time
                                  Text(
                                    _formatTime(widget.conversation.createdAt),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: hasUnread
                                          ? _channelColor
                                          : (isDark
                                                ? AppColors.textSecondaryDark
                                                : AppColors.textSecondaryLight),
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            if (hasUnread) ...[
                              const SizedBox(height: AppDimensions.spacing6),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutBack,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: theme.scaffoldBackgroundColor,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFFEF4444,
                                      ).withValues(alpha: 0.4),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 20,
                                  minHeight: 20,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  widget.conversation.unreadCount > 99
                                      ? '99+'
                                      : '${widget.conversation.unreadCount}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    height: 1,
                                    letterSpacing: -0.3,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Separator line (hide for last item)
                  if (!widget.isLast)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimensions.paddingMedium,
                      ),
                      child: Divider(
                        height: 1,
                        thickness: 1,
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAvatar(ThemeData theme, bool hasUnread) {
    final isSavedMessages =
        widget.conversation.senderContact == '__saved_messages__';

    return AppAvatar(
      radius: 24, // 48x48px avatar
      imageUrl: widget.conversation.avatarUrl,
      overlay: (widget.isSelected || !isSavedMessages)
          ? Positioned(
              bottom: -6,
              left: -6,
              child: Semantics(
                label: widget.isSelected
                    ? 'محدد'
                    : widget.conversation.channelDisplayName,
                child: Container(
                  padding: EdgeInsets.all(
                    widget.isSelected
                        ? AppDimensions.spacing2
                        : AppDimensions.spacing4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor,
                    shape: BoxShape.circle,
                    border: widget.isSelected
                        ? null
                        : Border.all(
                            color: theme.scaffoldBackgroundColor,
                            width: 2,
                          ),
                  ),
                  child: widget.isSelected
                      ? const Icon(
                          SolarBoldIcons.checkCircle,
                          color: AppColors.success,
                          size: 24,
                        )
                      : widget.conversation.channel.toLowerCase() == 'almudeer'
                      ? Image.asset(
                          'assets/images/app_icon.png',
                          width: 16,
                          height: 16,
                        )
                      : Icon(_channelIcon, size: 16, color: _channelColor),
                ),
              ),
            )
          : null,
      child: isSavedMessages
          ? Icon(SolarLinearIcons.bookmark, color: _channelColor, size: 24)
          : null,
    );
  }

  /// Build delivery status indicator for Almudeer channel
  Widget _buildDeliveryStatusIndicator(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    // Use deliveryStatus field if available, otherwise fall back to status
    final deliveryStatus = widget.conversation.deliveryStatus?.toLowerCase();
    final status = widget.conversation.status.toLowerCase();

    Color color;
    String label;

    // Prioritize deliveryStatus for Almudeer channel
    if (deliveryStatus == 'read') {
      // Read: SVG icon with vibrant blue color
      color = const Color(0xFF2196F3);
      label = 'مقروءة';
    } else if (deliveryStatus == 'delivered') {
      // Delivered: SVG icon with gray color
      color = isDark ? AppColors.textSecondaryDark : Colors.grey.shade500;
      label = 'تمَّ التسليم';
    } else if (deliveryStatus == 'sent' ||
        status == 'sent' ||
        status == 'approved' ||
        status == 'auto_replied') {
      // Sent: Single check with gray color
      return Semantics(
        label: 'تمَّ الإرسال',
        child: Icon(
          SolarBoldIcons.check,
          size: 20,
          color: isDark ? AppColors.textSecondaryDark : Colors.grey.shade500,
        ),
      );
    } else if (deliveryStatus == 'failed' || status == 'failed') {
      // Failed: Error icon
      return Semantics(
        label: 'فشل الإرسال',
        child: const Icon(
          SolarLinearIcons.dangerCircle,
          size: 20,
          color: AppColors.error,
        ),
      );
    } else {
      // Pending/Waiting: Clock
      return Semantics(
        label: 'قيد الانتظار',
        child: Icon(
          SolarLinearIcons.clockCircle,
          size: 20,
          color: isDark ? AppColors.textSecondaryDark : Colors.grey.shade500,
        ),
      );
    }

    return Semantics(
      label: label,
      child: SvgPicture.asset(
        'assets/icons/check-read.svg',
        width: 20,
        height: 20,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      ),
    );
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
      final localDate = date.toLocal();

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final msgDate = DateTime(localDate.year, localDate.month, localDate.day);

      if (msgDate == today) {
        return intl.DateFormat.jm('ar_AE').format(localDate).toEnglishNumbers;
      } else if (msgDate == today.subtract(const Duration(days: 1))) {
        return 'أمس';
      } else {
        HijriCalendar.setLocal(
          'en',
        ); // Use English to force Western numerals in dd/mm/yyyy
        final hijri = HijriCalendar.fromDate(localDate);
        return hijri.toFormat('dd/mm/yyyy').toEnglishNumbers;
      }
    } catch (e) {
      return '';
    }
  }
}
