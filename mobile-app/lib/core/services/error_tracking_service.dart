import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Error severity levels
enum ErrorSeverity { debug, info, warning, error, critical }

/// Error context for additional metadata
class ErrorContext {
  final String? userId;
  final String? licenseKey;
  final String? screen;
  final String? action;
  final Map<String, dynamic> metadata;
  final DateTime timestamp;

  ErrorContext({
    this.userId,
    this.licenseKey,
    this.screen,
    this.action,
    Map<String, dynamic>? metadata,
    DateTime? timestamp,
  }) : metadata = metadata ?? {},
       timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'license_key': licenseKey,
    'screen': screen,
    'action': action,
    'metadata': metadata,
    'timestamp': timestamp.toIso8601String(),
  };
}

/// Tracked error with all metadata
class TrackedError {
  final String id;
  final String message;
  final String errorType;
  final String? stackTrace;
  final ErrorSeverity severity;
  final ErrorContext context;
  final bool reported;

  TrackedError({
    required this.id,
    required this.message,
    required this.errorType,
    this.stackTrace,
    required this.severity,
    required this.context,
    this.reported = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'message': message,
    'error_type': errorType,
    'stack_trace': stackTrace,
    'severity': severity.name,
    'context': context.toJson(),
    'reported': reported,
  };

  factory TrackedError.fromJson(Map<String, dynamic> json) {
    return TrackedError(
      id: json['id'] as String,
      message: json['message'] as String,
      errorType: json['error_type'] as String,
      stackTrace: json['stack_trace'] as String?,
      severity: ErrorSeverity.values.firstWhere(
        (s) => s.name == json['severity'],
        orElse: () => ErrorSeverity.info,
      ),
      context: ErrorContext(
        userId: json['context']?['user_id'] as String?,
        licenseKey: json['context']?['license_key'] as String?,
        screen: json['context']?['screen'] as String?,
        action: json['context']?['action'] as String?,
        metadata: Map<String, dynamic>.from(json['context']?['metadata'] ?? {}),
        timestamp: DateTime.parse(json['context']?['timestamp'] as String),
      ),
      reported: json['reported'] as bool? ?? false,
    );
  }
}

/// Comprehensive error tracking service
///
/// Features:
/// - Centralized error tracking across all features
/// - Persistent storage with Hive
/// - Automatic error aggregation and deduplication
/// - Severity-based filtering
/// - Optional reporting to external services (Sentry, etc.)
/// - Error analytics and metrics
class ErrorTrackingService extends ChangeNotifier {
  static final ErrorTrackingService _instance =
      ErrorTrackingService._internal();
  factory ErrorTrackingService() => _instance;
  ErrorTrackingService._internal();

  static const String _boxName = 'error_tracking';
  static const int _criticalRetentionDays = 30;
  static const int _normalRetentionDays = 7;

  Box<Map<String, dynamic>>? _box;
  bool _isInitialized = false;

  // In-memory cache for quick access
  final List<TrackedError> _recentErrors = [];
  final Map<String, int> _errorCounts = {}; // errorType -> count (last hour)

  // StreamController for error events
  final _errorController = StreamController<TrackedError>.broadcast();
  Stream<TrackedError> get errorStream => _errorController.stream;

  // Callbacks for critical errors
  final List<Function(TrackedError)> _criticalErrorCallbacks = [];

  /// Initialize the service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _box = await Hive.openBox<Map<String, dynamic>>(_boxName);
      await _loadRecentErrors();
      _isInitialized = true;
      debugPrint(
        '[ErrorTrackingService] Initialized with ${_recentErrors.length} recent errors',
      );
    } catch (e) {
      debugPrint('[ErrorTrackingService] Initialization failed: $e');
      // Continue without persistence
      _isInitialized = true;
    }

