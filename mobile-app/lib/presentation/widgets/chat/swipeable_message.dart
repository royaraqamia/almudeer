import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

import '../../../core/constants/colors.dart';
import '../../../core/utils/haptics.dart';

/// Swipeable message wrapper for swipe-to-reply functionality
class SwipeableMessage extends StatelessWidget {
  final Widget child;
  final String messageId;
  final String messageBody;
  final bool isOutgoing;
  final VoidCallback onReply;

  const SwipeableMessage({
    super.key,
    required this.child,
    required this.messageId,
    required this.messageBody,
    required this.isOutgoing,
    required this.onReply,
  });

  void _handleReply(BuildContext context) {
    Haptics.lightTap();
    onReply();
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Semantics(
      label: isOutgoing ? 'رسالة صادرة' : 'رسالة واردة',
      onLongPress: () => _handleReply(context),
      child: Dismissible(
        key: Key('swipe_$messageId'),
        // Outgoing (Right): Drag R->L (EndToStart LTR / StartToEnd RTL)
        // Incoming (Left): Drag L->R (StartToEnd LTR / EndToStart RTL)
        direction: (isOutgoing == isRtl)
            ? DismissDirection.startToEnd
            : DismissDirection.endToStart,
        confirmDismiss: (direction) async {
          Haptics.lightTap();
          onReply();
          return false; // Don't dismiss, just trigger reply
        },
        movementDuration: const Duration(milliseconds: 200),
        background: Container(
          // Outgoing (Right): Reveal on Right. Incoming (Left): Reveal on Left.
          alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
          padding: EdgeInsets.only(
            left: isOutgoing ? 0 : 20,
            right: isOutgoing ? 20 : 0,
          ),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              SolarLinearIcons.reply,
              color: AppColors.primary,
              size: 20,
            ),
          ),
        ),
        child: child,
      ),
    );
  }
}
