import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almudeer_mobile_app/presentation/providers/calculator_provider.dart';

void main() {
  // Initialize SharedPreferences before tests
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('CalculatorProvider History Isolation', () {
    late CalculatorProvider calculatorProvider;

    setUp(() async {
      // Clear shared preferences before each test
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      
      calculatorProvider = CalculatorProvider();
    });

    tearDown(() async {
      calculatorProvider.reset();
      // Clear shared preferences after each test
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    });

    test('History is empty initially', () async {
      await calculatorProvider.setUserId('user1');
      expect(calculatorProvider.history, isEmpty);
    });

    test('History is stored per user', () async {
      // User 1
      await calculatorProvider.setUserId('user1');
      calculatorProvider.append('5');
      calculatorProvider.append('+');
      calculatorProvider.append('5');
      await calculatorProvider.evaluate();
      
      final user1History = List.from(calculatorProvider.history);
      expect(user1History.any((e) => e['entry'].toString().startsWith('5+5 = 10')), isTrue);

      // User 2 - should have separate history
      await calculatorProvider.setUserId('user2');
      expect(calculatorProvider.history, isEmpty);

      calculatorProvider.append('2');
      // Calculator uses '×' for multiplication in the UI but replaces it with '*' internally
      calculatorProvider.append('×');
      calculatorProvider.append('2');
      await calculatorProvider.evaluate();
      expect(calculatorProvider.history.any((e) => e['entry'].toString().startsWith('2×2 = 4')), isTrue);

      // Back to User 1 - should still have original history
      await calculatorProvider.setUserId('user1');
      expect(calculatorProvider.history.any((e) => e['entry'].toString().startsWith('5+5 = 10')), isTrue);
      expect(calculatorProvider.history.any((e) => e['entry'].toString().startsWith('2×2 = 4')), isFalse);
    });

    test('Operator replacement works correctly', () async {
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
      // 100 × 50% = 100 × 0.5 = 50
      expect(calculatorProvider.expression, '50');
    });

    test('Operators at start are ignored (except minus)', () async {
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
      // 100 * 50% = 100 * 0.5 = 50
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
      // 100 ÷ 5% = 100 ÷ 0.05 = 2000
      expect(calculatorProvider.expression, '2000');
    });

    test('Division by zero handled gracefully', () async {
      calculatorProvider.append('5');
      calculatorProvider.append('÷');
      calculatorProvider.append('0');
      await calculatorProvider.evaluate();
      // Should show error but keep result visible
      expect(calculatorProvider.expression, isEmpty);
      expect(calculatorProvider.result.isNotEmpty, isTrue);
    });

    test('Expression length is limited', () async {
      for (int i = 0; i < 600; i++) {
        calculatorProvider.append('1');
      }
      expect(calculatorProvider.expression.length, lessThanOrEqualTo(500));
    });

    test('Restore from history works', () async {
      // Entry format is now structured, but restoreFromHistory takes the entry string
      calculatorProvider.restoreFromHistory('5+5 = 10');
      expect(calculatorProvider.expression, '5+5');
      expect(calculatorProvider.result, '10');
    });

    test('Scientific functions work correctly', () async {
      calculatorProvider.append('sqrt(');
      calculatorProvider.append('1');
      calculatorProvider.append('6');
      calculatorProvider.append(')');
      await calculatorProvider.evaluate();
      expect(calculatorProvider.expression, '4');
    });

    test('Percentage with × (multiplication symbol) works correctly', () async {
      calculatorProvider.append('1');
      calculatorProvider.append('0');
      calculatorProvider.append('0');
      calculatorProvider.append('×');
      calculatorProvider.append('5');
      calculatorProvider.append('0');
      calculatorProvider.append('%');
      await calculatorProvider.evaluate();
      // 100 × 50% = 100 × 0.5 = 50
      expect(calculatorProvider.expression, '50');
    });

    test('Percentage with ÷ (division symbol) works correctly', () async {
      calculatorProvider.append('2');
      calculatorProvider.append('0');
      calculatorProvider.append('0');
      calculatorProvider.append('÷');
      calculatorProvider.append('2');
      calculatorProvider.append('5');
      calculatorProvider.append('%');
      await calculatorProvider.evaluate();
      // 200 ÷ 25% = 200 ÷ 0.25 = 800
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
      // 100 - 20% = 100 - (100 * 0.2) = 80
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
      // 100 + 20% = 100 + (100 * 0.2) = 120
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

    test('Preview shows during calculation', () async {
      calculatorProvider.append('1');
      calculatorProvider.append('0');
      calculatorProvider.append('×');
      calculatorProvider.append('5');
      // Result should show preview
      expect(calculatorProvider.result, '50');
    });

    test('Preview empty for incomplete scientific function', () async {
      calculatorProvider.append('sqrt(');
      calculatorProvider.append('1');
      calculatorProvider.append('6');
      // Missing closing paren - no preview
      expect(calculatorProvider.result, isEmpty);
    });

    test('Preview shows for complete scientific function', () async {
      calculatorProvider.append('sqrt(');
      calculatorProvider.append('1');
      calculatorProvider.append('6');
      calculatorProvider.append(')');
      expect(calculatorProvider.result, '4');
    });

    test('History limit is enforced at 50 entries', () async {
      await calculatorProvider.setUserId('test_user_history_limit');
      
      for (int i = 0; i < 60; i++) {
        calculatorProvider.append('$i');
        calculatorProvider.append('+');
        calculatorProvider.append('1');
        await calculatorProvider.evaluate();
      }
      
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
      calculatorProvider.append('sin(');
      calculatorProvider.append('0');
      calculatorProvider.append(')');
      await calculatorProvider.evaluate();
      expect(calculatorProvider.expression, '0');
    });

    test('Scientific functions: cos', () async {
      calculatorProvider.append('cos(');
      calculatorProvider.append('0');
      calculatorProvider.append(')');
      await calculatorProvider.evaluate();
      expect(calculatorProvider.expression, '1');
    });

    test('Scientific functions: tan', () async {
      calculatorProvider.append('tan(');
      calculatorProvider.append('0');
      calculatorProvider.append(')');
      await calculatorProvider.evaluate();
      expect(calculatorProvider.expression, '0');
    });

    test('Scientific functions: log', () async {
      calculatorProvider.append('log(');
      calculatorProvider.append('1');
      calculatorProvider.append('0');
      calculatorProvider.append('0');
      calculatorProvider.append(')');
      await calculatorProvider.evaluate();
      expect(calculatorProvider.expression, '2');
    });

    test('Scientific functions: ln (natural log)', () async {
      calculatorProvider.append('ln(');
      // e ≈ 2.718281828, ln(e) = 1
      calculatorProvider.append('2');
      calculatorProvider.append('.');
      calculatorProvider.append('7');
      calculatorProvider.append('1');
      calculatorProvider.append('8');
      calculatorProvider.append(')');
      await calculatorProvider.evaluate();
      // Should be approximately 1
      expect(double.tryParse(calculatorProvider.expression), closeTo(1.0, 0.1));
    });

    test('Power operator works correctly', () async {
      calculatorProvider.append('2');
      calculatorProvider.append('^');
      calculatorProvider.append('1');
      calculatorProvider.append('0');
      await calculatorProvider.evaluate();
      expect(calculatorProvider.expression, '1024');
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

    test('Unbalanced parentheses show error', () async {
      calculatorProvider.append('(');
      calculatorProvider.append('2');
      calculatorProvider.append('+');
      calculatorProvider.append('3');
      // Missing closing paren
      await calculatorProvider.evaluate();
      expect(calculatorProvider.result, 'تعبير غير صحيح');
    });

    test('sqrt of negative shows error', () async {
      calculatorProvider.append('sqrt(');
      calculatorProvider.append('-');
      calculatorProvider.append('4');
      calculatorProvider.append(')');
      await calculatorProvider.evaluate();
      expect(calculatorProvider.result, 'جذر تربيعي لسالب');
    });

    test('log of zero shows error', () async {
      calculatorProvider.append('log(');
      calculatorProvider.append('0');
      calculatorProvider.append(')');
      await calculatorProvider.evaluate();
      expect(calculatorProvider.result, 'لوغاريتم صفر أو سالب');
    });

    test('SyncStatus enum values exist', () {
      expect(SyncStatus.values, contains(SyncStatus.idle));
      expect(SyncStatus.values, contains(SyncStatus.loading));
      expect(SyncStatus.values, contains(SyncStatus.syncing));
      expect(SyncStatus.values, contains(SyncStatus.synced));
      expect(SyncStatus.values, contains(SyncStatus.failed));
    });

    test('SyncStatus is exposed via getter', () async {
      await calculatorProvider.setUserId('test_user');
      expect(calculatorProvider.syncStatus, isNotNull);
    });
  });
}
