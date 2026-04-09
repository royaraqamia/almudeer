import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';
import 'package:logging/logging.dart' as logging;

import 'core/app/app.dart';
import 'core/app/routes.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/inbox/presentation/providers/inbox_provider.dart';
import 'features/inbox/presentation/providers/conversation_detail_provider.dart';
import 'features/inbox/presentation/providers/message_input_provider.dart';
import 'features/customers/presentation/providers/customers_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
// Active Sessions screen removed
import 'features/notifications/data/services/fcm_service_mobile.dart' if (dart.library.js_interop) 'features/notifications/data/services/fcm_service_web.dart';
import 'features/tasks/presentation/providers/task_provider.dart';
import 'features/viewer/presentation/providers/audio_player_provider.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:almudeer_mobile_app/core/services/background_sync_service.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/pending_operations_service.dart';
import 'core/services/offline_sync_service.dart';
import 'core/services/websocket_service.dart';
import 'core/services/sharing_service.dart';

import 'features/library/presentation/providers/library_provider.dart';
import 'features/calculator/presentation/providers/calculator_provider.dart';
import 'features/transfer/presentation/providers/transfer_provider.dart';
import 'features/search/presentation/providers/global_search_provider.dart';
import 'features/users/presentation/providers/users_provider.dart';
import 'features/tasks/data/services/task_alarm_service.dart';
// SessionProvider removed

import 'features/athkar/presentation/providers/athkar_provider.dart';
import 'features/quran/presentation/providers/quran_provider.dart';
import 'features/settings/presentation/providers/settings_provider.dart';
import 'core/services/browser_download_manager.dart';
import 'core/services/media_cache_manager.dart'; // P3-15 FIX: Add import
import 'features/athkar/data/services/athkar_reminder_service.dart';
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
  final WidgetsBinding widgetsBinding =
      WidgetsFlutterBinding.ensureInitialized();

  // WEB PLATFORM: Skip Firebase and mobile-only services on web
  if (!kIsWeb) {
    // P9: Initialize Firebase first (required for Crashlytics)
    await Firebase.initializeApp();

    // P9: Initialize Firebase Crashlytics for production crash reporting
    if (kReleaseMode) {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
      // Pass all uncaught errors to Crashlytics
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
      debugPrint('Firebase Crashlytics initialized for production');
    } else {
      // Development: disable Crashlytics but keep error handling
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
      debugPrint('Firebase Crashlytics disabled in development mode');
    }
  } else {
    debugPrint('Running on WEB platform - skipping Firebase and mobile-only services');
  }

  // Preserve native splash screen until we explicitly remove it
  // This ensures seamless transition without flash
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Allow both portrait and landscape orientations (mobile only)
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

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

  // Initialize lightweight services first
  connectivityService.initialize();
  pendingOperationsService.initialize();

  // Defer heavy initializations to after first frame to improve startup performance
  // This prevents "Skipped XX frames" warnings during app launch
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // WEB PLATFORM: Skip mobile-only services
    if (!kIsWeb) {
      // Initialize background services (non-blocking)
      BackgroundSyncService().initialize();

      // Initialize Task Alarm Service
      try {
        TaskAlarmService().initialize().then((_) {
          debugPrint('TaskAlarmService initialized');
        }).catchError((e) {
          debugPrint('TaskAlarmService initialization error: $e');
        });
      } catch (e) {
        debugPrint('TaskAlarmService initialization error: $e');
      }

      // Initialize sharing service (non-blocking)
      SharingService().initialize();

      // Initialize Athkar Reminders (non-blocking)
      try {
        final athkarReminderService = AthkarReminderService();
        athkarReminderService.initialize().then((_) {
          athkarReminderService.scheduleReminders();
        }).catchError((e) {
          debugPrint('Athkar reminders error: $e');
        });
      } catch (e) {
        debugPrint('Athkar reminders error: $e');
      }
    }

    // Initialize Browser Download Manager (non-blocking)
    BrowserDownloadManager().init().then((_) {
      debugPrint('BrowserDownloadManager initialized');
    }).catchError((e) {
      debugPrint('BrowserDownloadManager initialization error: $e');
    });

    // P3-15 FIX: Perform startup cache cleanup for attachments (background)
    MediaCacheManager()
        .performStartupCleanup()
        .then((_) {
          debugPrint('Startup cache cleanup completed');
        })
        .catchError((e) {
          debugPrint('Startup cache cleanup error: $e');
        });
  });

  // WEB PLATFORM: Skip FCM on web
  if (!kIsWeb) {
    // FCM initialization (heavy, runs completely in background)
    FcmService()
        .initialize()
        .then((_) {
          debugPrint('FCM initialized in background');
        })
        .catchError((e) {
          debugPrint('FCM background initialization error: $e');
        });
  } else {
    debugPrint('Skipping FCM on web platform');
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
          create: (_) => SettingsProvider()..loadSettings(skipAutoRefresh: true),
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
          create: (context) =>
              LibraryProvider(webSocketService: webSocketService),
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
