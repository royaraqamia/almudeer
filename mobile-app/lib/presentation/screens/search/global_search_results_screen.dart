import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/extensions/string_extension.dart';
import '../../../data/models/user.dart';
import '../../../data/models/customer.dart';
import '../../../data/models/library_item.dart';
import '../../../data/models/conversation.dart';
import '../../providers/inbox_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/customers_provider.dart';
import '../../widgets/customers/premium_customer_tile.dart';
import '../customers/customer_detail_screen.dart';
import '../inbox/conversation_detail_screen.dart';
import '../../../features/tasks/models/task_model.dart';
import '../../../features/tasks/providers/task_provider.dart';
import '../../../features/tasks/ui/screens/task_edit_screen.dart';
import '../library/note_edit_screen.dart';
import '../../../data/repositories/users_repository.dart';
import '../../widgets/common_widgets.dart';

/// Global search results screen (Telegram-style unified search)
/// Shows users, conversations, library items, tasks, and customers in sections
/// Uses ISOLATED state - does NOT affect dashboard screen providers
class GlobalSearchResultsScreen extends StatefulWidget {
  final String initialQuery;

  const GlobalSearchResultsScreen({super.key, this.initialQuery = ''});

  @override
  State<GlobalSearchResultsScreen> createState() =>
      _GlobalSearchResultsScreenState();
}

