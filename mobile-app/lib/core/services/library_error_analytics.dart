import 'dart:async';
import 'package:flutter/foundation.dart';
import '../api/api_client.dart';

/// P2: Library error analytics service
///
/// Tracks and reports library operation errors for monitoring and debugging.
/// Integrates with crash reporting services (Firebase Crashlytics, Sentry, etc.)
class LibraryErrorAnalytics {
  static final LibraryErrorAnalytics _instance = LibraryErrorAnalytics._internal();
  factory LibraryErrorAnalytics() => _instance;
  LibraryErrorAnalytics._internal();

  // Error categories for classification
  static const String categoryAuthentication = 'authentication';
  static const String categoryNetwork = 'network';
  static const String categoryStorage = 'storage';
  static const String categoryUpload = 'upload';
  static const String categoryDownload = 'download';
  static const String categorySync = 'sync';
  static const String categoryPermission = 'permission';
  static const String categoryUnknown = 'unknown';

  // Error severity levels
  static const String severityLow = 'low';
  static const String severityMedium = 'medium';
  static const String severityHigh = 'high';
  static const String severityCritical = 'critical';

  // Stream for real-time error monitoring
  final _errorController = StreamController<LibraryErrorEvent>.broadcast();
  Stream<LibraryErrorEvent> get errorStream => _errorController.stream;

  // In-memory buffer for recent errors (last 100)
  final List<LibraryErrorEvent> _recentErrors = [];
  static const int _maxRecentErrors = 100;

  /// Record an error with full context
  void recordError({
    required String operation,
    required Object error,
    StackTrace? stackTrace,
    String? category,
    String? severity,
    Map<String, dynamic>? additionalContext,
  }) {
    final event = LibraryErrorEvent(
      timestamp: DateTime.now(),
      operation: operation,
      error: error,
      stackTrace: stackTrace,
      category: category ?? _categorizeError(error),
      severity: severity ?? _calculateSeverity(error, operation),
      additionalContext: additionalContext,
    );

    // Add to recent errors buffer
    _recentErrors.add(event);
    if (_recentErrors.length > _maxRecentErrors) {
      _recentErrors.removeAt(0);
    }

    // Emit to stream for real-time monitoring
    _errorController.add(event);

    // Log for debugging
    debugPrint('[LibraryErrorAnalytics] ${event.category}/${event.severity}: ${event.operation} - ${event.error}');

    // Future enhancement: Integrate with Firebase Crashlytics or Sentry
    // FirebaseCrashlytics.instance.recordError(error, stackTrace, reason: operation);
  }

  /// Record a failed API call with status code
  void recordApiError({
    required String endpoint,
    required String operation,
    int? statusCode,
    String? errorCode,
    Object? error,
    StackTrace? stackTrace,
  }) {
    String category;
    String severity;

    if (statusCode == 401 || statusCode == 403) {
      category = categoryAuthentication;
      severity = severityHigh;
    } else if (statusCode == 404) {
      category = categoryUnknown; // Not found
      severity = severityLow;
    } else if (statusCode == 413) {
      category = categoryUpload;
      severity = severityMedium;
    } else if (statusCode == 500 || statusCode == 503) {
      category = categoryNetwork;
      severity = severityCritical;
    } else {
      category = categoryUnknown;
      severity = statusCode != null && statusCode >= 500 ? severityHigh : severityMedium;
    }

    recordError(
      operation: '$operation ($endpoint)',
      error: error ?? ApiException('API Error', statusCode: statusCode, code: errorCode),
      stackTrace: stackTrace,
      category: category,
      severity: severity,
      additionalContext: {
        'status_code': statusCode,
        'error_code': errorCode,
        'endpoint': endpoint,
      },
    );
  }

  /// Get recent errors for debugging
  List<LibraryErrorEvent> getRecentErrors({int limit = 20}) {
    final start = _recentErrors.length > limit ? _recentErrors.length - limit : 0;
    return _recentErrors.sublist(start);
  }

  /// Clear recent errors
  void clearRecentErrors() {
    _recentErrors.clear();
  }

  /// Get error statistics
  Map<String, dynamic> getErrorStats() {
    final now = DateTime.now();
    final last24Hours = now.subtract(const Duration(hours: 24));

    final recentErrors = _recentErrors.where((e) => e.timestamp.isAfter(last24Hours)).toList();

    return {
      'total_errors_24h': recentErrors.length,
      'by_category': _groupByCategory(recentErrors),
      'by_severity': _groupBySeverity(recentErrors),
      'by_operation': _groupByOperation(recentErrors),
    };
  }

  String _categorizeError(Object error) {
    if (error is AuthenticationException) {
      return categoryAuthentication;
    } else if (error is ApiException) {
      final code = error.code?.toLowerCase();
      if (code == null) return categoryUnknown;
      if (code.contains('storage')) return categoryStorage;
      if (code.contains('upload')) return categoryUpload;
      if (code.contains('download')) return categoryDownload;
      if (code.contains('permission') || code.contains('unauthorized')) return categoryPermission;
      return categoryUnknown;
    } else if (error is TimeoutException || error.toString().contains('timeout')) {
      return categoryNetwork;
    } else if (error.toString().contains('socket') || error.toString().contains('connection')) {
      return categoryNetwork;
    }
    return categoryUnknown;
  }

  String _calculateSeverity(Object error, String operation) {
    if (error is AuthenticationException) {
      return severityHigh;
    } else if (error is ApiException && error.statusCode != null && error.statusCode! >= 500) {
      return severityCritical;
    } else if (error is ApiException && error.statusCode != null && error.statusCode! >= 400) {
      return severityMedium;
    } else if (operation.contains('upload') || operation.contains('download')) {
      return severityMedium;
    }
    return severityLow;
  }

  Map<String, int> _groupByCategory(List<LibraryErrorEvent> errors) {
    final Map<String, int> result = {};
    for (final error in errors) {
      result[error.category] = (result[error.category] ?? 0) + 1;
    }
    return result;
  }

  Map<String, int> _groupBySeverity(List<LibraryErrorEvent> errors) {
    final Map<String, int> result = {};
    for (final error in errors) {
      result[error.severity] = (result[error.severity] ?? 0) + 1;
    }
    return result;
  }

  Map<String, int> _groupByOperation(List<LibraryErrorEvent> errors) {
    final Map<String, int> result = {};
    for (final error in errors) {
      // Extract operation type (e.g., "upload_file" from "upload_file (/api/library/upload)")
      final operation = error.operation.split(' ').first;
      result[operation] = (result[operation] ?? 0) + 1;
    }
    return result;
  }

  void dispose() {
    _errorController.close();
  }
}

/// Event representing a library error
class LibraryErrorEvent {
  final DateTime timestamp;
  final String operation;
  final Object error;
  final StackTrace? stackTrace;
  final String category;
  final String severity;
  final Map<String, dynamic>? additionalContext;

  LibraryErrorEvent({
    required this.timestamp,
    required this.operation,
    required this.error,
    this.stackTrace,
    required this.category,
    required this.severity,
    this.additionalContext,
  });

  @override
  String toString() {
    return 'LibraryErrorEvent($category/$severity): $operation - $error';
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'operation': operation,
      'error': error.toString(),
      'category': category,
      'severity': severity,
      'stack_trace': stackTrace?.toString(),
      'additional_context': additionalContext,
    };
  }
}