    // Cleanup old errors periodically
    Timer.periodic(const Duration(hours: 1), (_) => _cleanupOldErrors());
  }

  /// Track an error
  Future<void> track(
    Object error, {
    StackTrace? stackTrace,
    ErrorSeverity severity = ErrorSeverity.error,
    ErrorContext? context,
  }) async {
    final trackedError = TrackedError(
      id: '${error.runtimeType}_${DateTime.now().millisecondsSinceEpoch}',
      message: error.toString(),
      errorType: error.runtimeType.toString(),
      stackTrace: stackTrace?.toString(),
      severity: severity,
      context: context ?? ErrorContext(),
    );

    // Add to recent errors
    _recentErrors.add(trackedError);
    if (_recentErrors.length > 100) {
      _recentErrors.removeAt(0);
    }

    // Update error counts
    _errorCounts[trackedError.errorType] =
        (_errorCounts[trackedError.errorType] ?? 0) + 1;

    // Persist to disk
    if (_isInitialized && _box != null) {
      try {
        await _box!.put(trackedError.id, trackedError.toJson());
      } catch (e) {
        debugPrint('[ErrorTrackingService] Failed to persist error: $e');
      }
    }

    // Notify listeners
    _errorController.add(trackedError);
    notifyListeners();

    // Trigger critical error callbacks
    if (severity == ErrorSeverity.critical) {
      for (final callback in _criticalErrorCallbacks) {
        try {
          callback(trackedError);
        } catch (e) {
          debugPrint(
            '[ErrorTrackingService] Critical error callback failed: $e',
          );
        }
      }
    }

    // Log to console in debug mode
    if (kDebugMode) {
      _logToConsole(trackedError);
    }
  }

  /// Track a Flutter error from FlutterError.onError
  void trackFlutterError(FlutterErrorDetails details) {
    track(
      details.exception,
      stackTrace: details.stack,
      severity: details.silent ? ErrorSeverity.warning : ErrorSeverity.error,
      context: ErrorContext(
        metadata: {
          'library': details.library,
          'context': details.context?.toString() ?? 'unknown',
        },
      ),
    );
  }

  /// Track an error from ZoneSpecification
  void trackZoneError(Object error, StackTrace stackTrace) {
    track(error, stackTrace: stackTrace, severity: ErrorSeverity.error);
  }

  /// Register callback for critical errors
  void onCriticalError(Function(TrackedError) callback) {
    _criticalErrorCallbacks.add(callback);
  }

  /// Get recent errors
  List<TrackedError> getRecentErrors({int limit = 50}) {
    return _recentErrors.reversed.take(limit).toList();
  }

  /// Get error counts by type
  Map<String, int> getErrorCounts() => Map.unmodifiable(_errorCounts);

  /// Get errors by severity
  List<TrackedError> getErrorsBySeverity(ErrorSeverity severity) {
    return _recentErrors.where((e) => e.severity == severity).toList();
  }

  /// Get errors by screen/action
  List<TrackedError> getErrorsByContext({String? screen, String? action}) {
    return _recentErrors.where((e) {
      if (screen != null && e.context.screen != screen) return false;
      if (action != null && e.context.action != action) return false;
      return true;
    }).toList();
  }

  /// Clear all tracked errors
  Future<void> clearAll() async {
    _recentErrors.clear();
    _errorCounts.clear();
    if (_box != null) {
      await _box!.clear();
    }
    notifyListeners();
  }

  /// Mark error as reported to external service
  Future<void> markAsReported(String errorId) async {
    final index = _recentErrors.indexWhere((e) => e.id == errorId);
    if (index != -1) {
      final error = _recentErrors[index];
      _recentErrors[index] = TrackedError(
        id: error.id,
        message: error.message,
        errorType: error.errorType,
        stackTrace: error.stackTrace,
        severity: error.severity,
        context: error.context,
        reported: true,
      );
    }

    if (_box != null) {
      await _box!.put(errorId, {
        ..._recentErrors.firstWhere((e) => e.id == errorId).toJson(),
        'reported': true,
      });
    }
  }

  /// Get unreported errors (for batch reporting)
  List<TrackedError> getUnreportedErrors() {
    return _recentErrors.where((e) => !e.reported).toList();
  }

  Future<void> _loadRecentErrors() async {
    if (_box == null) return;

    try {
      final keys = _box!.keys.toList();
      for (final key in keys.take(100)) {
        final data = _box!.get(key) as Map<dynamic, dynamic>?;
        if (data != null) {
          _recentErrors.add(
            TrackedError.fromJson(Map<String, dynamic>.from(data)),
          );
        }
      }
      _recentErrors.sort(
        (a, b) => b.context.timestamp.compareTo(a.context.timestamp),
      );
    } catch (e) {
      debugPrint('[ErrorTrackingService] Failed to load errors: $e');
    }
  }

  void _cleanupOldErrors() {
    final now = DateTime.now();
    final toRemove = <String>[];

    for (final error in _recentErrors) {
      final age = now.difference(error.context.timestamp);
      final isCritical = error.severity == ErrorSeverity.critical;
      final maxAge = isCritical
          ? const Duration(days: _criticalRetentionDays)
          : const Duration(days: _normalRetentionDays);

      if (age > maxAge) {
        toRemove.add(error.id);
      }
    }

    for (final id in toRemove) {
      _recentErrors.removeWhere((e) => e.id == id);
      _box?.delete(id);
    }

    // Cleanup error counts (reset every hour)
    _errorCounts.clear();

    if (toRemove.isNotEmpty) {
      debugPrint(
        '[ErrorTrackingService] Cleaned up ${toRemove.length} old errors',
      );
    }
  }

  void _logToConsole(TrackedError error) {
    final prefix = switch (error.severity) {
      ErrorSeverity.debug => '🐛 DEBUG',
      ErrorSeverity.info => 'ℹ️ INFO',
      ErrorSeverity.warning => '⚠️ WARNING',
      ErrorSeverity.error => '❌ ERROR',
      ErrorSeverity.critical => '🔥 CRITICAL',
    };

    debugPrint('$prefix [${error.errorType}]: ${error.message}');
    if (error.stackTrace != null) {
      debugPrint(
        'Stack: ${error.stackTrace!.split('\n').take(5).join('\n')}...',
      );
    }
    if (error.context.screen != null) {
      debugPrint('Screen: ${error.context.screen}');
    }
    if (error.context.action != null) {
      debugPrint('Action: ${error.context.action}');
    }
  }

  @override
  void dispose() {
    _errorController.close();
    _box?.close();
    super.dispose();
  }
}

/// Extension for easy error tracking on BuildContext
extension ErrorTrackingExtension on Object {
  void trackError({
    String? message,
    StackTrace? stackTrace,
    ErrorSeverity severity = ErrorSeverity.error,
  }) {
    ErrorTrackingService().track(
      this,
      stackTrace: stackTrace,
      severity: severity,
      context: ErrorContext(metadata: {'message': message}),
    );
  }
}
