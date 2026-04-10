import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:almudeer_mobile_app/features/users/data/models/user_info.dart';
import '../../data/repositories/auth_repository.dart';
import 'package:almudeer_mobile_app/core/api/api_client.dart';
import 'package:almudeer_mobile_app/features/notifications/data/services/fcm_service_mobile.dart' if (dart.library.js_interop) 'package:almudeer_mobile_app/features/notifications/data/services/fcm_service_web.dart';
import 'package:almudeer_mobile_app/core/services/security_event_service.dart';
import 'package:almudeer_mobile_app/core/services/websocket_service.dart';
import 'package:almudeer_mobile_app/core/services/persistent_cache_service.dart';
import 'dart:async';

/// Authentication state
enum AuthState { initial, loading, authenticated, unauthenticated, error, pendingApproval }

/// Authentication provider for managing login state
class AuthProvider extends ChangeNotifier {
  final AuthRepository _authRepository;
  final FcmService _fcmService;
  final WebSocketService _webSocketService;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  AuthState _state = AuthState.initial;
  UserInfo? _userInfo;
  final List<UserInfo> _accounts = []; // List to store multiple active accounts
  String? _errorMessage;
  int _loginAttempts = 0;
  DateTime? _lockoutUntil;
  bool _isDisposed = false;
  bool _isSwitching = false;

  static const int _maxAttempts = 5;
  static const Duration _lockoutDuration = Duration(minutes: 15);

  // P2-10 FIX: Track refresh failures to force re-authentication after grace period
  int _refreshFailures = 0;
  static const int _maxRefreshFailures = 3;

  // SECURITY FIX #25: Persist rate limit state to survive app restart
  // IMPORTANT: Client-side rate limiting is ONLY a UX improvement to show error messages.
  // REAL brute-force protection is server-side (login_protection.py with Redis).
  // On rooted/jailbroken devices, client-side rate limits CAN be bypassed.
  // This is acceptable because the server enforces the actual security boundary.
  static const String _rateLimitAttemptsKey = 'almudeer_login_attempts';
  static const String _rateLimitUntilKey = 'almudeer_lockout_until';

  /// Callback invoked when account is switched (for resetting other providers)
  VoidCallback? _onAccountSwitch;

  /// Key that changes on every account switch - use as ValueKey to force widget rebuild
  int _accountKey = 0;
  int get accountKey => _accountKey;

  /// Register a callback to be invoked when account is switched
  void setAccountSwitchCallback(VoidCallback callback) {
    _onAccountSwitch = callback;
  }

  AuthProvider({
    AuthRepository? authRepository,
    FcmService? fcmService,
    WebSocketService? webSocketService,
  }) : _authRepository = authRepository ?? AuthRepository(),
       _fcmService = fcmService ?? FcmService(),
       _webSocketService = webSocketService ?? WebSocketService();

  AuthState get state => _state;
  UserInfo? get userInfo => _userInfo;
  List<UserInfo> get accounts => _accounts;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _state == AuthState.authenticated;
  bool get isLoading => _state == AuthState.loading;

  /// Check if user is rate limited
  bool get isRateLimited {
    if (_lockoutUntil == null) return false;
    if (DateTime.now().isAfter(_lockoutUntil!)) {
      _lockoutUntil = null;
      _loginAttempts = 0;
      return false;
    }
    return true;
  }
  
  /// SECURITY FIX #25: Load rate limit state from SECURE storage
  /// CRITICAL: Moved from SharedPreferences to FlutterSecureStorage to prevent
  /// attackers from bypassing brute-force protection by clearing SharedPreferences
  Future<void> _loadRateLimitState() async {
    try {
      final attemptsStr = await _secureStorage.read(key: _rateLimitAttemptsKey);
      final untilStr = await _secureStorage.read(key: _rateLimitUntilKey);

      if (attemptsStr != null) {
        _loginAttempts = int.tryParse(attemptsStr) ?? 0;
      }

      if (untilStr != null) {
        final untilMs = int.tryParse(untilStr);
        if (untilMs != null) {
          _lockoutUntil = DateTime.fromMillisecondsSinceEpoch(untilMs);
        }
      }

      if (_lockoutUntil != null && _lockoutUntil!.isBefore(DateTime.now())) {
        // Lockout expired, clear it
        await _clearRateLimitState();
      }
    } catch (e) {
      debugPrint('[AuthProvider] Failed to load rate limit state from secure storage: $e');
    }
  }

