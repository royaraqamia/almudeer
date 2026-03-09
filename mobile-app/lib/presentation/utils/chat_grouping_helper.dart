import '../../data/models/inbox_message.dart';

/// Position of a message within a group of messages from the same sender
enum MessageGroupPosition {
  single, // Isolated message
  top, // First in a group
  middle, // Middle of a group
  bottom, // Last in a group
}

/// Base class for chat list items
sealed class ChatListItem {}

/// A date header item (e.g., "Today", "Yesterday")
class DateHeaderItem extends ChatListItem {
  final DateTime date;
  DateHeaderItem(this.date);
}

/// A message item
class MessageItem extends ChatListItem {
  final InboxMessage message;
  final MessageGroupPosition position;
  final bool showAvatar;

  MessageItem({
    required this.message,
    required this.position,
    this.showAvatar = false,
  });
}

class ChatGroupingHelper {
  static List<InboxMessage>? _lastMessages;
  static List<ChatListItem>? _cachedItems;

  /// Group messages and insert date headers
  static List<ChatListItem> groupMessages(List<InboxMessage> messages) {
    if (messages.isEmpty) return [];

    // Memoization check
    if (_lastMessages != null &&
        _cachedItems != null &&
        _lastMessages!.length == messages.length) {
      if (_lastMessages!.first.id == messages.first.id &&
          _lastMessages!.last.id == messages.last.id &&
          _lastMessages!.first.effectiveTimestamp ==
              messages.first.effectiveTimestamp &&
          _lastMessages!.last.effectiveTimestamp ==
              messages.last.effectiveTimestamp) {
        return _cachedItems!;
      }
    }

    final List<ChatListItem> items = [];

    // Messages are usually passed in order: [Newest, ..., Oldest] (if reverse list)
    // We want to process them to determine grouping logic.

    for (int i = 0; i < messages.length; i++) {
      final current = messages[i];
      final next = (i + 1 < messages.length)
          ? messages[i + 1]
          : null; // Older message
      final prev = (i - 1 >= 0) ? messages[i - 1] : null; // Newer message

      // 1. Determine Date Header
      // Since list is reverse (bottom to top), Date Header should appear AFTER (visually above) the *last* message of a day.
      // In a `reverse: true` list, "Above" means "Higher Index" or "Next Item in List"?
      // Let's visualize:
      // Index 0: msg (Today 10:00 PM)
      // Index 1: msg (Today 9:00 PM)
      // Index 2: DATE HEADER (Today) <-- Inserted here? No.
      //
      // Usually Date Header is at the "Top" of the group of messages for that day.
      // Visualization (Screen Top):
      // [Date Header: Yesterday]
      // [Msg Yesterday]
      // [Date Header: Today]
      // [Msg Today 1]
      // [Msg Today 2]
      // (Screen Bottom)
      //
      // In `reverse: true` list:
      // Bottom (Index 0) -> [Msg Today 2]
      // Index 1 -> [Msg Today 1]
      // Index 2 -> [Date Header: Today]
      // Index 3 -> [Msg Yesterday]
      // Index 4 -> [Date Header: Yesterday]
      //
      // So, if `current` (Index N) has a different day than `next` (Index N+1) (Older),
      // we need to insert a Date Header for `current`'s day *after* `current` (at Index N+1... processed next).

      // Let's just add the message item first.

      // Grouping Logic:
      // Check comparison with Newer (prev) and Older (next) neighbors to determine shape.
      // SENDER ID defines grouping.

      bool sameAsNewer = prev != null && _isSameSender(current, prev);
      bool sameAsOlder = next != null && _isSameSender(current, next);

      MessageGroupPosition position;
      if (sameAsNewer && sameAsOlder) {
        position = MessageGroupPosition.middle;
      } else if (sameAsNewer && !sameAsOlder) {
        // Connected to newer (below), but not older (above).
        // This is the "Top" of the visual bubble group.
        position = MessageGroupPosition.top;
      } else if (!sameAsNewer && sameAsOlder) {
        // Connected to older (above), but not newer (below).
        // This is the "Bottom" of the visual bubble group (Trigger tail).
        position = MessageGroupPosition.bottom;
      } else {
        position = MessageGroupPosition.single;
      }

      // Avatar Logic: Show avatar only on last message of group (Bottom or Single)
      // AND only if incoming?
      bool showAvatar =
          (position == MessageGroupPosition.bottom ||
              position == MessageGroupPosition.single) &&
          current.isIncoming;

      items.add(
        MessageItem(
          message: current,
          position: position,
          showAvatar: showAvatar,
        ),
      );

      // Check date change
      if (next != null) {
        if (!_isSameDay(current, next)) {
          // Identify the day of CURRENT message.
          items.add(DateHeaderItem(_getDate(current)));
        }
      } else {
        // Usage: Last item (Oldest message). Always needs a date header above it.
        items.add(DateHeaderItem(_getDate(current)));
      }
    }

    _lastMessages = messages;
    _cachedItems = items;
    return items;
  }

  static bool _isSameSender(InboxMessage a, InboxMessage b) {
    if (a.direction != b.direction) return false;

    // If incoming, they must have the same sender_contact
    if (a.isIncoming) {
      return a.senderContact == b.senderContact;
    }

    // If both are outgoing, they are from the same person (the user)
    return true;
  }

  static bool _isSameDay(InboxMessage a, InboxMessage b) {
    final dA = _getDate(a);
    final dB = _getDate(b);
    return dA.year == dB.year && dA.month == dB.month && dA.day == dB.day;
  }

  static DateTime _getDate(InboxMessage m) {
    try {
      return DateTime.parse(m.effectiveTimestamp);
    } catch (_) {
      return DateTime.now();
    }
  }
}
