import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/constants/dimensions.dart';
import '../../../../core/constants/animations.dart';
import '../../../../core/extensions/date_time_extension.dart';
import '../../../../core/extensions/string_extension.dart'; // Added this import
import 'package:almudeer_mobile_app/data/models/inbox_message.dart';
import '../../../providers/conversation_detail_provider.dart';
import '../../../utils/chat_grouping_helper.dart';
import '../../../widgets/chat/chat_widgets.dart';
import '../../../widgets/animated_toast.dart';
import '../../../widgets/custom_dialog.dart';
import '../../../../core/utils/haptics.dart';

// Forced update for test runner
class MessageListView extends StatefulWidget {
  final List<InboxMessage> messages;
  final Color channelColor;
  final String displayName;
  final Function(InboxMessage) onReply;
  final int? highlightMessageId;

  const MessageListView({
    super.key,
    required this.messages,
    required this.channelColor,
    required this.displayName,
    required this.onReply,
    this.highlightMessageId,
  });

  @override
  State<MessageListView> createState() => _MessageListViewState();
}

class _MessageListViewState extends State<MessageListView> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  List<ChatListItem> _cachedItems = [];
  final ValueNotifier<bool> _showScrollToBottom = ValueNotifier(false);
  int _unreadCount = 0;
  int? _flashingMessageId;

  @override
  void didUpdateWidget(MessageListView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // P1-4: Enhanced change detection to avoid unnecessary re-grouping
    // Most updates are status changes or typing indicators - don't re-group for those
    bool messagesStructureChanged = false;

    // Quick check: length change always requires re-grouping
    if (widget.messages.length != oldWidget.messages.length) {
      messagesStructureChanged = true;
    } else if (widget.messages.isNotEmpty && oldWidget.messages.isNotEmpty) {
      // Check if message order or content changed (not just status)
      // Compare first and last message IDs - if same, structure likely unchanged
      final firstIdMatch =
          widget.messages.first.id == oldWidget.messages.first.id;
      final lastIdMatch = widget.messages.last.id == oldWidget.messages.last.id;

      // If both ends match, check if any message was added/removed in middle
      // by comparing sum of IDs (quick heuristic)
      if (firstIdMatch && lastIdMatch) {
        final oldIdSum = oldWidget.messages
            .map((m) => m.id)
            .fold<int>(0, (a, b) => a + b);
        final newIdSum = widget.messages
            .map((m) => m.id)
            .fold<int>(0, (a, b) => a + b);
        if (oldIdSum != newIdSum) {
          messagesStructureChanged = true;
        } else {
          // P1-4: Additional check - only body/timestamp changes require re-grouping
          // Status changes (sending->sent) don't need re-grouping
          bool contentChanged = false;
          for (
            int i = 0;
            i < widget.messages.length && i < oldWidget.messages.length;
            i++
          ) {
            final oldMsg = oldWidget.messages[i];
            final newMsg = widget.messages[i];
            // Check if body, timestamp, or attachments changed (not just status)
            if (oldMsg.body != newMsg.body ||
                oldMsg.createdAt != newMsg.createdAt ||
                oldMsg.attachments?.length != newMsg.attachments?.length) {
              contentChanged = true;
              break;
            }
          }
          messagesStructureChanged = contentChanged;
        }
      } else {
        messagesStructureChanged = true;
      }
    } else if (widget.messages.isNotEmpty != oldWidget.messages.isNotEmpty) {
      messagesStructureChanged = true;
    }

    if (messagesStructureChanged) {
      // Re-calculate groupings only when message structure changes
      _cachedItems = ChatGroupingHelper.groupMessages(widget.messages);

      if (widget.messages.length > oldWidget.messages.length) {
        // Distinguish between NEW incoming messages vs. pagination loads.
        // In this reversed list, index 0 = newest message.
        // If the newest message hasn't changed, the growth is from loading
        // older messages at the end (pagination) – don't count those.
        final bool hasNewNewestMessage =
            oldWidget.messages.isEmpty ||
            widget.messages.isEmpty ||
            widget.messages.first.id != oldWidget.messages.first.id;

        if (hasNewNewestMessage) {
          // Genuinely new messages arrived at the front
          final positions = _itemPositionsListener.itemPositions.value;
          if (positions.isNotEmpty) {
            final min = positions
                .map((p) => p.index)
                .reduce((a, b) => a < b ? a : b);
            if (min > 1) {
              // Count only the truly new messages (difference at the front)
              int newCount = 0;
              for (int i = 0; i < widget.messages.length; i++) {
                if (oldWidget.messages.isNotEmpty &&
                    widget.messages[i].id == oldWidget.messages.first.id) {
                  break;
                }
                newCount++;
              }
              if (newCount > 0) {
                setState(() => _unreadCount += newCount);
              }
            }
          }
        }
      }
    }

    // Handle scroll request from parent or pending background loads
    if (widget.highlightMessageId != null &&
        widget.highlightMessageId != oldWidget.highlightMessageId) {
      _scrollToMessage(widget.highlightMessageId!, null);
    } else if (_pendingScrollId != null || _pendingScrollPlatformId != null) {
      // If we were waiting for messages to load, try scrolling again
      if (widget.messages.length > oldWidget.messages.length) {
        _scrollToMessage(_pendingScrollId, _pendingScrollPlatformId);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    // Initial grouping
    _cachedItems = ChatGroupingHelper.groupMessages(widget.messages);

    _itemPositionsListener.itemPositions.addListener(_onScroll);

    // Initial scroll if needed
    if (widget.highlightMessageId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToMessage(widget.highlightMessageId!, null); // Updated call
      });
    }
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(_onScroll);
    _showScrollToBottom.dispose();
    super.dispose();
  }

  void _onScroll() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    // Logic for reversed list:
    // Index 0 is the newest (bottom).
    // If index 0 is visible, we are at bottom.

    final minIndex = positions
        .map((p) => p.index)
        .reduce((a, b) => a < b ? a : b);
    final maxIndex = positions
        .map((p) => p.index)
        .reduce((a, b) => a > b ? a : b);

    // Show button if we are scrolled up (minIndex > 3)
    final show = minIndex > 3;
    if (show != _showScrollToBottom.value) {
      _showScrollToBottom.value = show;
    }

    // Reset unread count if we are close to bottom
    if (minIndex < 2 && _unreadCount > 0) {
      setState(() => _unreadCount = 0);
    }

    // Load more if at top (maxIndex is large)
    // We need to know total items.
    // Provider check.
    if (maxIndex >= widget.messages.length - 5) {
      final provider = context.read<ConversationDetailProvider>();
      if (provider.hasMore && !provider.isLoadingMore) {
        provider.loadMoreMessages();
      }
    }
  }

  void _scrollToBottom() {
    Haptics.selection();
    setState(() => _unreadCount = 0);
    _itemScrollController.scrollTo(
      index: 0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  int? _pendingScrollId;
  String? _pendingScrollPlatformId;
  int _scrollRetryCount = 0;
  static const int _maxScrollRetries = 3;

  void _scrollToMessage(int? messageId, String? platformId) {
    if (!mounted) return;

    final chatItems = _cachedItems;

    int targetIndex = -1;
    for (int i = 0; i < chatItems.length; i++) {
      final item = chatItems[i];
      if (item is MessageItem) {
        if (messageId != null && item.message.id == messageId) {
          targetIndex = i;
          break;
        }
        if (platformId != null &&
            (item.message.channelMessageId == platformId ||
                item.message.channelMessageId?.safeUtf16 == platformId)) {
          targetIndex = i;
          break;
        }
      }
    }

    if (targetIndex != -1) {
      // Clear pending scroll state on success
      _pendingScrollId = null;
      _pendingScrollPlatformId = null;
      _scrollRetryCount = 0;

      // Found it! Use scrollTo for smooth animation
      _itemScrollController.scrollTo(
        index: targetIndex,
        duration: AppAnimations.standard, // Apple standard: 350ms (was 600ms)
        curve: Curves.easeInOutCubic,
        alignment: 0.5, // Center the message
      );
      Haptics.heavyTap();

      if (messageId != null) {
        setState(() => _flashingMessageId = messageId);
        // Configurable duration based on screen size for better UX
        final highlightDuration = MediaQuery.of(context).size.height > 800
            ? const Duration(milliseconds: 2500)
            : const Duration(milliseconds: 1800);
        Future.delayed(highlightDuration, () {
          if (mounted && _flashingMessageId == messageId) {
            setState(() => _flashingMessageId = null);
          }
        });
      }
    } else {
      // Message not found in current list
      final provider = context.read<ConversationDetailProvider>();

      if (provider.hasMore && _scrollRetryCount < _maxScrollRetries) {
        // Load more and try again

        if (_scrollRetryCount == 0) {
          AnimatedToast.info(context, 'جاري البحث عن الرسالة...');
        }

        _pendingScrollId = messageId;
        _pendingScrollPlatformId = platformId;
        _scrollRetryCount++;

        provider.loadMoreMessages();
      } else if (provider.hasMore && _scrollRetryCount >= _maxScrollRetries) {
        // Show retry dialog after reaching retry limit
        _pendingScrollId = messageId;
        _pendingScrollPlatformId = platformId;
        _showRetryDialog(messageId, platformId);
        _scrollRetryCount = 0; // Reset for next attempt
      } else {
        // Truly not found or reached retry limit
        _pendingScrollId = null;
        _pendingScrollPlatformId = null;
        _scrollRetryCount = 0;
        AnimatedToast.info(context, 'الرسالة غير موجودة في القائمة الحالية');
      }
    }
  }

  /// Show retry dialog when message search fails after multiple attempts
  void _showRetryDialog(int? messageId, String? platformId) {
    if (!mounted) return;

    CustomDialog.show(
      context,
      title: 'الرسالة غير موجودة',
      message:
          'لم نتمكن من العثور على هذه الرسالة. هل تريد تحميل المزيد من الرسائل؟',
      type: DialogType.info,
      confirmText: 'تحميل المزيد',
      cancelText: 'إلغاء',
      onConfirm: () {
        // Retry loading more messages
        final provider = context.read<ConversationDetailProvider>();
        if (provider.hasMore) {
          provider.loadMoreMessages();
          // Will retry scroll after messages load in didUpdateWidget
        }
      },
      onCancel: () {
        _pendingScrollId = null;
        _pendingScrollPlatformId = null;
      },
    );
  }

  // _showMessageOptions removed

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detailProvider = context.watch<ConversationDetailProvider>();
    // Use cached items instead of recalculating
    final chatItems = _cachedItems;

    return Stack(
      children: [
        ScrollablePositionedList.builder(
          itemScrollController: _itemScrollController,
          itemPositionsListener: _itemPositionsListener,
          reverse: true,
          padding: const EdgeInsets.only(
            left: AppDimensions.paddingMedium,
            right: AppDimensions.paddingMedium,
            top: AppDimensions.paddingMedium,
            bottom: 80, // Space for input and typing indicator
          ),
          itemCount: chatItems.length + (detailProvider.hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            // 1. Loading More Spinner at the very end
            if (detailProvider.hasMore && index == chatItems.length) {
              return const Center(
                key: ValueKey('loading_more'),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }

            // If somehow index is out of bounds (safety check)
            if (index >= chatItems.length) return const SizedBox.shrink();

            final item = chatItems[index];

            if (item is DateHeaderItem) {
              return _buildDateHeader(
                item.date,
                theme,
                key: ValueKey('date_${item.date.millisecondsSinceEpoch}'),
              );
            }

            if (item is MessageItem) {
              final message = item.message;

              // Check if this is the first unread message
              final isFirstUnread =
                  _unreadCount > 0 &&
                  index == _unreadCount - 1 &&
                  !message.isOutgoing;

              return Column(
                children: [
                  // Unread message separator
                  if (isFirstUnread) _buildUnreadSeparator(theme),
                  SwipeableMessage(
                    key: ValueKey('swipe_${message.id}'),
                    messageId: message.id.toString(),
                    messageBody: message.body,
                    isOutgoing: message.isOutgoing,
                    onReply: () => widget.onReply(message),
                    child: MessageBubble(
                      key: ValueKey('bubble_${message.id}'),
                      message: message,
                      channelColor: widget.channelColor,
                      position: item.position,
                      onReplyTap: (id, pId) => _scrollToMessage(id, pId),
                      displayName: widget.displayName,
                      isHighlighted:
                          widget.highlightMessageId != null &&
                          message.id == widget.highlightMessageId,
                    ),
                  ),
                ],
              );
            }
            return const SizedBox.shrink();
          },
        ),

        // Typing/Recording Indicator
        if (detailProvider.isPeerTyping || detailProvider.isPeerRecording)
          Positioned(
            bottom: 8,
            right: Directionality.of(context) == TextDirection.rtl ? null : 16,
            left: Directionality.of(context) == TextDirection.rtl ? 16 : null,
            child: Semantics(
              label: detailProvider.isPeerTyping
                  ? '${widget.displayName} يكتب الآن'
                  : '${widget.displayName} يسجل الآن',
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: widget.channelColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: widget.channelColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      detailProvider.isPeerTyping
                          ? '${widget.displayName} يكتب الآن'
                          : '${widget.displayName} يسجل الآن',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: widget.channelColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    detailProvider.isPeerTyping
                        ? _buildTypingDots(widget.channelColor)
                        : _buildRecordingWave(widget.channelColor),
                  ],
                ),
              ),
            ),
          ),

        // Scroll to Bottom Button
        ValueListenableBuilder<bool>(
          valueListenable: _showScrollToBottom,
          builder: (context, show, _) {
            return show
                ? Positioned(
                    bottom: 16,
                    right: Directionality.of(context) == TextDirection.rtl
                        ? null
                        : 16,
                    left: Directionality.of(context) == TextDirection.rtl
                        ? 16
                        : null,
                    child: AnimatedScale(
                      scale: 1.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutBack,
                      child: _buildScrollToBottomButton(theme),
                    ),
                  )
                : const SizedBox.shrink();
          },
        ),
      ],
    );
  }

  Widget _buildScrollToBottomButton(ThemeData theme) {
    return ValueListenableBuilder<bool>(
      valueListenable: _showScrollToBottom,
      builder: (context, show, child) {
        if (!show) return const SizedBox.shrink();

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Semantics(
              label: 'انتقال إلى أحدث الرسائل',
              button: true,
              child: FloatingActionButton.small(
                heroTag: 'inbox_fab',
                onPressed: _scrollToBottom,
                backgroundColor: theme.colorScheme.primary,
                elevation: 4,
                child: const Icon(SolarLinearIcons.arrowDown, size: 20),
              ),
            ),
            if (_unreadCount > 0)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Center(
                    child: Text(
                      _unreadCount > 9 ? '9+' : '$_unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildUnreadSeparator(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              thickness: 1,
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    SolarLinearIcons.arrowDown,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'جديد',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Divider(
              thickness: 1,
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateHeader(DateTime date, ThemeData theme, {Key? key}) {
    final isDark = theme.brightness == Brightness.dark;
    return Center(
      key: key,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.8,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            date.toConversationHeaderString(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class TypingDot extends StatefulWidget {
  final Color color;
  final int delay;
  const TypingDot({super.key, required this.color, required this.delay});

  @override
  State<TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<TypingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppAnimations.standard, // Apple standard: 350ms (was 600ms)
    );

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) {
        _controller.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: widget.color.withValues(
              alpha: 0.3 + 0.7 * _controller.value,
            ),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

Widget _buildTypingDots(Color color) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      TypingDot(color: color, delay: 0),
      const SizedBox(width: 2),
      TypingDot(color: color, delay: 200),
      const SizedBox(width: 2),
      TypingDot(color: color, delay: 400),
    ],
  );
}

class RecordingBar extends StatefulWidget {
  final Color color;
  final int delay;
  const RecordingBar({super.key, required this.color, required this.delay});

  @override
  State<RecordingBar> createState() => _RecordingBarState();
}

class _RecordingBarState extends State<RecordingBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) {
        _controller.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 2,
          height: 4 + 8 * _controller.value,
          decoration: BoxDecoration(
            color: widget.color.withValues(
              alpha: 0.5 + 0.5 * _controller.value,
            ),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      },
    );
  }
}

Widget _buildRecordingWave(Color color) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      RecordingBar(color: color, delay: 0),
      const SizedBox(width: 2),
      RecordingBar(color: color, delay: 150),
      const SizedBox(width: 2),
      RecordingBar(color: color, delay: 300),
      const SizedBox(width: 2),
      RecordingBar(color: color, delay: 450),
    ],
  );
}
