import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../api/endpoints.dart';
import '../api/api_client.dart';
import '../../data/repositories/auth_repository.dart';
import 'security_event_service.dart';

/// Connection state for WebSocket
enum WebSocketState { disconnected, connecting, connected, reconnecting, error }

/// Service for real-time updates via WebSockets
///
/// Features:
/// - Automatic reconnection with exponential backoff + jitter
/// - Heartbeat ping/pong to detect stale connections
/// - Connection state stream for UI feedback
class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _stateController = StreamController<WebSocketState>.broadcast();

  WebSocketState _state = WebSocketState.disconnected;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  Timer? _heartbeatTimeoutTimer;

  bool _isConnecting = false;
  String? _currentLicenseKey;

  // Exponential backoff settings
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _initialBackoff = Duration(
    seconds: 2,
  ); // Increased from 1s to 2s
  static const Duration _maxBackoff = Duration(
    seconds: 60,
  ); // Increased from 30s to 60s

  // Heartbeat settings
  // P1-7: Increased timeout from 10s to 60s to prevent unnecessary reconnections on slow mobile networks
  static const Duration _heartbeatInterval = Duration(seconds: 45);
  static const Duration _heartbeatTimeout = Duration(seconds: 60);

  final Random _random = Random();

  /// Stream of incoming WebSocket messages
  Stream<Map<String, dynamic>> get stream => _messageController.stream;

  /// Stream of connection state changes
  Stream<WebSocketState> get stateStream => _stateController.stream;

  /// Current connection state
  WebSocketState get state => _state;

  /// Whether the WebSocket is currently connected
  bool get isConnected => _state == WebSocketState.connected;

  /// Initialize and connect to WebSocket
  Future<void> connect() async {
    final licenseKey = await ApiClient().getLicenseKey();
    if (licenseKey == null) {
      debugPrint('[WebSocketService] No license key available, cannot connect');
      _updateState(WebSocketState.disconnected);
      return;
    }

    debugPrint('[WebSocketService] Connecting with license key: ${licenseKey.substring(0, 6)}...');

    // FIX: Store license key FIRST, then check if it changed
    final previousLicenseKey = _currentLicenseKey;
    _currentLicenseKey = licenseKey;

    // Reconnect if license key changed
    if (previousLicenseKey != null && previousLicenseKey != licenseKey) {
      debugPrint('[WebSocketService] License key changed from $previousLicenseKey to $licenseKey, reconnecting...');
      disconnect();
      // Wait for disconnect to complete before proceeding
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (_state == WebSocketState.connected || _isConnecting) {
      return;
    }

    _isConnecting = true;
    _updateState(WebSocketState.connecting);

    // Security Check: Verify Auth
    try {
      if (!await AuthRepository().isAuthenticated()) {
        _updateState(WebSocketState.disconnected);
        _isConnecting = false;
        return;
      }
    } catch (_) {
      _updateState(WebSocketState.disconnected);
      _isConnecting = false;
      return;
    }

    final wsUrl = Endpoints.baseUrl.replaceFirst('http', 'ws');

    // FIX: Use header-based authentication instead of query params for better security
    // Query params can leak in logs, headers are more secure
    final uri = Uri.parse('$wsUrl/ws');

    try {
      debugPrint(
        '[WebSocketService] Connecting to $uri',
      );

      // SECURITY FIX #22: Use JWT access token instead of license key
      // Get the access token from ApiClient
      final accessToken = await ApiClient().getAccessToken(licenseKey);

      if (accessToken == null || accessToken.isEmpty) {
        debugPrint('[WebSocketService] No access token available, cannot connect');
        _updateState(WebSocketState.disconnected);
        _isConnecting = false;
        return;
      }

      // Connect with JWT authorization header
      // SECURITY: Never send license key in WebSocket headers
      final headers = <String, String>{
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      };

      _channel = IOWebSocketChannel.connect(
        uri,
        headers: headers,
      );

      // Wait for connection to be ready
      await _channel!.ready;

      _isConnecting = false;
      _updateState(WebSocketState.connected);
      _reconnectAttempts = 0;
      _startHeartbeat();

      debugPrint('[WebSocketService] Connected successfully');

      _subscription = _channel!.stream.listen(
        (message) => _handleMessage(message),
        onDone: () => _handleDisconnect('Connection closed'),
        onError: (error) => _handleDisconnect('Connection error: $error'),
        cancelOnError: false,
      );
    } catch (e) {
      _isConnecting = false;
      _updateState(WebSocketState.error);
      _handleDisconnect('Connection failed: $e');
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      final eventType = data['event'] as String?;

      // Handle security events
      if (eventType == 'account_disabled') {
        debugPrint('[WebSocketService] Account disabled event received');
        SecurityEventService().emit(SecurityEvent.accountDisabled);
        return;
      }

      // Handle heartbeat response
      if (eventType == 'pong') {
        _cancelHeartbeatTimeout();
        return;
      }

      // Forward all conversation-related events to providers
      // These events are handled by inbox_provider.dart and conversation_detail_provider.dart
      if (eventType != null &&
          [
            'new_message',
            'message_edited',
            'message_deleted',
            'conversation_deleted',
            'chat_cleared',
            'typing_indicator',
            'recording_indicator',
            'presence_update',
            'message_status_update',
            'notification',
            'customer_updated',
            'subscription_updated',
            'conversation_read',
            // Share events for instant UI updates
            'library_shared',
            'task_shared',
          ].contains(eventType)) {
        _messageController.add(data);
        return;
      }

      // Forward any other events by default
      _messageController.add(data);
    } catch (e, stackTrace) {
      // FIX P2-4: Handle parse error with logging to prevent crashing the listener
      debugPrint('[WebSocketService] Error parsing message: $e');
      debugPrint('Stack trace: $stackTrace');
      debugPrint('Raw message: $message');
    }
  }

  void _handleDisconnect(String reason) {
    _stopHeartbeat();
    _subscription?.cancel();
    _subscription = null;
    _channel = null;

    if (_state != WebSocketState.disconnected) {
      _updateState(WebSocketState.reconnecting);
      _scheduleReconnect();
    }
  }

  /// Send a message to the WebSocket
  void send(Map<String, dynamic> data) {
    if (isConnected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode(data));
      } catch (e) {
        _handleDisconnect('Send failed: $e');
      }
    }
  }

  /// Disconnect from WebSocket
  void disconnect() {
    _reconnectAttempts = _maxReconnectAttempts; // Prevent reconnection
    _reconnectTimer?.cancel();
    _stopHeartbeat();
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _updateState(WebSocketState.disconnected);
    _isConnecting = false;
  }

  void _updateState(WebSocketState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _updateState(WebSocketState.disconnected);
      return;
    }

    // P2-3 FIX: Improved jitter calculation with exponential distribution
    // This prevents thundering herd on server restart by spreading connections
    final backoffMs =
        _initialBackoff.inMilliseconds * pow(2, _reconnectAttempts);
    final cappedBackoffMs = min(backoffMs, _maxBackoff.inMilliseconds);
    
    // P2-3 FIX: Use exponential distribution for better spread
    // Previous linear jitter still caused clustering
    // Now using: base_delay * (0.5 + random * 0.5) = 50%-100% of base delay
    final jitterMultiplier = 0.5 + _random.nextDouble() * 0.5;
    final delayMs = (cappedBackoffMs * jitterMultiplier).toInt();

    _reconnectAttempts++;

    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () async {
      if (!await AuthRepository().isAuthenticated()) {
        _updateState(WebSocketState.disconnected);
        return;
      }

      if (_state == WebSocketState.reconnecting ||
          _state == WebSocketState.error) {
        connect();
      }
    });
  }

  void _startHeartbeat() {
    _stopHeartbeat();

    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (isConnected) {
        _sendPing();
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _cancelHeartbeatTimeout();
  }

  Future<void> _sendPing() async {
    if (!isConnected) return;

    try {
      final pingMessage = {'event': 'ping'};

      _channel?.sink.add(jsonEncode(pingMessage));

      // Set timeout for pong response
      _heartbeatTimeoutTimer = Timer(_heartbeatTimeout, () {
        _handleDisconnect('Heartbeat timeout');
      });
    } catch (e) {
      _handleDisconnect('Ping failed: $e');
    }
  }

  void _cancelHeartbeatTimeout() {
    _heartbeatTimeoutTimer?.cancel();
    _heartbeatTimeoutTimer = null;
  }

  /// Force immediate reconnection
  void forceReconnect() {
    _reconnectTimer?.cancel();
    _reconnectAttempts = 0;
    disconnect();
    _updateState(WebSocketState.disconnected);
    connect();
  }

  /// Dispose the service
  void dispose() {
    disconnect();
    _messageController.close();
    _stateController.close();
  }
}
