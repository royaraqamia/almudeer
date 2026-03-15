import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:math_expressions/math_expressions.dart';
import '../../data/repositories/settings_repository.dart';
import '../../core/utils/logger.dart';

/// Calculator provider with user-specific history sync and robust error handling.
///
/// Production-ready features:
/// - Per-user history isolation
/// - Backend sync with retry logic and debouncing
/// - Graceful error handling with detailed logging
/// - Sync status tracking with telemetry
/// - Race condition prevention during user switching
class CalculatorProvider extends ChangeNotifier {
  // Constants - extracted for maintainability
  static const int _maxExpressionLength = 500;
  static const int _maxHistoryEntries = 50;
  static const int _maxSyncRetries = 3;
  static const Duration _syncRetryDelay = Duration(seconds: 2);
  static const Duration _syncDebounceDelay = Duration(milliseconds: 500);

  String _expression = '';
  String _result = '';
  List<String> _history = [];
  String? _userId;
  SyncStatus _syncStatus = SyncStatus.idle;
  final SettingsRepository _settingsRepository;

  // Debouncing and race condition prevention
  DateTime? _lastSyncTime;
  bool _isSyncing = false;
  String? _syncingUserId; // Track which user ID the current sync is for

  String get expression => _expression;
  String get result => _result;
  List<String> get history => _history;
  String? get userId => _userId;
  SyncStatus get syncStatus => _syncStatus;

  CalculatorProvider({SettingsRepository? settingsRepository})
    : _settingsRepository = settingsRepository ?? SettingsRepository() {
    // Initial load will happen when setUserId is called via app initialization
  }

  /// Sets the current user ID and reloads their specific history
  ///
  /// CRITICAL: This method handles race conditions by:
  /// 1. Capturing the userId at call time
  /// 2. Checking userId before applying sync results
  /// 3. Cancelling pending syncs for different users
  Future<void> setUserId(String? userId) async {
    // Capture userId at call time for race condition prevention
    final callUserId = userId;

    // If userId changed during a pending sync, mark it as failed
    if (_syncingUserId != null && _syncingUserId != callUserId) {
      debugPrint('Calculator: User changed during pending sync, cancelling...');
      _isSyncing = false;
      _syncingUserId = null;
    }

    if (_userId == callUserId) return;

    _userId = callUserId;

    // Clear current history immediately to prevent leakage during load
    _expression = '';
    _result = '';
    _history = [];
    _syncStatus = SyncStatus.loading;
    _isSyncing = false;
    _syncingUserId = null;
    notifyListeners();

    if (_userId != null && _userId!.isNotEmpty) {
      await _loadHistory();
      // Migrate any anonymous history to user-specific storage
      await _migrateAnonymousHistory();

      // After loading local, sync from backend (fire and forget)
      // Use captured userId to prevent race conditions
      if (callUserId != null) {
        _syncFromBackend(callUserId)
            .then((_) {
              // Only update status if userId hasn't changed
              if (_userId == callUserId) {
                _syncStatus = SyncStatus.idle;
                notifyListeners();
              }
            })
            .catchError((e) {
              debugPrint('Calculator: Sync from backend failed: $e');
              if (_userId == callUserId) {
                _syncStatus = SyncStatus.failed;
                notifyListeners();
              }
            });
      }
    } else {
      _syncStatus = SyncStatus.idle;
      notifyListeners();
    }
  }

