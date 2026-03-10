import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AthkarReminderService {
  static const int morningNotificationId = 9001;
  static const int eveningNotificationId = 9002;

  static const String _morningHourKey = 'athkar_morning_hour';
  static const String _morningMinuteKey = 'athkar_morning_minute';
  static const String _eveningHourKey = 'athkar_evening_hour';
  static const String _eveningMinuteKey = 'athkar_evening_minute';
  static const String _enabledKey = 'athkar_reminders_enabled';
  static const String _lastTimezoneKey = 'athkar_last_timezone';

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  int _morningHour = 7;
  int _morningMinute = 0;
  int _eveningHour = 17;
  int _eveningMinute = 0;
  bool _enabled = true;
  String? _lastTimezone;

  Future<void> initialize() async {
    await _loadSettings();
    await _initializeTimeZone();
    await _checkTimezoneChange();
  }

  Future<void> _initializeTimeZone() async {
    try {
      tz.initializeTimeZones();
      await _setLocalTimeZone();
    } catch (e) {
      debugPrint('AthkarReminderService: Failed to initialize timezone: $e');
    }
  }

  Future<void> _setLocalTimeZone() async {
    try {
      final timeZone = await FlutterTimezone.getLocalTimezone();
      // Extract timezone ID from TimezoneInfo object
      String timeZoneId = timeZone.toString().trim();
      if (timeZoneId.startsWith('TimezoneInfo(')) {
        final match = RegExp(r'TimezoneInfo\(([^,]+)').firstMatch(timeZoneId);
        if (match != null) {
          timeZoneId = match.group(1)!.trim();
        }
      }
      tz.setLocalLocation(tz.getLocation(timeZoneId));
      debugPrint('AthkarReminderService: Timezone set to $timeZoneId');
    } catch (e) {
      debugPrint('AthkarReminderService: Failed to set timezone: $e');
    }
  }

  /// Check if timezone has changed since last run and reschedule if needed
  Future<void> _checkTimezoneChange() async {
    try {
      final currentTimezone = await FlutterTimezone.getLocalTimezone();
      // Extract timezone ID from TimezoneInfo object
      String currentTimezoneId = currentTimezone.toString().trim();
      if (currentTimezoneId.startsWith('TimezoneInfo(')) {
        final match = RegExp(r'TimezoneInfo\(([^,]+)').firstMatch(currentTimezoneId);
        if (match != null) {
          currentTimezoneId = match.group(1)!.trim();
        }
      }
      if (_lastTimezone != null && _lastTimezone != currentTimezoneId) {
        debugPrint('AthkarReminderService: Timezone changed from $_lastTimezone to $currentTimezoneId, rescheduling reminders');
        await scheduleReminders();
      }
      await _saveTimezone(currentTimezoneId);
    } catch (e) {
      debugPrint('AthkarReminderService: Failed to check timezone change: $e');
    }
  }

  Future<void> _saveTimezone(String timezone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastTimezoneKey, timezone);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _morningHour = prefs.getInt(_morningHourKey) ?? 7;
    _morningMinute = prefs.getInt(_morningMinuteKey) ?? 0;
    _eveningHour = prefs.getInt(_eveningHourKey) ?? 17;
    _eveningMinute = prefs.getInt(_eveningMinuteKey) ?? 0;
    _enabled = prefs.getBool(_enabledKey) ?? true;
    _lastTimezone = prefs.getString(_lastTimezoneKey);
  }

  Future<void> setMorningTime(int hour, int minute) async {
    _morningHour = hour;
    _morningMinute = minute;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_morningHourKey, hour);
    await prefs.setInt(_morningMinuteKey, minute);
  }

  Future<void> setEveningTime(int hour, int minute) async {
    _eveningHour = hour;
    _eveningMinute = minute;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_eveningHourKey, hour);
    await prefs.setInt(_eveningMinuteKey, minute);
  }

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }

  bool get isEnabled => _enabled;
  int get morningHour => _morningHour;
  int get morningMinute => _morningMinute;
  int get eveningHour => _eveningHour;
  int get eveningMinute => _eveningMinute;

  Future<void> scheduleReminders() async {
    if (!_enabled) {
      await cancelAll();
      debugPrint('AthkarReminderService: Reminders disabled, cancelled all scheduled notifications');
      return;
    }
    try {
      await _scheduleMorning();
      await _scheduleEvening();
      debugPrint('AthkarReminderService: Reminders scheduled successfully');
    } catch (e, stackTrace) {
      debugPrint('AthkarReminderService: Failed to schedule reminders: $e');
      debugPrint('AthkarReminderService: Stack trace: $stackTrace');
    }
  }

  Future<void> _scheduleMorning() async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      _morningHour,
      _morningMinute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _notifications.zonedSchedule(
      id: morningNotificationId,
      title: 'أذكار الصباح',
      body: 'حان وقت أذكار الصباح، اجعل بذكر الله صباحك أجمل',
      scheduledDate: scheduledDate,
      notificationDetails: _notificationDetails(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'athkar_morning',
    );
  }

  Future<void> _scheduleEvening() async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      _eveningHour,
      _eveningMinute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _notifications.zonedSchedule(
      id: eveningNotificationId,
      title: 'أذكار المساء',
      body: 'حان وقت أذكار المساء، حصن نفسك بذكر الله',
      scheduledDate: scheduledDate,
      notificationDetails: _notificationDetails(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'athkar_evening',
    );
  }

  NotificationDetails _notificationDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        'athkar_reminders',
        'أذكار',
        channelDescription: 'تنبيهات أذكار الصباح والمساء',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  Future<void> cancelAll() async {
    await _notifications.cancel(id: morningNotificationId);
    await _notifications.cancel(id: eveningNotificationId);
  }
}
