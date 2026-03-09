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

class TaskAlarmService {
  static final TaskAlarmService _instance = TaskAlarmService._internal();
  factory TaskAlarmService() => _instance;

  TaskAlarmService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  static const String actionComplete = 'action_complete';

  Future<void> initialize() async {
    if (_isInitialized) return;

    tz.initializeTimeZones();
    try {
      final timeZone = await FlutterTimezone.getLocalTimezone();
      // Fix: Extract timezone ID from the returned string
      // FlutterTimezone may return "TimezoneInfo(GMT, ...)" instead of just "GMT"
      String timeZoneId = timeZone.toString();
      
      // Try to extract timezone ID from TimezoneInfo format
      if (timeZoneId.startsWith('TimezoneInfo(')) {
        // Extract the first parameter (timezone abbreviation like GMT, EST, etc.)
        final match = RegExp(r'TimezoneInfo\(([^,]+)').firstMatch(timeZoneId);
        if (match != null) {
          timeZoneId = match.group(1)!.trim();
        }
      }
      
      // Try to get location with the extracted timezone ID
      try {
        tz.setLocalLocation(tz.getLocation(timeZoneId));
      } catch (e) {
        debugPrint('TaskAlarmService: Failed to get location for "$timeZoneId": $e');
        // Try common timezone ID formats
        final fallbackIds = [
          timeZoneId,
          timeZoneId.replaceAll(' ', '_'),
          'Etc/$timeZoneId',
          'UTC',
        ];
        
        bool located = false;
        for (final id in fallbackIds) {
          try {
            tz.setLocalLocation(tz.getLocation(id));
            debugPrint('TaskAlarmService: Successfully set timezone to "$id"');
            located = true;
            break;
          } catch (_) {}
        }
        
        if (!located) {
          debugPrint('TaskAlarmService: All timezone lookups failed, using UTC');
          tz.setLocalLocation(tz.getLocation('UTC'));
        }
      }
    } catch (e) {
      debugPrint('TaskAlarmService: Timezone error: $e');
      try {
        tz.setLocalLocation(tz.getLocation('UTC'));
      } catch (_) {}
    }

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
        // Create a critical channel for Alarms
        // ID changed to v2 to force update on devices that have the old channel
        const channel = AndroidNotificationChannel(
          'task_alarms_v2', // NEW ID
          'Task Alarms',
          description: 'High priority alarms for scheduled tasks',
          importance: Importance.max, // MAX for Heads-up + Sound
          playSound: true,
          enableVibration: true,
          sound: RawResourceAndroidNotificationSound(
            'system_ringtone_default',
          ), // Uses default if not found, or resource
          audioAttributesUsage: AudioAttributesUsage.alarm, // Treat as Alarm
        );

        await androidPlugin.createNotificationChannel(channel);

        // Request Permissions
        await _requestAndroidPermissions(androidPlugin);
      }
    }

    _isInitialized = true;
    debugPrint('TaskAlarmService: Initialized');
  }

  Future<void> _requestAndroidPermissions(
    AndroidFlutterLocalNotificationsPlugin androidPlugin,
  ) async {
    try {
      await androidPlugin.requestNotificationsPermission();
      await androidPlugin.requestExactAlarmsPermission();
    } catch (e) {
      debugPrint('TaskAlarmService: Error requesting permissions: $e');
    }
  }

  void _handleNotificationResponse(NotificationResponse details) {
    debugPrint(
      'TaskAlarmService: Notification clicked/actioned: ${details.payload}',
    );
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

  static void Function(String taskId, String action)? _onTaskAction;
  static void setActionCallback(
    void Function(String taskId, String action) callback,
  ) {
    _onTaskAction = callback;
  }

  Future<void> scheduleAlarm(TaskModel task) async {
    if (!task.alarmEnabled || task.alarmTime == null) {
      await cancelAlarm(task.id);
      return;
    }

    if (task.alarmTime!.isBefore(DateTime.now())) {
      debugPrint('TaskAlarmService: Skipping past alarm for ${task.title}');
      return;
    }

    final scheduledDate = tz.TZDateTime.from(task.alarmTime!, tz.local);

    // Use a unique integer ID
    final int notificationId = task.id.hashCode.abs();

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
            AndroidScheduleMode.alarmClock, // Critical for reliability
        payload: jsonEncode({
          'type': 'task_alarm',
          'task_id': task.id,
          'task': task.toJson(),
        }),
      );

      debugPrint(
        'TaskAlarmService: Scheduled alarm for ${task.title} at $scheduledDate (ID: $notificationId)',
      );
    } catch (e) {
      debugPrint('TaskAlarmService: Failed to schedule alarm: $e');
    }
  }

  /// Reschedule all active alarms (optimized: only updates changed alarms)
  Future<void> rescheduleAllAlarms(List<TaskModel> tasks) async {
    debugPrint('TaskAlarmService: Rescheduling ${tasks.length} tasks...');

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
        final int notificationId = task.id.hashCode.abs();
        expectedIds.add(notificationId);

        // Check if this alarm needs to be updated (exists with different time)
        final existingNotification = pendingNotifications.firstWhere(
          (p) => p.id == notificationId,
          orElse: () => PendingNotificationRequest(-1, '', '', null),
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

    debugPrint(
      'TaskAlarmService: Rescheduled $scheduledCount new, '
      'updated $updatedCount changed, '
      'cancelled $cancelledCount removed alarms.',
    );
  }

  Future<void> cancelAlarm(String taskId) async {
    final int notificationId = taskId.hashCode.abs();
    await _localNotifications.cancel(id: notificationId);
    debugPrint(
      'TaskAlarmService: Cancelled alarm for task $taskId (ID: $notificationId)',
    );
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
}