  /// SECURITY FIX #25: Save rate limit state to SECURE storage
  /// CRITICAL: Uses FlutterSecureStorage instead of SharedPreferences to prevent
  /// brute-force protection bypass on rooted/jailbroken devices
  Future<void> _saveRateLimitState() async {
    try {
      await _secureStorage.write(
        key: _rateLimitAttemptsKey,
        value: _loginAttempts.toString(),
      );

      if (_lockoutUntil != null) {
        await _secureStorage.write(
          key: _rateLimitUntilKey,
          value: _lockoutUntil!.millisecondsSinceEpoch.toString(),
        );
      } else {
        await _secureStorage.delete(key: _rateLimitUntilKey);
      }

      debugPrint('[AuthProvider] Saved rate limit state to secure storage: $_loginAttempts attempts');
    } catch (e) {
      debugPrint('[AuthProvider] Failed to save rate limit state to secure storage: $e');
    }
  }

  /// SECURITY FIX #25: Clear rate limit state from SECURE storage
  Future<void> _clearRateLimitState() async {
    try {
      await _secureStorage.delete(key: _rateLimitAttemptsKey);
      await _secureStorage.delete(key: _rateLimitUntilKey);
      debugPrint('[AuthProvider] Cleared rate limit state from secure storage');
    } catch (e) {
      debugPrint('[AuthProvider] Failed to clear rate limit state from secure storage: $e');
    }
  }

  /// Get remaining lockout time in minutes
  int get remainingLockoutMinutes {
    if (_lockoutUntil == null) return 0;
    final remaining = _lockoutUntil!.difference(DateTime.now()).inMinutes;
    return remaining > 0 ? remaining : 0;
  }

