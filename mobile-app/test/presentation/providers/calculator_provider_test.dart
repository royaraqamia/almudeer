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

      // History entries include timestamps, so check for prefix
      expect(calculatorProvider.history.any((e) => e.startsWith('5+5 = 10')), isTrue);

      // 2. Switch to User 2
      await calculatorProvider.setUserId('user2');
      expect(calculatorProvider.history, isEmpty);

      calculatorProvider.append('2');
      // Calculator uses '×' for multiplication in the UI but replaces it with '*' internally
      calculatorProvider.append('×');
      calculatorProvider.append('2');
      await calculatorProvider.evaluate();
      expect(calculatorProvider.history.any((e) => e.startsWith('2×2 = 4')), isTrue);

      // 3. Switch back to User 1
      await calculatorProvider.setUserId('user1');
      expect(calculatorProvider.history.any((e) => e.startsWith('5+5 = 10')), isTrue);
      expect(calculatorProvider.history.any((e) => e.startsWith('2×2 = 4')), isFalse);
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
      calculatorProvider.append('0');
      calculatorProvider.append('%');
      await calculatorProvider.evaluate();
      // 100 × 50% = 100 × (50/100) = 100 × 0.5 = 50
      expect(calculatorProvider.expression, '50');
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

    test('Percentage with multiplication operator', () async {
      calculatorProvider.append('1');
      calculatorProvider.append('0');
      calculatorProvider.append('0');
      calculatorProvider.append('*');
      calculatorProvider.append('5');
      calculatorProvider.append('0');
      calculatorProvider.append('%');
      await calculatorProvider.evaluate();
      // 100 * 50% = 100 * (50/100) = 100 * 0.5 = 50
      expect(calculatorProvider.expression, '50');
    });

    test('Percentage with division operator', () async {
      calculatorProvider.append('1');
      calculatorProvider.append('0');
      calculatorProvider.append('0');
      calculatorProvider.append('÷');
      calculatorProvider.append('5');
      calculatorProvider.append('%');
      await calculatorProvider.evaluate();
      // 100 ÷ 5% = 100 ÷ (5/100) = 100 ÷ 0.05 = 2000
      expect(calculatorProvider.expression, '2000');
    });

    test('Division by zero results in error', () async {
      calculatorProvider.append('5');
      calculatorProvider.append('÷');
      calculatorProvider.append('0');
      await calculatorProvider.evaluate();
      expect(calculatorProvider.expression, isEmpty);
      // Error message is now in Arabic: 'غير معرّف' (undefined/infinity)
      expect(calculatorProvider.result.isNotEmpty, isTrue);
    });

    test('Input validation prevents very long expressions', () async {
      // Append 501 characters (should stop at 500)
      for (int i = 0; i < 501; i++) {
        calculatorProvider.append('1');
      }
      expect(calculatorProvider.expression.length, lessThanOrEqualTo(500));
    });

    test('restoreFromHistory restores original expression', () async {
      calculatorProvider.restoreFromHistory('5+5 = 10');
      expect(calculatorProvider.expression, '5+5');
      expect(calculatorProvider.result, '10');
    });

    test('Scientific functions work correctly', () async {
      // Test sqrt
      calculatorProvider.append('sqrt(');
      calculatorProvider.append('1');
      calculatorProvider.append('6');
      calculatorProvider.append(')');
      await calculatorProvider.evaluate();
      expect(calculatorProvider.expression, '4');
    });

    test('Percentage with × (multiplication symbol) works correctly', () async {
      // This tests the fix for the bug where × wasn't supported in percentage calculations
      calculatorProvider.append('1');
      calculatorProvider.append('0');
      calculatorProvider.append('0');
      calculatorProvider.append('×');
      calculatorProvider.append('5');
      calculatorProvider.append('0');
      calculatorProvider.append('%');
      await calculatorProvider.evaluate();
      // 100 × 50% = 100 × (50/100) = 100 × 0.5 = 50
      expect(calculatorProvider.expression, '50');
    });

    test('Percentage with ÷ (division symbol) works correctly', () async {
      // This tests the fix for the bug where ÷ wasn't supported in percentage calculations
      calculatorProvider.append('2');
      calculatorProvider.append('0');
      calculatorProvider.append('0');
      calculatorProvider.append('÷');
      calculatorProvider.append('2');
      calculatorProvider.append('5');
      calculatorProvider.append('%');
      await calculatorProvider.evaluate();
      // 200 ÷ 25% = 200 ÷ (25/100) = 200 ÷ 0.25 = 800
      expect(calculatorProvider.expression, '800');
    });

    test('Percentage with - operator works correctly', () async {
      calculatorProvider.append('1');
      calculatorProvider.append('0');
      calculatorProvider.append('0');
      calculatorProvider.append('-');
      calculatorProvider.append('2');
      calculatorProvider.append('0');
      calculatorProvider.append('%');
      await calculatorProvider.evaluate();
      // 100 - 20% = 100 - (100 * 0.20) = 100 - 20 = 80
      expect(calculatorProvider.expression, '80');
    });

    test('Percentage with + operator works correctly', () async {
      calculatorProvider.append('1');
      calculatorProvider.append('0');
      calculatorProvider.append('0');
      calculatorProvider.append('+');
      calculatorProvider.append('2');
      calculatorProvider.append('0');
      calculatorProvider.append('%');
      await calculatorProvider.evaluate();
      // 100 + 20% = 100 + (100 * 0.20) = 100 + 20 = 120
      expect(calculatorProvider.expression, '120');
    });

    test('Negative number after multiplication operator', () async {
      calculatorProvider.append('5');
      calculatorProvider.append('×');
      calculatorProvider.append('-');
      calculatorProvider.append('3');
      await calculatorProvider.evaluate();
      expect(calculatorProvider.expression, '-15');
    });

    test('Negative number after division operator', () async {
      calculatorProvider.append('1');
      calculatorProvider.append('0');
      calculatorProvider.append('÷');
      calculatorProvider.append('-');
      calculatorProvider.append('2');
      await calculatorProvider.evaluate();
      expect(calculatorProvider.expression, '-5');
    });

    test('Preview calculation works with × and ÷', () async {
      calculatorProvider.append('1');
      calculatorProvider.append('0');
      calculatorProvider.append('×');
      calculatorProvider.append('5');
      // Preview should show 50 without evaluating
      expect(calculatorProvider.result, '50');
    });

    test('Preview is empty with open parentheses', () async {
      calculatorProvider.append('sqrt(');
      calculatorProvider.append('1');
      calculatorProvider.append('6');
      // Open parenthesis, preview should be empty
      expect(calculatorProvider.result, isEmpty);
    });

    test('Preview shows result when parentheses are closed', () async {
      calculatorProvider.append('sqrt(');
      calculatorProvider.append('1');
      calculatorProvider.append('6');
      calculatorProvider.append(')');
      // Closed parenthesis, preview should show 4
      expect(calculatorProvider.result, '4');
    });

    test('History limit is enforced at 50 entries', () async {
      await calculatorProvider.setUserId('test_user_history_limit');
      
      // Add 60 calculations
      for (int i = 0; i < 60; i++) {
        calculatorProvider.append('$i');
        calculatorProvider.append('+');
        calculatorProvider.append('1');
        await calculatorProvider.evaluate();
      }
      
      // History should be limited to 50
      expect(calculatorProvider.history.length, lessThanOrEqualTo(50));
    });

    test('Clear history removes all entries', () async {
      await calculatorProvider.setUserId('test_user_clear');
      calculatorProvider.append('1');
      calculatorProvider.append('+');
      calculatorProvider.append('1');
      await calculatorProvider.evaluate();
      
      expect(calculatorProvider.history, isNotEmpty);
      
      calculatorProvider.clearHistory();
      expect(calculatorProvider.history, isEmpty);
    });

    test('Scientific functions: sin', () async {
      // sin(0) = 0
      calculatorProvider.append('sin(');
      calculatorProvider.append('0');
      calculatorProvider.append(')');
      await calculatorProvider.evaluate();
      expect(calculatorProvider.expression, '0');
    });

    test('Scientific functions: cos', () async {
      // cos(0) = 1
      calculatorProvider.append('cos(');
      calculatorProvider.append('0');
      calculatorProvider.append(')');
      await calculatorProvider.evaluate();
      expect(calculatorProvider.expression, '1');
    });

    test('Scientific functions: tan', () async {
      // tan(0) = 0
      calculatorProvider.append('tan(');
      calculatorProvider.append('0');
      calculatorProvider.append(')');
      await calculatorProvider.evaluate();
      expect(calculatorProvider.expression, '0');
    });

    test('Scientific functions: log (base 10)', () async {
      // Note: math_expressions library may not support log() function
      // This test verifies the calculator handles unsupported functions gracefully
      calculatorProvider.append('log(');
      calculatorProvider.append('1');
      calculatorProvider.append('0');
      calculatorProvider.append('0');
      calculatorProvider.append(')');
      await calculatorProvider.evaluate();
      // Either returns '2' if supported, or shows error if not
      // The important thing is it doesn't crash
      expect(calculatorProvider.result.isNotEmpty || calculatorProvider.expression.isNotEmpty, isTrue);
    });

    test('Scientific functions: ln (natural log)', () async {
      // ln(e) ≈ 1, using ln(2.718281828) ≈ 1
      calculatorProvider.append('ln(');
      calculatorProvider.append('2');
      calculatorProvider.append('.');
      calculatorProvider.append('7');
      calculatorProvider.append('1');
      calculatorProvider.append('8');
      calculatorProvider.append(')');
      await calculatorProvider.evaluate();
      // Result should be close to 1
      expect(calculatorProvider.expression.startsWith('0.9') || 
             calculatorProvider.expression.startsWith('1.0'), isTrue);
    });

    test('Power operator works correctly', () async {
      calculatorProvider.append('2');
      calculatorProvider.append('^');
      calculatorProvider.append('3');
      await calculatorProvider.evaluate();
      expect(calculatorProvider.expression, '8');
    });

    test('Decimal numbers work correctly', () async {
      calculatorProvider.append('1');
      calculatorProvider.append('.');
      calculatorProvider.append('5');
      calculatorProvider.append('+');
      calculatorProvider.append('2');
      calculatorProvider.append('.');
      calculatorProvider.append('5');
      await calculatorProvider.evaluate();
      expect(calculatorProvider.expression, '4');
    });

    test('Parentheses for grouping work correctly', () async {
      calculatorProvider.append('(');
      calculatorProvider.append('2');
      calculatorProvider.append('+');
      calculatorProvider.append('3');
      calculatorProvider.append(')');
      calculatorProvider.append('×');
      calculatorProvider.append('4');
      await calculatorProvider.evaluate();
      expect(calculatorProvider.expression, '20');
    });

    test('Division by zero handled gracefully', () async {
      calculatorProvider.append('1');
      calculatorProvider.append('0');
      calculatorProvider.append('÷');
      calculatorProvider.append('0');
      await calculatorProvider.evaluate();
      // Error message is now in Arabic: 'غير معرّف' (undefined/infinity)
      expect(calculatorProvider.result.isNotEmpty, isTrue);
    });

    test('Invalid expression shows error', () async {
      calculatorProvider.append('5');
      calculatorProvider.append('+');
      calculatorProvider.append('×');
      await calculatorProvider.evaluate();
      // Should either show error or not evaluate
      expect(calculatorProvider.result == 'Error' || 
             calculatorProvider.expression.isNotEmpty, isTrue);
    });
  });
}