  /// Migrate anonymous history (saved before userId was set) to user-specific storage
  Future<void> _migrateAnonymousHistory() async {
    if (_userId == null || _userId!.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      const anonymousKey = 'calculator_history';
      final userKey = _getHistoryKey();

      // Don't migrate if already using user-specific key
      if (anonymousKey == userKey) return;

      final anonymousJson = prefs.getString(anonymousKey);
      if (anonymousJson != null && anonymousJson.isNotEmpty) {
        final anonymousHistoryRaw = List<dynamic>.from(
          jsonDecode(anonymousJson),
        );

        // Convert legacy format to simple string list
        final anonymousHistory = anonymousHistoryRaw
            .map((e) {
              if (e is String) {
                return e;
              } else if (e is Map<String, dynamic>) {
                // Extract entry from old structured format
                return e['entry'] as String?;
              }
              return null;
            })
            .whereType<String>()
            .toList();

        debugPrint(
          'Calculator: Found ${anonymousHistory.length} anonymous history entries to migrate',
        );

        // Merge with existing user history, avoiding duplicates
        final existingJson = prefs.getString(userKey);
        List<String> userHistory = [];
        if (existingJson != null) {
          userHistory = List<String>.from(
            jsonDecode(existingJson) as List<dynamic>,
          );
        }

        // Combine, avoiding duplicates by entry content, keeping most recent first
        final seenEntries = <String>{};
        var combined = <String>[];

        for (final entry in [...anonymousHistory, ...userHistory]) {
          if (entry.isNotEmpty && seenEntries.add(entry)) {
            combined.add(entry);
          }
        }

        // Limit to max entries
        if (combined.length > _maxHistoryEntries) {
          combined = combined.take(_maxHistoryEntries).toList();
        }

        // Save to user-specific key
        await prefs.setString(userKey, jsonEncode(combined));
        // Remove anonymous key
        await prefs.remove(anonymousKey);

        // Update in-memory history
        _history = combined;
        debugPrint(
          'Calculator: Migrated ${_history.length} entries to user-specific storage',
        );
      }
    } catch (e) {
      debugPrint('Calculator: Failed to migrate anonymous history: $e');
    }
  }

  /// Resets the calculator state (for logout or account switch)
  ///
  /// CRITICAL: Also clears backend history to prevent data leakage
  Future<void> reset() async {
    final userId = _userId;
    
    _expression = '';
    _result = '';
    _history = [];
    _userId = null;
    _syncStatus = SyncStatus.idle;
    _isSyncing = false;
    _syncingUserId = null;
    notifyListeners();

    // Clear from backend if there was a user
    if (userId != null && userId.isNotEmpty) {
      try {
        await _settingsRepository.clearCalculatorHistory();
        logger.info('Calculator history cleared from backend');
      } catch (e) {
        debugPrint('Calculator: Failed to clear backend history during reset: $e');
      }
    }
  }

  void append(String value) {
    // Input validation: prevent very long expressions
    if (_expression.length >= _maxExpressionLength) {
      return;
    }

    if (_expression.isEmpty) {
      if (isOperator(value) && value != '-') return;
      _expression = value;
    } else if (_expression == '0' && !isOperator(value)) {
      _expression = value;
    } else {
      // Operator replacement logic
      if (isOperator(value) &&
          isOperator(_expression[_expression.length - 1])) {
        // Allow negative sign after * / × ÷
        if (value == '-' &&
            (_expression.endsWith('*') ||
                _expression.endsWith('/') ||
                _expression.endsWith('×') ||
                _expression.endsWith('÷') ||
                _expression.endsWith('^'))) {
          _expression += value;
        } else {
          _expression =
              _expression.substring(0, _expression.length - 1) + value;
        }
      } else {
        _expression += value;
      }
    }
    _calculatePreview();
    notifyListeners();
  }

  void clear() {
    _expression = '';
    _result = '';
    notifyListeners();
  }

  void delete() {
    if (_expression.isNotEmpty) {
      _expression = _expression.substring(0, _expression.length - 1);
      _calculatePreview();
      notifyListeners();
    }
  }

  bool isOperator(String x) {
    return x == '/' ||
        x == '*' ||
        x == '-' ||
        x == '+' ||
        x == '÷' ||
        x == '×' ||
        x == '^';
  }

  /// Validates that parentheses are balanced and properly ordered
  bool _areParenthesesBalanced(String expr) {
    int balance = 0;
    for (int i = 0; i < expr.length; i++) {
      if (expr[i] == '(') {
        balance++;
      } else if (expr[i] == ')') {
        balance--;
        // If balance goes negative, we have a closing paren without opening
        if (balance < 0) return false;
      }
    }
    // Balance should be 0 if all parens are matched
    return balance == 0;
  }

