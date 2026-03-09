import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/constants/dimensions.dart';
import '../../models/task_comment_model.dart';
import 'comment_bubble.dart';

/// Groups comments by date for display
class CommentListItem {
  final DateTime date;
  final List<TaskCommentModel> comments;

  CommentListItem({
    required this.date,
    required this.comments,
  });
}

/// Comment list view with date headers and proper grouping
class CommentListView extends StatefulWidget {
  final List<TaskCommentModel> comments;
  final String? currentUserId;
  final bool isLoading;
  final ValueNotifier<bool>? showScrollToBottom;

  const CommentListView({
    super.key,
    required this.comments,
    required this.currentUserId,
    this.isLoading = false,
    this.showScrollToBottom,
  });

  @override
  State<CommentListView> createState() => _CommentListViewState();
}

class _CommentListViewState extends State<CommentListView> {
  List<CommentListItem> _cachedItems = [];

  @override
  void didUpdateWidget(CommentListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.comments.length != oldWidget.comments.length) {
      _groupComments();
    }
  }

  @override
  void initState() {
    super.initState();
    _groupComments();
  }

  void _groupComments() {
    final grouped = <DateTime, List<TaskCommentModel>>{};

    for (final comment in widget.comments) {
      final date = DateTime(
        comment.createdAt.year,
        comment.createdAt.month,
        comment.createdAt.day,
      );

      if (!grouped.containsKey(date)) {
        grouped[date] = [];
      }
      grouped[date]!.add(comment);
    }

    // Sort dates in descending order (newest first)
    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    _cachedItems = sortedDates
        .map((date) => CommentListItem(
              date: date,
              comments: grouped[date]!,
            ))
        .toList();
  }

  CommentGroupPosition _getPositionForComment(
    List<TaskCommentModel> comments,
    int index,
    String? currentUserId,
  ) {
    final comment = comments[index];

    // Check previous and next comments
    final prevComment = index > 0 ? comments[index - 1] : null;
    final nextComment = index < comments.length - 1 ? comments[index + 1] : null;

    final prevIsSameUser = prevComment?.userId == comment.userId;
    final nextIsSameUser = nextComment?.userId == comment.userId;

    // Check if dates are consecutive (for grouping purposes)
    final prevIsSameDay = prevComment != null &&
        _isSameDay(prevComment.createdAt, comment.createdAt);
    final nextIsSameDay = nextComment != null &&
        _isSameDay(nextComment.createdAt, comment.createdAt);

    if (!prevIsSameUser || !prevIsSameDay) {
      // Top of group
      if (nextIsSameUser && nextIsSameDay) {
        return CommentGroupPosition.top;
      }
      return CommentGroupPosition.single;
    } else if (!nextIsSameUser || !nextIsSameDay) {
      // Bottom of group
      return CommentGroupPosition.bottom;
    } else {
      // Middle of group
      return CommentGroupPosition.middle;
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final isToday = _isSameDay(date, now);
    final isYesterday = _isSameDay(date, DateTime(now.year, now.month, now.day - 1));

    if (isToday) {
      return 'اليوم';
    } else if (isYesterday) {
      return 'أمس';
    }

    // Format as "dd MMMM" in Hijri or Gregorian
    return DateFormat('EEEE, dd MMMM', 'ar_AE').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.isLoading && widget.comments.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.comments.isEmpty) {
      return Center(
        child: Text(
          'لا توجد تعليقات بعد',
          style: TextStyle(
            color: theme.brightness == Brightness.dark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
            fontSize: 13,
          ),
        ),
      );
    }

    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.only(
        left: AppDimensions.paddingMedium,
        right: AppDimensions.paddingMedium,
        top: AppDimensions.paddingMedium,
        bottom: 80,
      ),
      itemCount: _cachedItems.length,
      itemBuilder: (context, index) {
        final item = _cachedItems[index];

        return Column(
          children: [
            // Date header
            _buildDateHeader(item.date, theme),

            // Comments for this date
            ...item.comments.asMap().entries.map((entry) {
              final commentIndex = entry.key;
              final comment = entry.value;

              final position = _getPositionForComment(
                item.comments,
                commentIndex,
                widget.currentUserId ?? '',
              );

              return CommentBubble(
                key: ValueKey('comment_${comment.id}'),
                comment: comment,
                isOutgoing: comment.userId == widget.currentUserId,
                position: position,
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildDateHeader(DateTime date, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.8,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _formatDateHeader(date),
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
