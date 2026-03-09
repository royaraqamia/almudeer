import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';
import 'package:logging/logging.dart' as logging;
import 'app/app.dart';
import 'app/routes.dart';
import 'presentation/providers/auth_provider.dart';
import 'presentation/providers/inbox_provider.dart';
import 'presentation/providers/conversation_detail_provider.dart';
import 'presentation/providers/message_input_provider.dart';
import 'presentation/providers/customers_provider.dart';
import 'package:firebase_core/firebase_core.dart';
// Active Sessions screen removed
import 'services/fcm_service.dart';

import 'presentation/providers/settings_provider.dart';
import 'features/tasks/providers/task_provider.dart';
import 'presentation/providers/audio_player_provider.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:almudeer_mobile_app/core/services/background_sync_service.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/pending_operations_service.dart';
import 'core/services/offline_sync_service.dart';
import 'core/services/websocket_service.dart';
import 'core/services/sharing_service.dart';

import 'presentation/providers/library_provider.dart';
import 'presentation/providers/calculator_provider.dart';
import 'presentation/providers/transfer_provider.dart';
import 'presentation/providers/global_search_provider.dart';
import 'presentation/providers/users_provider.dart';
import 'features/tasks/services/task_alarm_service.dart';
// SessionProvider removed

import 'presentation/providers/athkar_provider.dart';
import 'presentation/providers/quran_provider.dart';
import 'core/services/browser_download_manager.dart';
import 'core/services/media_cache_manager.dart';  // P3-15 FIX: Add import
import 'services/athkar_reminder_service.dart';
import 'core/models/browser_tab_persistence.dart';

void main() async {
  // P3-1 FIX: Silence ALL logs in production release builds
  if (kReleaseMode) {
    Logger.level = Level.off;
    logging.Logger.root.level = logging.Level.OFF;
    // Override debugPrint to prevent any accidental logs in production
    debugPrint = (String? message, {int? wrapWidth}) {};
  } else {
    // Development: keep current logging
    Logger.level = Level.off;
    logging.Logger.root.level = logging.Level.OFF;
  }

  // Ensure Flutter bindings are initialized
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // Preserve native splash screen until we explicitly remove it
  // This ensures seamless transition without flash
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Set preferred orientations (portrait only for mobile) - fast, non-blocking
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // System UI overlay style will be handled dynamically by the app theme in AppRoot

  // Initialize offline services early
  // Pre-initialize Hive (required for PendingOperationsService)
  // This is done here once to avoid redundant init calls
  await Hive.initFlutter();
  Hive.registerAdapter(BrowserTabPersistenceAdapter());

  final connectivityService = ConnectivityService();
  final pendingOperationsService = PendingOperationsService();
  final offlineSyncService = OfflineSyncService(
    connectivityService: connectivityService,
    pendingOperationsService: pendingOperationsService,
  );

  final webSocketService = WebSocketService();

  // Initialize services (fire and forget to not block UI)
  // OfflineSyncService.initialize() will be called lazily when needed
  connectivityService.initialize();
  pendingOperationsService.initialize();

  // Initialize background services
  BackgroundSyncService().initialize();

  // Initialize Task Alarm Service
  try {
    await TaskAlarmService().initialize();
    debugPrint('TaskAlarmService initialized');
  } catch (e) {
    debugPrint('TaskAlarmService initialization error: $e');
  }

  // Initialize sharing service to handle "Open with" and "Share" intents
  SharingService().initialize();

  // Initialize Browser Download Manager
  await BrowserDownloadManager().init();

  // Initialize Athkar Reminders
  try {
    final athkarReminderService = AthkarReminderService();
    await athkarReminderService.initialize();
    await athkarReminderService.scheduleReminders();
  } catch (e) {
    debugPrint('Athkar reminders error: $e');
  }

  // P3-15 FIX: Perform startup cache cleanup for attachments
  // Run in background to avoid blocking startup
  MediaCacheManager().performStartupCleanup().then((_) {
    debugPrint('Startup cache cleanup completed');
  }).catchError((e) {
    debugPrint('Startup cache cleanup error: $e');
  });

  // Relocated from SplashScreen: Initialize core services early
  try {
    await Firebase.initializeApp();
    // FCM initialization (heavy, but needed for tokens)
    // FCM initialization (heavy, but needed for tokens)
    // Run in background to avoid blocking startup
    FcmService()
        .initialize()
        .then((_) {
          debugPrint('FCM initialized in background');
        })
        .catchError((e) {
          debugPrint('FCM background initialization error: $e');
        });
  } catch (e) {
    debugPrint('Early initialization error in main: $e');
  }

  runApp(
    AlMudeerApp(
      initialRoute:
          AppRoutes.root, // Start from root placeholder, AppRoot will decide
      connectivityService: connectivityService,
      pendingOperationsService: pendingOperationsService,
      offlineSyncService: offlineSyncService,
      webSocketService: webSocketService,
    ),
  );
}

/// Main application widget with provider setup
class AlMudeerApp extends StatelessWidget {
  final String initialRoute;
  final ConnectivityService connectivityService;
  final PendingOperationsService pendingOperationsService;
  final OfflineSyncService offlineSyncService;
  final WebSocketService webSocketService;

  const AlMudeerApp({
    super.key,
    required this.initialRoute,
    required this.connectivityService,
    required this.pendingOperationsService,
    required this.offlineSyncService,
    required this.webSocketService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Offline services (initialized first for other providers to use)
        ChangeNotifierProvider.value(value: connectivityService),
        ChangeNotifierProvider.value(value: pendingOperationsService),
        ChangeNotifierProvider.value(value: offlineSyncService),
        Provider.value(value: webSocketService),
        // Auth provider
        ChangeNotifierProvider(
          create: (_) =>
              AuthProvider(webSocketService: webSocketService)..init(),
        ),
        // Inbox provider
        ChangeNotifierProvider(
          create: (_) => InboxProvider(webSocketService: webSocketService),
        ),
        // Customers provider
        ChangeNotifierProvider(
          create: (_) => CustomersProvider(webSocketService: webSocketService),
        ),
        // Task provider
        ChangeNotifierProvider(
          create: (_) => TaskProvider(webSocketService: webSocketService),
        ),

        // Settings provider
        ChangeNotifierProvider(
          create: (_) => SettingsProvider()..loadSettings(),
        ),

        // Audio Player Provider
        ChangeNotifierProvider(create: (_) => AudioPlayerProvider()),

        // Conversation Detail provider
        ChangeNotifierProvider(
          create: (_) =>
              ConversationDetailProvider(webSocketService: webSocketService),
        ),
        // Message Input provider
        ChangeNotifierProvider(create: (_) => MessageInputProvider()),
        // Library Provider
        ChangeNotifierProvider(
          create: (context) => LibraryProvider(webSocketService: webSocketService),
        ),
        // Calculator Provider
        ChangeNotifierProvider(create: (_) => CalculatorProvider()),
        // Transfer Provider (for Send & Receive feature)
        ChangeNotifierProvider(create: (_) => TransferProvider()),
        // Session Provider
        // Session Provider removed

        // Athkar Provider
        ChangeNotifierProvider(
          create: (_) => AthkarProvider(syncService: offlineSyncService),
        ),
        // Quran Provider
        ChangeNotifierProvider(
          create: (_) => QuranProvider(syncService: offlineSyncService)..init(),
        ),
        // Global Search Provider
        ChangeNotifierProvider(create: (_) => GlobalSearchProvider()),
        // Users Provider
        ChangeNotifierProvider(create: (_) => UsersProvider()),
      ],
      child: AppRoot(initialRoute: initialRoute),
    );
  }
}