class _GlobalSearchResultsScreenState extends State<GlobalSearchResultsScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();

  // ISOLATED SEARCH STATE - does not affect providers
  String _currentQuery = '';
  List<User> _searchUsers = [];
  List<Conversation> _searchConversations = [];
  List<LibraryItem> _searchLibraryItems = [];
  List<Customer> _searchCustomers = [];
  List<TaskModel> _searchTasks = [];

  bool _isLoadingUsers = false;
  bool _isLoadingConversations = false;
  bool _isLoadingLibrary = false;
  bool _isLoadingCustomers = false;
  bool _isLoadingTasks = false;

  // Repositories for independent data fetching
  final UsersRepository _usersRepository = UsersRepository();

  @override
  void initState() {
    super.initState();
    _textController.text = widget.initialQuery;
    _currentQuery = widget.initialQuery;
    if (widget.initialQuery.isNotEmpty) {
      _performIndependentSearch(widget.initialQuery);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _textController.dispose();
    super.dispose();
  }

  /// Perform search using independent repository calls (does NOT mutate providers)
  void _performIndependentSearch(String query) {
    // FIX: Clear stale results immediately when query is empty
    if (query.isEmpty) {
      setState(() {
        _currentQuery = query;
        _searchUsers = [];
        _searchConversations = [];
        _searchLibraryItems = [];
        _searchCustomers = [];
        _searchTasks = [];
        _isLoadingUsers = false;
        _isLoadingConversations = false;
        _isLoadingLibrary = false;
        _isLoadingCustomers = false;
        _isLoadingTasks = false;
      });
      return;
    }

    setState(() {
      _currentQuery = query;
      _isLoadingUsers = true;
      _isLoadingConversations = true;
      _isLoadingLibrary = true;
      _isLoadingCustomers = true;
      _isLoadingTasks = true;
    });

    // Search users independently
    _searchUsersIndependent(query);

    // Search conversations independently
    _searchConversationsIndependent(query);

    // Search library independently
    _searchLibraryIndependent(query);

    // Search customers independently
    _searchCustomersIndependent(query);

    // Search tasks independently
    _searchTasksIndependent(query);
  }

  Future<void> _searchUsersIndependent(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchUsers = [];
        _isLoadingUsers = false;
      });
      return;
    }

    try {
      final response = await _usersRepository.searchUsers(
        query: query,
        limit: 20,
      );

      if (mounted) {
        setState(() {
          _searchUsers = response['error'] != null
              ? []
              : _usersRepository.parseSearchResults(response);
          _isLoadingUsers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchUsers = [];
          _isLoadingUsers = false;
        });
      }
    }
  }

  Future<void> _searchConversationsIndependent(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchConversations = [];
        _isLoadingConversations = false;
      });
      return;
    }

    // Get conversations from provider's current data (read-only)
    final inboxProvider = context.read<InboxProvider>();
    final allConversations = inboxProvider.conversations;

    if (mounted) {
      setState(() {
        _searchConversations = allConversations.where((c) {
          final name = c.senderName?.toLowerCase() ?? '';
          final contact = c.senderContact?.toLowerCase() ?? '';
          final body = c.body.toLowerCase();
          final q = query.toLowerCase();
          return name.contains(q) || contact.contains(q) || body.contains(q);
        }).toList();
        _isLoadingConversations = false;
      });
    }
  }

  Future<void> _searchLibraryIndependent(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchLibraryItems = [];
        _isLoadingLibrary = false;
      });
      return;
    }

    // Get library items from provider's current data (read-only)
    final libraryProvider = context.read<LibraryProvider>();
    final allItems = libraryProvider.items;

    if (mounted) {
      setState(() {
        _searchLibraryItems = allItems.where((item) {
          final title = item.title.toLowerCase();
          final fileType = item.type.toLowerCase();
          final q = query.toLowerCase();
          return title.contains(q) || fileType.contains(q);
        }).toList();
        _isLoadingLibrary = false;
      });
    }
  }

  Future<void> _searchCustomersIndependent(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchCustomers = [];
        _isLoadingCustomers = false;
      });
      return;
    }

    // Get customers from provider's current data (read-only)
    final customersProvider = context.read<CustomersProvider>();
    final allCustomers = customersProvider.customers;

    if (mounted) {
      setState(() {
        _searchCustomers = allCustomers.where((c) {
          final name = c.name?.toLowerCase() ?? '';
          final phone = c.phone?.toLowerCase() ?? '';
          final email = c.email?.toLowerCase() ?? '';
          final company = c.company?.toLowerCase() ?? '';
          final username = c.username?.toLowerCase() ?? '';
          final q = query.toLowerCase();
          return name.contains(q) ||
              phone.contains(q) ||
              email.contains(q) ||
              company.contains(q) ||
              username.contains(q);
        }).toList();
        _isLoadingCustomers = false;
      });
    }
  }

  Future<void> _searchTasksIndependent(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchTasks = [];
        _isLoadingTasks = false;
      });
      return;
    }

    // Get tasks from provider's current data (read-only)
    final taskProvider = context.read<TaskProvider>();
    final allTasks = taskProvider.tasks;

    if (mounted) {
      setState(() {
        _searchTasks = allTasks.where((task) {
          final title = task.title.toLowerCase();
          final description = task.description?.toLowerCase() ?? '';
          final q = query.toLowerCase();
          return title.contains(q) || description.contains(q);
        }).toList();
        _isLoadingTasks = false;
      });
    }
  }

  /// Filter users to exclude those who are also customers (to avoid duplicates)
  List<User> _filterNonCustomerUsers(
    List<User> users,
    List<Customer> customers,
  ) {
    final customerContacts = <String>{};
    for (final customer in customers) {
      if (customer.phone != null && customer.phone!.isNotEmpty) {
        customerContacts.add(customer.phone!);
      }
      if (customer.email != null && customer.email!.isNotEmpty) {
        customerContacts.add(customer.email!);
      }
      if (customer.username != null && customer.username!.isNotEmpty) {
        customerContacts.add(customer.username!);
      }
    }

    return users.where((user) {
      if (user.isCustomer) return false;
      if (user.username != null && customerContacts.contains(user.username)) {
        return false;
      }
      if (user.email != null && customerContacts.contains(user.email)) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        leading: IconButton(
          icon: const Icon(SolarLinearIcons.arrowRight),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: TextField(
          autofocus: true,
          controller: _textController,
          decoration: const InputDecoration(
            hintText: 'بحث...',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.5,
          ),
          textAlign: TextAlign.right,
          textDirection: TextDirection.rtl, // FIX: Proper RTL text direction
          onChanged: (query) {
            _performIndependentSearch(query);
          },
        ),
        centerTitle: true,
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    // Check if we have any results
    final hasUsers = _searchUsers.isNotEmpty;
    final hasInbox =
        _searchConversations.isNotEmpty && _currentQuery.isNotEmpty;
    final hasLibrary =
        _searchLibraryItems.isNotEmpty && _currentQuery.isNotEmpty;
    final hasTasks = _searchTasks.isNotEmpty && _currentQuery.isNotEmpty;
    final hasCustomers =
        _searchCustomers.isNotEmpty && _currentQuery.isNotEmpty;

    final hasAnyResults =
        hasUsers || hasInbox || hasLibrary || hasTasks || hasCustomers;

    final stillLoading =
        _isLoadingUsers ||
        _isLoadingConversations ||
        _isLoadingLibrary ||
        _isLoadingCustomers ||
        _isLoadingTasks;

    if (stillLoading && _currentQuery.isNotEmpty) {
      return const GlobalSearchSkeletonLoader();
    }

    if (!hasAnyResults && _currentQuery.isNotEmpty) {
      return _buildEmptyState(theme, '');
    }

    if (_currentQuery.isEmpty) {
      return _buildEmptyState(theme, '');
    }

    // Filter out users who are also customers to avoid duplicates
    final nonCustomerUsers = _filterNonCustomerUsers(
      _searchUsers,
      _searchCustomers,
    );
    final hasFilteredUsers = nonCustomerUsers.isNotEmpty;

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        // Users Section (only non-customer users)
        if (hasFilteredUsers) ...[
          _buildSectionHeader(
            theme,
            'المستخدمون',
            SolarLinearIcons.usersGroupTwoRounded,
            nonCustomerUsers.length,
          ),
          ...nonCustomerUsers.map((user) => _buildUserTile(theme, user)),
          const SizedBox(height: 8),
        ],

        // Conversations Section
        if (hasInbox) ...[
          _buildSectionHeader(
            theme,
            'المحادثات',
            SolarLinearIcons.chatRoundDots,
            _searchConversations.length,
          ),
          ..._searchConversations
              .take(10)
              .map((conv) => _buildConversationTile(theme, conv)),
          const SizedBox(height: 8),
        ],

        // Tasks Section
        if (hasTasks) ...[
          _buildSectionHeader(
            theme,
            'المهام',
            SolarLinearIcons.listCheck,
            _searchTasks.length,
          ),
          ..._searchTasks.take(10).map((task) => _buildTaskTile(theme, task)),
          const SizedBox(height: 8),
        ],

        // Library Section
        if (hasLibrary) ...[
          _buildSectionHeader(
            theme,
            'المكتبة',
            SolarLinearIcons.book,
            _searchLibraryItems.length,
          ),
          ..._searchLibraryItems
              .take(10)
              .map((item) => _buildLibraryTile(theme, item)),
          const SizedBox(height: 8),
        ],

        // Customers Section
        if (hasCustomers) ...[
          _buildSectionHeader(
            theme,
            'الأشخاص',
            SolarLinearIcons.user,
            _searchCustomers.length,
          ),
          ..._searchCustomers
              .take(10)
              .map((customer) => _buildCustomerTile(theme, customer)),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(
    ThemeData theme,
    String title,
    IconData icon,
    int count,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.hintColor.withValues(alpha: 0.7)),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.hintColor.withValues(alpha: 0.7),
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.hintColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserTile(ThemeData theme, User user) {
    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: user.image != null
            ? Colors.transparent
            : AppColors.primary.withValues(alpha: 0.1),
        backgroundImage: user.image != null
            ? NetworkImage(user.image!.toFullUrl)
            : null,
        child: user.image == null
            ? Text(
                user.displayName[0].toUpperCase(),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              )
            : null,
      ),
      title: Text(
        user.displayName,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: user.username != null
          ? Text(
              '@${user.username}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.primary,
              ),
            )
          : null,
      trailing: user.isCustomer
          ? const Icon(
              SolarLinearIcons.userCheck,
              size: 20,
              color: AppColors.success,
            )
          : null,
      onTap: () {
        Haptics.lightTap();
        _openUserChat(user);
      },
    );
  }

  Widget _buildConversationTile(ThemeData theme, Conversation conversation) {
    final name = conversation.displayName;
    final lastMessage = conversation.displayPreview;

    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
        child: const Icon(
          SolarLinearIcons.chatRoundDots,
          size: 20,
          color: AppColors.primary,
        ),
      ),
      title: Text(
        name,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: lastMessage.isNotEmpty
          ? Text(
              lastMessage,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            )
          : null,
      onTap: () {
        Haptics.lightTap();
        _openConversation(conversation);
      },
    );
  }

  Widget _buildTaskTile(ThemeData theme, TaskModel task) {
    IconData icon;
    Color iconColor;

    if (task.isCompleted) {
      icon = SolarLinearIcons.checkCircle;
      iconColor = AppColors.success;
    } else if (task.isOverdue) {
      icon = SolarLinearIcons.clockCircle;
      iconColor = AppColors.error;
    } else {
      icon = SolarLinearIcons.listCheck;
      iconColor = AppColors.primary;
    }

    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: iconColor.withValues(alpha: 0.1),
        child: Icon(icon, size: 20, color: iconColor),
      ),
      title: Text(
        task.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w500,
          decoration: task.isCompleted ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: task.description?.isNotEmpty == true
          ? Text(
              task.description!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            )
          : null,
      trailing: task.dueDate != null
          ? Text(
              _formatDueDate(task.dueDate!),
              style: theme.textTheme.bodySmall?.copyWith(
                color: task.isOverdue && !task.isCompleted
                    ? AppColors.error
                    : theme.hintColor,
              ),
            )
          : null,
      onTap: () {
        Haptics.lightTap();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => TaskEditScreen(task: task)),
        );
      },
    );
  }

  Widget _buildLibraryTile(ThemeData theme, LibraryItem item) {
    IconData icon;
    switch (item.type) {
      case 'pdf':
        icon = SolarLinearIcons.fileText;
        break;
      case 'image':
        icon = SolarLinearIcons.gallery;
        break;
      case 'video':
        icon = SolarLinearIcons.videocamera;
        break;
      case 'audio':
        icon = SolarLinearIcons.musicNote;
        break;
      default:
        icon = SolarLinearIcons.file;
    }

    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
        child: Icon(icon, size: 20, color: AppColors.primary),
      ),
      title: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(item.type.toUpperCase(), style: theme.textTheme.bodySmall),
      onTap: () {
        Haptics.lightTap();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => NoteEditScreen(item: item)),
        );
      },
    );
  }

  Widget _buildCustomerTile(ThemeData theme, Customer customer) {
    return PremiumCustomerTile(
      customer: customer,
      onTap: () => _openCustomerDetail(customer),
      isLast: false,
      isSelected: false,
      isSelectionMode: false,
    );
  }

  Widget _buildEmptyState(ThemeData theme, String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            SolarLinearIcons.magnifer,
            size: 64,
            color: theme.hintColor.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.hintColor),
          ),
        ],
      ),
    );
  }

  String _formatDueDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(date.year, date.month, date.day);

    final difference = due.difference(today).inDays;

    if (difference == 0) return 'اليوم';
    if (difference == 1) return 'غداً';
    if (difference == -1) return 'أمس';
    if (difference < 0) return 'منذ ${-difference} يوم';
    if (difference <= 7) return 'خلال $difference أيام';

    return '${date.day}/${date.month}/${date.year}';
  }

  void _openUserChat(User user) {
    // Navigate to customer detail screen for all users (customer or not)
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CustomerDetailScreen(
          customer: {
            'id': user.id,
            'name': user.name,
            'username': user.username,
            'email': user.email,
            'image': user.image,
            'is_almudeer_user': true,
          },
        ),
      ),
    );
  }

  void _openConversation(dynamic conversation) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            ConversationDetailScreen(conversation: conversation),
      ),
    );
  }

  void _openCustomerDetail(Customer customer) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CustomerDetailScreen(customer: customer.toJson()),
      ),
    );
  }
}
