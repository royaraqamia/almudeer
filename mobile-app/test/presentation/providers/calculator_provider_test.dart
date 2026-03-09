import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almudeer_mobile_app/presentation/providers/calculator_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CalculatorProvider History Isolation', () {
    late CalculatorProvider calculatorProvider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      calculatorProvider = CalculatorProvider();
    });

    test('History is empty initially', () async {
      await calculatorProvider.setUserId('user1');
      expect(calculatorProvider.history, isEmpty);
    });

    test('History is stored per user', () async {
      // 1. User 1 performs a calculation
      await calculatorProvider.setUserId('user1');
      calculatorProvider.append('5');
      calculatorProvider.append('+');
      calculatorProvider.append('5');
      await calculatorProvider.evaluate();

      expect(calculatorProvider.history, contains('5+5 = 10'));

      // 2. Switch to User 2
      await calculatorProvider.setUserId('user2');
      expect(calculatorProvider.history, isEmpty);

      calculatorProvider.append('2');
      // Calculator uses '×' for multiplication in the UI but replaces it with '*' internally
      calculatorProvider.append('×');
      calculatorProvider.append('2');
      await calculatorProvider.evaluate();
      expect(calculatorProvider.history, contains('2×2 = 4'));

      // 3. Switch back to User 1
      await calculatorProvider.setUserId('user1');
      expect(calculatorProvider.history, contains('5+5 = 10'));
      expect(calculatorProvider.history, isNot(contains('2×2 = 4')));
    });

    test('Operator replacement logic', () async {
      calculatorProvider.append('5');
      calculatorProvider.append('+');
      calculatorProvider.append('*'); // Should replace + with *
      expect(calculatorProvider.expression, '5*');
    });

    test('Percentage calculation', () async {
      calculatorProvider.append('5');
      calculatorProvider.append('0');
      calculatorProvider.append('%');
      await calculatorProvider.evaluate();
      expect(calculatorProvider.expression, '0.5');
    });

    test('Complex percentage calculation', () async {
      calculatorProvider.append('1');
      calculatorProvider.append('0');
      calculatorProvider.append('0');
      calculatorProvider.append('×');
      calculatorProvider.append('5');
      calculatorProvider.append('%');
      await calculatorProvider.evaluate();
      expect(calculatorProvider.expression, '5');
    });

    test('Invalid leading operator replacement', () async {
      calculatorProvider.append('×'); // Should be ignored
      expect(calculatorProvider.expression, isEmpty);

      calculatorProvider.append('-'); // Should be allowed
      expect(calculatorProvider.expression, '-');
    });

    test('Reset clears history from memory', () async {
      await calculatorProvider.setUserId('user1');
      calculatorProvider.append('1');
      calculatorProvider.append('+');
      calculatorProvider.append('1');
      await calculatorProvider.evaluate();
      expect(calculatorProvider.history, isNotEmpty);

      calculatorProvider.reset();
      expect(calculatorProvider.history, isEmpty);
      expect(calculatorProvider.expression, isEmpty);
      expect(calculatorProvider.userId, isNull);
    });
  });
}
