import 'package:flutter/material.dart';

import '../../../data/models/inbox_message.dart';
import '../../providers/conversation_detail_provider.dart';

/// Mixin for handling message bubble interactions
/// Separates interaction logic from rendering logic
mixin MessageBubbleInteraction<T extends StatefulWidget> on State<T> {
  // Drag-to-select state
  bool _isDragSelecting = false;
  bool _isInDragSelectMode = false;

  /// Get the current message being interacted with
  InboxMessage get message;

  /// Get the conversation detail provider
  ConversationDetailProvider get provider;

  /// Get the build context for overlays
  BuildContext get bubbleContext;

  /// Handle pan start for drag-to-select
  void onPanStart() {
    _isDragSelecting = true;
    provider.toggleMessageSelection(message.id);
  }

  /// Handle pan update for drag-to-select
  void onPanUpdate() {
    if (!_isDragSelecting) return;

    if (!_isInDragSelectMode) {
      _isInDragSelectMode = true;
      Future.delayed(const Duration(milliseconds: 100), () {
        _isInDragSelectMode = false;
      });
      provider.toggleMessageSelection(message.id);
    }
  }

  /// Handle pan end for drag-to-select
  void onPanEnd() {
    _isDragSelecting = false;
  }

  /// Clean up overlays
  void disposeOverlay() {
    // No cleanup needed now
  }
}
