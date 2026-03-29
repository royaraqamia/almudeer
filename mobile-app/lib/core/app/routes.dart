import 'package:flutter/material.dart';
import 'package:almudeer_mobile_app/features/auth/presentation/screens/login_screen.dart';
import 'package:almudeer_mobile_app/features/inbox/presentation/screens/inbox_screen.dart';
import 'package:almudeer_mobile_app/features/inbox/presentation/screens/conversation_detail_screen.dart';

import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:almudeer_mobile_app/features/integrations/presentation/screens/telegram_phone_setup_screen.dart';
import 'package:almudeer_mobile_app/features/settings/presentation/screens/settings_screen.dart';
import 'package:almudeer_mobile_app/features/settings/presentation/screens/subscription_screen.dart';
import 'package:provider/provider.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/custom_drawer.dart';
import 'package:almudeer_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:almudeer_mobile_app/features/tasks/presentation/ui/screens/task_list_screen.dart';
import 'package:almudeer_mobile_app/features/tasks/presentation/providers/task_provider.dart';
import 'package:almudeer_mobile_app/features/library/presentation/screens/library_screen.dart';
import 'package:almudeer_mobile_app/features/library/presentation/screens/tools/browser_screen.dart';
import 'package:almudeer_mobile_app/features/library/presentation/screens/tools/tools_screen.dart';

import 'package:almudeer_mobile_app/core/utils/haptics.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';

import 'package:almudeer_mobile_app/features/shared/presentation/widgets/custom_dialog.dart';
import 'package:almudeer_mobile_app/features/customers/presentation/screens/customers_screen.dart';
import 'package:almudeer_mobile_app/features/inbox/presentation/providers/inbox_provider.dart';
import 'package:almudeer_mobile_app/features/library/presentation/providers/library_provider.dart';
import 'package:almudeer_mobile_app/features/customers/presentation/providers/customers_provider.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/animated_toast.dart';
import 'package:almudeer_mobile_app/features/search/presentation/screens/global_search_results_screen.dart';
import 'package:almudeer_mobile_app/features/library/presentation/widgets/library/share_item_dialog.dart';

/// App route definitions
class AppRoutes {
  // Prevent instantiation
  AppRoutes._();

  // Route names
  static const String root = '/';
  static const String login = '/login';
  static const String dashboard = '/dashboard';
  static const String inbox = '/inbox';
  static const String conversationDetail = '/inbox/conversation';

  static const String customers = '/customers';
  static const String customerDetail = '/customers/detail';
  static const String integrations = '/integrations';
  static const String telegramPhoneSetup = '/integrations/telegram-phone-setup';
  static const String settingsRoute = '/settings';
  static const String subscription = '/subscription';
  static const String tasks = '/tasks';
  static const String library = '/library';
  static const String browser = '/browser';

  /// Generate route based on route settings
  static Route<dynamic> generateRoute(RouteSettings routeSettings) {
    switch (routeSettings.name) {
      case root:
        return PageRouteBuilder(
          pageBuilder: (_, _, _) => Container(color: const Color(0xFFE8EEFF)),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        );
      case login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());

      case dashboard:
      case inbox:
        return MaterialPageRoute(
          builder: (_) => const DashboardShell(initialIndex: 0),
        );

      case customers:
        return MaterialPageRoute(
          builder: (_) => const DashboardShell(initialIndex: 3),
        );
      case integrations:
        return MaterialPageRoute(
          builder: (_) => const DashboardShell(initialIndex: 4),
        );
      case tasks:
        return MaterialPageRoute(
          builder: (_) => const DashboardShell(initialIndex: 1),
        );
      case library:
        return MaterialPageRoute(
          builder: (_) => const DashboardShell(initialIndex: 2),
        );
      case telegramPhoneSetup:
        return MaterialPageRoute(
          builder: (_) => const TelegramPhoneSetupScreen(),
        );
      case settingsRoute:
        return MaterialPageRoute(builder: (_) => const SettingsScreen());
      case subscription:
        return MaterialPageRoute(builder: (_) => const SubscriptionScreen());
      case browser:
        final args = routeSettings.arguments as Map<String, dynamic>?;
        final initialUrl = args?['initialUrl'] as String?;
        return MaterialPageRoute(
          builder: (_) => BrowserScreen(initialUrl: initialUrl),
        );

      default:
        // Default to root to avoid initial flash
        return PageRouteBuilder(
          pageBuilder: (_, _, _) => Container(color: const Color(0xFFE8EEFF)),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        );
    }
  }
}

/// Dashboard shell with bottom navigation
class DashboardShell extends StatefulWidget {
  final int initialIndex;

