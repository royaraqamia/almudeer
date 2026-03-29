import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:intl/intl.dart' as intl;
import 'package:hijri/hijri_calendar.dart';

import 'package:almudeer_mobile_app/core/utils/haptics.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import '../../../data/models/conversation.dart';
import '../../providers/conversation_detail_provider.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/custom_dialog.dart';
import '../../screens/chat_selection_screen.dart';
import 'package:almudeer_mobile_app/features/customers/presentation/screens/customer_detail_screen.dart';
import 'package:almudeer_mobile_app/features/customers/presentation/providers/customers_provider.dart';
import 'package:almudeer_mobile_app/core/widgets/app_avatar.dart';
import 'package:almudeer_mobile_app/core/extensions/string_extension.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/animated_toast.dart';

/// Premium AppBar for conversation detail screen with lead score and typing indicators
class ConversationAppBar extends StatefulWidget
    implements PreferredSizeWidget {
  final ThemeData theme;
  final bool isDark;
  final Color channelColor;
  final Conversation conversation;
  final VoidCallback? onSearch;
  final VoidCallback? onCloseSearch;
  final Function(String)? onSearchQueryChanged;
  final bool isSearching;
  final String searchQuery;
  final int totalSearchResults;
  final int currentSearchIndex;
  final VoidCallback? onNextResult;
  final VoidCallback? onPreviousResult;

  const ConversationAppBar({
    super.key,
    required this.theme,
    required this.isDark,
    required this.channelColor,
    required this.conversation,
    this.onSearch,
    this.onCloseSearch,
    this.onSearchQueryChanged,
    this.isSearching = false,
    this.searchQuery = '',
    this.totalSearchResults = 0,
    this.currentSearchIndex = 0,
    this.onNextResult,
    this.onPreviousResult,
  });

  @override
  State<ConversationAppBar> createState() => _ConversationAppBarState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _ConversationAppBarState extends State<ConversationAppBar> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.searchQuery;
  }

  @override
  void didUpdateWidget(ConversationAppBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != oldWidget.searchQuery) {
      _searchController.text = widget.searchQuery;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _copySelected(
    BuildContext context,
    ConversationDetailProvider provider,
  ) async {
    final ids = provider.selectedMessageIds;
    if (ids.length != 1) return;

    final msgId = ids.first;
    final msg = provider.messages.firstWhere((m) => m.id == msgId);

    await Clipboard.setData(ClipboardData(text: msg.body));
    Haptics.lightTap();
    provider.clearSelection();
    if (context.mounted) {
      AnimatedToast.info(context, 'طھظ… ظ†ط³ط® ط§ظ„ط±ط³ط§ظ„ط©');
    }
  }

  void _editSelected(
    BuildContext context,
    ConversationDetailProvider provider,
  ) {
    final ids = provider.selectedMessageIds;
    if (ids.length != 1) return;

    final msgId = ids.first;
    final msg = provider.messages.firstWhere((m) => m.id == msgId);

    if (!msg.isOutgoing) return;

    provider.startEditingMessage(msg);
    provider.clearSelection();
  }

  Future<void> _deleteSelected(
    BuildContext context,
    ConversationDetailProvider provider,
  ) async {
    final confirmed = await CustomDialog.show(
      context,
      title: 'ط­ط°ظپ ط§ظ„ط±ط³ط§ط¦ظ„ ط§ظ„ظ…ط®طھط§ط±ط©طں',
      message: 'ط³ظٹطھظ… ط­ط°ظپ ${provider.selectedCount} ط±ط³ط§ط¦ظ„.',
      type: DialogType.error,
      confirmText: 'ط­ط°ظپ',
      cancelText: 'ط¥ظ„ط؛ط§ط،',
    );

    if (confirmed == true) {
      await provider.bulkDeleteMessages();
    }
  }

  void _shareSelected(
    BuildContext context,
    ConversationDetailProvider provider,
  ) async {
    final ids = provider.selectedMessageIds.toList();
    if (ids.isEmpty) return;

    // Detect if any selected message contains a task or note attachment
    final selectedMessages = provider.messages
        .where((m) => ids.contains(m.id))
        .toList();
    final hasTaskOrNote = selectedMessages.any((m) {
      if (m.attachments == null) return false;
      return m.attachments!.any((a) {
        final type = a['type']?.toString().toLowerCase();
        return type == 'task' || type == 'note';
      });
    });

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatSelectionScreen(
          excludeChannels: hasTaskOrNote
              ? ['whatsapp', 'telegram', 'telegram_bot']
              : null,
        ),
      ),
    );

    if (result != null && context.mounted) {
      final List<Conversation> conversations = result is List
          ? result.cast<Conversation>()
          : [result as Conversation];

      for (final conversation in conversations) {
        await provider.shareMessages(ids, conversation);
      }
    }
  }

  String _formatLastSeen(String? lastSeenAt) {
    if (lastSeenAt == null || lastSeenAt.isEmpty) return '';
    try {
      var date = DateTime.parse(lastSeenAt);
      if (!lastSeenAt.endsWith('Z') && !lastSeenAt.contains('+')) {
        date = DateTime.utc(
          date.year,
          date.month,
          date.day,
          date.hour,
          date.minute,
          date.second,
        );
      }
      final localDate = date.toLocal();
      final now = DateTime.now();
      final difference = now.difference(localDate);

      if (difference.inMinutes < 1) {
        return 'ظ†ط´ط· ظ…ظ†ط° ط«ظˆط§ظ†ظچ';
      } else if (difference.inMinutes < 60) {
        return 'ظ†ط´ط· ظ…ظ†ط° ${difference.inMinutes} ط¯ظ‚ظٹظ‚ط©';
      } else if (localDate.year == now.year &&
          localDate.month == now.month &&
          localDate.day == now.day) {
        return 'ط¢ط®ط± ط¸ظ‡ظˆط± ط§ظ„ظٹظˆظ… ${intl.DateFormat.jm('ar_AE').format(localDate).toEnglishNumbers}';
      } else if (localDate.year == now.year &&
          localDate.month == now.month &&
          localDate.day == now.day - 1) {
        return 'ط¢ط®ط± ط¸ظ‡ظˆط± ط£ظ…ط³ ${intl.DateFormat.jm('ar_AE').format(localDate).toEnglishNumbers}';
      } else {
        final hijri = HijriCalendar.fromDate(localDate);
        return 'ط¢ط®ط± ط¸ظ‡ظˆط± ${hijri.toFormat("dd/mm/yyyy").toEnglishNumbers}';
      }
    } catch (e) {
      return 'ط¢ط®ط± ط¸ظ‡ظˆط± ط؛ظٹط± ظ…ط¹ط±ظˆظپ';
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ConversationDetailProvider>();
    final isSelectionMode = provider.isSelectionMode;

    if (isSelectionMode) {
      return _buildSelectionAppBar(context, provider);
    }

    if (widget.isSearching) {
      return _buildSearchAppBar(context, provider);
    }

    return _buildNormalAppBar(context, provider);
  }

  PreferredSizeWidget _buildNormalAppBar(
    BuildContext context,
    ConversationDetailProvider provider,
  ) {
    return AppBar(
      elevation: 0,
      titleSpacing: 0,
      automaticallyImplyLeading: false,
      backgroundColor: widget.theme.scaffoldBackgroundColor,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      actions: [
        if (widget.onSearch != null)
          IconButton(
            onPressed: widget.onSearch,
            splashRadius: 24,
            icon: Icon(
              SolarLinearIcons.magnifer,
              color: widget.theme.iconTheme.color,
              size: 22,
            ),
          ),
        const SizedBox(width: 8),
      ],
      leadingWidth: 56,
      leading: IconButton(
        icon: Icon(
          SolarLinearIcons.arrowRight,
          size: 24,
          color: widget.theme.iconTheme.color,
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: _buildTitle(context, provider),
    );
  }

  PreferredSizeWidget _buildSearchAppBar(
    BuildContext context,
    ConversationDetailProvider provider,
  ) {
    return AppBar(
      elevation: 0,
      titleSpacing: 0,
      automaticallyImplyLeading: false,
      backgroundColor: widget.theme.scaffoldBackgroundColor,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      leadingWidth: 56,
      leading: IconButton(
        icon: const Icon(
          SolarLinearIcons.arrowRight,
          size: 24,
        ),
        color: widget.theme.iconTheme.color,
        onPressed: widget.onCloseSearch,
      ),
      title: TextField(
        controller: _searchController,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'ط§ظ„ط¨ط­ط« ظپظٹ ط§ظ„ظ…ط­ط§ط¯ط«ط©...',
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          hintStyle: widget.theme.textTheme.bodyMedium?.copyWith(
            color: widget.theme.hintColor,
            fontSize: 16,
          ),
        ),
        style: widget.theme.textTheme.bodyMedium?.copyWith(
          fontSize: 16,
        ),
        textDirection: TextDirection.rtl,
        onChanged: widget.onSearchQueryChanged,
      ),
      actions: [
        if (widget.totalSearchResults > 0) ...[
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${widget.currentSearchIndex + 1}/${widget.totalSearchResults}',
              style: widget.theme.textTheme.labelSmall?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
        ],
        if (widget.totalSearchResults > 1) ...[
          IconButton(
            onPressed: widget.onPreviousResult,
            icon: const Icon(SolarLinearIcons.arrowUp, size: 20),
            color: widget.theme.colorScheme.onSurface,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: widget.onNextResult,
            icon: const Icon(SolarLinearIcons.arrowDown, size: 20),
            color: widget.theme.colorScheme.onSurface,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 12),
        ],
      ],
    );
  }

  Widget _buildTitle(BuildContext context, ConversationDetailProvider provider) {
    return Row(
      children: [
        Hero(
          tag: 'avatar_${widget.conversation.senderContact}',
          child: AppAvatar(
            radius: 24,
            imageUrl: widget.conversation.avatarUrl,
            overlay: widget.conversation.senderContact != '__saved_messages__'
                ? Positioned(
                    bottom: -4,
                    left: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: widget.theme.scaffoldBackgroundColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: widget.theme.scaffoldBackgroundColor,
                          width: 2,
                        ),
                      ),
                      child: widget.conversation.channel.toLowerCase() == 'almudeer'
                          ? Image.asset(
                              'assets/images/app_icon.png',
                              width: 14,
                              height: 14,
                            )
                          : Icon(
                              widget.conversation.channel.toLowerCase() == 'whatsapp'
                                  ? SolarLinearIcons.chatRound
                                  : widget.conversation.channel.toLowerCase() ==
                                            'telegram' ||
                                        widget.conversation.channel.toLowerCase() ==
                                            'telegram_bot'
                                  ? SolarLinearIcons.plain
                                  : SolarLinearIcons.chatRoundDots,
                              size: 12,
                              color: widget.channelColor,
                            ),
                    ),
                  )
                : null,
            child: widget.conversation.senderContact == '__saved_messages__'
                ? Icon(
                    SolarLinearIcons.bookmark,
                    color: widget.channelColor,
                    size: 20,
                  )
                : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: () => _handleAppBarTap(context),
            focusColor: widget.channelColor.withValues(alpha: 0.12),
            hoverColor: widget.channelColor.withValues(alpha: 0.04),
            highlightColor: widget.channelColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Consumer<CustomersProvider>(
                          builder: (context, customersProvider, _) {
                            final customer = customersProvider.getCustomerByContact(widget.conversation.senderContact);
                            final displayName = (customer != null && customer.name != null && customer.name!.isNotEmpty)
                                ? customer.name!
                                : widget.conversation.displayName;
                            return Text(
                              displayName,
                              style: widget.theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                height: 1.2,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  if (provider.activeChannel?.toLowerCase() ==
                      'almudeer') ...[
                    if (provider.isPeerTyping) ...[
                      const SizedBox(height: 2),
                      Text(
                        'ظٹظƒطھط¨...',
                        style: widget.theme.textTheme.bodySmall?.copyWith(
                          color: widget.theme.colorScheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ] else if (provider.isPeerRecording) ...[
                      const SizedBox(height: 2),
                      Text(
                        'ظٹط³ط¬ظگظ‘ظ„ ظ…ظ‚ط·ط¹ طµظˆطھظٹ...',
                        style: widget.theme.textTheme.bodySmall?.copyWith(
                          color: widget.theme.colorScheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ] else if (provider.isLocalUserOnline) ...[
                      if (provider.isPeerOnline) ...[
                        const SizedBox(height: 2),
                        Text(
                          'ظ…طھظژظ‘طµظ„ ط§ظ„ط¢ظ†',
                          style: widget.theme.textTheme.bodySmall?.copyWith(
                            color: widget.theme.colorScheme.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ] else if (_formatLastSeen(
                        provider.peerLastSeen ?? widget.conversation.lastSeenAt,
                      ).isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          _formatLastSeen(
                            provider.peerLastSeen ?? widget.conversation.lastSeenAt,
                          ),
                          style: widget.theme.textTheme.bodySmall?.copyWith(
                            color: widget.theme.hintColor.withValues(alpha: 0.6),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ] else if (widget.conversation.senderContact != '__saved_messages__') ...[
                    const SizedBox(height: 2),
                    Text(
                      ' ${widget.conversation.channelDisplayName}',
                      style: widget.theme.textTheme.bodySmall?.copyWith(
                        color: widget.theme.hintColor.withValues(alpha: 0.6),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleAppBarTap(BuildContext context) async {
    if (widget.conversation.senderContact == '__saved_messages__') return;

    Haptics.lightTap();
    final customersProvider = context.read<CustomersProvider>();

    // 1. Determine contact lookup parameters based on channel
    String? phone;
    String? username;

    final channel = widget.conversation.channel.toLowerCase();
    final contact = widget.conversation.senderContact;

    if (channel == 'whatsapp') {
      phone = contact;
    } else if (channel == 'telegram' || channel == 'telegram_bot') {
      if (contact != null &&
          !contact.startsWith('+') &&
          !contact.contains(RegExp(r'^\d+$'))) {
        username = contact;
      } else {
        phone = contact;
      }
    } else if (channel == 'almudeer') {
      username = contact;
    }

    // 2. Lookup customer
    final customer = await customersProvider.findCustomer(
      phone: phone,
      username: username,
    );

    if (context.mounted) {
      // 3. Always navigate to detail screen
      final customerData =
          customer?.toJson() ??
          {
            'id': null,
            'name': widget.conversation.senderName,
            'phone': phone,
            'username': username,
            'is_almudeer_user': channel == 'almudeer',
            'avatar_url': widget.conversation.avatarUrl,
          };

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CustomerDetailScreen(customer: customerData),
        ),
      );
    }
  }

  PreferredSizeWidget _buildSelectionAppBar(
    BuildContext context,
    ConversationDetailProvider provider,
  ) {
    final count = provider.selectedCount;

    // Check if single selection is outgoing
    bool canEdit = false;
    if (count == 1) {
      final msgId = provider.selectedMessageIds.first;
      try {
        final msg = provider.messages.firstWhere((m) => m.id == msgId);
        canEdit = msg.canEdit;
      } catch (_) {}
    }

    return AppBar(
      elevation: 0,
      backgroundColor: widget.theme.scaffoldBackgroundColor,
      leading: IconButton(
        icon: const Icon(SolarLinearIcons.arrowRight, size: 24),
        onPressed: () => provider.clearSelection(),
        color: widget.theme.iconTheme.color,
      ),
      title: Text(
        '$count',
        style: widget.theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: [
        if (count == 1) ...[
          IconButton(
            icon: const Icon(SolarLinearIcons.reply, size: 28),
            onPressed: () {
              final msgId = provider.selectedMessageIds.first;
              final msg = provider.messages.firstWhere((m) => m.id == msgId);
              provider.setReplyMessage(msg);
              provider.clearSelection();
            },
            color: widget.theme.iconTheme.color,
            tooltip: 'ط±ط¯',
          ),
          IconButton(
            icon: SvgPicture.asset(
              'assets/icons/copy.svg',
              width: 24,
              height: 24,
              colorFilter: ColorFilter.mode(
                widget.theme.iconTheme.color ?? Colors.black,
                BlendMode.srcIn,
              ),
            ),
            onPressed: () => _copySelected(context, provider),
            color: widget.theme.iconTheme.color,
            tooltip: 'ظ†ط³ط®',
          ),
          if (canEdit)
            IconButton(
              icon: const Icon(SolarLinearIcons.pen),
              onPressed: () => _editSelected(context, provider),
              color: widget.theme.iconTheme.color,
              tooltip: 'طھط¹ط¯ظٹظ„',
            ),
        ],
        IconButton(
          icon: const Icon(SolarLinearIcons.shareCircle),
          onPressed: () => _shareSelected(context, provider),
          color: widget.theme.iconTheme.color,
          tooltip: 'ظ…ط´ط§ط±ظƒط©',
        ),
        IconButton(
          icon: const Icon(SolarLinearIcons.trashBinMinimalistic),
          onPressed: () => _deleteSelected(context, provider),
          color: AppColors.error,
          tooltip: 'ط­ط°ظپ',
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}
