// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../core/theme/app_theme.dart';
import '../core/constants/colors.dart';
import '../core/constants/animations.dart';
import '../core/services/permission_service.dart';
import '../core/services/deep_link_service.dart';
import '../presentation/providers/auth_provider.dart';
import '../presentation/providers/inbox_provider.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import '../core/services/notification_navigator.dart';
import '../core/services/offline_sync_service.dart';
import '../core/services/websocket_service.dart';
import '../presentation/providers/customers_provider.dart';
import '../presentation/providers/conversation_detail_provider.dart';
import '../presentation/providers/library_provider.dart';
import '../presentation/providers/settings_provider.dart';
import '../presentation/providers/athkar_provider.dart';
import '../presentation/providers/quran_provider.dart';
import '../presentation/providers/transfer_provider.dart';
import '../presentation/providers/message_input_provider.dart';
import '../features/tasks/providers/task_provider.dart';
import '../presentation/providers/calculator_provider.dart';
import '../presentation/screens/login/login_screen.dart';
import '../core/localization/app_localizations.dart';
import 'routes.dart';

import '../features/tasks/services/task_alarm_service.dart';

/// Root application widget with theme and routing
/// 
/// Apple HIG Compliance:
/// - Respects system Reduce Motion preferences
/// - Supports Dynamic Type (text scaling)
/// - Proper accessibility support
class AppRoot extends StatefulWidget {
  final String initialRoute;

  const AppRoot({super.key, required this.initialRoute});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  bool _isInitializing = true;
  DateTime? _lastResumeTime;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final DeepLinkService _deepLinkService = DeepLinkService();
  StreamSubscription<DeepLinkResult>? _deepLinkSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _performAppInitialization();

      context.read<OfflineSyncService>().addListener(_onSyncStatusChange);

      context.read<AuthProvider>().setAccountSwitchCallback(() {
        _handleAccountSwitch();
      });

