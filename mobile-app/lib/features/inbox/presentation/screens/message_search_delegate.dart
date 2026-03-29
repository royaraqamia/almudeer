import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/constants/animations.dart';
import 'package:almudeer_mobile_app/features/inbox/presentation/providers/inbox_provider.dart';
import 'package:almudeer_mobile_app/features/inbox/data/models/inbox_message.dart';
import 'package:almudeer_mobile_app/core/extensions/date_time_extension.dart';

class MessageSearchDelegate extends SearchDelegate<InboxMessage?> {
  final InboxProvider inboxProvider;
  final String? senderContact; // If provided, search is scoped to this contact

  MessageSearchDelegate(this.inboxProvider, {this.senderContact})
    : super(
        searchFieldLabel: 'ط¨ط­ط« ظپظٹ ط§ظ„ط±ط³ط§ط¦ظ„...',
        searchFieldStyle: const TextStyle(fontSize: 16),
      );

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return theme.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.iconTheme.color),
        toolbarHeight: 70,
        titleSpacing: 0,
        shape: Border(
          bottom: BorderSide(
            color: (isDark ? AppColors.borderDark : AppColors.borderLight)
                .withValues(alpha: 0.5),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: InputBorder.none,
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          color: theme.hintColor.withValues(alpha: 0.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionColor: AppColors.primary.withValues(alpha: 0.2),
        selectionHandleColor: AppColors.primary,
      ),
    );
  }

  @override
  List<Widget> buildActions(BuildContext context) {
    final theme = Theme.of(context);
    return [
      if (query.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 16.0), // RTL padding
          child: IconButton(
            icon: const Icon(SolarLinearIcons.closeCircle),
            color: theme.hintColor,
            onPressed: () {
              query = '';
              showSuggestions(context);
            },
          ),
        ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      icon: const Icon(SolarLinearIcons.arrowRight, size: 24), // RTL Back
      color: theme.iconTheme.color,
      onPressed: () {
        close(context, null);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    if (query.trim().isEmpty) {
      return buildSuggestions(context);
    }

    return FutureBuilder<List<InboxMessage>>(
      future: inboxProvider.searchMessages(query, senderContact: senderContact),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        } else if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  SolarLinearIcons.dangerTriangle,
                  size: 48,
                  color: AppColors.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'ط­ط¯ط« ط®ط·ط£ ظ…ط§',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'ظٹط±ط¬ظ‰ ط§ظ„ظ…ط­ط§ظˆظ„ط© ظ…ط±ط© ط£ط®ط±ظ‰ ظ„ط§ط­ظ‚ط§ظ‹',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).hintColor,
                  ),
                ),
              ],
            ),
          );
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildEmptyState(context, isNoResults: true);
        }

        final messages = snapshot.data!;

        return Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 16),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[index];
              return _buildResultItem(context, message, index);
            },
          ),
        );
      },
    );
  }

  Widget _buildResultItem(
    BuildContext context,
    InboxMessage message,
    int index,
  ) {
    final bool isMe = message.isOutgoing;

    // Parse Date
    final createdAt = message.createdAt.parseServerDate().toLocal();
    final timeStr = createdAt.toTimeString();
    final dateStr = createdAt.toInboxTimeString();

    return TweenAnimationBuilder<double>(
      duration: AppAnimations.normal,
      curve: AppAnimations.enter,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, value, child) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(
                  color: (isDark ? AppColors.borderDark : AppColors.borderLight)
                      .withValues(alpha: 0.5),
                ),
              ),
              child: child,
            ),
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          focusColor: AppColors.primary.withValues(alpha: 0.12),
          hoverColor: AppColors.primary.withValues(alpha: 0.04),
          highlightColor: AppColors.primary.withValues(alpha: 0.08),
          onTap: () => close(context, message),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isMe
                            ? AppColors.primary.withValues(alpha: 0.1)
                            : AppColors.surfaceCardDark.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isMe
                            ? SolarLinearIcons.uploadMinimalistic
                            : SolarLinearIcons.downloadMinimalistic,
                        color: isMe
                            ? AppColors.primary
                            : AppColors.textSecondaryLight,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final theme = Theme.of(context);
                          return Text(
                            isMe
                                ? 'ط£ظ†طھ'
                                : (message.senderName ??
                                      message.senderContact ??
                                      'ظ…ط¬ظ‡ظˆظ„'),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        },
                      ),
                    ),
                    Builder(
                      builder: (context) {
                        final theme = Theme.of(context);
                        final isDark = theme.brightness == Brightness.dark;
                        return Text(
                          '$timeStr â€¢ $dateStr',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight,
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildHighlightedText(context, message.body),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightedText(BuildContext context, String text) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (query.isEmpty) {
      return Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.textTheme.bodySmall?.color,
          height: 1.5,
        ),
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();

    // Find highlight range
    final int startIndex = lowerText.indexOf(lowerQuery);

    if (startIndex == -1) {
      return Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: isDark
              ? AppColors.textSecondaryDark
              : AppColors.textSecondaryLight,
          height: 1.5,
        ),
      );
    }

    // Create a snippet around the match if the text is long
    // This is optional, but for now we'll just show matching logic

    final List<TextSpan> spans = [];
    int start = 0;
    int indexOfHighlight;

    // We only highlight the first few occurrences or just do simple split
    // For search result snippets, typically we want to show the context around the match
    // Simple implementation:

    while ((indexOfHighlight = lowerText.indexOf(lowerQuery, start)) != -1) {
      if (indexOfHighlight > start) {
        spans.add(
          TextSpan(
            text: text.substring(start, indexOfHighlight),
            style: TextStyle(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
        );
      }

      spans.add(
        TextSpan(
          text: text.substring(
            indexOfHighlight,
            indexOfHighlight + query.length,
          ),
          style: TextStyle(
            color: isDark ? AppColors.textPrimaryDark : AppColors.primary,
            backgroundColor: isDark
                ? AppColors.primary.withValues(
                    alpha: 0.3,
                  ) // More visible in dark mode
                : AppColors.infoLight,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

      start = indexOfHighlight + query.length;
    }

    if (start < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(start),
          style: TextStyle(
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
          ),
        ),
      );
    }

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
        children: spans,
      ),
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildEmptyState(context, isNoResults: false);
  }

  Widget _buildEmptyState(BuildContext context, {required bool isNoResults}) {
    final theme = Theme.of(context);

    return Container(
      color: theme.scaffoldBackgroundColor,
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isNoResults
                  ? AppColors.error.withValues(alpha: 0.1)
                  : AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              SolarLinearIcons.magnifer,
              size: 48,
              color: isNoResults ? AppColors.error : AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
