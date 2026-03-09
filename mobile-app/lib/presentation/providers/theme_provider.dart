import 'package:flutter/material.dart';

/// Theme provider for managing app theme
/// Always uses dark mode
class ThemeProvider extends ChangeNotifier {
  bool _isInitialized = false;
  bool _isDisposed = false;

  bool get isInitialized => _isInitialized;

  /// Get the effective theme mode - always dark
  ThemeMode get effectiveThemeMode => ThemeMode.dark;

  /// Check if dark mode is active - always true
  bool isDarkMode(BuildContext context) => true;

  /// Initialize theme provider
  Future<void> init() async {
    _isInitialized = true;
    notifyListeners();
  }

  /// Toggle theme (no-op, always dark)
  Future<void> toggleTheme() async {
    // No-op: app is always in dark mode
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
}