      final authProvider = context.read<AuthProvider>();
      _deepLinkService.init(authProvider);
      _deepLinkSubscription = _deepLinkService.resultStream.listen((result) {
        _deepLinkService.showResultToast(result);
      });
    });
  }

  @override
  void dispose() {
    try {
      context.read<OfflineSyncService>().removeListener(_onSyncStatusChange);
    } catch (_) {}

    _deepLinkSubscription?.cancel();
    _deepLinkService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Check for updates when app comes back to foreground
    if (state == AppLifecycleState.resumed) {
      debugPrint('[AppRoot] App Resumed');

      // Debounce: Skip if resumed within last 5 seconds to prevent cascade
      final now = DateTime.now();
      if (_lastResumeTime != null &&
          now.difference(_lastResumeTime!).inSeconds < 5) {
        debugPrint('[AppRoot] Debounced - skipping duplicate resume');
        return;
      }
      _lastResumeTime = now;

      // Security Check: Only sync data if authenticated
      final auth = context.read<AuthProvider>();
      if (!auth.isAuthenticated) {
        debugPrint(
          '[AppRoot] Unauthenticated - Skipping Sync',
        );
        return;
      }

      debugPrint(
        '[AppRoot] Authenticated - Triggering Sync & Additional Checks',
      );

      _resetBadgeCount();

      // Staggered Execution: Spread tasks across frames to avoid ANR
      // T+100ms: Kick off sync
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) context.read<OfflineSyncService>().syncAll();
      });

      // T+800ms: Library specific resume logic
      // Apple HIG: Staggered loading for smooth UX
      Future.delayed(AppAnimations.extended, () {
        if (mounted) context.read<LibraryProvider>().onAppResume();
      });

      // T+900ms: Check athkar daily reset
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) context.read<AthkarProvider>().checkAndResetIfNeeded();
      });

      // T+2500ms: Ensure WebSocket Connected (Network)
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted) context.read<WebSocketService>().connect();
      });
    }
  }

  void _onSyncStatusChange() {
    if (!mounted) return;
    final syncService = context.read<OfflineSyncService>();

    // When sync completes successfully, refresh UI providers to show new data
    if (syncService.status == SyncStatus.success) {
      debugPrint('[AppRoot] Sync Success - Refreshing UI Providers');

      // Use microtask to yield to UI thread and avoid blocking
      Future.microtask(() {
        if (!mounted) return;

        // Silent refresh for Inbox (New Messages)
        context.read<InboxProvider>().refresh();

        // Silent refresh for Customers - triggerSync:false to avoid re-syncing
        context.read<CustomersProvider>().loadCustomers(
          refresh: true,
          triggerSync: false, // Data already synced, just refresh UI
        );

        // Refresh active conversation if open
        final conversationProvider = context.read<ConversationDetailProvider>();
        if (conversationProvider.senderContact != null) {
          conversationProvider.loadConversation(
            conversationProvider.senderContact!,
            fresh: true,
          );
        }
      });
    }
  }

  /// Handle account switch by resetting all data providers and reloading fresh data
  void _handleAccountSwitch() {
    if (!mounted) return;

    debugPrint('[AppRoot] Account switched - Resetting all providers');

    // 1. Reset ALL data providers to clear old account's data
    // Order matters: Reset first, then reload
    context.read<InboxProvider>().reset();
    context.read<CustomersProvider>().reset();
    context.read<LibraryProvider>().reset();
    context.read<SettingsProvider>().reset();
    context.read<TaskProvider>().reset();
    context.read<ConversationDetailProvider>().reset();
    context.read<CalculatorProvider>().reset();
    context.read<TransferProvider>().reset();
    context.read<MessageInputProvider>().reset();

    // Force WebSocket reconnection with the new account's license key
    context.read<WebSocketService>().forceReconnect();

    // 2. Reload data for the new account
    final auth = context.read<AuthProvider>();
    final licenseKey = auth.userInfo?.licenseKey;

    // Set license key for providers that need it
    context.read<CalculatorProvider>().setUserId(licenseKey);

    // Trigger data loading for all features
    // Using addPostFrameCallback to ensure UI has updated after reset
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      debugPrint('[AppRoot] Loading fresh data for new account');

      // Load conversations (inbox) - no filters, all chats in unified list
      context.read<InboxProvider>().loadConversations();

      // Load customers
      context.read<CustomersProvider>().loadCustomers();

      // Load library items (notes, files, audio, links)
      context.read<LibraryProvider>().fetchItems(refresh: true);

      // Load settings and preferences
      context.read<SettingsProvider>().loadSettings();

      // Load tasks
      context.read<TaskProvider>().loadTasks();

      // Load Quran data (tafsir and translation)
      context.read<QuranProvider>().loadTafsir();
      context.read<QuranProvider>().loadTranslation();

      // Load Athkar (daily reminders)
      context.read<AthkarProvider>().checkAndResetIfNeeded();

      debugPrint('[AppRoot] All providers reloaded for new account');
    });
  }

  /// Reset iOS badge count when app is opened
  Future<void> _resetBadgeCount() async {
    if (!Platform.isIOS) return;

    try {
      // Use flutter_local_notifications to reset badge
      final iosPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();

      if (iosPlugin != null) {
        // Cancel all displayed notifications to reset badge
        await _localNotifications.cancelAll();
      }

      debugPrint('iOS badge count reset');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to reset iOS badge: $e');
      }
    }
  }

  /// Perform all startup initialization previously handled by SplashScreen
  Future<void> _performAppInitialization() async {
    if (!mounted) return;

    try {
      final authProvider = context.read<AuthProvider>();

      // 1. Critical Init Only (Auth) - Fast!
      await authProvider.init();

      // Request Critical Permissions (Storage) - essential for app function
      await PermissionService().requestManageExternalStorage();

      // Initialize Task Alarm Service
      await TaskAlarmService().initialize();

      if (!mounted) return;

      // 2. Determine final destination immediately
      if (authProvider.isAuthenticated) {
        context.read<CalculatorProvider>().setUserId(
          authProvider.userInfo?.licenseKey,
        );
        // Load all conversations - no filters, unified list
        context.read<InboxProvider>().loadConversations();

        // Use no-transition for the very first navigation to avoid flash
        navigatorKey.currentState?.pushAndRemoveUntil(
          PageRouteBuilder(
            pageBuilder: (_, _, _) => const DashboardShell(initialIndex: 0),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            settings: const RouteSettings(name: AppRoutes.dashboard),
          ),
          (route) => false,
        );
      } else {
        // Use no-transition for the very first navigation to avoid flash
        navigatorKey.currentState?.pushAndRemoveUntil(
          PageRouteBuilder(
            pageBuilder: (_, _, _) => const LoginScreen(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            settings: const RouteSettings(name: AppRoutes.login),
          ),
          (route) => false,
        );
      }

      // 3. Success! Remove native splash after a short delay to ensure target page has rendered
      // This eliminates the "background flash" because Navigator will have switched routes
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _isInitializing = false);
          FlutterNativeSplash.remove();
        }
      });
    } catch (e) {
      debugPrint('[AppRoot] Init Error: $e');
      setState(() => _isInitializing = false);
      FlutterNativeSplash.remove();
      // Fallback to login
      navigatorKey.currentState?.pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (_, _, _) => const LoginScreen(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          settings: const RouteSettings(name: AppRoutes.login),
        ),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'المدير',
      debugShowCheckedModeBanner: false,

      // Theme configuration - always dark mode
      themeMode: ThemeMode.dark,
      darkTheme: AppTheme.dark,

      // RTL and Arabic locale
      // Using 'ar_AE' (UAE) to force Western numerals (0, 1, 2) but keep standard Arabic months (يناير)
      locale: const Locale('ar', 'AE'),
      supportedLocales: const [
        Locale('ar', 'AE'),
        Locale('ar', 'SA'),
        Locale('ar', 'SY'),
      ],
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        const AppLocalizationsDelegate(),
      ],

      // Navigation - use home instead of initialRoute for reliable initial build
      // Programmatically navigate after init to actual destination
      home: Container(color: AppColors.backgroundDark),
      onGenerateRoute: AppRoutes.generateRoute,
      builder: (context, child) {
        // Apple HIG: Respect system Reduce Motion preference
        // Check if user prefers reduced motion and apply accordingly
        final mediaQuery = MediaQuery.of(context);
        final reduceMotion = mediaQuery.disableAnimations || mediaQuery.accessibleNavigation;
        
        // Apple HIG: Support Dynamic Type (text scaling)
        // Scale text based on system accessibility settings
        final textScaler = MediaQuery.textScalerOf(context);

        child = MediaQuery(
          data: mediaQuery.copyWith(
            // Reduce motion: Disable animations if user prefers
            disableAnimations: reduceMotion,
            // Dynamic Type: Respect system text scale
            textScaler: textScaler,
          ),
          child: child ?? const SizedBox.shrink(),
        );

        // Apply RTL directionality
        child = Directionality(
          textDirection: TextDirection.rtl,
          child: child,
        );

        // Splash overlay during initialization
        if (_isInitializing) {
          return Stack(
            children: [
              child,
              Container(
                color: AppColors.backgroundDark,
              ),
            ],
          );
        }

        return child;
      },
    );
  }
}
