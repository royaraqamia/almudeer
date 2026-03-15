import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/dimensions.dart';
import '../../../core/constants/animations.dart';
import '../../../core/utils/haptics.dart';
import '../../../data/models/conversation.dart';
import '../../providers/inbox_provider.dart';
import 'conversation_detail_screen.dart';

import 'widgets/inbox_conversation_tile.dart';
import 'package:hijri/hijri_calendar.dart';
import '../../../core/extensions/string_extension.dart';
import '../../widgets/premium_fab.dart';

/// Premium Inbox screen with conversation list
class InboxScreen extends StatefulWidget {
  final VoidCallback? onNavigateToCustomers;

  const InboxScreen({super.key, this.onNavigateToCustomers});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen>
    with TickerProviderStateMixin {
  late AnimationController _staggerController;
  late ScrollController _scrollController;

  // Pre-fetch threshold: load more when within this many items of the end
  static const int _prefetchThreshold = 3;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);

    _staggerController = AnimationController(
      duration: AppAnimations.slow, // Apple standard: 400ms (was 800ms)
      vsync: this,
    );

    // Load cached data ONLY - no auto-fetch for instant offline-first experience
    // Fresh data will be fetched only when user pulls to refresh or cache expires
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InboxProvider>().loadConversations(skipAutoRefresh: true);
      _staggerController.forward();
    });
  }

  /// Pre-fetch pagination: trigger load when approaching end of list
  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final inbox = context.read<InboxProvider>();
    if (inbox.isLoadingMore || !inbox.hasMore) return;

    final position = _scrollController.position;
    final threshold = position.maxScrollExtent - (80 * _prefetchThreshold);

    if (position.pixels >= threshold) {
      inbox.loadMoreConversations();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _staggerController.dispose();
    super.dispose();
  }

  void _openConversation(Conversation conversation) async {
    // Instant optimistic read status
    context.read<InboxProvider>().markAsRead(conversation.id);

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationDetailScreen(conversation: conversation),
      ),
    );
    // Refresh list on return to update "last message" preview and unread counts
    if (mounted) {
      context.read<InboxProvider>().refresh();
    }
  }

  /// Consolidated handler for approve/ignore - both navigate to detail
  void _navigateToAction(Conversation conversation) {
    Haptics.mediumTap();
    _openConversation(conversation);
  }

  void _navigateToCustomers() {
    Haptics.mediumTap();
    widget.onNavigateToCustomers?.call();
  }

  /// Handle pull-to-refresh
  Future<void> _handleRefresh() async {
    await context.read<InboxProvider>().loadConversations(forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    HijriCalendar.setLocal('ar');
    final hijriNow = HijriCalendar.now();
    final dateStr = hijriNow.toFormat('DD, dd MMMM yyyy').toEnglishNumbers;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(
          bottom: AppDimensions.bottomNavHeight + AppDimensions.spacing24,
        ),
        child: PremiumFAB(
          onPressed: _navigateToCustomers,
          standalone: false, // Use gradient circle style
          icon: const Icon(
            SolarBoldIcons.chatRoundLine,
            color: Colors.white,
            size: 32,
          ),
          heroTag: 'inbox_compose_fab',
          gradientColors: const [Color(0xFF2563EB), Color(0xFF0891B2)],
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildRegularHeader(
              theme,
              dateStr,
              Provider.of<InboxProvider>(context, listen: false),
            ),
            // Content with pull-to-refresh
            Expanded(
              child: RefreshIndicator(
                onRefresh: _handleRefresh,
                color: AppColors.primary,
                child: Consumer<InboxProvider>(
                  builder: (context, inbox, _) {
                    // Show cached data immediately - no skeleton loader
                    // Only show empty state if no conversations
                    if (inbox.conversations.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(
                        bottom: AppDimensions.listBottomPadding,
                      ),
                      itemCount:
                          inbox.filteredConversations.length +
                          (inbox.hasMore && inbox.searchQuery.isEmpty ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= inbox.filteredConversations.length) {
                          // Load more indicator
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(
                                AppDimensions.paddingMedium,
                              ),
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppColors.primary,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }

                        final conversation = inbox.filteredConversations[index];
                        final isLast =
                            index == inbox.filteredConversations.length - 1 &&
                            !inbox.hasMore;
                        return _buildAnimatedTile(
                          index: index,
                          child: InboxConversationTile(
                            conversation: conversation,
                            isSelectionMode: inbox.isSelectionMode,
                            isSelected: inbox.isSelected(conversation.id),
                            onSelectionChanged: (selected) {
                              inbox.toggleSelection(conversation.id);
                            },
                            onTap: () {
                              if (inbox.isSelectionMode) {
                                inbox.toggleSelection(conversation.id);
                              } else {
                                _openConversation(conversation);
                              }
                            },
                            onApprove: () => _navigateToAction(conversation),
                            isLast: isLast,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedTile({required int index, required Widget child}) {
    // Stagger delay for each item
    final delay = (index * 0.05).clamp(0.0, 0.5);

    return AnimatedBuilder(
      animation: _staggerController,
      builder: (context, _) {
        final progress = _staggerController.value;
        final adjustedProgress = ((progress - delay) / (1.0 - delay)).clamp(
          0.0,
          1.0,
        );
        final curvedValue = Curves.easeOutCubic.transform(adjustedProgress);

        return Opacity(
          opacity: curvedValue,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - curvedValue)),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildRegularHeader(
    ThemeData theme,
    String dateStr,
    InboxProvider inbox,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      key: const ValueKey('regular_header'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text(
            dateStr,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
              fontSize: 14,
              fontFamily: 'IBM Plex Sans Arabic',
            ),
          ),
        ],
      ),
    );
  }
}
