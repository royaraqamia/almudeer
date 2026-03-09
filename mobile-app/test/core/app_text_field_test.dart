import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almudeer_mobile_app/core/widgets/app_text_field.dart';
import 'package:figma_squircle/figma_squircle.dart';

void main() {
  testWidgets('AppTextField respects borderRadius', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppTextField(hintText: 'Test', borderRadius: 12)),
      ),
    );

    // Find the Container that holds the decoration
    final containerFinder = find.byType(Container);
    final containers = tester.widgetList<Container>(containerFinder);

    // Find the one with our decoration
    final decorationContainer = containers.firstWhere(
      (c) => c.decoration is ShapeDecoration,
    );
    final decoration = decorationContainer.decoration as ShapeDecoration;
    final shape = decoration.shape as SmoothRectangleBorder;

    // Verify corner radius
    expect(shape.borderRadius.topLeft.cornerRadius, 12);
  });

  testWidgets('AppTextField respects lineHeight', (WidgetTester tester) async {
    const double testLineHeight = 1.8;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppTextField(hintText: 'Test', lineHeight: testLineHeight),
        ),
      ),
    );

    final textFieldFinder = find.byType(TextField);
    final textField = tester.widget<TextField>(textFieldFinder);

    expect(textField.style?.height, testLineHeight);
    expect(textField.decoration?.hintStyle?.height, testLineHeight);
  });
}
