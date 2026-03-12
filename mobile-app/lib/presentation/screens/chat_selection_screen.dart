import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import '../../core/constants/colors.dart';
import '../../data/models/conversation.dart';
import '../../data/models/customer.dart';
import '../providers/customers_provider.dart';
import '../providers/inbox_provider.dart';
import 'inbox/widgets/inbox_conversation_tile.dart';
import '../widgets/customers/premium_customer_tile.dart';

class ChatSelectionScreen extends StatefulWidget {
  final bool allowBulkSelection;
  final List<String>? excludeChannels;

  const ChatSelectionScreen({
    super.key,
    this.allowBulkSelection = true,
    this.excludeChannels,
  });

  @override
  State<ChatSelectionScreen> createState() => _ChatSelectionScreenState();
}

class _ChatSelectionScreenState extends State<ChatSelectionScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  // Selection state for bulk mode
  final Set<String> _selectedIds =
      {}; // Format: "type_id" (e.g. "chat_123", "contact_456")
  final List<Conversation> _selectedConversations = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InboxProvider>().loadConversations();
      context.read<CustomersProvider>().loadCustomers();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onConversationSelected(Conversation conversation) {
    _handleSelection('chat_${conversation.id}', conversation);
  }

  void _onContactSelected(Customer customer) {
    if (!customer.isAlmudeerUser) return;

    final conversation = Conversation(
      id: -1 * customer.id,
      channel: 'almudeer',
      senderName: customer.name ?? customer.displayName,
      senderContact: customer.phone ?? '',
      senderId: customer.id.toString(),
      body: '',
      status: 'new',
      createdAt: DateTime.now().toIso8601String(),
      messageCount: 0,
      unreadCount: 0,
      avatarUrl: null,
    );

    _handleSelection('contact_${customer.id}', conversation);
  }

  void _handleSelection(String uniqueId, Conversation item) {
    setState(() {
      if (widget.allowBulkSelection) {
        // Bulk Mode: Toggle logic
        if (_selectedIds.contains(uniqueId)) {
          _selectedIds.remove(uniqueId);
          _selectedConversations.removeWhere(
            (c) =>
                (c.id == item.id && uniqueId.startsWith('chat_')) ||
                (c.senderId == item.senderId &&
                    uniqueId.startsWith('contact_')),
          );
        } else {
          _selectedIds.add(uniqueId);
          _selectedConversations.add(item);
        }
      } else {
        // Single Mode: Radio logic (Select one, replacing previous)
        // If clicking the same one, maybe keep it selected or toggle?
        // User pattern usually allows deselect or just keeping it.
        // Let's enforce selection (clicking new one replaces old).

        _selectedIds.clear();
        _selectedConversations.clear();

        _selectedIds.add(uniqueId);
        _selectedConversations.add(item);
      }
    });
  }

  void _submitSelection() {
    if (_selectedConversations.isEmpty) return;

    if (widget.allowBulkSelection) {
      Navigator.of(context).pop(_selectedConversations);
    } else {
      // Return single conversation for legacy compatibility
      Navigator.of(context).pop(_selectedConversations.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // FAB Visibility: Show if any item is selected (in both Single and Bulk modes)
    final showFab = _selectedConversations.isNotEmpty;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(SolarLinearIcons.arrowRight, size: 24),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.allowBulkSelection ? ' مشاركة مع...' : 'مشاركة مع...',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      floatingActionButton: showFab
          ? FloatingActionButton(
              onPressed: _submitSelection,
              backgroundColor: AppColors.primary,
              child: const Icon(SolarBoldIcons.plain3, color: Colors.white),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'بحث...',
                prefixIcon: const Icon(SolarLinearIcons.magnifer),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey.withValues(alpha: 0.1),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: (value) {
                context.read<InboxProvider>().setSearchQuery(value);
                context.read<CustomersProvider>().setSearchQuery(value);
              },
            ),
          ),
          Expanded(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                // 1. CHATS SECTION
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'المحادثات',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ),
                Consumer<InboxProvider>(
                  builder: (context, inbox, _) {
                    if (inbox.isLoading && inbox.conversations.isEmpty) {
                      return const SliverToBoxAdapter(
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final conversations = widget.excludeChannels == null
                        ? inbox.filteredConversations
                        : inbox.filteredConversations.where((c) {
                            return !widget.excludeChannels!.contains(
                              c.channel.toLowerCase(),
                            );
                          }).toList();

                    if (conversations.isEmpty) {
                      return const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'لا توجد محادثات مطابقة',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }

                    return SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final conversation = conversations[index];
                        final isSelected = _selectedIds.contains(
                          'chat_${conversation.id}',
                        );

                        return InboxConversationTile(
                          conversation: conversation,
                          isSelectionMode:
                              true, // Always show selection (Radio/Checkbox)
                          isSelected: isSelected,
                          canSelectSavedMessages: true,
                          onSelectionChanged: (value) =>
                              _onConversationSelected(conversation),
                          onTap: () => _onConversationSelected(conversation),
                          isLast: index == conversations.length - 1,
                        );
                      }, childCount: conversations.length),
                    );
                  },
                ),

                // 2. CONTACTS SECTION
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                    child: Text(
                      'جهات الاتصال',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ),
                Consumer<CustomersProvider>(
                  builder: (context, customersProvider, _) {
                    if (customersProvider.isLoading &&
                        customersProvider.customers.isEmpty) {
                      return const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      );
                    }

                    final customers = customersProvider.customers;

                    if (customers.isEmpty) {
                      return const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'لا توجد جهات اتصال مطابقة',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }

                    return SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final customer = customers[index];
                        final isAlmudeer = customer.isAlmudeerUser;
                        final isSelected = _selectedIds.contains(
                          'contact_${customer.id}',
                        );

                        return PremiumCustomerTile(
                          customer: customer,
                          isSelectionMode: true,
                          isSelected: isSelected,
                          isEnabled: isAlmudeer,
                          onTap: isAlmudeer
                              ? () => _onContactSelected(customer)
                              : () {},
                          isLast: index == customers.length - 1,
                        );
                      }, childCount: customers.length),
                    );
                  },
                ),

                // Add some padding at bottom (for FAB)
                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
