import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:almudeer_mobile_app/core/api/api_client.dart';
import 'package:almudeer_mobile_app/core/api/endpoints.dart';
import 'package:almudeer_mobile_app/core/services/notification_navigator.dart';
import 'package:almudeer_mobile_app/core/services/security_event_service.dart';

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kIsWeb) return; // Skip on web
  await Firebase.initializeApp();
  debugPrint('FCM Background message: ${message.messageId}');

  if (message.data['type'] == 'task_alarm') {
    final taskData = message.data['task'];
    if (taskData != null) {
      NotificationNavigator().importTaskAndShowOverlay(taskData);
    }
  } else if (message.data['type'] == 'account_disabled') {
    try {
      // 1. Persist flag for next app open (Main Isolate check)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('force_logout_required', true);

      // 2. Try to emit via bus (only works if in foreground or same isolate)
      SecurityEventService().emit(SecurityEvent.accountDisabled);
    } catch (e) {
      debugPrint('FCM Background: Error handling account_disabled: $e');
    }
  }
}

/// FCM Push Notification Service
class FcmService {
  static FcmService? _instance;
  factory FcmService() => _instance ??= FcmService._internal();

  @visibleForTesting
  factory FcmService.test({
    required FirebaseMessaging messaging,
    required FlutterLocalNotificationsPlugin localNotifications,
  }) {
    return FcmService._internal(
      messaging: messaging,
      localNotifications: localNotifications,
    );
  }

  /// Protected constructor for testing purposes
  @visibleForTesting
  FcmService.protected()
    : _messaging = _TestFirebaseMessaging(),
      _localNotifications = _TestFlutterLocalNotificationsPlugin();

  FcmService._internal({
    FirebaseMessaging? messaging,
    FlutterLocalNotificationsPlugin? localNotifications,
  }) : _messaging = messaging ?? FirebaseMessaging.instance,
       _localNotifications =
           localNotifications ?? FlutterLocalNotificationsPlugin();

  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications;

  String? _fcmToken;
  bool _isInitialized = false;

  /// Track if background handler has been registered to prevent duplicate registration
  static bool _backgroundHandlerRegistered = false;

  /// Atomic counter for notification IDs to avoid collisions
  int _notificationIdCounter = 0;

  /// Android notification group key for message grouping
  static const String _groupKey = 'com.almudeer.messages';

  /// Debounce timer for token registration to prevent duplicate calls
  Timer? _tokenRegistrationDebounce;

  /// Debounce duration for token registration
  static const Duration _tokenRegistrationDebounceDuration = Duration(seconds: 2);

  /// Get the current FCM token
  String? get fcmToken => _fcmToken;

  Future<void>? _initializationFuture;

  /// Initialize FCM service
  Future<void> initialize() {
    if (_initializationFuture != null) return _initializationFuture!;
    _initializationFuture = _doInitialize();
    return _initializationFuture!;
  }

  Future<void> _doInitialize() async {
    if (_isInitialized) return;
    
    // WEB PLATFORM: Skip FCM initialization on web
    if (kIsWeb) {
      debugPrint('FCM: Skipping FCM initialization on web platform');
      _isInitialized = true;
      return;
    }

    try {
      // Set up background handler only once
      if (!_backgroundHandlerRegistered) {
        FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler,
        );
        _backgroundHandlerRegistered = true;
        debugPrint('FCM: Background handler registered');
      } else {
        debugPrint('FCM: Background handler already registered, skipping');
      }

      // Request notification permission (Android 13+)
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        announcement: false,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
      );

      debugPrint('FCM Permission status: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        // Get FCM token
        _fcmToken = await _messaging.getToken();
        debugPrint('FCM Token: $_fcmToken');

        // Listen for token refresh
        _messaging.onTokenRefresh.listen((newToken) {
          debugPrint('FCM Token refreshed: $newToken');
          _fcmToken = newToken;
          _registerTokenWithBackend(newToken);
        });

        // iOS: Set foreground notification presentation options
        if (Platform.isIOS) {
          await _messaging.setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          );
          debugPrint('FCM: iOS foreground presentation options set');
        }

