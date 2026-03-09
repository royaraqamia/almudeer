import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:math_expressions/math_expressions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/models/user_preferences.dart';

class CalculatorProvider extends ChangeNotifier {
  String _expression = '';
  String _result = '';
  List<String> _history = [];
  String? _userId;
  final SettingsRepository _settingsRepository;

  String get expression => _expression;
  String get result => _result;
  List<String> get history => _history;
  String? get userId => _userId;

  CalculatorProvider({SettingsRepository? settingsRepository})
    : _settingsRepository = settingsRepository ?? SettingsRepository() {
    // Initial load will happen when setUserId is called via app initialization
  }

  /// Sets the current user ID and reloads their specific history
  Future<void> setUserId(String? userId) async {
    if (_userId == userId) return;
    _userId = userId;

    // Clear current history and state immediately to prevent leakage during load
    _expression = '';
    _result = '';
    _history = [];

    if (_userId != null && _userId!.isNotEmpty) {
      await _loadHistory();
      // Migrate any anonymous history to user-specific storage
      await _migrateAnonymousHistory();
      // After loading local, sync from backend (fire and forget)
      // Don't await - we don't want to block UI on network
      _syncFromBackend().then((_) => notifyListeners());
    } else {
      notifyListeners();
    }
  }

  /// Migrate anonymous history (saved before userId was set) to user-specific storage
  Future<void> _migrateAnonymousHistory() async {
    if (_userId == null || _userId!.isEmpty) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final anonymousKey = 'calculator_history';
      final userKey = _getHistoryKey();
      
      // Don't migrate if already using user-specific key
      if (anonymousKey == userKey) return;
      
      final anonymousJson = prefs.getString(anonymousKey);
      if (anonymousJson != null && anonymousJson.isNotEmpty) {
        final anonymousHistory = List<String>.from(jsonDecode(anonymousJson));
        debugPrint('Calculator: Found ${anonymousHistory.length} anonymous history entries to migrate');
        
        // Merge with existing user history
        final existingJson = prefs.getString(userKey);
        List<String> userHistory = [];
        if (existingJson != null) {
          userHistory = List<String>.from(jsonDecode(existingJson));
        }
        
        // Combine, avoiding duplicates, keeping most recent first
        final Set<String> combined = {...anonymousHistory, ...userHistory};
        userHistory = combined.toList();
        if (userHistory.length > 50) userHistory = userHistory.sublist(0, 50);
        
        // Save to user-specific key
        await prefs.setString(userKey, jsonEncode(userHistory));
        // Remove anonymous key
        await prefs.remove(anonymousKey);
        
        // Update in-memory history
        _history = userHistory;
        debugPrint('Calculator: Migrated ${_history.length} entries to user-specific storage');
      }
    } catch (e) {
      debugPrint('Calculator: Failed to migrate anonymous history: $e');
    }
  }

  /// Resets the calculator state (for logout or account switch)
  void reset() {
    _expression = '';
    _result = '';
    _history = [];
    _userId = null;
    notifyListeners();
  }

  void append(String value) {
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

  Future<void> evaluate() async {
    if (_expression.isEmpty) return;
    if (isOperator(_expression[_expression.length - 1])) return;

    try {
      String finalExpression = _expression;
      finalExpression = finalExpression.replaceAll('×', '*');
      finalExpression = finalExpression.replaceAll('÷', '/');

      // Enhanced Percentage Logic:
      // Case 1: num + val% => num + (num * val/100)
      // Case 2: num - val% => num - (num * val/100)
      // Case 3: else num% => (num * 0.01)

      finalExpression = finalExpression.replaceAllMapped(
        RegExp(r'(\d+\.?\d*)\s*([+\-])\s*(\d+\.?\d*)%'),
        (match) {
          final base = match.group(1);
          final op = match.group(2);
          final percentage = match.group(3);
          return '$base$op($base*($percentage*0.01))';
        },
      );

      finalExpression = finalExpression.replaceAllMapped(
        RegExp(r'(\d+\.?\d*)%'),
        (match) => '(${match.group(1)}*0.01)',
      );

      GrammarParser p = GrammarParser();
      Expression exp = p.parse(finalExpression);
      double eval = RealEvaluator().evaluate(exp).toDouble();

      _result = eval.toString();
      if (_result.endsWith('.0')) {
        _result = _result.substring(0, _result.length - 2);
      }

      await _addToHistory('$_expression = $_result');
      _expression = _result;
      _result = '';
      notifyListeners();
    } catch (e) {
      _result = 'Error';
      notifyListeners();
    }
  }

  void _calculatePreview() {
    if (_expression.isEmpty ||
        isOperator(_expression[_expression.length - 1])) {
      _result = '';
      return;
    }

    // Check for open parentheses
    int openCount = '('.allMatches(_expression).length;
    int closeCount = ')'.allMatches(_expression).length;
    if (openCount > closeCount) {
      _result = '';
      return;
    }

    try {
      String finalExpression = _expression;
      finalExpression = finalExpression.replaceAll('×', '*');
      finalExpression = finalExpression.replaceAll('÷', '/');

      finalExpression = finalExpression.replaceAllMapped(
        RegExp(r'(\d+\.?\d*)%'),
        (match) => '(${match.group(1)}*0.01)',
      );

      GrammarParser p = GrammarParser();
      Expression exp = p.parse(finalExpression);
      double eval = RealEvaluator().evaluate(exp).toDouble();

      String preview = eval.toString();
      if (preview.endsWith('.0')) {
        preview = preview.substring(0, preview.length - 2);
      }
      _result = preview;
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
    final prefs = await SharedPreferences.getInstance();
    final key = _getHistoryKey();
    final historyJson = prefs.getString(key);
    if (historyJson != null) {
      _history = List<String>.from(jsonDecode(historyJson));
      debugPrint('Calculator: Loaded ${_history.length} history entries from local storage');
    } else {
      debugPrint('Calculator: No local history found for key: $key');
      _history = [];
    }
    notifyListeners();
  }

  Future<void> _addToHistory(String entry) async {
    _history.insert(0, entry);
    if (_history.length > 50) _history.removeLast();

    final prefs = await SharedPreferences.getInstance();
    final key = _getHistoryKey();
    await prefs.setString(key, jsonEncode(_history));
    debugPrint('Calculator: Saved ${_history.length} entries to local storage (key: $key)');

    // Sync to backend
    if (_userId == null || _userId!.isEmpty) {
      debugPrint('Calculator: Skipping backend sync - no userId');
    } else {
      debugPrint('Calculator: Syncing to backend with userId: $_userId');
      _syncToBackend();
    }

    notifyListeners();
  }

  Future<void> _syncToBackend() async {
    if (_userId == null || _userId!.isEmpty) return;
    try {
      // Get existing preferences or create minimal update with just calculator history
      var prefs = await _settingsRepository.getLocalPreferences();
      if (prefs != null) {
        await _settingsRepository.updatePreferences(
          prefs.copyWith(calculatorHistory: _history),
        );
        debugPrint('Calculator: Synced ${_history.length} entries to backend (with existing prefs)');
      } else {
        // No existing preferences, create minimal update with just calculator history
        // This ensures calculator history is saved even if user hasn't changed other settings
        await _settingsRepository.updatePreferences(
          UserPreferences(calculatorHistory: _history),
        );
        debugPrint('Calculator: Synced ${_history.length} entries to backend (new prefs)');
      }
    } catch (e) {
      debugPrint('Calculator sync to backend failed: $e');
    }
  }

  Future<void> _syncFromBackend() async {
    if (_userId == null || _userId!.isEmpty) return;

    try {
      final prefs = await _settingsRepository.getPreferences();
      debugPrint('Calculator: Backend returned ${prefs.calculatorHistory.length} history entries');
      // Only merge if backend has history
      // If backend is empty, keep local history (it might be new unsynced data)
      if (prefs.calculatorHistory.isNotEmpty) {
        // Merge: prefer backend as source of truth, but add any local-only entries
        final Set<String> combined = {...prefs.calculatorHistory, ..._history};
        _history = combined.toList();
        // Sort by most recent (entries at the front are newer)
        if (_history.length > 50) _history = _history.sublist(0, 50);
        debugPrint('Calculator: Merged history, now ${_history.length} entries');

        // Save merged back to local
        final sharedPrefs = await SharedPreferences.getInstance();
        await sharedPrefs.setString(_getHistoryKey(), jsonEncode(_history));
      } else {
        debugPrint('Calculator: Backend has no history, keeping local (${_history.length} entries)');
      }
      // If backend has no history, keep local history as-is (don't overwrite)
    } catch (e) {
      debugPrint('Calculator sync from backend failed: $e');
    }
  }

  void clearHistory() async {
    _history.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_getHistoryKey());
    notifyListeners();
  }

  void restoreFromHistory(String entry) {
    // Entry format is "$expression = $result"
    final parts = entry.split(' = ');
    if (parts.length == 2) {
      _expression = parts[1]; // Restore the result as the new expression
      _result = '';
      notifyListeners();
    }
  }
}