  /// Initialize authentication state
  ///
  /// Prioritizes local storage to ensure offline session preservation.
  /// User stays authenticated if they have a stored license key, even when offline.
  Future<void> init() async {
    // SECURITY FIX #25: Load rate limit state from persistent storage
    await _loadRateLimitState();
    
    // Listen for security events
    SecurityEventService().eventStream.listen((event) {
      if (event == SecurityEvent.accountDisabled) {
        debugPrint(
          '[AuthProvider] Account disabled event received, logging out...',
        );
        logout(reason: 'طھظ… طھط¹ط·ظٹظ„ ط§ظ„ط­ط³ط§ط¨ ط£ظˆ ط§ظ†طھظ‡ط§ط، ط§ظ„ط§ط´طھط±ط§ظƒ');
      }
    });

    // Listen for WebSocket events
    _webSocketService.stream.listen((event) {
      if (event['event'] == 'subscription_updated') {
        final data = event['data'] as Map<String, dynamic>? ?? {};
        final isSelf = data['is_self'] == true;

        if (isSelf) {
          debugPrint(
            '[AuthProvider] Subscription updated event received (self)',
          );
          // Refresh user info to get the latest data from server
          refreshUserInfo();
        }
      }
    });

    try {
      // 1. Parallelize all initialization checks: SharedPreferences, Saved Accounts, and Current Key status
      final results = await Future.wait([
        SharedPreferences.getInstance(),
        _authRepository.getSavedAccounts(),
        _authRepository.isAuthenticated(),
        _authRepository.getLicenseKey(),
      ]);

      final prefs = results[0] as SharedPreferences;
      final savedAccounts = results[1] as List<UserInfo>;
      final hasStoredKey = results[2] as bool;
      final currentStoredKey = results[3] as String?;

      // Check for persistent background logout flag
      if (prefs.getBool('force_logout_required') == true) {
        await prefs.remove('force_logout_required');
        debugPrint(
          '[AuthProvider] Persistent logout flag found, triggering logout...',
        );
        await logout(reason: 'طھظ… طھط¹ط·ظٹظ„ ط§ظ„ط­ط³ط§ط¨ ط£ظˆ ط§ظ†طھظ‡ط§ط، ط§ظ„ط§ط´طھط±ط§ظƒ');
        return;
      }

      _accounts.clear();

      // CLEANUP: Deduplicate accounts by license key (ignoring case)
      final Set<String> seenKeys = {};
      for (var account in savedAccounts) {
        if (account.licenseKey != null) {
          final normalized = account.licenseKey!.toUpperCase().trim();
          if (!seenKeys.contains(normalized)) {
            seenKeys.add(normalized);
            _accounts.add(account);
          }
        }
      }

      if (hasStoredKey && _accounts.isNotEmpty) {
        // Find the account that matches the currently stored key
        UserInfo? activeAccount;
        if (currentStoredKey != null) {
          final normalizedKey = currentStoredKey.toUpperCase().trim();
          try {
            activeAccount = _accounts.firstWhere(
              (a) => a.licenseKey?.toUpperCase().trim() == normalizedKey,
            );
          } catch (_) {
            // Not found in accounts list
          }
        }

        // Use the matching account, or fall back to the first one if not matched
        _userInfo = activeAccount ?? _accounts.first;
        _state = AuthState.authenticated;
        notifyListeners();

        // 3. Background refresh and FCM registration (production hardening)
        _refreshUserInfoSilently();
        _fcmService.registerTokenWithBackend();

        // Schedule proactive token refresh to prevent expired token errors
        ApiClient().scheduleProactiveRefresh();
      } else if (hasStoredKey) {
        // Has key but no saved accounts - try to fetch from server
        try {
          _userInfo = await _authRepository.getUserInfo();
          _addToAccounts(_userInfo!);
          _state = AuthState.authenticated;
        } catch (e) {
          // Network error - but we have a stored key, so stay authenticated
          // Create a minimal user info from local data
          final licenseKey =
              currentStoredKey ?? await _authRepository.getLicenseKey();
          if (licenseKey != null) {
            _userInfo = UserInfo(
              fullName: 'ط¬ط§ط±ظٹ ط§ظ„طھط­ظ…ظٹظ„...',
              expiresAt: '',
              licenseKey: licenseKey,
            );
            _state = AuthState.authenticated;
          } else {
            _state = AuthState.unauthenticated;
          }
        }
      } else {
        _state = AuthState.unauthenticated;
      }
    } on AuthenticationException catch (e) {
      // Only logout if it's an authentication error (e.g., key expired)
      await _authRepository.logout();
      _state = AuthState.unauthenticated;
      _errorMessage = e.message;
    } catch (e) {
      // Network or other error - check if we have local auth
      final hasStoredKey = await _authRepository.isAuthenticated();
      if (hasStoredKey) {
        // Stay authenticated with cached data
        if (_accounts.isNotEmpty) {
          final currentStoredKey = await _authRepository.getLicenseKey();
          if (currentStoredKey != null) {
            final normalizedKey = currentStoredKey.toUpperCase().trim();
            _userInfo = _accounts.firstWhere(
              (a) => a.licenseKey?.toUpperCase().trim() == normalizedKey,
              orElse: () => _accounts.first,
            );
          } else {
            _userInfo = _accounts.first;
          }
        }
        _state = AuthState.authenticated;
      } else {
        _state = AuthState.unauthenticated;
        _errorMessage = e.toString();
      }
    }

    notifyListeners();
  }

  /// Refresh user info silently in background (no state changes on failure)
  // P2-10 FIX: Added grace period with failure tracking
  Future<void> _refreshUserInfoSilently() async {
    if (_state != AuthState.authenticated || _userInfo?.licenseKey == null) {
      return;
    }

    final currentKey = _userInfo!.licenseKey!;

    try {
      final freshUser = await _authRepository.getUserInfo(key: currentKey);

      // Race condition check: Ensure we are still looking at the same account
      if (_state != AuthState.authenticated ||
          _userInfo?.licenseKey != currentKey) {
        return;
      }

      _userInfo = freshUser;
      _addToAccounts(freshUser);
      // P2-10 FIX: Reset failure counter on success
      _refreshFailures = 0;
      notifyListeners();
    } catch (e) {
      // FIX: Differentiate network errors from auth errors
      // Network errors (SocketException, TimeoutException) should NOT trigger forced logout
      // Only auth errors (401, 403) should force re-authentication
      final isNetworkError = e.toString().contains('SocketException') ||
          e.toString().contains('TimeoutException') ||
          e.toString().contains('انتهت مهلة') ||
          e.toString().contains('تعذر الاتصال') ||
          e.toString().contains('خطأ في تنسيق');

      if (!isNetworkError) {
        _refreshFailures++;
        debugPrint('[AuthProvider] Auth refresh failed (attempt $_refreshFailures/$_maxRefreshFailures): $e');

        if (_refreshFailures >= _maxRefreshFailures) {
          debugPrint('[AuthProvider] Max auth failures reached, forcing re-authentication');
          await logout(reason: 'انتهت الجلسة. يرجى تسجيل الدخول مرة أخرى');
        }
      } else {
        // Network error — don't increment failures, don't force logout
        debugPrint('[AuthProvider] Network error during silent refresh (not forcing logout): $e');
      }
    }
  }