        // Initialize local notifications for foreground display
        await _initializeLocalNotifications();

        // Handle foreground messages
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

        // Handle notification taps
        FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

        // Check for initial message (app opened from notification)
        final initialMessage = await _messaging.getInitialMessage();
        if (initialMessage != null) {
          _handleNotificationTap(initialMessage);
        }

        // Check for initial local notification (app opened from local notification)
        final localAppLaunchDetails = await _localNotifications
            .getNotificationAppLaunchDetails();
        if (localAppLaunchDetails?.didNotificationLaunchApp ?? false) {
          final response = localAppLaunchDetails!.notificationResponse;
          if (response != null && response.payload != null) {
            _handleLocalNotificationTap(response);
          }
        }

        // Subscribe to general topic for broadcasts
        _messaging.subscribeToTopic('all_users');

        // Subscribe to license-specific topic
        final licenseKey = await ApiClient().getLicenseKey();
        if (licenseKey != null && licenseKey.isNotEmpty) {
          // Normalize license key for topic name (FCM topics only allow [a-zA-Z0-9-_.~%]+)
          final topicSafeKey = licenseKey.replaceAll(
            RegExp(r'[^a-zA-Z0-9-_]'),
            '',
          );
          _messaging.subscribeToTopic('license_$topicSafeKey');
          debugPrint(
            'FCM: Subscribed to topics: all_users, license_$topicSafeKey',
          );
        }
      }

      _isInitialized = true;
      debugPrint('FCM Service initialized successfully');

      // Production Hardening: Force register token on startup if authenticated
      // This ensures backend is always up to date even if no token refresh occurred
      if (_fcmToken != null) {
        final isAuthenticated = await ApiClient().isAuthenticated();
        if (isAuthenticated) {
          registerTokenWithBackend();
        }
      }
    } catch (e) {
      debugPrint('FCM initialization error: $e');
    }
  }

  /// Initialize local notifications for foreground display
  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@drawable/ic_notification',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _handleLocalNotificationTap,
    );

    // Create notification channels for Android
    if (Platform.isAndroid) {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      // Main notifications channel (messages, alerts)
      const channel = AndroidNotificationChannel(
        'almudeer_notifications',
        'Al-Mudeer Notifications',
        description: 'Notifications from Al-Mudeer',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );
      await androidPlugin?.createNotificationChannel(channel);

      // Downloads channel (low importance, silent)
      const downloadChannel = AndroidNotificationChannel(
        'almudeer_downloads',
        'ط§ظ„طھط­ظ…ظٹظ„ط§طھ',
        description: 'ط¥ط´ط¹ط§ط±ط§طھ طھظ‚ط¯ظ… ط§ظ„طھط­ظ…ظٹظ„',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      );
      await androidPlugin?.createNotificationChannel(downloadChannel);
    }
  }

  /// Handle foreground messages
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('FCM Foreground message: ${message.notification?.title}');

    if (message.data['type'] == 'account_disabled') {
      SecurityEventService().emit(SecurityEvent.accountDisabled);
      return; // Don't show notification for logout
    }

    if (message.data['type'] == 'task_alarm') {
      final taskData = message.data['task'];
      if (taskData != null) {
        NotificationNavigator().importTaskAndShowOverlay(taskData);
      }
      return;
    }

    final notification = message.notification;
    if (notification != null) {
      // Determine group key based on message type
      final senderContact = message.data['sender_contact'] as String?;
      // FIX P0-12: Normalize contact to prevent multiple notification groups for same person
      final normalizedContact = senderContact != null
          ? _normalizeContactForGrouping(senderContact)
          : null;
      final groupKey = normalizedContact != null
          ? 'com.almudeer.chat.$normalizedContact'
          : _groupKey;

      // Get custom sound and image from data payload
      final customSound = message.data['sound'] as String? ?? 'default';
      final imageUrl = message.data['sender_image'] as String?;

      // Foreground silencing: Don't show notification if user is already in this chat
      if (senderContact != null && _isUserInChat(senderContact)) {
        debugPrint(
          'FCM: Silencing notification - user is already in chat with $senderContact',
        );
        return;
      }

      _showLocalNotification(
        title: notification.title ?? 'ط§ظ„ظ…ط¯ظٹط±',
        body: notification.body ?? '',
        payload: jsonEncode(message.data),
        groupKey: groupKey,
        sound: customSound,
        imageUrl: imageUrl,
      );
    }
  }

  /// FIX P0-12: Normalize contact for notification grouping
  /// Prevents multiple notification groups for same person with different contact formats
  /// e.g., "+971123456789", "971123456789", "tg:username" all group together
  String _normalizeContactForGrouping(String contact) {
    // For Telegram usernames, keep as-is (they're already unique)
    if (contact.startsWith('tg:')) {
      return contact.toLowerCase();
    }

    // For phone numbers, remove all non-digit characters
    // This ensures "+971-123-456-789" and "971123456789" group together
    final normalized = contact.replaceAll(RegExp(r'[^\d]'), '');

    // Remove leading zeros after country code (common normalization)
    // e.g., "9710501234567" -> "971501234567" (UAE)
    if (normalized.length > 10 && normalized.startsWith('9710')) {
      return normalized.replaceFirst('9710', '971');
    }
    if (normalized.length > 10 && normalized.startsWith('9660')) {
      return normalized.replaceFirst('9660', '966');
    }
    if (normalized.length > 10 && normalized.startsWith('200')) {
      return normalized.replaceFirst('200', '20');
    }

    return normalized;
  }

  /// Handle local notification tap - navigates to correct screen
  void _handleLocalNotificationTap(NotificationResponse response) {
    debugPrint('Local notification tapped: ${response.payload}');

    if (response.payload != null && response.payload!.isNotEmpty) {
      try {
        final data = jsonDecode(response.payload!) as Map<String, dynamic>;
        NotificationNavigator().handleNotificationTap(data);
      } catch (e) {
        debugPrint('Error parsing notification payload: $e');
        // Navigate to home as fallback
        NotificationNavigator().handleNotificationTap({});
      }
    }
  }

  /// Get next notification ID (atomic counter to avoid collisions)
  int _getNextNotificationId() {
    _notificationIdCounter++;
    if (_notificationIdCounter > 2147483647) {
      _notificationIdCounter = 1; // Reset before int overflow
    }
    return _notificationIdCounter;
  }

  /// Show local notification
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
    String? groupKey,
    String sound = 'default',
    String? imageUrl,
  }) async {
    BigPictureStyleInformation? bigPictureStyleInformation;
    ByteArrayAndroidBitmap? largeIcon;

    // Handle image if provided
    if (imageUrl != null && imageUrl.isNotEmpty) {
      try {
        final client = ApiClient();
        final response = await client.getRaw(imageUrl);
        if (response.statusCode == 200) {
          final bytes = response.bodyBytes;
          largeIcon = ByteArrayAndroidBitmap(bytes);
          bigPictureStyleInformation = BigPictureStyleInformation(
            largeIcon,
            contentTitle: title,
            summaryText: body,
          );
        }
      } catch (e) {
        debugPrint('FCM: Error downloading notification image: $e');
      }
    }

    // Android details with notification grouping support
    final androidDetails = AndroidNotificationDetails(
      'almudeer_notifications',
      'Al-Mudeer Notifications',
      channelDescription: 'Notifications from Al-Mudeer',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@drawable/ic_notification',
      largeIcon: largeIcon,
      styleInformation: bigPictureStyleInformation,
      groupKey: groupKey ?? _groupKey,
      setAsGroupSummary: false,
      playSound: sound != 'none',
    );

    // iOS details with custom sound support
    List<DarwinNotificationAttachment>? attachments;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      try {
        final client = ApiClient();
        final response = await client.getRaw(imageUrl);
        if (response.statusCode == 200) {
          final bytes = response.bodyBytes;
          final tempDir = Directory.systemTemp;
          final fileName = 'notif_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final file = File('${tempDir.path}/$fileName');
          await file.writeAsBytes(bytes);
          attachments = [DarwinNotificationAttachment(file.path)];
        }
      } catch (e) {
        debugPrint('FCM: iOS attachment error: $e');
      }
    }

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: sound != 'none',
      sound: sound == 'default' ? null : sound,
      attachments: attachments,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      id: _getNextNotificationId(),
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );

    // Show group summary notification on Android
    if (Platform.isAndroid && groupKey != null) {
      await _showGroupSummaryNotification(groupKey);
    }
  }

  /// Show Android group summary notification
  Future<void> _showGroupSummaryNotification(String groupKey) async {
    final androidDetails = AndroidNotificationDetails(
      'almudeer_notifications',
      'Al-Mudeer Notifications',
      channelDescription: 'Notifications from Al-Mudeer',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
      groupKey: groupKey,
      setAsGroupSummary: true,
      groupAlertBehavior: GroupAlertBehavior.children,
    );

    final details = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      id: groupKey.hashCode, // Use group key hash as summary ID
      title: 'ط§ظ„ظ…ط¯ظٹط±',
      body: 'ظ„ط¯ظٹظƒ ط±ط³ط§ط¦ظ„ ط¬ط¯ظٹط¯ط©',
      notificationDetails: details,
    );
  }

  /// Handle notification tap
  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('Notification tapped: ${message.data}');

    // Use notification navigator for deep linking
    try {
      // Import dynamically to avoid circular dependencies
      // ignore: depend_on_referenced_packages
      final data = Map<String, dynamic>.from(message.data);

      // Add notification title/body to data for context
      if (message.notification != null) {
        data['title'] = message.notification!.title;
        data['body'] = message.notification!.body;
      }

      // Navigate using the notification navigator
      _navigateFromNotification(data);
    } catch (e) {
      debugPrint('Error handling notification tap: $e');
    }
  }

  /// Navigate based on notification data
  void _navigateFromNotification(Map<String, dynamic> data) {
    // Use the notification navigator singleton
    NotificationNavigator().handleNotificationTap(data);
  }

  /// Register FCM token with backend (with retry logic)
  ///
  /// Retries up to [maxRetries] times with exponential backoff.
  /// Safe to call before authentication - will skip if not authenticated.
  /// Uses debouncing to prevent duplicate registration calls.
  Future<void> registerTokenWithBackend({int maxRetries = 3}) async {
    if (_fcmToken == null) {
      debugPrint('FCM: No token to register');
      return;
    }

    // Cancel any pending registration to avoid duplicates
    _tokenRegistrationDebounce?.cancel();

    // Debounce token registration to prevent duplicate calls
    _tokenRegistrationDebounce = Timer(
      _tokenRegistrationDebounceDuration,
      () => _registerTokenWithRetry(_fcmToken!, maxRetries),
    );
  }

  /// Internal method to register token with retry logic
  ///
  /// Only retries on transient errors (network, 5xx).
  /// Stops immediately on client errors (4xx) as those won't be fixed by retrying.
  Future<void> _registerTokenWithRetry(String token, int maxRetries) async {
    final client = ApiClient();

    // Check auth first - don't retry if not authenticated
    final isAuthenticated = await client.isAuthenticated();
    if (!isAuthenticated) {
      debugPrint('FCM: User not authenticated, skipping token registration');
      return;
    }

    int consecutiveFailures = 0;
    const int failureThreshold = 5; // Show warning after 5 consecutive failures

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        debugPrint(
          'FCM: Registering token with backend (attempt ${attempt + 1}/$maxRetries)',
        );

        String? deviceId;
        try {
          final deviceInfo = DeviceInfoPlugin();
          if (Platform.isAndroid) {
            final androidInfo = await deviceInfo.androidInfo;
            deviceId = androidInfo.id; // Unique ID on Android
          } else if (Platform.isIOS) {
            final iosInfo = await deviceInfo.iosInfo;
            deviceId = iosInfo.identifierForVendor; // Unique ID on iOS
          }
        } catch (e) {
          debugPrint('FCM: Error getting device ID: $e');
        }

        await client.post(
          Endpoints.fcmSubscribe, // Use dedicated FCM endpoint
          body: {
            'token': token,
            'platform': Platform.isAndroid ? 'android' : 'ios',
            'device_id': deviceId,
          },
        );
        debugPrint('FCM: Token registered with backend');
        
        // Reset failure counter on success
        await _resetFcmFailureCounter();
        return; // Success!
      } on ApiException catch (e) {
        consecutiveFailures++;
        
        // Check if this is a client error (4xx) - don't retry these
        if (e.statusCode != null &&
            e.statusCode! >= 400 &&
            e.statusCode! < 500) {
          if (e.statusCode == 404) {
            // Endpoint doesn't exist - backend doesn't support FCM yet
            debugPrint('FCM: Backend FCM endpoint not implemented yet (404)');
            debugPrint(
              'FCM: Push notifications will not work until backend supports /api/notifications/fcm/subscribe',
            );
          } else if (e.statusCode == 422) {
            // Validation error - wrong request format
            debugPrint(
              'FCM: Backend rejected token format (422) - check API contract',
            );
          } else {
            debugPrint('FCM: Client error ${e.statusCode}: $e');
          }
          
          // Track failure for user notification
          await _incrementFcmFailureCounter();
          if (consecutiveFailures >= failureThreshold) {
            await _notifyUserOfFcmFailure();
          }
          return; // Don't retry client errors
        }

        // Server error (5xx) - worth retrying
        debugPrint(
          'FCM: Server error (attempt ${attempt + 1}/$maxRetries): $e',
        );
        if (attempt < maxRetries - 1) {
          final delay = Duration(seconds: 1 << attempt);
          debugPrint('FCM: Retrying in ${delay.inSeconds}s...');
          await Future.delayed(delay);
        } else {
          // Final attempt failed
          await _incrementFcmFailureCounter();
          if (consecutiveFailures >= failureThreshold) {
            await _notifyUserOfFcmFailure();
          }
        }
      } catch (e) {
        consecutiveFailures++;
        // Network or other error - worth retrying
        debugPrint('FCM: Error (attempt ${attempt + 1}/$maxRetries): $e');
        if (attempt < maxRetries - 1) {
          final delay = Duration(seconds: 1 << attempt);
          debugPrint('FCM: Retrying in ${delay.inSeconds}s...');
          await Future.delayed(delay);
        } else {
          // Final attempt failed
          await _incrementFcmFailureCounter();
          if (consecutiveFailures >= failureThreshold) {
            await _notifyUserOfFcmFailure();
          }
        }
      }
    }

    debugPrint('FCM: Token registration failed after $maxRetries attempts');
  }

  /// Track consecutive FCM registration failures
  Future<void> _incrementFcmFailureCounter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = prefs.getInt('fcm_failure_count') ?? 0;
      await prefs.setInt('fcm_failure_count', count + 1);
    } catch (e) {
      debugPrint('FCM: Failed to track failure counter: $e');
    }
  }

  /// Reset FCM failure counter on success
  Future<void> _resetFcmFailureCounter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('fcm_failure_count');
      await prefs.remove('fcm_failure_notified');
    } catch (e) {
      debugPrint('FCM: Failed to reset failure counter: $e');
    }
  }

  /// Notify user if FCM consistently fails (shown via UI, not notification)
  Future<void> _notifyUserOfFcmFailure() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadyNotified = prefs.getBool('fcm_failure_notified') ?? false;
      
      if (!alreadyNotified) {
        await prefs.setBool('fcm_failure_notified', true);
        debugPrint(
          'FCM: Persistent registration failures detected. User should be notified via UI.',
        );
        // Note: Actual UI notification should be handled by checking
        // 'fcm_failure_notified' in settings screen and showing a banner
      }
    } catch (e) {
      debugPrint('FCM: Failed to notify user of FCM failure: $e');
    }
  }

  /// Internal method to register token (no retry - used by onTokenRefresh)
  Future<void> _registerTokenWithBackend(String token) async {
    try {
      final client = ApiClient();
      final isAuthenticated = await client.isAuthenticated();

      if (!isAuthenticated) {
        debugPrint('FCM: User not authenticated, skipping token registration');
        return;
      }

      String? deviceId;
      try {
        final deviceInfo = DeviceInfoPlugin();
        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          deviceId = androidInfo.id;
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          deviceId = iosInfo.identifierForVendor;
        }
      } catch (e) {
        debugPrint('FCM: Error getting device ID: $e');
      }

      await client.post(
        Endpoints.fcmSubscribe, // Use dedicated FCM endpoint
        body: {
          'token': token,
          'platform': Platform.isAndroid ? 'android' : 'ios',
          'device_id': deviceId,
        },
      );
      debugPrint('FCM: Token registered with backend');
    } catch (e) {
      debugPrint('FCM Token registration error: $e');
    }
  }

  /// Unregister token from backend (on logout)
  /// SECURITY FIX: Requires authentication to prevent attackers from
  /// unregistering legitimate devices' push notifications
  /// P1-18 FIX: Added retry logic and proper error handling
  Future<void> unregisterToken() async {
    if (_fcmToken == null) return;

    const maxRetries = 3;
    int retryCount = 0;
    
    while (retryCount < maxRetries) {
      try {
        final client = ApiClient();
        // SECURITY FIX: Require authentication for FCM unregistration
        // This prevents attackers from disabling push notifications for targeted users
        await client.post(
          Endpoints.fcmUnsubscribe,
          body: {'token': _fcmToken},
          requiresAuth: true,  // Changed from false to true
        );
        debugPrint('FCM Token unregistered from backend (attempt ${retryCount + 1})');
        return; // Success - exit retry loop
      } catch (e) {
        retryCount++;
        if (retryCount >= maxRetries) {
          // P1-18 FIX: Log final failure but don't fail logout
          debugPrint('FCM Token unregister failed after $maxRetries attempts: $e');
          // Store flag to retry on next login
          await _markFcmUnregistrationPending();
          return;
        }
        // Wait before retry (exponential backoff)
        await Future.delayed(Duration(milliseconds: 500 * retryCount));
      }
    }
  }
  
  /// P1-18 FIX: Mark FCM unregistration as pending for retry on next login
  Future<void> _markFcmUnregistrationPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('fcm_unregistration_pending', true);
    } catch (e) {
      debugPrint('Failed to mark FCM unregistration pending: $e');
    }
  }

  /// Check if the user is currently looking at a specific chat
  bool _isUserInChat(String contact) {
    try {
      final context = navigatorKey.currentContext;
      if (context == null) return false;

      // In Al-Mudeer, we can check the current route and arguments
      // This is a more robust way to silence notifications for the active chat
      final route = ModalRoute.of(context);
      if (route == null) return false;

      final routeName = route.settings.name;
      final arguments = route.settings.arguments;

      // If we're on the conversation screen and the contact matches, silence it
      if (routeName == '/conversation' && arguments is Map) {
        final activeContact = arguments['sender_contact'] as String?;
        return activeContact == contact;
      }

      return false;
    } catch (e) {
      debugPrint('FCM: Error checking active chat: $e');
      return false;
    }
  }

  /// Dispose resources to prevent memory leaks
  void dispose() {
    _tokenRegistrationDebounce?.cancel();
    _tokenRegistrationDebounce = null;
  }
}

// Test stubs for protected constructor
class _TestFirebaseMessaging implements FirebaseMessaging {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestFlutterLocalNotificationsPlugin
    implements FlutterLocalNotificationsPlugin {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
