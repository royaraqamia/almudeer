import 'package:almudeer_mobile_app/features/tasks/data/models/task_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TaskModel Priority Parsing', () {
    group('fromMap - String priority (backend format)', () {
      test('should parse "low" priority correctly', () {
        final map = {
          'id': 'test-1',
          'title': 'Test Task',
          'priority': 'low',
        };

        final task = TaskModel.fromMap(map);

        expect(task.priority, equals(TaskPriority.low));
      });

      test('should parse "medium" priority correctly', () {
        final map = {
          'id': 'test-2',
          'title': 'Test Task',
          'priority': 'medium',
        };

        final task = TaskModel.fromMap(map);

        expect(task.priority, equals(TaskPriority.medium));
      });

      test('should parse "high" priority correctly', () {
        final map = {
          'id': 'test-3',
          'title': 'Test Task',
          'priority': 'high',
        };

        final task = TaskModel.fromMap(map);

        expect(task.priority, equals(TaskPriority.high));
      });

      test('should parse "urgent" priority correctly', () {
        final map = {
          'id': 'test-4',
          'title': 'Test Task',
          'priority': 'urgent',
        };

        final task = TaskModel.fromMap(map);

        expect(task.priority, equals(TaskPriority.urgent));
      });

      test('should default to "medium" for invalid string priority', () {
        final map = {
          'id': 'test-5',
          'title': 'Test Task',
          'priority': 'invalid_priority',
        };

        final task = TaskModel.fromMap(map);

        expect(task.priority, equals(TaskPriority.medium));
      });

      test('should default to "medium" for null priority', () {
        final map = {
          'id': 'test-6',
          'title': 'Test Task',
          'priority': null,
        };

        final task = TaskModel.fromMap(map);

        expect(task.priority, equals(TaskPriority.medium));
      });
    });

    group('fromMap - Int priority (legacy mobile format)', () {
      test('should parse priority 0 as "low"', () {
        final map = {
          'id': 'test-7',
          'title': 'Test Task',
          'priority': 0,
        };

        final task = TaskModel.fromMap(map);

        expect(task.priority, equals(TaskPriority.low));
      });

      test('should parse priority 1 as "medium"', () {
        final map = {
          'id': 'test-8',
          'title': 'Test Task',
          'priority': 1,
        };

        final task = TaskModel.fromMap(map);

        expect(task.priority, equals(TaskPriority.medium));
      });

      test('should parse priority 2 as "high"', () {
        final map = {
          'id': 'test-9',
          'title': 'Test Task',
          'priority': 2,
        };

        final task = TaskModel.fromMap(map);

        expect(task.priority, equals(TaskPriority.high));
      });

      test('should parse priority 3 as "urgent"', () {
        final map = {
          'id': 'test-10',
          'title': 'Test Task',
          'priority': 3,
        };

        final task = TaskModel.fromMap(map);

        expect(task.priority, equals(TaskPriority.urgent));
      });

      test('should default to "medium" for invalid int priority (negative)', () {
        final map = {
          'id': 'test-11',
          'title': 'Test Task',
          'priority': -1,
        };

        final task = TaskModel.fromMap(map);

        expect(task.priority, equals(TaskPriority.medium));
      });

      test('should default to "medium" for invalid int priority (out of range)', () {
        final map = {
          'id': 'test-12',
          'title': 'Test Task',
          'priority': 10,
        };

        final task = TaskModel.fromMap(map);

        expect(task.priority, equals(TaskPriority.medium));
      });
    });

    group('toJson - String priority format (backend compatibility)', () {
      test('should serialize "low" priority as string', () {
        final task = TaskModel(
          id: 'test-13',
          title: 'Test Task',
          priority: TaskPriority.low,
        );

        final json = task.toJson();

        expect(json['priority'], equals('low'));
      });

      test('should serialize "medium" priority as string', () {
        final task = TaskModel(
          id: 'test-14',
          title: 'Test Task',
          priority: TaskPriority.medium,
        );

        final json = task.toJson();

        expect(json['priority'], equals('medium'));
      });

      test('should serialize "high" priority as string', () {
        final task = TaskModel(
          id: 'test-15',
          title: 'Test Task',
          priority: TaskPriority.high,
        );

        final json = task.toJson();

        expect(json['priority'], equals('high'));
      });

      test('should serialize "urgent" priority as string', () {
        final task = TaskModel(
          id: 'test-16',
          title: 'Test Task',
          priority: TaskPriority.urgent,
        );

        final json = task.toJson();

        expect(json['priority'], equals('urgent'));
      });
    });

    group('toMap - Int priority format (local database)', () {
      test('should serialize "low" priority as int 0', () {
        final task = TaskModel(
          id: 'test-17',
          title: 'Test Task',
          priority: TaskPriority.low,
        );

        final map = task.toMap();

        expect(map['priority'], equals(0));
      });

      test('should serialize "medium" priority as int 1', () {
        final task = TaskModel(
          id: 'test-18',
          title: 'Test Task',
          priority: TaskPriority.medium,
        );

        final map = task.toMap();

        expect(map['priority'], equals(1));
      });

      test('should serialize "high" priority as int 2', () {
        final task = TaskModel(
          id: 'test-19',
          title: 'Test Task',
          priority: TaskPriority.high,
        );

        final map = task.toMap();

        expect(map['priority'], equals(2));
      });

      test('should serialize "urgent" priority as int 3', () {
        final task = TaskModel(
          id: 'test-20',
          title: 'Test Task',
          priority: TaskPriority.urgent,
        );

        final map = task.toMap();

        expect(map['priority'], equals(3));
      });
    });

    group('Priority round-trip conversion', () {
      test('should preserve priority through fromMap -> toJson -> fromMap', () {
        final originalMap = {
          'id': 'test-21',
          'title': 'Test Task',
          'priority': 'high',
        };

        final task1 = TaskModel.fromMap(originalMap);
        final json = task1.toJson();
        final task2 = TaskModel.fromJson(json);

        expect(task2.priority, equals(TaskPriority.high));
        expect(task2.priority, equals(task1.priority));
      });

      test('should handle legacy int format through round-trip', () {
        final originalMap = {
          'id': 'test-22',
          'title': 'Test Task',
          'priority': 2, // Legacy int format
        };

        final task1 = TaskModel.fromMap(originalMap);
        // When converting to JSON for backend, should become string
        final json = task1.toJson();
        
        expect(json['priority'], equals('high'));
        
        // And back from backend format
        final task2 = TaskModel.fromJson(json);
        expect(task2.priority, equals(TaskPriority.high));
      });
    });

    group('TaskPriorityExtension', () {
      test('should return correct Arabic labels', () {
        expect(TaskPriority.low.label, equals('منخفضة'));
        expect(TaskPriority.medium.label, equals('متوسطة'));
        expect(TaskPriority.high.label, equals('عالية'));
        expect(TaskPriority.urgent.label, equals('عاجلة'));
      });

      test('should return correct color values', () {
        expect(TaskPriority.low.colorValue, equals(0xFF6B7280));
        expect(TaskPriority.medium.colorValue, equals(0xFF2563EB));
        expect(TaskPriority.high.colorValue, equals(0xFFF59E0B));
        expect(TaskPriority.urgent.colorValue, equals(0xFFEF4444));
      });
    });
  });
}