  const DashboardShell({super.key, this.initialIndex = 0});

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  late int _currentIndex;
  late AuthProvider _authProvider;

  // App bar constants for pixel-perfect UI
  static const double _iconPadding = 12.0;
  static const double _touchTargetRadius = 24.0;
  static const double _iconSize = 24.0;
  static const double _bottomBorderAlpha = 0.06;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _authProvider = context.read<AuthProvider>();

    // Listen to Auth changes for global redirection (e.g., on logout or account removal)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _authProvider.addListener(_handleAuthStateChange);
      }
    });

    // Fetch notifications for badge
    // Note: Version check is now handled in SplashScreen before authentication
  }

  @override
  void dispose() {
    // Remove listener to prevent memory leaks and redundant navigation calls
    _authProvider.removeListener(_handleAuthStateChange);
    super.dispose();
  }

  void _openGlobalSearch() {
    Haptics.lightTap();
    // Navigate directly to global search results screen
    // No need to activate search mode in app bar
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const GlobalSearchResultsScreen(initialQuery: ''),
      ),
    );
  }

  void _handleAuthStateChange() {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();

    // If state becomes unauthenticated, redirect to Login
    // This handles both explicit logout and removing the last saved account
    if (auth.state == AuthState.unauthenticated) {
      // CRITICAL: Remove listener immediately to prevent infinite loops
      // if LoginScreen (appearing next) triggers notifications
      _authProvider.removeListener(_handleAuthStateChange);

      debugPrint(
        '[DashboardShell] Auth changed to Unauthenticated - Navigating to Login',
      );
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final auth = context.watch<AuthProvider>();

    // Guard: If we are unauthenticated, don't build the expensive dashboard widgets.
    // This stops redundant rebuilds during the logout transition frames.
    if (auth.state == AuthState.unauthenticated) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Using a key based on the accountKey forces a complete rebuild of the dashboard
    // and its children (Inbox, Tasks, etc.) whenever the active account changes.
    // This ensures all screens re-run their initState and fetch fresh data.
    return Scaffold(
      key: ValueKey('dashboard_${auth.accountKey}'),
      drawer: CustomDrawer(
        currentIndex: _currentIndex,
        onIndexChanged: (index) {
          setState(() => _currentIndex = index);
        },
      ),
      extendBody: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Consumer4<InboxProvider, LibraryProvider, CustomersProvider, TaskProvider>(
          builder: (context, inbox, library, customers, tasks, _) {
            final isInboxSelectionMode =
                _currentIndex == 0 && inbox.isSelectionMode;
            final isTasksSelectionMode =
                _currentIndex == 1 && tasks.isSelectionMode;
            final isLibrarySelectionMode =
                _currentIndex == 2 && library.isSelectionMode;
            final isCustomersSelectionMode =
                _currentIndex == 3 && customers.isSelectionMode;
            final isSelectionMode =
                isInboxSelectionMode ||
                isTasksSelectionMode ||
                isLibrarySelectionMode ||
                isCustomersSelectionMode;

            return Stack(
              alignment: Alignment.bottomCenter,
              children: [
                AppBar(
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  backgroundColor: Colors.transparent,
                  leading: isSelectionMode
                      ? Semantics(
                          label: 'ط¥ظ„ط؛ط§ط،',
                          button: true,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(
                              _touchTargetRadius,
                            ),
                            onTap: () {
                              if (isSelectionMode) {
                                if (isInboxSelectionMode) {
                                  inbox.toggleSelectionMode(false);
                                } else if (isTasksSelectionMode) {
                                  tasks.clearSelection();
                                } else if (isLibrarySelectionMode) {
                                  library.clearSelection();
                                } else if (isCustomersSelectionMode) {
                                  customers.clearSelection();
                                }
                              }
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(_iconPadding),
                              child: Icon(
                                SolarLinearIcons.arrowRight,
                                size: _iconSize,
                              ),
                            ),
                          ),
                        )
                      : Builder(
                          builder: (context) => Semantics(
                            label: 'ط§ظ„ظ‚ط§ط¦ظ…ط©',
                            button: true,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                _touchTargetRadius,
                              ),
                              onTap: () {
                                Haptics.lightTap();
                                Scaffold.of(context).openDrawer();
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(_iconPadding),
                                child: Icon(
                                  SolarLinearIcons.hamburgerMenu,
                                  size: _iconSize,
                                ),
                              ),
                            ),
                          ),
                        ),
                  title: Text(
                    isSelectionMode
                        ? '${isInboxSelectionMode ? inbox.selectedCount : (isTasksSelectionMode ? tasks.selectedCount : (isLibrarySelectionMode ? library.selectedCount : customers.selectedCount))}'
                        : _getPageTitle(_currentIndex),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.5,
                    ),
                  ),
                  centerTitle: true,
                  actions: [
                    if (isSelectionMode) ...[
                      if ((isInboxSelectionMode && inbox.selectedCount > 0) ||
                          (isTasksSelectionMode && tasks.selectedCount > 0) ||
                          (isLibrarySelectionMode &&
                              library.selectedCount > 0) ||
                          (isCustomersSelectionMode &&
                              customers.selectedCount > 0)) ...[
                        if (isLibrarySelectionMode && library.selectedCount > 0)
                          Semantics(
                            label: 'ظ…ط´ط§ط±ظƒط© ظ…ط¹ ظ…ط³طھط®ط¯ظ…ظٹظ†',
                            button: true,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                _touchTargetRadius,
                              ),
                              onTap: () =>
                                  _bulkShareLibraryItemsWithUsers(context),
                              child: const Padding(
                                padding: EdgeInsets.all(_iconPadding),
                                child: Icon(
                                  SolarLinearIcons.usersGroupRounded,
                                  size: _iconSize,
                                ),
                              ),
                            ),
                          ),
                        if (isTasksSelectionMode && tasks.selectedCount > 0)
                          Semantics(
                            label: 'ط¥ط³ظ†ط§ط¯',
                            button: true,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                _touchTargetRadius,
                              ),
                              onTap: () => _bulkAssignTasks(context),
                              child: const Padding(
                                padding: EdgeInsets.all(_iconPadding),
                                child: Icon(
                                  SolarLinearIcons.usersGroupRounded,
                                  size: _iconSize,
                                ),
                              ),
                            ),
                          ),
                      ],
                      IconButton(
                        icon: const Icon(
                          SolarLinearIcons.trashBinMinimalistic,
                          color: AppColors.error,
                        ),
                        onPressed: () async {
                          final message = isInboxSelectionMode
                              ? 'ظ‡ظ„ ط£ظ†طھ ظ…طھط£ظƒظ‘ظگط¯ ظ…ظ† ط§ظ„ط­ط°ظپطں'
                              : (isTasksSelectionMode
                                    ? 'ظ‡ظ„ ط£ظ†طھ ظ…طھط£ظƒظ‘ظگط¯ ظ…ظ† ط­ط°ظپ ط§ظ„ظ…ظ‡ط§ظ… ط§ظ„ظ…ط®طھط§ط±ط©طں'
                                    : (isLibrarySelectionMode
                                          ? 'ظ‡ظ„ ط£ظ†طھ ظ…طھط£ظƒظ‘ظگط¯ ظ…ظ† ط§ظ„ط­ط°ظپطں'
                                          : 'ظ‡ظ„ ط£ظ†طھ ظ…طھط£ظƒظ‘ظگط¯ ظ…ظ† ط§ظ„ط­ط°ظپطں'));

                          final confirmed = await CustomDialog.show(
                            context,
                            title:
                                message, // We use the generated message as the title
                            message: '',
                            type: DialogType.error,
                            confirmText: 'ط­ط°ظپ',
                            cancelText: 'ط¥ظ„ط؛ط§ط،',
                          );

                          if (confirmed == true && context.mounted) {
                            if (isInboxSelectionMode) {
                              inbox.bulkDelete();
                            } else if (isTasksSelectionMode) {
                              tasks.bulkDelete();
                              AnimatedToast.success(
                                context,
                                'طھظ… ط­ط°ظپ ط§ظ„ظ…ظ‡ط§ظ… ط¨ظ†ط¬ط§ط­',
                              );
                            } else if (isLibrarySelectionMode) {
                              library.deleteSelected();
                            } else if (isCustomersSelectionMode) {
                              customers.bulkDelete();
                            }
                          }
                        },
                        tooltip: 'ط­ط°ظپ',
                      ),
                    ] else ...[
                      Semantics(
                        label: 'ط¨ط­ط«',
                        button: true,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(
                            _touchTargetRadius,
                          ),
                          onTap: _openGlobalSearch,
                          child: const Padding(
                            padding: EdgeInsets.all(_iconPadding),
                            child: Icon(
                              SolarLinearIcons.magnifer,
                              size: _iconSize,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                  ],
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 1,
                    color: theme.dividerColor.withValues(
                      alpha: _bottomBorderAlpha,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Tablet split-view for width >= 900px
          final isTablet = constraints.maxWidth >= 900;

          if (isTablet && _currentIndex == 0) {
            // Split view for inbox: list on left, detail on right
            return Row(
              children: [
                // Inbox list (350px fixed width)
                Container(
                  width: 350,
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.1),
                        width: 1,
                      ),
                    ),
                  ),
                  child: InboxScreen(
                    key: ValueKey('inbox_${auth.accountKey}'),
                    onNavigateToCustomers: () {
                      setState(() => _currentIndex = 3);
                    },
                  ),
                ),
                // Conversation detail (expanded)
                Expanded(
                  child: Consumer<InboxProvider>(
                    builder: (context, inbox, _) {
                      final selectedConversation =
                          inbox.conversations.isNotEmpty
                          ? inbox.conversations.first
                          : null;

                      if (selectedConversation == null) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                SolarLinearIcons.chatRoundDots,
                                size: 64,
                                color: theme.hintColor.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'ط§ط®طھط± ظ…ط­ط§ط¯ط«ط© ظ„ظ„ط¨ط¯ط،',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.hintColor,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ConversationDetailScreen(
                        key: ValueKey('detail_${selectedConversation.id}'),
                        conversation: selectedConversation,
                      );
                    },
                  ),
                ),
              ],
            );
          }

          // Mobile layout or other tabs
          return IndexedStack(
            index: _currentIndex,
            children: [
              // Each screen has a key with accountKey to force rebuild on account switch
              InboxScreen(
                key: ValueKey('inbox_${auth.accountKey}'),
                onNavigateToCustomers: () {
                  setState(() => _currentIndex = 3);
                },
              ),
              TaskListScreen(key: ValueKey('tasks_${auth.accountKey}')),
              LibraryScreen(key: ValueKey('library_${auth.accountKey}')),
              CustomersScreen(key: ValueKey('customers_${auth.accountKey}')),
              ToolsScreen(key: ValueKey('tools_${auth.accountKey}')),
            ],
          );
        },
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(
              color: theme.dividerColor.withValues(alpha: _bottomBorderAlpha),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? AppColors.shadowPrimaryDark
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Consumer<InboxProvider>(
                  builder: (context, inbox, _) {
                    return _buildPremiumNavItem(
                      0,
                      SolarLinearIcons.letter,
                      SolarLinearIcons.letter,
                      'ط§ظ„ظ…ط­ط§ط¯ط«ط§طھ',
                      badgeCount: inbox.totalUnreadCount,
                    );
                  },
                ),
                _buildPremiumNavItem(
                  1,
                  SolarLinearIcons.checkCircle,
                  SolarLinearIcons.checkCircle,
                  'ط§ظ„ظ…ظ‡ط§ظ…',
                ),
                _buildPremiumNavItem(
                  2,
                  SolarLinearIcons.widget,
                  SolarLinearIcons.widget,
                  'ط§ظ„ظ…ظƒطھط¨ط©',
                  svgAsset: 'assets/icons/library.svg',
                ),
                _buildPremiumNavItem(
                  3,
                  SolarLinearIcons.usersGroupTwoRounded,
                  SolarLinearIcons.usersGroupTwoRounded,
                  'ط§ظ„ظ…ط¬طھظ…ط¹',
                ),
                _buildPremiumNavItem(
                  4,
                  SolarLinearIcons.widget,
                  SolarLinearIcons.widget,
                  'ط§ظ„ط£ط¯ظˆط§طھ',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _animationDuration = Duration(milliseconds: 300);

  Future<void> _bulkAssignTasks(BuildContext context) async {
    final tasksProvider = context.read<TaskProvider>();
    final selectedTasks = tasksProvider.tasks
        .where((t) => tasksProvider.selectedIds.contains(t.id))
        .toList();

    if (selectedTasks.isEmpty) return;

    // Use ShareItemDialog for task assignment (assign to Almudeer users)
    // Pass task IDs as a comma-separated string
    final taskIds = selectedTasks.map((t) => t.id).join(',');
    ShareItemDialog.show(
      context,
      itemId: 0, // Not used for tasks
      itemTitle: selectedTasks.length == 1
          ? selectedTasks.first.title
          : '${selectedTasks.length} ظ…ظ‡ط§ظ…',
      taskIds: taskIds,
    );

    // Clear selection after showing share dialog
    tasksProvider.clearSelection();

    if (selectedTasks.length > 1) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (context.mounted) {
          AnimatedToast.info(context, 'ط³ظٹطھظ… ط¥ط³ظ†ط§ط¯ ط§ظ„ظ…ظ‡ط§ظ… ظ„ظ„ظ…ط³طھط®ط¯ظ…ظٹظ† ط§ظ„ظ…ط­ط¯ط¯ظٹظ†');
        }
      });
    }
  }

  Future<void> _bulkShareLibraryItemsWithUsers(BuildContext context) async {
    final library = context.read<LibraryProvider>();
    final authProvider = context.read<AuthProvider>();
    final selectedItems = library.items
        .where((item) => library.selectedIds.contains(item.id))
        .toList();

    if (selectedItems.isEmpty) return;

    // Check if user owns all selected items
    final isOwner = selectedItems.every(
      (item) => item.userId == authProvider.userInfo?.licenseId?.toString(),
    );

    if (!isOwner) {
      library.clearSelection();
      if (context.mounted) {
        AnimatedToast.warning(context, 'ظ„ط§ ظٹظ…ظƒظ†ظƒ ظ…ط´ط§ط±ظƒط© ط¹ظ†ط§طµط± ظ„ط§ طھظ…ظ„ظƒظ‡ط§');
      }
      return;
    }

    // Show share dialog for bulk library items
    // Pass item IDs as a comma-separated string
    final itemIds = selectedItems.map((item) => item.id.toString()).join(',');
    ShareItemDialog.show(
      context,
      itemId: selectedItems
          .first
          .id, // First item ID (required but not used for bulk)
      itemTitle: selectedItems.length == 1
          ? selectedItems.first.title
          : '${selectedItems.length} ط¹ظ†ط§طµط±',
      libraryItemIds: itemIds, // NEW: Pass all item IDs for bulk sharing
    );

    // Note: Selection is cleared inside ShareItemDialog after successful share
  }

  String _getPageTitle(int index) {
    switch (index) {
      case 0:
        return 'ط§ظ„ظ…ط­ط§ط¯ط«ط§طھ';
      case 1:
        return 'ط§ظ„ظ…ظ‡ط§ظ…';
      case 2:
        return 'ط§ظ„ظ…ظƒطھط¨ط©';
      case 3:
        return 'ط§ظ„ظ…ط¬طھظ…ط¹';
      case 4:
        return 'ط§ظ„ط£ط¯ظˆط§طھ';
      default:
        return 'ط§ظ„ظ…ط¯ظٹط±';
    }
  }

  Widget _buildPremiumNavItem(
    int index,
    IconData icon,
    IconData activeIcon,
    String label, {
    String? svgAsset,
    int badgeCount = 0,
  }) {
    final isSelected = _currentIndex == index;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final activeColor = isDark
        ? AppColors.activeStateDark
        : AppColors.activeStateLight;
    final pillColor = activeColor.withValues(alpha: 0.12);

    return Semantics(
      label: label,
      button: true,
      selected: isSelected,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () {
            if (_currentIndex != index) {
              Haptics.lightTap();
              setState(() => _currentIndex = index);
            }
          },
          borderRadius: BorderRadius.circular(12),
          overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.pressed)) {
              return activeColor.withValues(alpha: 0.12);
            }
            if (states.contains(WidgetState.hovered)) {
              return activeColor.withValues(alpha: _bottomBorderAlpha);
            }
            if (states.contains(WidgetState.focused)) {
              return activeColor.withValues(alpha: 0.16);
            }
            return null;
          }),
          child: AnimatedContainer(
            duration: _animationDuration,
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            constraints: const BoxConstraints(minWidth: 64, minHeight: 48),
            decoration: BoxDecoration(
              color: isSelected ? pillColor : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: AnimatedScale(
              scale: isSelected ? 1.05 : 1.0,
              duration: _animationDuration,
              curve: Curves.easeOutCubic,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (svgAsset != null)
                        SvgPicture.asset(
                          svgAsset,
                          colorFilter: ColorFilter.mode(
                            isSelected ? activeColor : theme.hintColor,
                            BlendMode.srcIn,
                          ),
                          width: 24,
                          height: 24,
                        )
                      else
                        Icon(
                          isSelected ? activeIcon : icon,
                          color: isSelected ? activeColor : theme.hintColor,
                          size: _iconSize,
                        ),
                      if (badgeCount > 0)
                        Positioned(
                          top: -1,
                          right: -7,
                          child: AnimatedContainer(
                            duration: _animationDuration,
                            curve: Curves.easeOutBack,
                            padding: EdgeInsets.symmetric(
                              horizontal: badgeCount > 99 ? 3.5 : 4,
                              vertical: 0,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: theme.scaffoldBackgroundColor,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFFEF4444,
                                  ).withValues(alpha: 0.4),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 17,
                              minHeight: 17,
                            ),
                            child: Center(
                              child: Text(
                                badgeCount > 99 ? '99+' : '$badgeCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  height: 1,
                                  letterSpacing: -0.3,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: isSelected ? activeColor : theme.hintColor,
                      height: 1.3,
                      letterSpacing: -0.2,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