  /// Transforms log(x) to ln(x)/ln(10) for base 10 logarithm
  /// math_expressions library uses ln() for natural logarithm, not log()
  String _transformLogToLog10(String expr) {
    // Simple approach: replace log(...) with ln(...)/ln(10)
    // Use regex to find log(...) patterns and transform them
    return expr.replaceAllMapped(
      RegExp(r'log\s*\(([^()]*(?:\([^()]*\)[^()]*)*)\)'),
      (match) {
        final content = match.group(1);
        return 'ln($content)/ln(10)';
      },
    );
  }

  /// Validates domain constraints for scientific functions
  /// Returns error message if invalid, null if valid
  String? _validateScientificFunctions(String expr) {
    // Check for sqrt of negative numbers: sqrt(-...)
    final sqrtNegative = RegExp(r'sqrt\s*\(\s*-');
    if (sqrtNegative.hasMatch(expr)) {
      return 'جذر تربيعي لسالب'; // Square root of negative
    }

    // Check for log(0) or log of negative numbers
    final logZeroOrNegative = RegExp(r'log\s*\(\s*(-?0|-[^0-9])');
    if (logZeroOrNegative.hasMatch(expr)) {
      return 'لوغاريتم صفر أو سالب'; // Log of zero or negative
    }

    // Check for ln(0) or ln of negative numbers
    final lnZeroOrNegative = RegExp(r'ln\s*\(\s*(-?0|-[^0-9])');
    if (lnZeroOrNegative.hasMatch(expr)) {
      return 'لوغاريتم طبيعي لصفر أو سالب'; // Natural log of zero or negative
    }

    return null; // Valid
  }

  /// Validates percentage usage in expression
  /// Returns error message if invalid, null if valid
  String? _validatePercentage(String expr) {
    // Check for consecutive % (e.g., 5%%)
    final doublePercent = RegExp(r'%\s*%');
    if (doublePercent.hasMatch(expr)) {
      return 'صيغة غير صحيحة'; // Invalid format
    }

    // Check for % followed by another operator (e.g., 5% % + 3)
    final percentFollowedByOp = RegExp(r'%\s*[+\-*/×÷^]');
    if (percentFollowedByOp.hasMatch(expr)) {
      return 'صيغة غير صحيحة'; // Invalid format
    }

    // Check for % at the end without operator before it (standalone %)
    final trailingPercent = RegExp(r'[+\-*/×÷^]\s*%(?!\d)');
    if (trailingPercent.hasMatch(expr)) {
      return 'صيغة غير صحيحة'; // Invalid format
    }

    return null; // Valid
  }

