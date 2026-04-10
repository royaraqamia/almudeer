import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:almudeer_mobile_app/features/tasks/data/models/task_model.dart';
import 'package:almudeer_mobile_app/features/tasks/data/services/task_alarm_service.dart';

/// Global navigator key for notification-based navigation
/// This allows navigation from outside the widget tree (e.g., from FCM service)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Notification Navigator Service
/// Handles navigation when user taps on push notifications
class NotificationNavigator {
  static final NotificationNavigator _instance =
      NotificationNavigator._internal();
  factory NotificationNavigator() => _instance;
  NotificationNavigator._internal();

  /// Navigate based on notification data
  ///
  /// Supported data fields:
  /// - `link`: Route path like "/inbox", "/notifications", "/conversations/{contact}"
  /// - `type`: Notification type for determining default route
  /// - `sender_contact`: For navigating to specific conversation
  void handleNotificationTap(Map<String, dynamic> data) {
    final link = data['link'] as String?;
    final type = data['type'] as String?;
    final senderContact = data['sender_contact'] as String?;

    // Extract tracking IDs
    final notificationId = data['notification_id'] != null
        ? int.tryParse(data['notification_id'].toString())
        : null;

    debugPrint(
      'NotificationNavigator: Handling tap - link=$link, type=$type, notifId=$notificationId',
    );

    // Track notification open
    _trackOpen(notificationId: notificationId);

    // Determine route based on link or type
    String route;
    Object? arguments;

    if (link != null && link.isNotEmpty) {
      // Use the provided link directly
      if (link.startsWith('/conversations/') && link.length > 15) {
        // Extract contact from link like "/conversations/+123456789"
        route = '/conversation';
        arguments = {'contact': Uri.decodeComponent(link.substring(15))};
      } else if (link.startsWith('/tasks/') && link.length > 7) {
        // Extract taskId from link like "/tasks/abcd-1234"
        route = '/tasks';
        arguments = {'taskId': Uri.decodeComponent(link.substring(7))};
      } else if (link == '/tasks') {
        route = '/tasks';
      } else if (link == '/dashboard/inbox' || link == '/inbox') {
        route = '/inbox';
      } else if (link == '/dashboard' || link == '/') {
        route = '/home';
      } else {
        // Default to home for unknown routes
        route = '/home';
      }
    } else if (senderContact != null && senderContact.isNotEmpty) {
      // Navigate to specific conversation
      route = '/conversation';
      arguments = {'contact': senderContact};
    } else if (type != null) {
      // Use type to determine route
      switch (type) {
        case 'message':
        case 'new_message':
        case 'urgent_message':
        case 'vip_message':
          route = '/inbox';
          break;
        case 'task_alarm':
          // For task alarms, we show the overlay.
          // This should work even if navigator is not ready yet because it's a CallKit overlay.
          final taskData = data['task'];
          if (taskData != null) {
            importTaskAndShowOverlay(taskData);
          }
          return;
        case 'task_assigned':
          route = '/tasks';
          if (data['task_id'] != null) {
            arguments = {'taskId': data['task_id']};
          }
          break;
        case 'notification':
        case 'system':
        case 'alert':
        case 'subscription_expiring':
        case 'subscription_expired':
        case 'team_update':
        case 'promotion':
          // Redirect general notifications to home since notifications screen is gone
          route = '/home';
          break;
        default:
          route = '/home';
      }
    } else {
      // Default fallback
      route = '/home';
    }

    // Perform navigation
    _navigateTo(route, arguments: arguments);
  }

  /// Navigate to a specific route
  void _navigateTo(String route, {Object? arguments}) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      debugPrint('NotificationNavigator: Navigator not available yet');
      // Store pending navigation for later
      _pendingRoute = route;
      _pendingArguments = arguments;
      return;
    }

    debugPrint('NotificationNavigator: Navigating to $route');

    // Use pushNamedAndRemoveUntil to ensure clean navigation stack
    navigator.pushNamedAndRemoveUntil(
      route,
      (routeCheck) => routeCheck.isFirst,
      arguments: arguments,
    );
  }

  // Pending navigation storage
  String? _pendingRoute;
  Object? _pendingArguments;

  /// Track open with the provider
  void _trackOpen({int? notificationId}) {
    // Analytics tracking removed as NotificationsProvider is deleted
    // Future: Re-implement using a dedicated AnalyticsService if needed
    debugPrint('Notification tracked: id=$notificationId');
  }

  void executePendingNavigation() {
    if (_pendingRoute != null) {
      debugPrint(
        'NotificationNavigator: Executing pending navigation to $_pendingRoute',
      );
      _navigateTo(_pendingRoute!, arguments: _pendingArguments);
      _pendingRoute = null;
      _pendingArguments = null;
    }
  }

  /// Import task model and show the ringing overlay
  /// This helps in handling task alarms from both foreground and background
  void importTaskAndShowOverlay(dynamic taskData) {
    try {
      final taskJson = taskData is String ? jsonDecode(taskData) : taskData;
      if (taskJson == null) return;

      final task = TaskModel.fromJson(taskJson as Map<String, dynamic>);
      TaskAlarmService.showRingingOverlay(task);
    } catch (e) {
      debugPrint('NotificationNavigator: Error parsing task data: $e');
    }
  }
}
