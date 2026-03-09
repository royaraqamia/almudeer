import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

// Test runner for verifying notification icon
void main() {
  runApp(const MaterialApp(home: NotificationTestScreen()));
}

class NotificationTestScreen extends StatefulWidget {
  const NotificationTestScreen({super.key});

  @override
  State<NotificationTestScreen> createState() => _NotificationTestScreenState();
}

class _NotificationTestScreenState extends State<NotificationTestScreen> {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  String _status = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    try {
      // EXACT CONFIGURATION FROM FcmService
      const androidSettings = AndroidInitializationSettings(
        '@drawable/ic_notification',
      );
      const iosSettings = DarwinInitializationSettings();
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notifications.initialize(settings: initSettings);

      setState(() {
        _initialized = true;
        _status = 'Ready. Tap button to test.';
      });
    } catch (e) {
      setState(() {
        _status = 'Error initializing: $e';
      });
    }
  }

  Future<void> _showNotification() async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'test_channel',
        'Test Channel',
        channelDescription: 'Channel for verifying icon',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@drawable/ic_notification', // THE KEY PART
      );

      const details = NotificationDetails(android: androidDetails);

      await _notifications.show(
        id: 1,
        title: 'Notification Icon Test',
        body: 'Check the status bar icon now!',
        notificationDetails: details,
      );

      setState(() {
        _status = 'Notification sent! Check status bar.';
      });
    } catch (e) {
      setState(() {
        _status = 'Error showing notification: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Icon Verification')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_status, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _initialized ? _showNotification : null,
                icon: const Icon(SolarLinearIcons.bellBing),
                label: const Text('Show Test Notification'),
              ),
              const SizedBox(height: 10),
              const Text(
                'If the app crashes or shows a white square,\nthe icon configuration is incorrect.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
