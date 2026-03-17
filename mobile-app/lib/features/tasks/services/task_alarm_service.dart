import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../../../core/services/notification_navigator.dart';
import '../models/task_model.dart';
import '../utils/task_logger.dart'; // FIX #8: Centralized logging

class TaskAlarmService {
  static final TaskAlarmService _instance = TaskAlarmService._internal();
  factory TaskAlarmService() => _instance;

  TaskAlarmService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  static const String actionComplete = 'action_complete';

  // FIX #4: Cache timezone ID to prevent repeated lookups
  String? _cachedTimezoneId;
  DateTime? _lastTimezoneCheck;

  Future<void> initialize() async {
    if (_isInitialized) return;

    tz.initializeTimeZones();
    
    // FIX #4: Improved timezone handling with better error handling and caching
    await _initializeTimezone();

    const androidSettings = AndroidInitializationSettings(
      '@drawable/ic_notification',
    );

    // Request permissions explicitly later, but setup listeners here
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
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );

    if (Platform.isAndroid) {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      if (androidPlugin != null) {
        // FIX #7: Notification channel migration for existing users
        // Delete old channel if it exists (from previous versions)
        try {
          await androidPlugin.deleteNotificationChannel(channelId: 'task_alarms');
          TaskLogger.alarm('Deleted old notification channel: task_alarms');
        } catch (_) {
          // Old channel may not exist, ignore error
        }
        
        // Create new critical channel for Alarms with v2 ID
        const channel = AndroidNotificationChannel(
          'task_alarms_v2',
          'Task Alarms',
          description: 'High priority alarms for scheduled tasks',
          importance: Importance.max, // MAX for Heads-up + Sound
          playSound: true,
          enableVibration: true,
          sound: RawResourceAndroidNotificationSound(
            'system_ringtone_default',
          ),
          audioAttributesUsage: AudioAttributesUsage.alarm,
        );

        await androidPlugin.createNotificationChannel(channel);
        TaskLogger.alarm('Created notification channel: task_alarms_v2');

        // Request Permissions
        await _requestAndroidPermissions(androidPlugin);
      }
    }

