import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almudeer_mobile_app/presentation/screens/inbox/widgets/message_list_view.dart';
import 'package:almudeer_mobile_app/data/models/inbox_message.dart';
import 'package:provider/provider.dart';
import 'package:almudeer_mobile_app/presentation/providers/conversation_detail_provider.dart';
import 'package:almudeer_mobile_app/core/errors/failures.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class MockProvider extends ChangeNotifier
    implements ConversationDetailProvider {
  @override
  bool get hasMore => false;
  @override
  bool get isLoadingMore => false;
  @override
  bool get isLoading => false;
  @override
  bool get isPeerTyping => false;
  @override
  bool get isPeerRecording => false;
  @override
  bool get isPeerOnline => false;
  @override
  String? get peerLastSeen => null;
  @override
  String? get activeChannel => null;
  @override
  String? get senderContact => null;
  @override
  String? get senderName => null;
  @override
  InboxMessage? get replyToMessage => null;
  @override
  bool get isSelectionMode => false;
  @override
  Set<int> get selectedMessageIds => {};
  @override
  int get selectedCount => 0;
  @override
  bool isMessageSelected(int id) => false;
  @override
  ConversationState get state => ConversationState.initial;
  @override
  List<InboxMessage> get messages => [];
  @override
  Failure? get failure => null;
  @override
  int? get editingMessageId => null;
  @override
  String? get editingMessageBody => null;
  @override
  bool get isEditing => false;
  @override
  InboxMessage? get latestMessage => null;

  @override
  bool get isLocalUserOnline => true;

  @override
  Future<void> loadMoreMessages() async {}
  @override
  Future<void> loadConversation(
    String contact, {
    String? senderName,
    String? channel,
    String? lastSeenAt,
    bool isOnline = false,
    bool fresh = true,
    bool skipAutoRefresh = false,
  }) async {}
  @override
  void setReplyMessage(InboxMessage? message) {}
  @override
  void cancelReply() {}
  @override
  void toggleSelectionMode(bool enabled) {}
  @override
  void toggleMessageSelection(int id) {}
  @override
  void clearSelection() {}
  @override
  void clear() {}
  @override
  void setTypingStatus(bool isTyping) {}
  @override
  void setRecordingStatus(bool isRecording) {}
  @override
  void startEditingMessage(InboxMessage message) {}
  @override
  void cancelEditing() {}
  @override
  Future<bool> saveEditedMessage(String newBody, dynamic inboxProvider) async => true;
  @override
  void reset() {}
  @override
  void clearAllCache() {}
  @override
  void selectAll() {}
  @override
  Future<void> bulkDeleteMessages() async {}
  @override
  Future<void> shareMessages(List<int> ids, dynamic target) async {}
  Future<bool> approveMessage(int id, {String? editedBody}) async => true;
  @override
  Future<bool> editMessage(int id, String body) async => true;
  @override
  Future<bool> deleteMessage(int id) async => true;
  @override
  void addOptimisticMessage(InboxMessage message) {}
  @override
  @override
  void confirmMessageSent(int tId, int rId, String status, {int? outboxId}) {}

  @override
  void markMessageFailed(int id) {}
  @override
  Future<bool> clearActiveChatMessages() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('MessageListView smoke test', (WidgetTester tester) async {
    // Basic smoke test with empty list to verify composition
    final messages = <InboxMessage>[];

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ConversationDetailProvider>(
          create: (_) => MockProvider(),
          child: Scaffold(
            body: MessageListView(
              messages: messages,
              channelColor: Colors.blue,
              displayName: 'Test',
              onReply: (_) {},
              highlightMessageId: 100, // Should not crash even if not found
            ),
          ),
        ),
      ),
    );

    expect(find.byType(MessageListView), findsOneWidget);
    // Verify underlying list implementation
    expect(find.byType(ScrollablePositionedList), findsOneWidget);
  });
}
