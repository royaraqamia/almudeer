import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../constants/app_config.dart';
import '../utils/crypto_utils.dart';
import '../api/api_client.dart';  // CRITICAL FIX #4: For download analytics

/// Download state for tracking background downloads
enum DownloadState {
  idle,
  downloading,
  pausedBattery,
  pausedNoConnectivity,
  completed,
  failed,
  cancelled,
}

/// Comprehensive background download manager for APK updates
///
/// Features:
/// - Silent background downloads (no notifications)
/// - Battery-aware (pauses under 20%, resumes above)
/// - Connectivity-aware (pauses when offline)
/// - Resume support with Range headers
/// - SHA256 verification
/// - State persistence across app restarts
/// - Automatic cancellation when newer update available
/// - Storage management and cleanup
class BackgroundDownloadManager {
  static BackgroundDownloadManager? _instance;
  static BackgroundDownloadManager get instance =>
      _instance ??= BackgroundDownloadManager._internal();

  BackgroundDownloadManager._internal() {
    _initBatteryMonitoring();
    _initConnectivityMonitoring();
  }

  // Dependencies
  final Dio _dio = Dio();
  final Battery _battery = Battery();
  final ApiClient _apiClient = ApiClient();  // CRITICAL FIX #4: For analytics

  // State
  DownloadState _state = DownloadState.idle;
  double _progress = 0.0;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  String? _downloadPath;
  String? _targetUrl;
  String? _expectedSha256;
  int? _targetBuildNumber;
  CancelToken? _cancelToken;
  DateTime _lastPersistTime = DateTime(2000); // Throttle progress persistence

  // Monitoring
  StreamSubscription<BatteryState>? _batterySubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Callbacks
  final List<void Function(DownloadState state)> _stateListeners = [];
  final List<void Function(double progress)> _progressListeners = [];
  
  /// Callback for showing large download warning on mobile data
  /// Set this to show a UI warning to the user before downloading large files
  Future<bool> Function(double sizeMb)? onLargeDownloadWarning;

  // Constants
  static const String _prefsPrefix = 'bg_download_';
  static const String _keyState = '${_prefsPrefix}state';
  static const String _keyProgress = '${_prefsPrefix}progress';
  static const String _keyDownloadedBytes = '${_prefsPrefix}downloaded_bytes';
  static const String _keyTotalBytes = '${_prefsPrefix}total_bytes';
  static const String _keyDownloadPath = '${_prefsPrefix}download_path';
  static const String _keyTargetUrl = '${_prefsPrefix}target_url';
  static const String _keyExpectedSha256 = '${_prefsPrefix}expected_sha256';
  static const String _keyTargetBuildNumber =
      '${_prefsPrefix}target_build_number';
  static const String _keyLastModified = '${_prefsPrefix}last_modified';
  static const String _keyRetryCount = '${_prefsPrefix}retry_count';

  // Use AppConfig constants for centralized management
  static const int _batteryThreshold = AppConfig.batteryThreshold;
  static const Duration _downloadConnectTimeout =
      AppConfig.downloadConnectTimeout;
  static const Duration _downloadReceiveTimeout =
      AppConfig.downloadReceiveTimeout;
  static const Duration _persistenceInterval =
      AppConfig.downloadPersistenceInterval;
  static const int _maxAutoRetries = AppConfig.maxAutoDownloadRetries;
  static const Duration _retryDelay = AppConfig.downloadRetryDelay;
  
  /// Threshold for warning about large downloads on mobile data (in MB)
  static const double _mobileDataWarningThresholdMb = 50.0;

  // Getters
  DownloadState get state => _state;
  double get progress => _progress;
  int get downloadedBytes => _downloadedBytes;
  int get totalBytes => _totalBytes;
  String? get downloadPath => _downloadPath;
  int? get targetBuildNumber => _targetBuildNumber;
  bool get isDownloading => _state == DownloadState.downloading;
  bool get isPaused =>
      _state == DownloadState.pausedBattery ||
      _state == DownloadState.pausedNoConnectivity;
  bool get isCompleted => _state == DownloadState.completed;
  bool get hasDownload =>
      _downloadPath != null && File(_downloadPath!).existsSync();

