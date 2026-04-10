import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

import '../api/endpoints.dart';

/// Connectivity status enum
enum ConnectivityStatus {
  online,
  offline,

  /// Weak connection (e.g., mobile with poor signal)
  weak,
}

/// Service for real-time network monitoring with debouncing.
///
/// Features:
/// - Stream-based connectivity status
/// - Debounced state changes to avoid rapid toggling
/// - Automatic sync trigger callbacks on reconnection
/// - **Actual server reachability verification**
class ConnectivityService extends ChangeNotifier {
  static ConnectivityService? _instance;

  factory ConnectivityService() {
    return _instance ??= ConnectivityService._internal();
  }

  @visibleForTesting
  factory ConnectivityService.test({
    required Connectivity connectivity,
    required http.Client client,
  }) {
    return ConnectivityService._internal(
      connectivity: connectivity,
      client: client,
    );
  }

  ConnectivityService._internal({
    Connectivity? connectivity,
    http.Client? client,
  }) : _connectivity = connectivity ?? Connectivity(),
       _client = client ?? http.Client();

  final Connectivity _connectivity;
  final http.Client _client;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  ConnectivityStatus _status = ConnectivityStatus.online;
  bool _isInitialized = false;

  /// Debounce timer to prevent rapid state changes
  Timer? _debounceTimer;
  static const Duration _debounceDuration = Duration(milliseconds: 500);

  /// Server reachability cache
  DateTime? _lastReachabilityCheck;
  bool _isServerReachable = true;
  static const Duration _reachabilityCacheDuration = Duration(seconds: 5);
  static const Duration _reachabilityTimeout = Duration(seconds: 5);

  /// Callbacks to trigger when connectivity is restored
  final List<VoidCallback> _onReconnectCallbacks = [];

  /// Current connectivity status
  ConnectivityStatus get status => _status;

  /// Quick check for online status
  bool get isOnline => _status == ConnectivityStatus.online;

  /// Quick check for offline status
  bool get isOffline => _status == ConnectivityStatus.offline;

  /// Whether server is reachable (last check result)
  bool get isServerReachable => _isServerReachable;

  /// Initialize the service and start listening
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Get initial status
    final result = await _connectivity.checkConnectivity();
    final networkStatus = _mapResultToStatus(result);

    // Initialize with optimistic status based on OS signal
    // We don't wait for the HTTP check here to avoid blocking app startup
    _updateStatus(networkStatus, notify: false);

