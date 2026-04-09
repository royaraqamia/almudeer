// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

import 'package:almudeer_desktop/main.dart';

void main() {
  testWidgets('App loads successfully', (WidgetTester tester) async {
    // Initialize window manager before running app
    WidgetsFlutterBinding.ensureInitialized();
    await windowManager.ensureInitialized();

    // Build our app and trigger a frame.
    await tester.pumpWidget(const AlmudeerDesktop());

    // Verify that the app title is displayed.
    expect(find.text('Al-Mudeer'), findsOneWidget);
  });
}