  /// Validate license key format
  /// Supports both legacy format (4 chars per segment) and new high-entropy format (8 chars per segment)
  /// Note: Backend uses token_hex() which generates HEX only (0-9, A-F), not full alphabet
  bool validateLicenseFormat(String key) {
    final upperKey = key.toUpperCase();
    // Old format: MUDEER-XXXX-XXXX-XXXX (4 hex chars per segment = 48 bits entropy)
    // New format: MUDEER-XXXXXXXX-XXXXXXXX-XXXXXXXX (8 hex chars per segment = 96 bits entropy)
    // Pattern uses [A-F0-9] because backend generates keys with secrets.token_hex()
    final legacyPattern = RegExp(
      r'^MUDEER-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}$',
    );
    final newPattern = RegExp(r'^MUDEER-[A-F0-9]{8}-[A-F0-9]{8}-[A-F0-9]{8}$');
    return legacyPattern.hasMatch(upperKey) || newPattern.hasMatch(upperKey);
  }

  /// Get detailed license format error message
  String getLicenseFormatErrorMessage() {
    return 'طھظ†ط³ظٹظ‚ ط§ظ„ظ…ظپطھط§ط­ ط؛ظٹط± طµط­ظٹط­. ظٹط¬ط¨ ط£ظ† ظٹظƒظˆظ† ط¨ط§ظ„ط´ظƒظ„: MUDEER-XXXX-XXXX-XXXX ط£ظˆ MUDEER-XXXXXXXX-XXXXXXXX-XXXXXXXX';
  }