    // Listen for changes
    _subscription = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
    );

    _isInitialized = true;
    debugPrint('[ConnectivityService] Initialized with status: $_status');

    // Verify actual server reachability in background if network appears available
    if (networkStatus != ConnectivityStatus.offline) {
      _verifyServerReachable().then((isReachable) {
        if (!isReachable && _status != ConnectivityStatus.offline) {
          _updateStatus(ConnectivityStatus.offline);
        }
      });
    }
  }

  /// Periodic timer for active polling when offline
  Timer? _pollingTimer;

  /// P1-2 FIX: Adaptive poll interval based on offline duration
  /// Starts fast (5s) but backs off to 60s after prolonged offline
  Duration _currentPollInterval = const Duration(seconds: 5);
  DateTime? _offlineSince;
  static const Duration _minPollInterval = Duration(seconds: 5);
  static const Duration _maxPollInterval = Duration(seconds: 60);

  /// Get current poll interval (for testing)
  Duration get currentPollInterval => _currentPollInterval;

  /// Calculate adaptive poll interval based on offline duration
  /// P1-2 FIX: Exponential backoff to save battery and reduce server load
  Duration _calculateAdaptivePollInterval() {
    if (_offlineSince == null) {
      return _minPollInterval;
    }

    final offlineDuration = DateTime.now().difference(_offlineSince!);
    
    // Exponential backoff: 5s, 10s, 20s, 40s, 60s, 60s...
    // Caps at 60 seconds to ensure eventual recovery detection
    final intervals = [5, 10, 20, 40, 60];
    final stage = (offlineDuration.inSeconds / 30).floor(); // New stage every 30s offline
    
    if (stage >= intervals.length) {
      return _maxPollInterval;
    }
    
    return Duration(seconds: intervals[stage]);
  }

  /// Handle connectivity changes with debouncing
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () async {
      final networkStatus = _mapResultToStatus(results);

      // If network is completely gone (Airplane mode, no WiFi), stop polling and go offline
      if (networkStatus == ConnectivityStatus.offline) {
        _updateStatus(ConnectivityStatus.offline);
        _stopPolling();
        return;
      }

      // Connectivity changed (e.g. WiFi connected), force verify immediately
      // ignoring cache to ensure we catch the "back online" state quickly.
      await _verifyServerReachable(forceRefresh: true);

      final isNowReachable = _isServerReachable;

      _updateStatus(
        isNowReachable ? networkStatus : ConnectivityStatus.offline,
      );

      // If we are still effectively offline (server unreachable despite WiFi), start polling
      if (!isNowReachable) {
        _startPolling();
      } else {
        _stopPolling();
      }
    });
  }

  /// Verify actual server reachability by pinging health endpoint
  Future<bool> _verifyServerReachable({bool forceRefresh = false}) async {
    // Check cache first (unless forced)
    if (!forceRefresh && _lastReachabilityCheck != null) {
      final age = DateTime.now().difference(_lastReachabilityCheck!);
      if (age < _reachabilityCacheDuration) {
        return _isServerReachable;
      }
    }

    try {
      final response = await _client
          .get(Uri.parse('${Endpoints.baseUrl}/health'))
          .timeout(_reachabilityTimeout);

      final prevReachable = _isServerReachable;
      _isServerReachable =
          response.statusCode >= 200 && response.statusCode < 400;
      _lastReachabilityCheck = DateTime.now();

      if (prevReachable != _isServerReachable) {
        debugPrint(
          '[ConnectivityService] Reachability changed: $_isServerReachable (${response.statusCode})',
        );
      }
    } on SocketException {
      _isServerReachable = false;
      _lastReachabilityCheck = DateTime.now();
      // debugPrint('[ConnectivityService] Server unreachable (SocketException)'); // Reduce noise
    } on TimeoutException {
      _isServerReachable = false;
      _lastReachabilityCheck = DateTime.now();
      // debugPrint('[ConnectivityService] Server unreachable (Timeout)'); // Reduce noise
    } catch (e) {
      _isServerReachable = false;
      _lastReachabilityCheck = DateTime.now();
      debugPrint('[ConnectivityService] Reachability check failed: $e');
    }

    return _isServerReachable;
  }

  void _startPolling() {
    if (_pollingTimer != null && _pollingTimer!.isActive) return;
    
    // P1-2 FIX: Track when we went offline for adaptive backoff
    _offlineSince ??= DateTime.now();
    
    debugPrint('[ConnectivityService] Starting adaptive polling for recovery...');
    _pollingTimer = Timer.periodic(_currentPollInterval, (timer) async {
      // Force check
      await _verifyServerReachable(forceRefresh: true);

      if (_isServerReachable) {
        debugPrint('[ConnectivityService] Recovered via polling!');
        _updateStatus(ConnectivityStatus.online);
        _stopPolling();
      } else {
        // P1-2 FIX: Adjust poll interval based on offline duration
        final newInterval = _calculateAdaptivePollInterval();
        if (newInterval != _currentPollInterval) {
          debugPrint('[ConnectivityService] Adjusting poll interval: ${_currentPollInterval.inSeconds}s -> ${newInterval.inSeconds}s');
          _currentPollInterval = newInterval;
          _pollingTimer?.cancel();
          _startPolling(); // Restart with new interval
        }
      }
    });
  }

  void _stopPolling() {
    if (_pollingTimer != null) {
      _pollingTimer!.cancel();
      _pollingTimer = null;
      // P1-2 FIX: Reset offline tracking
      _offlineSince = null;
      _currentPollInterval = _minPollInterval;
      debugPrint('[ConnectivityService] Stopped polling');
    }
  }

  /// Map connectivity results to our status enum
  ConnectivityStatus _mapResultToStatus(List<ConnectivityResult> results) {
    if (results.isEmpty || results.contains(ConnectivityResult.none)) {
      return ConnectivityStatus.offline;
    }

    // WiFi or Ethernet = strong connection
    if (results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet)) {
      return ConnectivityStatus.online;
    }

    // Mobile data - could be weak depending on signal
    // For now, treat as online (could enhance with signal strength check)
    if (results.contains(ConnectivityResult.mobile)) {
      return ConnectivityStatus.online;
    }

    // VPN or other
    if (results.contains(ConnectivityResult.vpn)) {
      return ConnectivityStatus.online;
    }

    return ConnectivityStatus.offline;
  }

  /// Update status and trigger callbacks if reconnected
  void _updateStatus(ConnectivityStatus newStatus, {bool notify = true}) {
    final wasOffline = _status == ConnectivityStatus.offline;
    final previousStatus = _status;
    _status = newStatus;

    if (notify && previousStatus != newStatus) {
      debugPrint(
        '[ConnectivityService] Status changed: $previousStatus -> $newStatus',
      );
      notifyListeners();

      // Trigger reconnection callbacks if we came back online
      if (wasOffline && newStatus == ConnectivityStatus.online) {
        _triggerReconnectCallbacks();
      }
    }
  }

  /// Register a callback to be called when connectivity is restored
  void addReconnectCallback(VoidCallback callback) {
    _onReconnectCallbacks.add(callback);
  }

  /// Remove a reconnection callback
  void removeReconnectCallback(VoidCallback callback) {
    _onReconnectCallbacks.remove(callback);
  }

  /// Trigger all reconnection callbacks
  void _triggerReconnectCallbacks() {
    debugPrint(
      '[ConnectivityService] Triggering ${_onReconnectCallbacks.length} reconnect callbacks',
    );
    for (final callback in _onReconnectCallbacks) {
      try {
        callback();
      } catch (e) {
        debugPrint('[ConnectivityService] Reconnect callback error: $e');
      }
    }
  }

  /// Force check connectivity (useful for manual refresh)
  Future<ConnectivityStatus> checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    final networkStatus = _mapResultToStatus(result);

    if (networkStatus != ConnectivityStatus.offline) {
      await _verifyServerReachable();
    }

    final finalStatus =
        networkStatus == ConnectivityStatus.offline || !_isServerReachable
        ? ConnectivityStatus.offline
        : networkStatus;

    _updateStatus(finalStatus);
    return finalStatus;
  }

  /// Force clear reachability cache (for testing or retry)
  void clearReachabilityCache() {
    _lastReachabilityCheck = null;
  }

  /// Dispose the service
  @override
  void dispose() {
    _debounceTimer?.cancel();
    _subscription?.cancel();
    _onReconnectCallbacks.clear();
    super.dispose();
  }
}