  Future<void> evaluate() async {
    if (_expression.isEmpty) return;
    if (isOperator(_expression[_expression.length - 1])) return;

    // Validate parentheses are balanced
    if (!_areParenthesesBalanced(_expression)) {
      _result = 'تعبير غير صحيح'; // Invalid expression
      _expression = '';
      notifyListeners();
      return;
    }

    // Validate scientific function domains
    final domainError = _validateScientificFunctions(_expression);
    if (domainError != null) {
      _result = domainError;
      _expression = '';
      notifyListeners();
      return;
    }

    // Validate percentage usage
    final percentError = _validatePercentage(_expression);
    if (percentError != null) {
      _result = percentError;
      _expression = '';
      notifyListeners();
      return;
    }

    try {
      String finalExpression = _expression;
      finalExpression = finalExpression.replaceAll('×', '*');
      finalExpression = finalExpression.replaceAll('÷', '/');

      // Scientific functions mapping for math_expressions library
      // The library uses: sin, cos, tan, log (natural log), ln (natural log), sqrt
      // Transform log(x) to log(x)/log(10) for base 10 logarithm (user expectation)
      // Use a pattern that matches log(...) where ... is any content up to matching )
      finalExpression = _transformLogToLog10(finalExpression);

      // Enhanced Percentage Logic:
      // Case 1: num + val% => num + (num * val/100)
      // Case 2: num - val% => num - (num * val/100)
      // Case 3: num × val% => num * (val/100)
      // Case 4: num ÷ val% => num / (val/100)
      // Case 5: else num% => (num * 0.01)

      // Handle percentage with any operator (+, -, *, /, ×, ÷)
      finalExpression = finalExpression.replaceAllMapped(
        RegExp(r'(\d+\.?\d*)\s*([+\-*/×÷])\s*(-?\d+\.?\d*)%'),
        (match) {
          final base = match.group(1);
          final op = match.group(2);
          final percentage = match.group(3);
          // Normalize × and ÷ to * and / for calculation
          final normalizedOp = op == '×' ? '*' : (op == '÷' ? '/' : op);
          // FIX: For multiplication/division, use (percentage * 0.01) directly
          // For addition/subtraction, use (base * percentage * 0.01)
          if (normalizedOp == '*' || normalizedOp == '/') {
            return '$base$normalizedOp($percentage*0.01)';
          } else {
            return '$base$normalizedOp($base*($percentage*0.01))';
          }
        },
      );

      finalExpression = finalExpression.replaceAllMapped(
        RegExp(r'(?<!\d)(\d+\.?\d*)%'),
        (match) => '(${match.group(1)}*0.01)',
      );

      final GrammarParser p = GrammarParser();
      final Expression exp = p.parse(finalExpression);
      final double eval = RealEvaluator().evaluate(exp).toDouble();

      // Handle Infinity and NaN
      if (!eval.isFinite) {
        if (eval.isInfinite) {
          _result = 'غير معرّف'; // Undefined (infinity)
        } else {
          _result = 'خطأ'; // Error (NaN)
        }
        _expression = '';
        notifyListeners();
        return;
      }

      _result = eval.toString();
      if (_result.endsWith('.0')) {
        _result = _result.substring(0, _result.length - 2);
      }

      await _addToHistory('$_expression = $_result');
      // Don't set error messages as new expression - only set valid numeric results
      // If result is a valid number, allow chaining; otherwise clear
      final isNumericResult = double.tryParse(_result) != null;
      _expression = isNumericResult ? _result : '';
      _result = '';
      notifyListeners();
    } catch (e) {
      // Provide more specific error messages based on the exception
      if (e is FormatException) {
        _result = 'صيغة غير صحيحة'; // Invalid format
      } else if (e.toString().contains('parse')) {
        _result = 'تعبير غير صحيح'; // Invalid expression
      } else {
        _result = 'خطأ'; // Generic error
      }
      _expression = ''; // Clear invalid expression
      notifyListeners();
    }
  }

  void _calculatePreview() {
    if (_expression.isEmpty ||
        isOperator(_expression[_expression.length - 1])) {
      _result = '';
      return;
    }

    // Validate parentheses are balanced before calculating preview
    if (!_areParenthesesBalanced(_expression)) {
      _result = '';
      return;
    }

    // Skip preview for scientific functions with domain errors
    // (will show error on evaluate instead)
    if (_validateScientificFunctions(_expression) != null) {
      _result = '';
      return;
    }

    // Skip preview for invalid percentage usage
    // (will show error on evaluate instead)
    if (_validatePercentage(_expression) != null) {
      _result = '';
      return;
    }

    try {
      String finalExpression = _expression;
      finalExpression = finalExpression.replaceAll('×', '*');
      finalExpression = finalExpression.replaceAll('÷', '/');

      // Scientific functions are supported by math_expressions library:
      // sin, cos, tan, log (natural log), ln (natural log), sqrt
      // Transform log(x) to log(x)/log(10) for base 10 logarithm (user expectation)
      finalExpression = _transformLogToLog10(finalExpression);

      // Handle percentage with any operator (+, -, *, /, ×, ÷)
      finalExpression = finalExpression.replaceAllMapped(
        RegExp(r'(\d+\.?\d*)\s*([+\-*/×÷])\s*(-?\d+\.?\d*)%'),
        (match) {
          final base = match.group(1);
          final op = match.group(2);
          final percentage = match.group(3);
          // Normalize × and ÷ to * and / for calculation
          final normalizedOp = op == '×' ? '*' : (op == '÷' ? '/' : op);
          // FIX: For multiplication/division, use (percentage * 0.01) directly
          // For addition/subtraction, use (base * percentage * 0.01)
          if (normalizedOp == '*' || normalizedOp == '/') {
            return '$base$normalizedOp($percentage*0.01)';
          } else {
            return '$base$normalizedOp($base*($percentage*0.01))';
          }
        },
      );

      finalExpression = finalExpression.replaceAllMapped(
        RegExp(r'(?<!\d)(\d+\.?\d*)%'),
        (match) => '(${match.group(1)}*0.01)',
      );

      try {
        final GrammarParser p = GrammarParser();
        final Expression exp = p.parse(finalExpression);
        final double eval = RealEvaluator().evaluate(exp).toDouble();

        // Handle Infinity and NaN
        if (!eval.isFinite) {
          _result = '';
          return;
        }

        String preview = eval.toString();
        if (preview.endsWith('.0')) {
          preview = preview.substring(0, preview.length - 2);
        }
        _result = preview;
      } catch (e) {
        _result = '';
      }
    } catch (e) {
      _result = '';
    }
  }

