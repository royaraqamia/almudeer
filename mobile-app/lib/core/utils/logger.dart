import 'package:flutter/foundation.dart';

/// Simple logging utility for the app
/// 
/// Provides consistent logging with levels for production monitoring
class Logger {
  static const bool _isProduction = bool.fromEnvironment('dart.vm.product');
  
  /// Log info message (always shown in debug, limited in production)
  void info(String message, {Map<String, dynamic>? data}) {
    if (!_isProduction || kDebugMode) {
      debugPrint('[INFO] $message${data != null ? ' - $data' : ''}');
    }
  }
  
  /// Log warning message
  void warning(String message, {Object? error, StackTrace? stackTrace}) {
    debugPrint('[WARNING] $message');
    if (error != null) {
      debugPrint('Error: $error');
    }
    if (stackTrace != null) {
      debugPrint('StackTrace: $stackTrace');
    }
  }
  
  /// Log error message
  void error(String message, {Object? error, StackTrace? stackTrace}) {
    debugPrint('[ERROR] $message');
    if (error != null) {
      debugPrint('Error: $error');
    }
    if (stackTrace != null) {
      debugPrint('StackTrace: $stackTrace');
    }
  }
  
  /// Log debug message (only in debug mode)
  void debug(String message, {Map<String, dynamic>? data}) {
    if (kDebugMode) {
      debugPrint('[DEBUG] $message${data != null ? ' - $data' : ''}');
    }
  }
}

// Export a singleton instance for convenience
final logger = Logger();
