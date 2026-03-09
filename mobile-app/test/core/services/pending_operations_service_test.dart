import 'package:flutter_test/flutter_test.dart';
import 'package:almudeer_mobile_app/core/services/pending_operations_service.dart';

void main() {
  group('PendingOperation', () {
    test('should infer high priority for approve and send', () {
      final approveOp = PendingOperation(
        id: 'test_1',
        type: 'approve',
        payload: {'messageId': 1},
        createdAt: DateTime.now(),
      );

      final sendOp = PendingOperation(
        id: 'test_2',
        type: 'send',
        payload: {'senderContact': 'test'},
        createdAt: DateTime.now(),
      );

      expect(approveOp.priority, equals(OperationPriority.high));
      expect(sendOp.priority, equals(OperationPriority.high));
    });

    test('should infer medium priority for ignore and edit', () {
      final ignoreOp = PendingOperation(
        id: 'test_1',
        type: 'ignore',
        payload: {'messageId': 1},
        createdAt: DateTime.now(),
      );

      final editOp = PendingOperation(
        id: 'test_2',
        type: 'edit',
        payload: {'messageId': 1, 'newBody': 'test'},
        createdAt: DateTime.now(),
      );

      expect(ignoreOp.priority, equals(OperationPriority.medium));
      expect(editOp.priority, equals(OperationPriority.medium));
    });

    test('should infer low priority for mark_read and delete', () {
      final markReadOp = PendingOperation(
        id: 'test_1',
        type: 'mark_read',
        payload: {'senderContact': 'test'},
        createdAt: DateTime.now(),
      );

      final deleteOp = PendingOperation(
        id: 'test_2',
        type: 'delete',
        payload: {'messageId': 1},
        createdAt: DateTime.now(),
      );

      expect(markReadOp.priority, equals(OperationPriority.low));
      expect(deleteOp.priority, equals(OperationPriority.low));
    });

    test('shouldRetry returns true for new operations with no attempts', () {
      final op = PendingOperation(
        id: 'test_1',
        type: 'approve',
        payload: {},
        createdAt: DateTime.now(),
      );

      expect(op.shouldRetry, isTrue);
    });

    test('shouldRetry returns false after max retries (5)', () {
      final op = PendingOperation(
        id: 'test_1',
        type: 'approve',
        payload: {},
        createdAt: DateTime.now(),
        retryCount: 5,
        lastAttempt: DateTime.now(),
      );

      expect(op.shouldRetry, isFalse);
    });

    test('isStale returns true for operations older than 7 days', () {
      final staleOp = PendingOperation(
        id: 'test_1',
        type: 'approve',
        payload: {},
        createdAt: DateTime.now().subtract(const Duration(days: 8)),
      );

      expect(staleOp.isStale, isTrue);
    });

    test('isStale returns false for recent operations', () {
      final recentOp = PendingOperation(
        id: 'test_1',
        type: 'approve',
        payload: {},
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      );

      expect(recentOp.isStale, isFalse);
    });

    test('incrementRetry preserves priority', () {
      final op = PendingOperation(
        id: 'test_1',
        type: 'approve',
        payload: {},
        createdAt: DateTime.now(),
      );

      final incremented = op.incrementRetry('Test error');

      expect(incremented.priority, equals(OperationPriority.high));
      expect(incremented.retryCount, equals(1));
      expect(incremented.error, equals('Test error'));
    });

    test('JSON serialization roundtrip preserves all fields', () {
      final op = PendingOperation(
        id: 'test_1',
        type: 'approve',
        payload: {'messageId': 123, 'editedBody': 'test'},
        createdAt: DateTime(2024, 1, 15, 10, 30),
        retryCount: 2,
        lastAttempt: DateTime(2024, 1, 15, 10, 35),
        error: 'Network error',
      );

      final json = op.toJson();
      final restored = PendingOperation.fromJson(json);

      expect(restored.id, equals(op.id));
      expect(restored.type, equals(op.type));
      expect(restored.payload, equals(op.payload));
      expect(restored.retryCount, equals(op.retryCount));
      expect(restored.error, equals(op.error));
      expect(restored.priority, equals(OperationPriority.high));
    });
  });

  group('OperationPriority', () {
    test('priority ordering is correct', () {
      expect(
        OperationPriority.high.index,
        lessThan(OperationPriority.medium.index),
      );
      expect(
        OperationPriority.medium.index,
        lessThan(OperationPriority.low.index),
      );
    });
  });
}