  String _getHistoryKey() {
    if (_userId == null || _userId!.isEmpty) return 'calculator_history';
    final key = 'calculator_history_$_userId';
    debugPrint('Calculator: Using history key: $key');
    return key;
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getHistoryKey();
      final historyJson = prefs.getString(key);
      if (historyJson != null) {
        final historyRaw = List<dynamic>.from(jsonDecode(historyJson));
        _history = historyRaw.map((e) {
          String entryStr;
          if (e is String) {
            entryStr = e;
          } else if (e is Map<String, dynamic>) {
            entryStr = e['entry'] as String? ?? '';
          } else if (e is Map) {
            entryStr = e['entry'] as String? ?? '';
          } else {
            entryStr = '';
          }
          // Clean timestamps from entries for display purposes only
          // Don't re-save here to avoid unnecessary writes and potential data loss
          entryStr = _cleanTimestampFromEntry(entryStr);
          return entryStr;
        }).where((e) => e.isNotEmpty).toList();

        debugPrint(
          'Calculator: Loaded ${_history.length} history entries from local storage',
        );
      } else {
        debugPrint('Calculator: No local history found for key: $key');
        _history = [];
      }
    } catch (e) {
      debugPrint('Calculator: Failed to load history: $e');
      _history = [];
    }
    notifyListeners();
  }

  /// Remove timestamp suffix from entry string
  /// Handles formats like: "5+5 = 10 2024-01-01" or "5+5 = 10 2024/01/01 10:00"
  /// or "5+5 = 10 2024-01-01T10:30:00Z"
  String _cleanTimestampFromEntry(String entry) {
    if (entry.isEmpty) return entry;
    
    // Pattern to match date/timestamp at the end of the string
    // Matches: YYYY-MM-DD, YYYY/MM/DD, YYYY-MM-DDTHH:MM:SS, with optional time
    final timestampPattern = RegExp(
      r'\s+\d{4}[-/T]\d{2}[-/]\d{2}([T\s]\d{2}:\d{2}(:\d{2})?([.,]\d+)?(Z|[+-]\d{2}:\d{2})?)?$',
    );
    
    String cleaned = entry.replaceAll(timestampPattern, '').trim();
    
    // Also clean any JSON-like timestamp patterns
    cleaned = cleaned.replaceAll(RegExp(r'\s*\{[^}]*timestamp[^}]*\}\s*'), '').trim();
    
    return cleaned;
  }

  Future<void> _addToHistory(String entry) async {
    try {
      _history.insert(0, entry);
      if (_history.length > _maxHistoryEntries) {
        _history.removeLast();
      }

      final prefs = await SharedPreferences.getInstance();
      final key = _getHistoryKey();
      await prefs.setString(key, jsonEncode(_history));
      debugPrint(
        'Calculator: Saved ${_history.length} entries to local storage (key: $key)',
      );

      // Sync to backend with debouncing
      // Capture userId at call time to prevent race conditions
      final syncUserId = _userId;
      if (syncUserId == null || syncUserId.isEmpty) {
        debugPrint('Calculator: Skipping backend sync - no userId');
      } else {
        debugPrint('Calculator: Scheduling backend sync with userId: $syncUserId');
        _scheduleSyncToBackend(syncUserId);
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Calculator: Failed to add entry to history: $e');
    }
  }

  /// Schedule sync with debouncing to prevent rapid API calls
  /// 
  /// [capturedUserId] The user ID to sync for (captured at call time to prevent race conditions)
  void _scheduleSyncToBackend(String capturedUserId) {
    final now = DateTime.now();
    final timeSinceLastSync = _lastSyncTime != null
        ? now.difference(_lastSyncTime!)
        : _syncDebounceDelay;

    // If we synced recently, wait for debounce delay
    if (timeSinceLastSync < _syncDebounceDelay) {
      final remainingDelay = _syncDebounceDelay - timeSinceLastSync;
      debugPrint(
        'Calculator: Debouncing sync, waiting ${remainingDelay.inMilliseconds}ms for user: $capturedUserId',
      );
      Future.delayed(remainingDelay, () {
        // Only sync if userId hasn't changed since scheduling
        if (_userId == capturedUserId && capturedUserId.isNotEmpty) {
          _syncToBackend(capturedUserId);
        } else {
          debugPrint(
            'Calculator: Cancelled scheduled sync - userId changed from $capturedUserId to $_userId',
          );
        }
      });
    } else {
      // Sync immediately
      _syncToBackend(capturedUserId);
    }
  }

  Future<void> _syncToBackend(String syncUserId, {int retryCount = 0}) async {
    // Validate userId - prevent sync if user changed or is null
    if (syncUserId.isEmpty || _userId == null || _userId!.isEmpty) {
      debugPrint('Calculator: Sync cancelled - invalid userId (sync: $syncUserId, current: $_userId)');
      return;
    }

    // Prevent concurrent syncs
    if (_isSyncing) {
      debugPrint('Calculator: Sync already in progress, skipping');
      return;
    }

    // Double-check userId before starting sync
    if (_userId != syncUserId) {
      debugPrint(
        'Calculator: Sync cancelled - userId changed from $syncUserId to $_userId',
      );
      return;
    }

    _syncingUserId = syncUserId;
    _isSyncing = true;
    _syncStatus = SyncStatus.syncing;
    notifyListeners();

    try {
      // Use the dedicated calculator history endpoint
      await _settingsRepository.updateCalculatorHistory(_history);
      debugPrint(
        'Calculator: Synced ${_history.length} entries to backend',
      );

      _lastSyncTime = DateTime.now();
      _syncStatus = SyncStatus.synced;
      logger.info(
        'Calculator history synced successfully',
        data: {'entries': _history.length},
      );
    } catch (e) {
      debugPrint('Calculator sync to backend failed: $e');
      logger.error(
        'Calculator sync to backend failed',
        error: e,
        stackTrace: StackTrace.current,
      );

      // Retry with exponential backoff
      if (retryCount < _maxSyncRetries) {
        debugPrint(
          'Calculator: Retrying sync in ${_syncRetryDelay.inSeconds}s (attempt ${retryCount + 1}/$_maxSyncRetries) for user: $syncUserId',
        );
        await Future.delayed(_syncRetryDelay);
        await _syncToBackend(syncUserId, retryCount: retryCount + 1);
      } else {
        debugPrint(
          'Calculator: Max retries reached. History saved locally but not synced to backend for user: $syncUserId',
        );
        _syncStatus = SyncStatus.failed;
      }
    } finally {
      // Only reset syncing state if this sync was for the current user
      if (_syncingUserId == syncUserId) {
        _isSyncing = false;
        _syncingUserId = null;
      }
      notifyListeners();
    }
  }

  Future<void> _syncFromBackend(String originalUserId) async {
    if (_userId == null || _userId!.isEmpty) return;

    _syncStatus = SyncStatus.loading;
    notifyListeners();

    try {
      // Use dedicated calculator history endpoint
      final backendHistory = await _settingsRepository.getCalculatorHistory();

      // CRITICAL: Check if userId changed during the async call
      if (originalUserId != _userId) {
        debugPrint(
          'Calculator: User changed during sync ($originalUserId -> $_userId), discarding sync result',
        );
        logger.warning(
          'Calculator: User changed during sync, discarding result',
        );
        _syncStatus = SyncStatus.idle;
        notifyListeners();
        return;
      }

      debugPrint(
        'Calculator: Backend returned ${backendHistory.length} history entries',
      );

      // Only merge if backend has history
      // If backend is empty, keep local history (it might be new unsynced data)
      if (backendHistory.isNotEmpty) {
        // Merge: backend is source of truth, but preserve local-only entries
        final combined = <String>[];
        final seenEntries = <String>{};

        // Add backend entries first (source of truth)
        for (final entry in backendHistory) {
          // Clean any timestamps from backend entries
          final cleanEntry = _cleanTimestampFromEntry(entry);
          if (cleanEntry.isNotEmpty && seenEntries.add(cleanEntry)) {
            combined.add(cleanEntry);
          }
        }

        // Add local-only entries (not already in backend)
        // Clean timestamps from local entries for consistent comparison
        for (final entry in _history) {
          final cleanEntry = _cleanTimestampFromEntry(entry);
          if (cleanEntry.isNotEmpty && seenEntries.add(cleanEntry)) {
            combined.add(cleanEntry);
          }
        }

        _history = combined.take(_maxHistoryEntries).toList();
        debugPrint(
          'Calculator: Merged history, now ${_history.length} entries',
        );

        // Save merged back to local
        final sharedPrefs = await SharedPreferences.getInstance();
        await sharedPrefs.setString(_getHistoryKey(), jsonEncode(_history));
      } else {
        debugPrint(
          'Calculator: Backend has no history, keeping local (${_history.length} entries)',
        );
      }

      _syncStatus = SyncStatus.synced;
      logger.info(
        'Calculator history synced from backend: ${_history.length} entries',
      );
    } catch (e) {
      debugPrint('Calculator sync from backend failed: $e');
      logger.error(
        'Calculator sync from backend failed',
        error: e,
        stackTrace: StackTrace.current,
      );
      _syncStatus = SyncStatus.failed;
    }

    notifyListeners();
  }

  /// Clear history from backend (used on logout)
  /// 
  /// [capturedUserId] The user ID captured at call time to prevent race conditions
  Future<void> _clearBackendHistory(String capturedUserId) async {
    // Validate userId - prevent clear if user changed
    if (capturedUserId.isEmpty || _userId == null || _userId!.isEmpty) {
      debugPrint('Calculator: Clear cancelled - invalid userId (captured: $capturedUserId, current: $_userId)');
      return;
    }

    // Double-check userId before clearing
    if (_userId != capturedUserId) {
      debugPrint(
        'Calculator: Clear cancelled - userId changed from $capturedUserId to $_userId',
      );
      return;
    }

    try {
      debugPrint('Calculator: Clearing backend history for userId: $capturedUserId');

      // Use dedicated calculator history endpoint
      await _settingsRepository.clearCalculatorHistory();

      logger.info('Calculator history cleared from backend');
    } catch (e) {
      debugPrint('Calculator: Failed to clear backend history: $e');
      logger.error('Calculator: Failed to clear backend history', error: e);
      rethrow;
    }
  }

  Future<void> clearHistory() async {
    try {
      // Capture userId to prevent race conditions
      final clearUserId = _userId;

      _history.clear();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_getHistoryKey());
      notifyListeners();

      // Also clear from backend with race condition check
      if (clearUserId != null && clearUserId.isNotEmpty) {
        await _clearBackendHistory(clearUserId);
      }
    } catch (e) {
      debugPrint('Calculator: Failed to clear history: $e');
      logger.error('Calculator: Failed to clear history', error: e);
      rethrow;
    }
  }

  void restoreFromHistory(String entry) {
    // Entry format is "$expression = $result"
    final calcParts = entry.split(' = ');
    if (calcParts.length == 2) {
      _expression = calcParts[0]; // Restore the original expression
      _result = calcParts[1]; // Keep result as preview
      notifyListeners();
    }
  }
}

/// Sync status for calculator history
enum SyncStatus {
  /// No sync operation in progress
  idle,

  /// Currently loading history from backend
  loading,

  /// Currently syncing to backend
  syncing,

  /// Successfully synced
  synced,

  /// Sync failed after retries
  failed,
}
