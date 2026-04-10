import 'dart:async';

/// Types of security events that can be emitted
enum SecurityEvent {
  /// Triggered when the account is disabled or deleted on the backend
  accountDisabled,
}

/// A global event bus for security-related signals.
///
/// This allows services like [FcmService] or [WebSocketService] to emit
/// critical security signals that UI providers (like [AuthProvider])
/// can listen to and react upon.
class SecurityEventService {
  static final SecurityEventService _instance =
      SecurityEventService._internal();
  factory SecurityEventService() => _instance;
  SecurityEventService._internal();

  final _eventController = StreamController<SecurityEvent>.broadcast();

  /// Stream of security events
  Stream<SecurityEvent> get eventStream => _eventController.stream;

  /// Emit a new security event
  void emit(SecurityEvent event) {
    _eventController.add(event);
  }

  /// Close the stream controller (typically not needed for a global singleton)
  void dispose() {
    _eventController.close();
  }
}