    _isInitialized = true;
    TaskLogger.alarm('Initialized');
  }

  Future<void> _requestAndroidPermissions(
    AndroidFlutterLocalNotificationsPlugin androidPlugin,
  ) async {
    try {
      // Request basic notification permission (Android 13+)
      final notifGranted = await androidPlugin.requestNotificationsPermission();
      TaskLogger.alarm('Notification permission: $notifGranted');
      
      // FIX #5: Request exact alarm permission with fallback handling
      // On Android 12+, SCHEDULE_EXACT_ALARM may require special approval
      try {
        final exactAlarmGranted = await androidPlugin.requestExactAlarmsPermission();
        TaskLogger.alarm('Exact alarm permission: $exactAlarmGranted');

        if (exactAlarmGranted != true) {
          TaskLogger.w('Exact alarm permission denied - alarms may be inexact', tag: 'Alarm');
          // Note: Alarms will still work but may fire slightly late
          // User can manually enable in Settings > Apps > Al-Mudeer > Alarms & reminders
        }
      } catch (e) {
        TaskLogger.w('Exact alarm permission request failed: $e', tag: 'Alarm');
        // Fallback: Alarms will use inexact scheduling (still functional)
      }
    } catch (e) {
      TaskLogger.e('Error requesting permissions: $e', tag: 'Alarm');
    }
  }

  void _handleNotificationResponse(NotificationResponse details) async {
    TaskLogger.alarm('Notification clicked/actioned: ${details.payload}');
    if (details.payload != null) {
      try {
        final data = jsonDecode(details.payload!) as Map<String, dynamic>;

        if (details.actionId == actionComplete) {
          final taskId = data['task_id'] as String?;
          if (taskId != null) {
            _markTaskAsCompletedLocally(taskId);
          }
          return;
        }

        // FIX #8: Reschedule recurring alarm if task has recurrence
        final taskData = data['task'] as Map<String, dynamic>?;
        if (taskData != null) {
          final task = TaskModel.fromJson(taskData);
          if (task.recurrence != null) {
            await _rescheduleRecurringAlarm(task);
          }
        }

        // Navigate or show task details
        NotificationNavigator().handleNotificationTap(data);
      } catch (e) {
        debugPrint('TaskAlarmService: Payload parsing error: $e');
      }
    }
  }

  void _markTaskAsCompletedLocally(String taskId) {
    _onTaskAction?.call(taskId, actionComplete);
  }

  // FIX #8: Handle recurring task alarm rescheduling
  Future<void> _rescheduleRecurringAlarm(TaskModel task) async {
    if (task.recurrence == null || task.alarmTime == null) {
      return; // Not recurring
    }

    DateTime? nextAlarmTime;
    final now = DateTime.now();

    switch (task.recurrence) {
      case 'daily':
        nextAlarmTime = task.alarmTime!.add(const Duration(days: 1));
        break;
      case 'weekly':
        nextAlarmTime = task.alarmTime!.add(const Duration(days: 7));
        break;
      case 'monthly':
        // Add one month, handling month overflow
        nextAlarmTime = DateTime(
          task.alarmTime!.year,
          task.alarmTime!.month + 1,
          task.alarmTime!.day,
          task.alarmTime!.hour,
          task.alarmTime!.minute,
        );
        break;
    }

    if (nextAlarmTime != null && nextAlarmTime.isAfter(now)) {
      // Create updated task with next alarm time
      final nextTask = task.copyWith(alarmTime: nextAlarmTime);
      await scheduleAlarm(nextTask);
      TaskLogger.alarm(
        'Rescheduled recurring alarm for "${task.title}" to $nextAlarmTime',
      );
    }
  }

  static void Function(String taskId, String action)? _onTaskAction;
  static void setActionCallback(
    void Function(String taskId, String action) callback,
  ) {
    _onTaskAction = callback;
  }

  // FIX #6: Use incremental counter for notification IDs to prevent hash collisions
  int _notificationIdCounter = 0;
  static const int _notificationIdMax = 2147483647; // Max int32
  
  // FIX #6: Map task IDs to notification IDs for cancellation
  final Map<String, int> _taskToNotificationId = {};
  
  // FIX #6: Generate unique notification ID
  int _generateNotificationId(String taskId) {
    // Use incremental counter to guarantee uniqueness
    _notificationIdCounter++;
    if (_notificationIdCounter > _notificationIdMax) {
      _notificationIdCounter = 1; // Reset before overflow
    }
    return _notificationIdCounter;
  }

  Future<void> scheduleAlarm(TaskModel task) async {
    if (!task.alarmEnabled || task.alarmTime == null) {
      await cancelAlarm(task.id);
      return;
    }

    if (task.alarmTime!.isBefore(DateTime.now())) {
      TaskLogger.alarm('Skipping past alarm for ${task.title}');
      return;
    }

    final scheduledDate = tz.TZDateTime.from(task.alarmTime!, tz.local);

    // FIX #6: Use incremental ID instead of hashCode to prevent collisions
    final int notificationId = _generateNotificationId(task.id);
    
    // Store mapping for cancellation lookup
    _taskToNotificationId[task.id] = notificationId;

    const androidDetails = AndroidNotificationDetails(
      'task_alarms_v2',
      'Task Alarms',
      channelDescription: 'High priority alarms for scheduled tasks',
      importance: Importance.max,
      priority: Priority.max, // MAX for full screen intent possibility
      fullScreenIntent: true, // Attempt to show over lockscreen
      category: AndroidNotificationCategory.alarm,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          actionComplete,
          'تَمَّ الإنجاز',
          icon: DrawableResourceAndroidBitmap('@drawable/ic_check'),
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
      // Sound: fallback to default if not specified/bundled
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
      sound: 'default',
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _localNotifications.zonedSchedule(
        id: notificationId,
        title: '⏰ تذكير مهمَّة',
        body: '${task.title}\n${task.description ?? ''}',
        scheduledDate: scheduledDate,
        notificationDetails: details,
        androidScheduleMode:
            AndroidScheduleMode.inexactAllowWhileIdle,
        payload: jsonEncode({
          'type': 'task_alarm',
          'task_id': task.id,
          'task': task.toJson(),
        }),
      );

      TaskLogger.alarm('Scheduled alarm for ${task.title} at $scheduledDate (ID: $notificationId)');
    } catch (e) {
      TaskLogger.e('Failed to schedule alarm with inexactAllowWhileIdle: $e', tag: 'Alarm');
      // FIX #5: Fallback to exact mode if inexact fails
      try {
        await _localNotifications.zonedSchedule(
          id: notificationId,
          title: '⏰ تذكير مهمَّة',
          body: '${task.title}\n${task.description ?? ''}',
          scheduledDate: scheduledDate,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.exact,
          payload: jsonEncode({
            'type': 'task_alarm',
            'task_id': task.id,
            'task': task.toJson(),
          }),
        );
        TaskLogger.alarm('Scheduled alarm with exact mode (fallback)');
      } catch (e2) {
        TaskLogger.e('Failed with fallback mode: $e2', tag: 'Alarm');
      }
    }
  }

  /// Reschedule all active alarms (optimized: only updates changed alarms)
  Future<void> rescheduleAllAlarms(List<TaskModel> tasks) async {
    TaskLogger.alarm('Rescheduling ${tasks.length} tasks...');

    // OPTIMIZATION: Get currently pending notifications to avoid unnecessary cancel/reschedule
    final List<PendingNotificationRequest> pendingNotifications =
        await _localNotifications.pendingNotificationRequests();
    final Set<int> pendingIds = pendingNotifications.map((p) => p.id).toSet();
    final Set<int> expectedIds = {};

    int scheduledCount = 0;
    int updatedCount = 0;
    int cancelledCount = 0;

    // Schedule/update alarms for active tasks
    for (final task in tasks) {
      if (task.alarmEnabled &&
          !task.isCompleted &&
          task.alarmTime != null &&
          task.alarmTime!.isAfter(DateTime.now())) {
        // FIX #6: Use incremental ID instead of hashCode
        final int notificationId = _generateNotificationId(task.id);
        expectedIds.add(notificationId);
        _taskToNotificationId[task.id] = notificationId;

        // Check if this alarm needs to be updated (exists with different time)
        final existingNotification = pendingNotifications.firstWhere(
          (p) => p.id == notificationId,
          orElse: () => const PendingNotificationRequest(-1, '', '', null),
        );

        if (existingNotification.id == notificationId) {
          // Alarm exists - check if payload changed (time update)
          final existingPayload = existingNotification.payload;
          if (existingPayload != null) {
            try {
              final existingData =
                  jsonDecode(existingPayload) as Map<String, dynamic>;
              final existingTask = TaskModel.fromJson(
                existingData['task'] as Map<String, dynamic>,
              );

              // Only reschedule if alarm time changed
              if (existingTask.alarmTime?.isAtSameMomentAs(task.alarmTime!) !=
                  true) {
                await scheduleAlarm(task);
                updatedCount++;
              }
            } catch (_) {
              // Payload parse error, reschedule to be safe
              await scheduleAlarm(task);
              updatedCount++;
            }
          }
        } else {
          // New alarm
          await scheduleAlarm(task);
          scheduledCount++;
        }
      }
    }

    // Cancel alarms that no longer exist (task deleted, completed, or alarm disabled)
    for (final pendingId in pendingIds) {
      if (!expectedIds.contains(pendingId)) {
        await _localNotifications.cancel(id: pendingId);
        cancelledCount++;
      }
    }

    TaskLogger.alarm(
      'Rescheduled $scheduledCount new, '
      'updated $updatedCount changed, '
      'cancelled $cancelledCount removed alarms.',
    );
  }

  Future<void> cancelAlarm(String taskId) async {
    // FIX #6: Use stored notification ID from mapping, fallback to hashCode
    final int notificationId = _taskToNotificationId[taskId] ?? taskId.hashCode.abs();
    await _localNotifications.cancel(id: notificationId);
    _taskToNotificationId.remove(taskId);
    TaskLogger.alarm('Cancelled alarm for task $taskId (ID: $notificationId)');
  }

  /// Show the ringing overlay using CallKit
  static Future<void> showRingingOverlay(TaskModel task) async {
    final params = CallKitParams(
      id: task.id,
      nameCaller: 'تنبيه مهمَّة',
      appName: 'Al-Mudeer',
      handle: task.title,
      type: 0, // 0 for Audio, 1 for Video
      duration: 30000,
      textAccept: 'فتح المهمَّة',
      textDecline: 'إغلاق',
      extra: <String, dynamic>{'task_id': task.id, 'type': 'task_alarm'},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0955fa',
        actionColor: '#4CAF50',
      ),
      ios: const IOSParams(
        iconName: 'AppIcon',
        handleType: 'generic',
        supportsVideo: false,
        audioSessionActive: true,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  /// FIX #4: Improved timezone initialization with caching and better error handling
  Future<void> _initializeTimezone() async {
    // Check cache (valid for 1 hour)
    final now = DateTime.now();
    if (_cachedTimezoneId != null && 
        _lastTimezoneCheck != null && 
        now.difference(_lastTimezoneCheck!).inHours < 1) {
      TaskLogger.timezone('cache_hit', _cachedTimezoneId!);
      try {
        tz.setLocalLocation(tz.getLocation(_cachedTimezoneId!));
        return;
      } catch (e) {
        TaskLogger.w('Cached timezone "$_cachedTimezoneId" failed, refreshing', tag: 'Timezone');
      }
    }

    try {
      final timeZone = await FlutterTimezone.getLocalTimezone();
      String timeZoneId = _parseTimezoneString(timeZone.toString());

      // Convert Windows timezone to IANA if needed
      if (timeZoneId.contains(' ') && !timeZoneId.contains('/')) {
        timeZoneId = _convertWindowsToIana(timeZoneId);
      }

      // Try to set timezone with fallbacks
      await _setTimezoneWithFallbacks(timeZoneId);
      
    } catch (e) {
      TaskLogger.e('Timezone initialization error: $e', tag: 'Timezone');
      // Ultimate fallback to UTC
      try {
        tz.setLocalLocation(tz.getLocation('UTC'));
        _cachedTimezoneId = 'UTC';
        _lastTimezoneCheck = now;
        TaskLogger.timezone('fallback_utc', 'UTC');
      } catch (_) {}
    }
  }

  /// FIX #4: Parse timezone string from various formats
  String _parseTimezoneString(String timeZone) {
    String timeZoneId = timeZone.trim();

    // Handle TimezoneInfo format: "TimezoneInfo(GMT, ...)"
    if (timeZoneId.startsWith('TimezoneInfo(')) {
      final match = RegExp(r'TimezoneInfo\(([^,]+)').firstMatch(timeZoneId);
      if (match != null) {
        timeZoneId = match.group(1)!.trim();
      }
    }

    return timeZoneId;
  }

  /// FIX #4: Set timezone with multiple fallback strategies
  Future<void> _setTimezoneWithFallbacks(String timeZoneId) async {
    final now = DateTime.now();
    
    // Try primary timezone ID
    try {
      tz.setLocalLocation(tz.getLocation(timeZoneId));
      _cachedTimezoneId = timeZoneId;
      _lastTimezoneCheck = now;
      TaskLogger.timezone('primary_success', timeZoneId);
      return;
    } catch (e) {
      TaskLogger.w('Primary timezone "$timeZoneId" failed: $e', tag: 'Timezone');
    }

    // Build fallback list
    final fallbackIds = <String>[
      timeZoneId,
      timeZoneId.replaceAll(' ', '_'),
      'Etc/$timeZoneId',
      ..._getIanaTimezoneFallbacks(timeZoneId),
      'UTC',
    ];

    // Try each fallback
    for (final id in fallbackIds) {
      if (id.isEmpty || id == timeZoneId) continue;
      try {
        tz.setLocalLocation(tz.getLocation(id));
        _cachedTimezoneId = id;
        _lastTimezoneCheck = now;
        TaskLogger.timezone('fallback_success', id);
        return;
      } catch (_) {}
    }

    // All fallbacks failed
    TaskLogger.timezone('complete_failure', timeZoneId);
    throw Exception('Failed to set timezone: $timeZoneId');
  }

  /// FIX: Convert Windows timezone names to IANA format
  static String _convertWindowsToIana(String windowsTimezone) {
    final normalized = windowsTimezone.trim().toLowerCase();
    // Common Windows to IANA timezone mappings
    final windowsToIana = {
      'western european time': 'Europe/London',
      'gmt standard time': 'Europe/London',
      'west europe standard time': 'Europe/Berlin',
      'romance standard time': 'Europe/Paris',
      'central europe standard time': 'Europe/Berlin',
      'eastern europe standard time': 'Europe/Bucharest',
      'fLE standard time': 'Europe/Helsinki',
      'gtb standard time': 'Europe/Bucharest',
      'egypt standard time': 'Africa/Cairo',
      'south africa standard time': 'Africa/Johannesburg',
      'russian standard time': 'Europe/Moscow',
      'arabic standard time': 'Asia/Riyadh',
      'iran standard time': 'Asia/Tehran',
      'india standard time': 'Asia/Kolkata',
      'singapore standard time': 'Asia/Singapore',
      'west pacific standard time': 'Pacific/Port_Moresby',
      'central pacific standard time': 'Pacific/Guadalcanal',
      'eastern australia standard time': 'Australia/Sydney',
      'aus eastern standard time': 'Australia/Sydney',
      'tasmania standard time': 'Australia/Hobart',
      'new zealand standard time': 'Pacific/Auckland',
      'utc+12': 'Pacific/Auckland',
      'hawaiian standard time': 'Pacific/Honolulu',
      'alaskan standard time': 'America/Anchorage',
      'pacific standard time': 'America/Los_Angeles',
      'us mountain standard time': 'America/Denver',
      'mountain standard time': 'America/Denver',
      'central standard time': 'America/Chicago',
      'eastern standard time': 'America/New_York',
      'atlantic standard time': 'America/Halifax',
      'greenland standard time': 'America/Godthab',
      'mid-atlantic standard time': 'Atlantic/South_Georgia',
      'azores standard time': 'Atlantic/Azores',
      'cape verde standard time': 'Atlantic/Cape_Verde',
      'morocco standard time': 'Africa/Casablanca',
      'central brazilian standard time': 'America/Cuiaba',
      'sa western standard time': 'America/Bahia',
      'pacific sa standard time': 'America/Santiago',
      'venezuela standard time': 'America/Caracas',
    };
    return windowsToIana[normalized] ?? windowsTimezone;
  }

  /// FIX: Get IANA timezone fallbacks for common abbreviations
  static List<String> _getIanaTimezoneFallbacks(String abbreviation) {
    final normalized = abbreviation.trim().toUpperCase();
    // Common timezone abbreviation to IANA mappings
    final abbrevToIana = {
      'UTC': ['UTC'],
      'GMT': ['Europe/London', 'UTC'],
      'EST': ['America/New_York'],
      'EDT': ['America/New_York'],
      'CST': ['America/Chicago', 'Asia/Shanghai'],
      'CDT': ['America/Chicago'],
      'MST': ['America/Denver'],
      'MDT': ['America/Denver'],
      'PST': ['America/Los_Angeles'],
      'PDT': ['America/Los_Angeles'],
      'AST': ['America/Halifax'],
      'ADT': ['America/Halifax'],
      'HST': ['Pacific/Honolulu'],
      'AKST': ['America/Anchorage'],
      'AKDT': ['America/Anchorage'],
      'CET': ['Europe/Berlin'],
      'CEST': ['Europe/Berlin'],
      'EET': ['Europe/Helsinki'],
      'EEST': ['Europe/Helsinki'],
      'WET': ['Europe/Lisbon'],
      'WEST': ['Europe/Lisbon'],
      'BST': ['Europe/London'],
      'IST': ['Europe/Dublin', 'Asia/Kolkata', 'Asia/Jerusalem'],
      'JST': ['Asia/Tokyo'],
      'KST': ['Asia/Seoul'],
      'CST_CHINA': ['Asia/Shanghai'],
      'HKT': ['Asia/Hong_Kong'],
      'SGT': ['Asia/Singapore'],
      'AEST': ['Australia/Sydney'],
      'AEDT': ['Australia/Sydney'],
      'NZST': ['Pacific/Auckland'],
      'NZDT': ['Pacific/Auckland'],
      'CAT': ['Africa/Johannesburg'],
      'EAT': ['Africa/Nairobi'],
      'WAT': ['Africa/Lagos'],
      'ECT': ['Europe/Paris'],
      'SAST': ['Africa/Johannesburg'],
      'AST_ARABIC': ['Asia/Riyadh'],
      'IST_IRAN': ['Asia/Tehran'],
    };
    return abbrevToIana[normalized] ?? [];
  }
}
