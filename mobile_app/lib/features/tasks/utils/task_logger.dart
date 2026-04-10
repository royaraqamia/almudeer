import 'package:flutter/foundation.dart';

/// Task feature logging utility
/// 
/// Centralized logging for the tasks feature with environment-based control.
/// 
/// Usage:
///   TaskLogger.d('Debug message');  // Only shows in debug mode
///   TaskLogger.i('Info message');   // Only shows in debug mode
///   TaskLogger.w('Warning message'); // Always shown
///   TaskLogger.e('Error message');   // Always shown
/// 
/// To enable/disable logging:
///   TaskLogger.enabled = false;  // Disable all debug/info logs
class TaskLogger {
  /// Enable/disable debug and info level logging
  /// In production, set this to false to reduce log verbosity
  static bool enabled = kDebugMode;

  /// Optional prefix for all log messages (useful for filtering)
  static String prefix = '[Task]';

  /// Debug level logging (only when enabled)
  static void d(String message, {String? tag}) {
    if (enabled) {
      debugPrint(_formatMessage(message, tag, 'DEBUG'));
    }
  }

  /// Info level logging (only when enabled)
  static void i(String message, {String? tag}) {
    if (enabled) {
      debugPrint(_formatMessage(message, tag, 'INFO'));
    }
  }

  /// Warning level logging (always shown)
  static void w(String message, {String? tag}) {
    debugPrint(_formatMessage(message, tag, 'WARN'));
  }

  /// Error level logging (always shown)
  static void e(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    final formatted = _formatMessage(message, tag, 'ERROR');
    if (error != null) {
      debugPrint('$formatted - Error: $error');
      if (stackTrace != null) {
        debugPrint('Stack trace: $stackTrace');
      }
    } else {
      debugPrint(formatted);
    }
  }

  /// Verbose logging for detailed debugging (only when enabled)
  static void v(String message, {String? tag}) {
    if (enabled) {
      debugPrint(_formatMessage(message, tag, 'VERBOSE'));
    }
  }

  /// Format log message with prefix and tag
  static String _formatMessage(String message, String? tag, String level) {
    final tagStr = tag != null ? '[$tag]' : '';
    return '$prefix$tagStr $level: $message';
  }

  /// Log timezone resolution events (for Fix #7)
  static void timezone(String eventType, String timezoneId) {
    if (enabled) {
      debugPrint('[TimezoneTelemetry] $eventType: $timezoneId');
    }
  }

  /// Log sync events
  static void sync(String message) {
    if (enabled) {
      d(message, tag: 'Sync');
    }
  }

  /// Log alarm events
  static void alarm(String message) {
    if (enabled) {
      d(message, tag: 'Alarm');
    }
  }

  /// Log cache events
  static void cache(String message) {
    if (enabled) {
      d(message, tag: 'Cache');
    }
  }

  /// Log permission events
  static void permission(String message) {
    if (enabled) {
      d(message, tag: 'Permission');
    }
  }

  /// Log WebSocket events
  static void websocket(String message) {
    if (enabled) {
      d(message, tag: 'WebSocket');
    }
  }
}