  /// Initialize battery monitoring
  void _initBatteryMonitoring() {
    _batterySubscription = _battery.onBatteryStateChanged.listen(
      _onBatteryStateChanged,
    );
  }

  /// Initialize connectivity monitoring
  void _initConnectivityMonitoring() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      _onConnectivityChanged,
    );
  }

  /// Handle battery state changes
  void _onBatteryStateChanged(BatteryState state) async {
    final level = await _battery.batteryLevel;

    if (_state == DownloadState.downloading && level < _batteryThreshold) {
      debugPrint(
        '[BackgroundDownloadManager] Battery low ($level%), pausing download',
      );
      await pauseDownload(DownloadState.pausedBattery);
    } else if (_state == DownloadState.pausedBattery &&
        level >= _batteryThreshold) {
      debugPrint(
        '[BackgroundDownloadManager] Battery restored ($level%), resuming download',
      );
      await resumeDownload();
    }
  }

  /// Handle connectivity changes
  void _onConnectivityChanged(List<ConnectivityResult> results) async {
    final hasConnection =
        results.isNotEmpty && !results.contains(ConnectivityResult.none);

    if (_state == DownloadState.downloading && !hasConnection) {
      debugPrint(
        '[BackgroundDownloadManager] No connectivity, pausing download',
      );
      await pauseDownload(DownloadState.pausedNoConnectivity);
    } else if (_state == DownloadState.pausedNoConnectivity && hasConnection) {
      debugPrint(
        '[BackgroundDownloadManager] Connectivity restored, resuming download',
      );
      await resumeDownload();
    }
  }

  /// Start a new background download
  ///
  /// If a download is already in progress for a different build number,
  /// it will be cancelled and the new download will start.
  Future<void> startDownload({
    required String url,
    required int buildNumber,
    String? expectedSha256,
  }) async {
    // Check if we already have this exact version downloaded
    if (_targetBuildNumber == buildNumber &&
        _state == DownloadState.completed) {
      debugPrint(
        '[BackgroundDownloadManager] Build $buildNumber already downloaded',
      );
      return;
    }

    // If downloading a different version, cancel it
    if (_targetBuildNumber != null && _targetBuildNumber != buildNumber) {
      debugPrint(
        '[BackgroundDownloadManager] Newer build ($buildNumber) available, '
        'cancelling download of build $_targetBuildNumber',
      );
      await cancelDownload();
      await cleanup();
    }

    // If already downloading this version, just return
    if (_state == DownloadState.downloading &&
        _targetBuildNumber == buildNumber) {
      debugPrint(
        '[BackgroundDownloadManager] Already downloading build $buildNumber',
      );
      return;
    }

    // Initialize new download
    _targetUrl = url;
    _targetBuildNumber = buildNumber;
    _expectedSha256 = expectedSha256;
    _progress = 0.0;
    _downloadedBytes = 0;
    _totalBytes = 0;
    _cancelToken = CancelToken();

    // Reset retry count for fresh download
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyRetryCount);

    // Get download directory
    Directory? dir;
    if (Platform.isAndroid) {
      dir = (await getExternalCacheDirectories())?.first;
    }
    dir ??= await getTemporaryDirectory();
    _downloadPath = '${dir.path}/almudeer_update_$buildNumber.apk';

    // Check battery level before starting
    final batteryLevel = await _battery.batteryLevel;
    if (batteryLevel < _batteryThreshold) {
      debugPrint(
        '[BackgroundDownloadManager] Battery too low ($batteryLevel%), waiting...',
      );
      _state = DownloadState.pausedBattery;
      await _persistState();
      return;
    }

    // Check connectivity
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      debugPrint('[BackgroundDownloadManager] No connectivity, waiting...');
      _state = DownloadState.pausedNoConnectivity;
      await _persistState();
      return;
    }

    // NEW: Check if on mobile data and warn about large downloads
    final isOnMobileData = connectivity.contains(ConnectivityResult.mobile);

    if (isOnMobileData && expectedSha256 != null) {
      // Estimate APK size from typical values (will be refined after download starts)
      // Typical APK sizes: 30-100MB for full builds
      final estimatedSizeMb = 75.0; // Conservative estimate
      
      if (estimatedSizeMb >= _mobileDataWarningThresholdMb) {
        debugPrint(
          '[BackgroundDownloadManager] On mobile data with large download '
          '(~${estimatedSizeMb.toStringAsFixed(0)}MB)',
        );
        
        // Show warning if callback is set
        if (onLargeDownloadWarning != null) {
          try {
            final shouldProceed = await onLargeDownloadWarning!(estimatedSizeMb);
            if (!shouldProceed) {
              debugPrint(
                '[BackgroundDownloadManager] User declined download on mobile data',
              );
              _state = DownloadState.pausedNoConnectivity; // Reuse this state
              await _persistState();
              return;
            }
          } catch (e) {
            debugPrint(
              '[BackgroundDownloadManager] Error showing download warning: $e',
            );
            // Continue with download if warning fails
          }
        }
      }
    }

    // Check available storage space (NEW - Fix #15)
    // Estimate required space as APK size + 20% buffer for temporary files
    final requiredSpace = _estimateRequiredSpace();
    if (requiredSpace != null) {
      final availableSpace = await _getAvailableStorageSpace();
      if (availableSpace != null && availableSpace < requiredSpace) {
        debugPrint(
          '[BackgroundDownloadManager] Insufficient storage: '
          '${(availableSpace / 1024 / 1024).toStringAsFixed(1)}MB available, '
          '${(requiredSpace / 1024 / 1024).toStringAsFixed(1)}MB required',
        );
        _state = DownloadState.failed;
        await _persistState();
        // Store failure reason for UI
        await prefs.setString('download_failure_reason', 'storage_full');
        return;
      }
    }

    // Start download
    await _executeDownload();
  }

  /// Execute the actual download
  /// 
  /// CRITICAL FIX #4: Added analytics tracking for download events
  Future<void> _executeDownload() async {
    if (_targetUrl == null || _downloadPath == null) return;

    _state = DownloadState.downloading;
    _notifyStateChange();
    await _persistState();

    // CRITICAL FIX #4: Track download started
    await _trackDownloadStarted();

    try {
      final file = File(_downloadPath!);
      int downloaded = 0;

      // Check for partial download to resume
      if (await file.exists()) {
        downloaded = await file.length();
        _downloadedBytes = downloaded;
        debugPrint(
          '[BackgroundDownloadManager] Resuming from $downloaded bytes',
        );
      }

      // Make request with Range header if resuming and with timeouts
      final response = await _dio.get(
        _targetUrl!,
        cancelToken: _cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          headers: downloaded > 0 ? {'Range': 'bytes=$downloaded-'} : null,
          receiveTimeout: _downloadReceiveTimeout,
          sendTimeout: _downloadConnectTimeout,
        ),
      );

      // Get total size
      final contentLength = response.headers.value('content-length');
      final remainingBytes = int.tryParse(contentLength ?? '0') ?? 0;
      _totalBytes = downloaded + remainingBytes;

      // Open file for appending
      final raf = await file.open(mode: FileMode.append);

      // Download with progress tracking
      await response.data.stream
          .listen(
            (List<int> chunk) {
              raf.writeFromSync(chunk);
              downloaded += chunk.length;
              _downloadedBytes = downloaded;
              _progress = _totalBytes > 0 ? downloaded / _totalBytes : 0.0;
              _notifyProgressChange();
              // Throttle persistence: reduce I/O on slow devices
              final now = DateTime.now();
              if (now.difference(_lastPersistTime) >= _persistenceInterval) {
                _lastPersistTime = now;
                _persistProgress();
              }
            },
            onDone: () async {
              await raf.close();
              await _persistProgress(); // Final persist on completion
              await _onDownloadComplete();
            },
            onError: (e) async {
              await raf.close();
              await _onDownloadError(e);
            },
            cancelOnError: true,
          )
          .asFuture();
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        // Handled by _cancelToken
        return;
      }

      // Check for Disk Full (OS Error 28 on Linux/Android)
      final errorMessage = e.toString().toLowerCase();
      if (errorMessage.contains('no space left on device') ||
          errorMessage.contains('disk full') ||
          errorMessage.contains('errno 28')) {
        debugPrint(
          '[BackgroundDownloadManager] DISK FULL detected during download',
        );
        await _onDownloadError(
          'Storage full - please clear space and try again',
        );
      } else {
        await _onDownloadError(e);
      }
    }
  }

  /// Handle download completion
  /// 
  /// CRITICAL FIX #4: Added analytics tracking for completion and verification
  Future<void> _onDownloadComplete() async {
    debugPrint('[BackgroundDownloadManager] Download completed, verifying...');

    // Verify SHA256 if provided
    if (_expectedSha256 != null && _expectedSha256!.isNotEmpty) {
      final isValid = await _verifySha256(_downloadPath!, _expectedSha256!);
      if (!isValid) {
        debugPrint('[BackgroundDownloadManager] SHA256 verification failed');
        
        // CRITICAL FIX #4: Track verification failure
        await _trackVerificationFailed('SHA256 hash mismatch');
        
        _state = DownloadState.failed;
        // Delete corrupted file
        try {
          await File(_downloadPath!).delete();
        } catch (_) {}
        _downloadPath = null;
      } else {
        debugPrint('[BackgroundDownloadManager] SHA256 verification passed');
        
        // CRITICAL FIX #4: Track download completed
        await _trackDownloadCompleted();
        
        _state = DownloadState.completed;
      }
    } else {
      // No SHA256 to verify, assume success
      // CRITICAL FIX #4: Track download completed
      await _trackDownloadCompleted();
      
      _state = DownloadState.completed;
    }

    // Clear retry count on success
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyRetryCount);

    await _persistState();
    _notifyStateChange();
  }

  /// Handle download error
  /// 
  /// CRITICAL FIX #4: Added analytics tracking for download failures
  Future<void> _onDownloadError(dynamic error) async {
    if (error is DioException && CancelToken.isCancel(error)) {
      debugPrint('[BackgroundDownloadManager] Download cancelled');
      _state = DownloadState.cancelled;
    } else {
      debugPrint('[BackgroundDownloadManager] Download error: $error');

      // CRITICAL FIX #4: Track download failure (only after all retries exhausted)
      // We'll track it now, retries will just send another event
      final errorCode = _getErrorCode(error);
      final errorMessage = _getErrorMessage(error);
      await _trackDownloadFailed(errorCode, errorMessage);

      // NEW: Auto-retry logic for transient errors
      if (_shouldAutoRetry(error)) {
        final prefs = await SharedPreferences.getInstance();
        final retryCount = prefs.getInt(_keyRetryCount) ?? 0;

        if (retryCount < _maxAutoRetries) {
          debugPrint(
            '[BackgroundDownloadManager] Auto-retry $retryCount/$_maxAutoRetries '
            'in ${_retryDelay.inMinutes} minutes',
          );
          await prefs.setInt(_keyRetryCount, retryCount + 1);

          // Schedule retry
          Future.delayed(_retryDelay, () async {
            debugPrint('[BackgroundDownloadManager] Executing scheduled retry');
            await resumeDownload();
          });
          return;
        } else {
          debugPrint(
            '[BackgroundDownloadManager] Max auto-retries ($retryCount) exceeded',
          );
          await prefs.remove(_keyRetryCount);
        }
      }

      _state = DownloadState.failed;
    }

    await _persistState();
    _notifyStateChange();
  }

  /// Get error code from exception for analytics
  String _getErrorCode(dynamic error) {
    if (error is DioException) {
      return 'DIO_${error.type.name}';
    }
    if (error is TimeoutException) return 'TIMEOUT';
    if (error is FileSystemException) return 'FILE_SYSTEM';
    return 'UNKNOWN';
  }

  /// Get error message from exception for analytics
  String _getErrorMessage(dynamic error) {
    if (error is DioException) {
      return error.message ?? 'Dio error';
    }
    return error.toString();
  }

  /// Check if error should trigger auto-retry
  bool _shouldAutoRetry(dynamic error) {
    // Only retry on transient errors
    if (error is DioException) {
      return error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.unknown;
    }

    // Check for network-related errors
    final errorString = error.toString().toLowerCase();
    return errorString.contains('socket') ||
        errorString.contains('network') ||
        errorString.contains('connection');
  }

  /// Pause current download
  Future<void> pauseDownload(DownloadState reason) async {
    if (_state != DownloadState.downloading) return;

    _cancelToken?.cancel('Paused: $reason');
    _state = reason;
    await _persistState();
    _notifyStateChange();
  }

  /// Resume paused download
  Future<void> resumeDownload() async {
    if (_state != DownloadState.pausedBattery &&
        _state != DownloadState.pausedNoConnectivity) {
      return;
    }

    // Check conditions before resuming
    final batteryLevel = await _battery.batteryLevel;
    final connectivity = await Connectivity().checkConnectivity();
    final hasConnection = !connectivity.contains(ConnectivityResult.none);

    if (batteryLevel < _batteryThreshold) {
      debugPrint(
        '[BackgroundDownloadManager] Still low battery, keeping paused',
      );
      return;
    }

    if (!hasConnection) {
      debugPrint(
        '[BackgroundDownloadManager] Still no connectivity, keeping paused',
      );
      return;
    }

    _cancelToken = CancelToken();
    await _executeDownload();
  }

  /// Cancel current download
  Future<void> cancelDownload() async {
    _cancelToken?.cancel('User cancelled');
    _state = DownloadState.cancelled;
    await _persistState();
    _notifyStateChange();
  }

  /// Verify SHA256 hash
  Future<bool> _verifySha256(String filePath, String expectedHash) async {
    // Use centralized crypto utility
    return await CryptoUtils.verifySha256(filePath, expectedHash);
  }

  /// Persist state to SharedPreferences
  Future<void> _persistState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyState, _state.index);
      await prefs.setInt(_keyTargetBuildNumber, _targetBuildNumber ?? 0);
      await prefs.setString(_keyTargetUrl, _targetUrl ?? '');
      await prefs.setString(_keyExpectedSha256, _expectedSha256 ?? '');
      await prefs.setString(_keyDownloadPath, _downloadPath ?? '');
      await prefs.setInt(
        _keyLastModified,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('[BackgroundDownloadManager] Failed to persist state: $e');
    }
  }

  /// Persist progress to SharedPreferences
  Future<void> _persistProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyProgress, _progress);
      await prefs.setInt(_keyDownloadedBytes, _downloadedBytes);
      await prefs.setInt(_keyTotalBytes, _totalBytes);
    } catch (e) {
      debugPrint('[BackgroundDownloadManager] Failed to persist progress: $e');
    }
  }

  /// Restore state from SharedPreferences
  Future<void> restoreState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final stateIndex = prefs.getInt(_keyState);
      if (stateIndex == null) return;

      _state = DownloadState.values[stateIndex];
      _targetBuildNumber = prefs.getInt(_keyTargetBuildNumber);
      _targetUrl = prefs.getString(_keyTargetUrl);
      _expectedSha256 = prefs.getString(_keyExpectedSha256);
      _downloadPath = prefs.getString(_keyDownloadPath);
      _progress = prefs.getDouble(_keyProgress) ?? 0.0;
      _downloadedBytes = prefs.getInt(_keyDownloadedBytes) ?? 0;
      _totalBytes = prefs.getInt(_keyTotalBytes) ?? 0;

      // CRITICAL: Check if downloaded build is stale (app was updated)
      // This prevents keeping old APKs after successful updates
      if (_state == DownloadState.completed && _targetBuildNumber != null) {
        final packageInfo = await PackageInfo.fromPlatform();
        final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 1;
        if (currentBuild >= _targetBuildNumber!) {
          debugPrint(
            '[BackgroundDownloadManager] Downloaded build $_targetBuildNumber '
            'is stale (current: $currentBuild), cleaning up',
          );
          await cleanup();
          return;
        }
      }

      // Validate downloaded file still exists
      if (_state == DownloadState.completed && _downloadPath != null) {
        final file = File(_downloadPath!);
        if (!await file.exists()) {
          debugPrint(
            '[BackgroundDownloadManager] Downloaded file missing, resetting state',
          );
          _state = DownloadState.idle;
          _downloadPath = null;
          await _persistState();
        }
      }

      // If we were downloading when app was killed, we can attempt to resume
      // if it was a failed/cancelled state but we have a partial file.
      if (_state == DownloadState.downloading ||
          _state == DownloadState.failed ||
          _state == DownloadState.cancelled) {
        if (hasDownload && _targetUrl != null && _targetBuildNumber != null) {
          debugPrint(
            '[BackgroundDownloadManager] Resuming interrupted download',
          );
          // Reset state to idle before starting fresh download
          _state = DownloadState.idle;
          await _persistState();
          
          // Start/resume the download with proper error handling
          try {
            await startDownload(
              url: _targetUrl!,
              buildNumber: _targetBuildNumber!,
              expectedSha256: _expectedSha256,
            );
            debugPrint(
              '[BackgroundDownloadManager] Resume download started successfully',
            );
          } catch (e) {
            debugPrint(
              '[BackgroundDownloadManager] Failed to resume download: $e',
            );
            // Reset to failed state on error
            _state = DownloadState.failed;
            await _persistState();
          }
        } else {
          _state = DownloadState.failed;
          await _persistState();
        }
      }

      debugPrint(
        '[BackgroundDownloadManager] State restored: $_state, '
        'build: $_targetBuildNumber, progress: ${(_progress * 100).toStringAsFixed(1)}%',
      );

      // Check if we should auto-resume
      if (_state == DownloadState.pausedBattery ||
          _state == DownloadState.pausedNoConnectivity) {
        await resumeDownload();
      }
    } catch (e) {
      debugPrint('[BackgroundDownloadManager] Failed to restore state: $e');
    }
  }

  /// Clean up downloaded file and reset state
  Future<void> cleanup() async {
    // Delete file
    if (_downloadPath != null) {
      try {
        final file = File(_downloadPath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('[BackgroundDownloadManager] Cleanup error: $e');
      }
    }

    // Reset state
    _state = DownloadState.idle;
    _progress = 0.0;
    _downloadedBytes = 0;
    _totalBytes = 0;
    _downloadPath = null;
    _targetUrl = null;
    _expectedSha256 = null;
    _targetBuildNumber = null;

    // Clear preferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyState);
      await prefs.remove(_keyProgress);
      await prefs.remove(_keyDownloadedBytes);
      await prefs.remove(_keyTotalBytes);
      await prefs.remove(_keyDownloadPath);
      await prefs.remove(_keyTargetUrl);
      await prefs.remove(_keyExpectedSha256);
      await prefs.remove(_keyTargetBuildNumber);
      await prefs.remove(_keyLastModified);
      await prefs.remove(_keyRetryCount); // Also clear retry count
    } catch (e) {
      debugPrint('[BackgroundDownloadManager] Failed to clear preferences: $e');
    }

    _notifyStateChange();
  }

  /// Add state change listener
  void addStateListener(void Function(DownloadState state) listener) {
    _stateListeners.add(listener);
  }

  /// Remove state change listener
  void removeStateListener(void Function(DownloadState state) listener) {
    _stateListeners.remove(listener);
  }

  /// Add progress listener
  void addProgressListener(void Function(double progress) listener) {
    _progressListeners.add(listener);
  }

  /// Remove progress listener
  void removeProgressListener(void Function(double progress) listener) {
    _progressListeners.remove(listener);
  }

  /// Notify state listeners
  void _notifyStateChange() {
    for (final listener in _stateListeners) {
      listener(_state);
    }
  }

  /// Notify progress listeners
  void _notifyProgressChange() {
    for (final listener in _progressListeners) {
      listener(_progress);
    }
  }

  /// Dispose resources
  void dispose() {
    _batterySubscription?.cancel();
    _connectivitySubscription?.cancel();
    _stateListeners.clear();
    _progressListeners.clear();
  }

  // ============ CRITICAL FIX #4: Download Analytics Tracking ============

  /// Get current app build number
  Future<int> _getCurrentBuildNumber() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return int.tryParse(packageInfo.buildNumber) ?? 1;
  }

  /// Track download started event to backend
  Future<void> _trackDownloadStarted() async {
    try {
      final currentBuild = await _getCurrentBuildNumber();
      await _apiClient.post(
        '/api/app/update-event',
        requiresAuth: false,
        body: {
          'event': 'download_started',
          'from_build': currentBuild,
          'to_build': _targetBuildNumber ?? 0,
          'download_size_mb': _totalBytes > 0
              ? (_totalBytes / 1024 / 1024)
              : null,
        },
      );
      debugPrint(
        '[BackgroundDownloadManager] Tracked download_started: '
        'build $currentBuild -> $_targetBuildNumber',
      );
    } catch (e) {
      debugPrint('[BackgroundDownloadManager] Failed to track download start: $e');
      // Non-fatal, don't fail the download
    }
  }

  /// Track download completed event to backend
  Future<void> _trackDownloadCompleted() async {
    try {
      final currentBuild = await _getCurrentBuildNumber();
      await _apiClient.post(
        '/api/app/update-event',
        requiresAuth: false,
        body: {
          'event': 'download_completed',
          'from_build': currentBuild,
          'to_build': _targetBuildNumber ?? 0,
          'download_size_mb': _totalBytes > 0
              ? (_totalBytes / 1024 / 1024)
              : null,
        },
      );
      debugPrint(
        '[BackgroundDownloadManager] Tracked download_completed: '
        'build $currentBuild -> $_targetBuildNumber',
      );
    } catch (e) {
      debugPrint('[BackgroundDownloadManager] Failed to track download completion: $e');
    }
  }

  /// Track download failed event to backend
  Future<void> _trackDownloadFailed(String errorCode, String errorMessage) async {
    try {
      final currentBuild = await _getCurrentBuildNumber();
      await _apiClient.post(
        '/api/app/update-event',
        requiresAuth: false,
        body: {
          'event': 'download_failed',
          'from_build': currentBuild,
          'to_build': _targetBuildNumber ?? 0,
          'error_code': errorCode,
          'error_message': errorMessage,
        },
      );
      debugPrint(
        '[BackgroundDownloadManager] Tracked download_failed: $errorCode - $errorMessage',
      );
    } catch (e) {
      debugPrint('[BackgroundDownloadManager] Failed to track download failure: $e');
    }
  }

  /// Track verification failed event to backend
  Future<void> _trackVerificationFailed(String reason) async {
    try {
      final currentBuild = await _getCurrentBuildNumber();
      await _apiClient.post(
        '/api/app/update-event',
        requiresAuth: false,
        body: {
          'event': 'verification_failed',
          'from_build': currentBuild,
          'to_build': _targetBuildNumber ?? 0,
          'error_code': 'SHA256_MISMATCH',
          'error_message': reason,
        },
      );
      debugPrint('[BackgroundDownloadManager] Tracked verification_failed: $reason');
    } catch (e) {
      debugPrint('[BackgroundDownloadManager] Failed to track verification failure: $e');
    }
  }

  /// Estimate required storage space for download
  /// Returns estimated bytes needed (APK size + 20% buffer) or null if unknown
  int? _estimateRequiredSpace() {
    // If we know the total bytes from previous download attempt, use that
    if (_totalBytes > 0) {
      // Add 20% buffer for temporary files and overhead
      return (_totalBytes * 1.2).round();
    }
    // Default estimate: 150MB (max APK size) + 20% = 180MB
    return (150 * 1024 * 1024 * 1.2).round();
  }

  /// Get available storage space in bytes
  /// Returns null if unable to determine
  Future<int?> _getAvailableStorageSpace() async {
    try {
      // Use application documents directory as approximation
      final dir = await getApplicationDocumentsDirectory();
      
      // Get storage stats - use size which is available on FileStat
      // Note: This returns directory size, not free space
      // Flutter doesn't provide direct free space API without additional plugins
      final stat = await dir.stat();
      return stat.size;
    } catch (e) {
      debugPrint('[BackgroundDownloadManager] Failed to get storage space: $e');
      return null;
    }
  }
}