  /// Login with license key
  Future<bool> login(String licenseKey) async {
    // Check rate limiting
    if (isRateLimited) {
      _errorMessage =
          'ظ„ط­ظ…ط§ظٹط© ط­ط³ط§ط¨ظƒطŒ ظٹط±ط¬ظ‰ ط§ظ„ط§ظ†طھط¸ط§ط± $remainingLockoutMinutes ط¯ظ‚ظٹظ‚ط© ظ‚ط¨ظ„ ط§ظ„ظ…ط­ط§ظˆظ„ط© ظ…ط¬ط¯ط¯ظ‹ط§';
      _state = AuthState.error;
      notifyListeners();
      return false;
    }

    // Validate format first
    final normalizedKey = licenseKey.toUpperCase().trim();
    if (!validateLicenseFormat(normalizedKey)) {
      _incrementAttempt();
      // LOW FIX #7: Use detailed format error message
      _errorMessage = getLicenseFormatErrorMessage();
      _state = AuthState.error;
      notifyListeners();
      return false;
    }

    _state = AuthState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _authRepository.validateLicense(normalizedKey);

      if (result.valid) {
        // Tokens are already stored by _authRepository.validateLicense call inside its _apiClient.setLicenseInfo

        _userInfo = UserInfo.fromJson(
          result.toJson(),
        ).copyWith(licenseKey: normalizedKey, licenseId: result.licenseId);

        await _addToAccounts(
          _userInfo!,
        ); // Add to local accounts list and persist
        _state = AuthState.authenticated;

        // SECURITY FIX #25: Clear rate limit state on successful login
        _loginAttempts = 0;
        _lockoutUntil = null;
        await _clearRateLimitState();

        // SECURITY FIX: Await FCM registration to prevent race condition
        // This ensures FCM token is registered to the correct account before login completes
        try {
          await _fcmService.registerTokenWithBackend();
          debugPrint('[AuthProvider] FCM token registered successfully for ${_userInfo?.username}');
        } catch (e) {
          // Non-fatal - log but don't fail login
          debugPrint('[AuthProvider] FCM registration failed (non-fatal): $e');
        }

        // Schedule proactive token refresh to prevent expired token errors
        ApiClient().scheduleProactiveRefresh();

        notifyListeners();
        return true;
      } else {
        if (result.retryAfterSeconds != null && result.retryAfterSeconds! > 0) {
          _lockoutUntil = DateTime.now().add(
            Duration(seconds: result.retryAfterSeconds!),
          );
          final minutes = result.retryAfterSeconds! ~/ 60;
          _errorMessage = minutes > 0
              ? 'طھظ… ط­ط¸ط± ط§ظ„ط­ط³ط§ط¨ ظ…ط¤ظ‚طھظ‹ط§. ط­ط§ظˆظ„ ظ…ط±ط© ط£ط®ط±ظ‰ ط¨ط¹ط¯ $minutes ط¯ظ‚ط§ط¦ظ‚'
              : 'طھظ… ط­ط¸ط± ط§ظ„ط­ط³ط§ط¨ ظ…ط¤ظ‚طھظ‹ط§. ط­ط§ظˆظ„ ظ…ط±ط© ط£ط®ط±ظ‰ ط¨ط¹ط¯ ${result.retryAfterSeconds} ط«ط§ظ†ظٹط©';
          
          // SECURITY FIX #25: Save rate limit state
          await _saveRateLimitState();
        } else {
          _incrementAttempt();
          _errorMessage =
              result.error ??
              'ط§ظ„ظ…ظپطھط§ط­ ط؛ظٹط± طµط§ظ„ط­. طھط­ظ‚ظ‚ ظ…ظ† طµط­ط© ط§ظ„ظ…ظپطھط§ط­ ط£ظˆ طھظˆط§طµظ„ ظ…ط¹ظ†ط§ ظ„ظ„ظ…ط³ط§ط¹ط¯ط©';
          
          // SECURITY FIX #25: Save rate limit state
          await _saveRateLimitState();
        }

        _state = AuthState.error;
        notifyListeners();
        return false;
      }
    } on AuthenticationException catch (e) {
      _incrementAttempt();
      _errorMessage = e.message;
      _state = AuthState.error;
      notifyListeners();
      return false;
    } on ApiException catch (e) {
      _incrementAttempt();
      _errorMessage = e.message;
      _state = AuthState.error;
      notifyListeners();
      return false;
    } catch (e) {
      _incrementAttempt();
      _errorMessage =
          'طھط¹ط°ط± ط§ظ„ط§طھطµط§ظ„ ط¨ط§ظ„ط®ط§ط¯ظ…. طھط£ظƒط¯ ظ…ظ† ط§طھطµط§ظ„ظƒ ط¨ط§ظ„ط¥ظ†طھط±ظ†طھ ظˆط­ط§ظˆظ„ ظ…ط¬ط¯ط¯ظ‹ط§ ($e)';
      _state = AuthState.error;
      notifyListeners();
      return false;
    }
  }

  /// Add a new account (Multi-account support)
  Future<bool> addAccount(String licenseKey) async {
    if (isRateLimited) return false;

    final normalizedKey = licenseKey.toUpperCase().trim();
    if (!validateLicenseFormat(normalizedKey)) {
      _errorMessage = 'طھظ†ط³ظٹظ‚ ط§ظ„ظ…ظپطھط§ط­ ط؛ظٹط± طµط­ظٹط­';
      notifyListeners();
      return false;
    }

    // Check if account already exists (by attempting to fetch info or just trusting the key)
    // For this implementation, we will perform a validation call similar to login

    try {
      final result = await _authRepository.validateLicense(normalizedKey);

      if (result.valid) {
        // We need to Temporarily switch the client key to fetch this user's info,
        // OR assuming the existing validateLicense returns info (it only returns validation).
        // Since we can't easily change `ApiClient` safely in this step,
        // we will assume for this "add" flow we can just add a MOCK user if offline,
        // OR better: we actually set the key, fetch info, and if we want to "switch back" we can.
        // BUT logic says "Add Account" usually implies switching to it immediately.

        // Create new user object with key
        final newUser = UserInfo.fromJson(
          result.toJson(),
        ).copyWith(licenseKey: normalizedKey, licenseId: result.licenseId);

        // Save to accounts
        await _addToAccounts(newUser);

        // OPTIONAL: Auto-switch to new account?
        // User requested "Instant... when adding". Usually adding implies switching.
        // We will switch context.
        await switchAccount(newUser);

        _loginAttempts = 0;
        _errorMessage = null;
        notifyListeners();
        return true;
      } else {
        _errorMessage = result.error ?? 'ط§ظ„ظ…ظپطھط§ط­ ط؛ظٹط± طµط§ظ„ط­';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'ط­ط¯ط« ط®ط·ط£ ط£ط«ظ†ط§ط، ط¥ط¶ط§ظپط© ط§ظ„ط­ط³ط§ط¨: $e';
      notifyListeners();
      return false;
    }
  }

  /// Switch to an existing account
  Future<void> switchAccount(UserInfo user) async {
    if (_isSwitching) return;
    if (user.licenseKey == null) {
      _errorMessage = 'ط¨ظٹط§ظ†ط§طھ ط§ظ„ط­ط³ط§ط¨ ط؛ظٹط± ظ…ظƒطھظ…ظ„ط©';
      notifyListeners();
      return;
    }

    _isSwitching = true;
    try {
      // 1. CRITICAL FIX P0-9: Cancel old proactive refresh timer SYNCHRONOUSLY BEFORE any state changes
      ApiClient().cancelProactiveRefresh();

      // 2. FIX: Persist key FIRST before notifying listeners (prevents race condition)
      // If persistence fails, don't notify — avoid showing wrong user
      await _authRepository.storeLicenseKey(
        user.licenseKey!,
        id: user.licenseId,
      );

      // 3. NOW update state and notify (all persistence is done)
      _userInfo = user;
      _accountKey++;
      _state = AuthState.authenticated;
      notifyListeners();

      // 4. Notify listeners to reset other providers' data
      _onAccountSwitch?.call();

      // 5. Register FCM Token for the new active user
      try {
        await _fcmService.registerTokenWithBackend();
      } catch (e) {
        debugPrint('Failed to register FCM after switch (non-fatal): $e');
      }

      // 6. CRITICAL FIX P0-9: Schedule proactive token refresh
      ApiClient().scheduleProactiveRefresh();

      // 7. Background Refresh — get fresh user data
      try {
        final freshUser = await _authRepository.getUserInfo(
          key: user.licenseKey,
        );
        // Double check we haven't switched away again during the network call
        if (_userInfo?.licenseKey == user.licenseKey) {
          _userInfo = freshUser.copyWith(licenseKey: user.licenseKey);
          await _addToAccounts(_userInfo!);
          notifyListeners();
        }
      } catch (e) {
        // Silent failure on background refresh is acceptable
      }
    } catch (e) {
      _errorMessage = 'ظپط´ظ„ ط§ظ„طھط¨ط¯ظٹظ„ ط¥ظ„ظ‰ ط§ظ„ط­ط³ط§ط¨';
      notifyListeners();
    } finally {
      _isSwitching = false;
    }
  }

  /// Remove an account
  Future<void> removeAccount(UserInfo user) async {
    // 1. Optimistic Update: Remove from local list immediately
    _accounts.removeWhere((u) => u.licenseKey == user.licenseKey);

    // Check if we are removing the current user
    final bool isCurrentUser = _userInfo?.licenseKey == user.licenseKey;

    if (isCurrentUser) {
      // If current user, we must switch or logout. This inherently notifies listeners via those methods,
      // so we don't need a separate notify here for the list removal if we are switching quickly.
      if (_accounts.isNotEmpty) {
        // Switch to the first available account
        await switchAccount(_accounts.first);
      } else {
        notifyListeners(); // Notify list update before logout process
        await logout();
      }
    } else {
      // If removing another account, update UI instantly
      notifyListeners();
    }

    // 2. Background Persistence
    try {
      await _authRepository.removeAccount(user);
    } catch (e) {
      // If persistence fails, practically we can't do much (revert? toast?).
      // For this feature, failure to delete from local storage is rare/minor.
      // We will log or ignore, as the UI state is the priority.
    }
  }

  Future<void> _addToAccounts(UserInfo user) async {
    if (user.licenseKey == null) {
      return;
    }

    // CRITICAL FIX P1-14: Consistent normalization across all storage operations
    // Use the same normalization as ApiClient to prevent duplicates
    final normalized = _normalizeLicenseKey(user.licenseKey!);

    // Prevent duplicates based on normalized License Key
    final index = _accounts.indexWhere(
      (u) => _normalizeLicenseKey(u.licenseKey ?? '') == normalized,
    );

    if (index != -1) {
      _accounts[index] = user; // Update existing
    } else {
      _accounts.add(user);
    }
    // Persist
    await _authRepository.saveAccount(user);
  }

  /// CRITICAL FIX P1-14: Centralized license key normalization
  /// Ensures consistent comparison across all account operations
  String _normalizeLicenseKey(String key) {
    return key.toUpperCase().trim();
  }

  /// Increment login attempts and apply lockout if needed
  void _incrementAttempt() {
    _loginAttempts++;
    if (_loginAttempts >= _maxAttempts) {
      _lockoutUntil = DateTime.now().add(_lockoutDuration);
    }
  }

  /// Logout
  ///
  /// SECURITY FIX #28: Fix race condition with refresh timer during logout
  Future<void> logout({String? reason}) async {
    final currentUserInfo = _userInfo;

    // SECURITY FIX #28: Cancel proactive refresh FIRST to prevent race condition
    ApiClient().cancelProactiveRefresh();

    if (reason != null) {
      _errorMessage = reason;
    }

    // 1. Snapshot and clear state immediately to block background refreshes
    _userInfo = null;
    _state = AuthState.unauthenticated;
    _accounts.removeWhere((u) => u.licenseKey == currentUserInfo?.licenseKey);
    notifyListeners();

    // 2. Perform persistence cleanup
    if (currentUserInfo != null) {
      await _authRepository.removeAccount(currentUserInfo);
    }
    
    // SECURITY FIX #25: Clear rate limit state on logout
    await _clearRateLimitState();

    // 3. Multi-account logic: Switch if others exist
    if (_accounts.isNotEmpty) {
      final nextAccount = _accounts.last;
      await switchAccount(nextAccount);
    } else {
      // 4. Pure Logout cleanup

      // Notify listeners to reset all data providers
      _onAccountSwitch?.call();

      try {
        // 1. Await critical disk cleanup
        await _authRepository.logout();

        // 2. Clear all account-specific caches
        final cache = PersistentCacheService();
        await cache.clearBox(PersistentCacheService.boxKnowledge);
        await cache.clearBox(PersistentCacheService.boxInbox);
        await cache.clearBox(PersistentCacheService.boxCustomers);
        await cache.clearBox(PersistentCacheService.boxIntegrations);
        await cache.clearBox(PersistentCacheService.boxLibrary);

        // 3. Fire-and-forget (with timeout) for non-critical network cleanup
        // SECURITY FIX: Handle timeout gracefully with async-await
        try {
          await _fcmService
              .unregisterToken()
              .timeout(const Duration(seconds: 3));
        } catch (e) {
          debugPrint('FCM unregister background error: $e');
          // Non-fatal - continue with logout
        }
      } catch (e) {
        debugPrint('Logout cleanup error: $e');
        // Note: Even if backend logout fails, we clear local tokens
        // The user is logged out locally, but session may be active on server
        // This is acceptable as the user initiated logout from their device
      }

      // Ensure state is unauthenticated (redundant but safe)
      _userInfo = null;
      _state = AuthState.unauthenticated;
      notifyListeners();
    }
  }

  /// Refresh user info
  Future<void> refreshUserInfo() async {
    if (_userInfo?.licenseKey == null) return;
    try {
      _userInfo = await _authRepository.getUserInfo(key: _userInfo!.licenseKey);
      _addToAccounts(_userInfo!);
      notifyListeners();
    } catch (e) {
      // Silently fail on refresh
    }
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  /// Clear error
  void clearError() {
    if (_errorMessage == null && _state != AuthState.error) return;

    _errorMessage = null;
    if (_state == AuthState.error) {
      _state = AuthState.unauthenticated;
    }
    notifyListeners();
  }

  // ==================== Email/Password Auth Methods ====================

  /// Sign up with email and password
  Future<bool> signUp(String email, String password, String fullName) async {
    _state = AuthState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authRepository.signUp(email: email, password: password, fullName: fullName);
      _state = AuthState.unauthenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _state = AuthState.error;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Verify OTP code
  Future<bool> verifyOTP(String email, String otpCode) async {
    _state = AuthState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authRepository.verifyOTP(email, otpCode);
      _state = AuthState.unauthenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _state = AuthState.error;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Resend OTP code
  Future<bool> resendOTP(String email) async {
    _errorMessage = null;
    try {
      await _authRepository.resendOTP(email);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Login with email and password
  Future<bool> loginWithEmail(String email, String password) async {
    // P1-7 FIX: Add rate limiting check (same as license key login)
    if (isRateLimited) {
      _errorMessage =
          'للحماية حسابك، يرجى الانتظار $remainingLockoutMinutes دقيقة قبل المحاولة مجدداً';
      _state = AuthState.error;
      notifyListeners();
      return false;
    }

    _state = AuthState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _authRepository.loginWithEmail(email, password);

      if (result.valid) {
        // P1-7 FIX: Clear rate limit state on successful login
        _loginAttempts = 0;
        _lockoutUntil = null;
        await _clearRateLimitState();

        _userInfo = UserInfo(
          licenseId: result.licenseId,
          fullName: result.fullName ?? '',
          profileImageUrl: result.profileImageUrl,
          createdAt: result.createdAt,
          expiresAt: result.expiresAt ?? '',
          isTrial: result.isTrial ?? false,
          referralCode: result.referralCode,
          referralCount: result.referralCount ?? 0,
          username: result.username,
          licenseKey: email, // Use email as identifier for email auth
        );
        _state = AuthState.authenticated;
        _addToAccounts(_userInfo!);
        _refreshFailures = 0;

        // Schedule proactive token refresh
        _scheduleTokenRefresh();

        // Register FCM
        _registerFCM();

        notifyListeners();
        return true;
      } else {
        // Check for pending approval
        if (result.approvalStatus == 'pending') {
          _state = AuthState.pendingApproval;
          _errorMessage = result.error ?? 'حسابك قيد المراجعة';
          notifyListeners();
          return false;
        }

        // P1-7 FIX: Track failed attempts and apply lockout
        _incrementAttempt();
        if (result.retryAfterSeconds != null && result.retryAfterSeconds! > 0) {
          _lockoutUntil = DateTime.now().add(
            Duration(seconds: result.retryAfterSeconds!),
          );
          final minutes = result.retryAfterSeconds! ~/ 60;
          _errorMessage = minutes > 0
              ? 'تم حظر الحساب مؤقتاً. حاول مرة أخرى بعد $minutes دقائق'
              : 'تم حظر الحساب مؤقتاً. حاول مرة أخرى بعد ${result.retryAfterSeconds} ثانية';
        } else {
          _errorMessage = result.error ?? 'البريد الإلكتروني أو كلمة المرور غير صحيحة';
        }

        // P1-7 FIX: Persist rate limit state
        await _saveRateLimitState();

        _state = AuthState.error;
        notifyListeners();
        return false;
      }
    } on AuthenticationException catch (e) {
      // P1-7 FIX: Track rate limiting from server response
      if (e.statusCode == 429) {
        _incrementAttempt();
        // Extract retry-after if available
        _lockoutUntil = DateTime.now().add(const Duration(minutes: 15));
        await _saveRateLimitState();
      }
      _state = AuthState.error;
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } on ApiException catch (e) {
      // P1-7 FIX: Track rate limiting from server response
      if (e.statusCode == 429 && e.retryAfterSeconds != null) {
        _incrementAttempt();
        _lockoutUntil = DateTime.now().add(
          Duration(seconds: e.retryAfterSeconds!),
        );
        await _saveRateLimitState();
      } else {
        _incrementAttempt();
      }
      await _saveRateLimitState();
      _state = AuthState.error;
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _incrementAttempt();
      await _saveRateLimitState();
      _state = AuthState.error;
      _errorMessage = 'تعذر الاتصال بالخادم. تأكد من اتصالك بالإنترنت وحاول مجدداً ($e)';
      notifyListeners();
      return false;
    }
  }

  /// Forgot password - send reset email
  Future<bool> forgotPassword(String email) async {
    _state = AuthState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authRepository.forgotPassword(email);
      _state = AuthState.unauthenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _state = AuthState.error;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Reset password with token
  Future<bool> resetPassword(String token, String newPassword) async {
    _state = AuthState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authRepository.resetPassword(token, newPassword);
      _state = AuthState.unauthenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _state = AuthState.error;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Check approval status (for polling while waiting)
  Future<Map<String, dynamic>?> checkApprovalStatus() async {
    try {
      if (!isAuthenticated) return null;
      return await _authRepository.getApprovalStatus();
    } catch (e) {
      debugPrint('[AuthProvider] Failed to check approval status: $e');
      return null;
    }
  }

  /// Schedule proactive token refresh to prevent expired token errors
  void _scheduleTokenRefresh() {
    ApiClient().scheduleProactiveRefresh();
  }

  /// Register FCM token with backend
  Future<void> _registerFCM() async {
    try {
      await _fcmService.registerTokenWithBackend();
      debugPrint('[AuthProvider] FCM token registered successfully for ${_userInfo?.username}');
    } catch (e) {
      debugPrint('[AuthProvider] FCM registration failed (non-fatal): $e');
    }
  }
}
