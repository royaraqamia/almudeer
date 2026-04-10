import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Service to monitor network connectivity
/// Provides real-time connectivity status for network operations
class NetworkConnectivityService {
  static final NetworkConnectivityService _instance =
      NetworkConnectivityService._internal();
  factory NetworkConnectivityService() => _instance;
  NetworkConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  List<ConnectivityResult> _lastKnownResults = [];

  /// Stream of connectivity changes
  final StreamController<List<ConnectivityResult>> _connectivityStream =
      StreamController<List<ConnectivityResult>>.broadcast();

  Stream<List<ConnectivityResult>> get connectivityStream =>
      _connectivityStream.stream;

  /// Check if network is available (any type)
  Future<bool> get isConnected async {
    try {
      final results = await _connectivity.checkConnectivity();
      _lastKnownResults = results;
      return results.any((r) => r != ConnectivityResult.none);
    } catch (e) {
      // If we can't check, use last known state
      return _lastKnownResults.isNotEmpty &&
          _lastKnownResults.any((r) => r != ConnectivityResult.none);
    }
  }

  /// Check if connected via WiFi (preferred for large downloads)
  Future<bool> get isWifiConnected async {
    try {
      final results = await _connectivity.checkConnectivity();
      return results.any((r) =>
          r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet);
    } catch (e) {
      return false;
    }
  }

  /// Check if connected via mobile data
  Future<bool> get isMobileDataConnected async {
    try {
      final results = await _connectivity.checkConnectivity();
      return results.any((r) => r == ConnectivityResult.mobile);
    } catch (e) {
      return false;
    }
  }

  /// Start listening to connectivity changes
  void startListening() {
    _connectivitySubscription ??= _connectivity.onConnectivityChanged.listen(
      (results) {
        _lastKnownResults = results;
        _connectivityStream.add(results);
      },
      onError: (error) {
        // Log error but don't crash
        debugPrint('Connectivity monitoring error: $error');
      },
    );
  }

  /// Stop listening to connectivity changes
  void stopListening() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  /// Get current connectivity status
  List<ConnectivityResult> get currentConnectivity =>
      _lastKnownResults.isNotEmpty
          ? _lastKnownResults
          : [ConnectivityResult.none];

  /// Get human-readable connectivity status
  String get connectivityStatus {
    if (_lastKnownResults.isEmpty) return 'Unknown';
    if (_lastKnownResults.any((r) => r == ConnectivityResult.wifi)) {
      return 'WiFi';
    }
    if (_lastKnownResults.any((r) => r == ConnectivityResult.ethernet)) {
      return 'Ethernet';
    }
    if (_lastKnownResults.any((r) => r == ConnectivityResult.mobile)) {
      return 'Mobile Data';
    }
    if (_lastKnownResults.any((r) => r == ConnectivityResult.bluetooth)) {
      return 'Bluetooth';
    }
    return 'No Connection';
  }

  /// Dispose resources
  void dispose() {
    stopListening();
    _connectivityStream.close();
  }
}
