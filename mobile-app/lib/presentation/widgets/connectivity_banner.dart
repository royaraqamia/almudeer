import 'package:flutter/material.dart';

/// Animated banner that shows connectivity and sync status.
///
/// Features:
/// - Slides in/out smoothly on connectivity changes
/// - Shows sync progress when syncing
/// - Tap to retry sync when offline
class ConnectivityBanner extends StatelessWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context) {
    // Hidden from UI as requested, but keeping the class for reference
    return const SizedBox.shrink();
  }
}

/// Wrap scaffold body with this to show connectivity banner at top
class ConnectivityAwareScaffold extends StatelessWidget {
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final Color? backgroundColor;

  const ConnectivityAwareScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      backgroundColor: backgroundColor,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      body: body,
    );
  }
}
