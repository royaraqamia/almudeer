import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/colors.dart';
import '../../../core/extensions/channel_color_extension.dart';
import '../../../data/models/conversation.dart';
import '../../../data/models/inbox_message.dart';
import '../../providers/inbox_provider.dart';
import '../../providers/conversation_detail_provider.dart';
import '../../providers/message_input_provider.dart';
import '../../widgets/chat/chat_widgets.dart';
import '../../widgets/common_widgets.dart';

import 'widgets/message_list_view.dart';

/// Premium Conversation detail screen with message thread
class ConversationDetailScreen extends StatefulWidget {
  final Conversation conversation;

  const ConversationDetailScreen({super.key, required this.conversation});

  @override
  State<ConversationDetailScreen> createState() =>
      _ConversationDetailScreenState();
}

class _ConversationDetailScreenState extends State<ConversationDetailScreen> {
  late ConversationDetailProvider _detailProvider;

  // Scroll to message functionality

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.conversation.senderContact != null) {
        // Load from cache only - no API call for instant offline-first experience
        // Fresh data will be fetched only when user pulls to refresh
        _detailProvider.loadConversation(
          widget.conversation.senderContact!,
          senderName: widget.conversation.senderName, // Optimistic name
          channel: widget.conversation.channel,
          lastSeenAt: widget.conversation.lastSeenAt,
          isOnline: widget.conversation.isOnline,
          skipAutoRefresh: true,
        );
      }
    });
  }

  /// Handle pull-to-refresh
  Future<void> _handleRefresh() async {
    if (widget.conversation.senderContact != null) {
      await _detailProvider.loadConversation(
        widget.conversation.senderContact!,
        senderName: widget.conversation.senderName,
        channel: widget.conversation.channel,
        lastSeenAt: widget.conversation.lastSeenAt,
        isOnline: widget.conversation.isOnline,
        skipAutoRefresh: false,
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _detailProvider = context.read<ConversationDetailProvider>();
    // Set up error callback to show toasts when operations fail
    _detailProvider.onError = (String errorMessage) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    };
  }

  @override
  void dispose() {
    _detailProvider.clear();
    super.dispose();
  }

  void _handleReply(InboxMessage message) {
    _detailProvider.setReplyMessage(message);
  }

  void _cancelReply() {
    _detailProvider.cancelReply();
  }

  void _openSearch() {
    context.read<ConversationDetailProvider>().startSearching();
  }

  void _closeSearch() {
    context.read<ConversationDetailProvider>().stopSearching();
  }

  void _handleSearchQuery(String query) {
    context.read<ConversationDetailProvider>().updateSearchQuery(query);
  }

  void _nextSearchResult() {
    context.read<ConversationDetailProvider>().nextSearchResult();
  }

  void _previousSearchResult() {
    context.read<ConversationDetailProvider>().previousSearchResult();
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ThemeData theme,
    bool isDark,
  ) {
    final provider = context.watch<ConversationDetailProvider>();
    return ConversationAppBar(
      theme: theme,
      isDark: isDark,
      channelColor: widget.conversation.channel.channelColor,
      conversation: widget.conversation,
      onSearch: _openSearch,
      onCloseSearch: _closeSearch,
      onSearchQueryChanged: _handleSearchQuery,
      isSearching: provider.isSearching,
      searchQuery: provider.searchQuery,
      totalSearchResults: provider.totalSearchResults,
      currentSearchIndex: provider.currentSearchIndex,
      onNextResult: _nextSearchResult,
      onPreviousResult: _previousSearchResult,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        final provider = context.read<ConversationDetailProvider>();
        if (provider.replyToMessage != null) {
          provider.cancelReply();
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: _buildAppBar(context, theme, isDark),
        body: Selector<
              ConversationDetailProvider,
              List<InboxMessage>
            >(
              selector: (_, p) => List.unmodifiable(p.messages),
              builder: (context, messages, _) {
                final provider = context.watch<ConversationDetailProvider>();
                final activeContact = provider.senderContact;
                final isLoading = provider.isLoading;
                final replyTo = provider.replyToMessage;
                final searchResultId = provider.currentSearchResultId;
                
                final isMismatch =
                    activeContact != widget.conversation.senderContact;

                if (isMismatch || (isLoading && messages.isEmpty)) {
                  return _buildMessagesSkeleton(context);
                }

                return Stack(
                  children: [
                    Column(
                      children: [
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _handleRefresh,
                            color: AppColors.primary,
                            child: messages.isEmpty
                                ? EmptyConversationState(
                                    channel: widget.conversation.channel,
                                    channelColor:
                                        widget.conversation.channel.channelColor,
                                  )
                                : MessageListView(
                                    messages: messages,
                                    channelColor:
                                        widget.conversation.channel.channelColor,
                                    displayName: widget.conversation.displayName,
                                    onReply: _handleReply,
                                    highlightMessageId: searchResultId,
                                  ),
                          ),
                        ),

                        // Message Input Section
                        MessageInputSection(
                      replyToSender: replyTo != null
                          ? (replyTo.isOutgoing
                                ? 'أنت'
                                : widget.conversation.displayName)
                          : null,
                      replyToBody: replyTo?.body,
                      replyToPlatformId: replyTo?.channelMessageId,
                      replyToBodyPreview: replyTo?.body,
                      replyToAttachments: replyTo?.attachments,
                      onCancelReply: _cancelReply,
                      isReplyToOutgoing: replyTo?.isOutgoing ?? false,
                      onTypingChanged: (isTyping) {
                        context
                            .read<ConversationDetailProvider>()
                            .setTypingStatus(isTyping);
                      },
                      onSend:
                          (
                            text, {
                            mediaFiles,
                            metadata,
                            replyToPlatformId,
                            replyToBodyPreview,
                            customAttachments,
                          }) async {
                            final detailProvider = context
                                .read<ConversationDetailProvider>();
                            final inputProvider = context
                                .read<MessageInputProvider>();
                            String? replyToSenderName;
                            if (replyTo != null) {
                              if (replyTo.isOutgoing) {
                                replyToSenderName = 'أنت';
                              } else {
                                // Use displayName getter which handles fallbacks for senderName/Contact
                                replyToSenderName = replyTo.displayName;
                                if (replyToSenderName == 'مجهول' ||
                                    replyToSenderName.isEmpty) {
                                  replyToSenderName =
                                      widget.conversation.displayName;
                                }
                              }
                            }

                            final replyToPlatformId =
                                replyTo?.channelMessageId ??
                                replyTo?.platformMessageId;

                            final success = await inputProvider.sendMessage(
                              detailProvider,
                              text,
                              mediaFiles: mediaFiles,
                              metadata: metadata,
                              replyToMessageId: replyTo?.id,
                              replyToPlatformId: replyToPlatformId,
                              replyToBodyPreview: replyToBodyPreview,
                              replyToSenderName: replyToSenderName,
                              customAttachments: customAttachments,
                            );

                            if (success && context.mounted) {
                              // Instant update of Inbox List Snippet
                              context.read<InboxProvider>().updateLastMessage(
                                conversationId: widget.conversation.id,
                                body: text,
                                status: 'sent',
                                createdAt: DateTime.now(),
                              );
                            }

                            if (!mounted) return;
                            _cancelReply();
                          },
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMessagesSkeleton(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return PremiumSkeleton(
      child: ListView.builder(
        reverse: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        itemCount: 8,
        itemBuilder: (context, index) {
          final isOutgoing = index % 3 == 0;
          final width = 180.0 + (index % 4) * 30.0;
          final height = 50.0 + (index % 2) * 30.0;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: isOutgoing
                  ? (isRtl ? MainAxisAlignment.start : MainAxisAlignment.end)
                  : (isRtl ? MainAxisAlignment.end : MainAxisAlignment.start),
              children: [
                if (isOutgoing != isRtl) const SizedBox(width: 48),
                Container(
                  height: height,
                  width: width,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isOutgoing ? 20 : 4),
                      bottomRight: Radius.circular(isOutgoing ? 4 : 20),
                    ),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.02),
                    ),
                  ),
                ),
                if (isOutgoing == isRtl) const SizedBox(width: 48),
              ],
            ),
          );
        },
      ),
    );
  }
}
