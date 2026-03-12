import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import '../common_widgets.dart';

/// Rich empty state for conversations with channel-specific tips and CTA
class EmptyConversationState extends StatelessWidget {
  final String channel;
  final Color channelColor;

  const EmptyConversationState({
    super.key,
    required this.channel,
    required this.channelColor,
  });

  IconData get _channelIcon {
    switch (channel.toLowerCase()) {
      case 'whatsapp':
        return SolarLinearIcons.chatRound;
      case 'telegram':
      case 'telegram_bot':
        return SolarLinearIcons.plain;
      case 'saved':
        return SolarLinearIcons.bookmark;
      default:
        return SolarLinearIcons.chatRoundDots;
    }
  }

  @override
  Widget build(BuildContext context) {
    return EmptyStateWidget(
      icon: _channelIcon,
      iconColor: channelColor,
      iconBgColor: channelColor.withValues(alpha: 0.1),
    );
  }
}
