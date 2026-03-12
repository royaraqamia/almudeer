/// FIX #11: Centralized logging utility for library operations
///
/// Replaces debugPrint with structured logging that can be:
/// - Disabled in production
/// - Filtered by log level
/// - Sent to analytics/crash reporting services
///
/// Usage:
///   LibraryLogger.info('Item created', details: {'id': 123});
///   LibraryLogger.error('Upload failed', error: e, stackTrace: stack);
library;

import 'package:flutter/foundation.dart';

/// Log levels for filtering
enum LogLevel {
  debug,
  info,
  warning,
  error,
}

/// Library Logger with configurable log levels
class LibraryLogger {
  static LogLevel _currentLevel = kDebugMode ? LogLevel.debug : LogLevel.warning;
  
  /// Set minimum log level (messages below this level will be filtered)
  static void setLogLevel(LogLevel level) {
    _currentLevel = level;
  }
  
  /// Check if a log level should be printed
  static bool _shouldLog(LogLevel level) {
    return level.index >= _currentLevel.index;
  }
  
  /// Log debug message (only in debug mode by default)
  static void debug(String message, {String? tag, Map<String, dynamic>? details}) {
    if (!_shouldLog(LogLevel.debug)) return;
    
    _printLog('DEBUG', tag, message, details);
  }
  
  /// Log info message
  static void info(String message, {String? tag, Map<String, dynamic>? details}) {
    if (!_shouldLog(LogLevel.info)) return;
    
    _printLog('INFO', tag, message, details);
  }
  
  /// Log warning message
  static void warning(String message, {String? tag, Map<String, dynamic>? details}) {
    if (!_shouldLog(LogLevel.warning)) return;
    
    _printLog('WARN', tag, message, details);
  }
  
  /// Log error message with optional stack trace
  static void error(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? details,
  }) {
    if (!_shouldLog(LogLevel.error)) return;
    
    _printLog('ERROR', tag, message, details);
    
    if (error != null) {
      debugPrint('├─ Error: $error');
    }
    
    if (stackTrace != null && kDebugMode) {
      debugPrint('└─ Stack: $stackTrace');
    }
    
    // FIX #11: In production, send errors to analytics service
    if (!kDebugMode) {
      _reportToAnalytics(message, error, stackTrace, details);
    }
  }
  
  /// Print formatted log message
  static void _printLog(
    String level,
    String? tag,
    String message,
    Map<String, dynamic>? details,
  ) {
    final timestamp = DateTime.now().toIso8601String();
    final tagStr = tag != null ? '[$tag]' : '[Library]';
    
    debugPrint('$timestamp $tagStr $level: $message');
    
    if (details != null && kDebugMode) {
      for (final entry in details.entries) {
        debugPrint('  ├─ ${entry.key}: ${entry.value}');
      }
    }
  }
  
  /// Report error to analytics service (Firebase Crashlytics, Sentry, etc.)
  static void _reportToAnalytics(
    String message,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? details,
  ) {
    // In production, errors can be reported to Firebase Crashlytics or Sentry
    // Example for Firebase Crashlytics:
    // FirebaseCrashlytics.instance.log('[Library] $message');
    // if (error != null) {
    //   FirebaseCrashlytics.instance.recordError(error, stackTrace, reason: message);
    // }
  }
  
  /// Create a tagged logger for a specific component
  static LibraryLoggerComponent forComponent(String component) {
    return LibraryLoggerComponent(component);
  }
}

/// Component-specific logger for consistent tagging
class LibraryLoggerComponent {
  final String _component;
  
  LibraryLoggerComponent(this._component);
  
  void debug(String message, {Map<String, dynamic>? details}) {
    LibraryLogger.debug(message, tag: _component, details: details);
  }
  
  void info(String message, {Map<String, dynamic>? details}) {
    LibraryLogger.info(message, tag: _component, details: details);
  }
  
  void warning(String message, {Map<String, dynamic>? details}) {
    LibraryLogger.warning(message, tag: _component, details: details);
  }
  
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? details,
  }) {
    LibraryLogger.error(message, tag: _component, error: error, stackTrace: stackTrace, details: details);
  }
}
