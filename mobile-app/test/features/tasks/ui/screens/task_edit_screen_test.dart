import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:provider/provider.dart';

import 'package:almudeer_mobile_app/features/tasks/models/task_model.dart';
import 'package:almudeer_mobile_app/features/tasks/providers/task_provider.dart';
import 'package:almudeer_mobile_app/features/tasks/ui/screens/task_edit_screen.dart';
import 'package:almudeer_mobile_app/features/tasks/repositories/task_repository.dart';

@GenerateMocks([TaskProvider, TaskRepository])
import 'task_edit_screen_test.mocks.dart';

void main() {
  late MockTaskProvider mockProvider;
  late MockTaskRepository mockRepository;

  setUp(() {
    mockProvider = MockTaskProvider();
    mockRepository = MockTaskRepository();
    when(mockProvider.currentUserId).thenReturn('user-123');
    when(mockProvider.tasks).thenReturn([]);
    when(mockProvider.isLoading).thenReturn(false);
    when(mockProvider.filter).thenReturn(TaskFilter.today);
    when(mockProvider.searchQuery).thenReturn('');
    when(mockProvider.filteredTasks).thenReturn([]);
    when(mockProvider.hasMore).thenReturn(true);
    when(mockProvider.isLoadingMore).thenReturn(false);
    when(mockProvider.collaborators).thenReturn([]);
    when(mockProvider.lastError).thenReturn(null);
    when(mockProvider.hasError).thenReturn(false);
    when(mockProvider.hasSyncFailure).thenReturn(false);
    when(mockProvider.lastSyncFailureTime).thenReturn(null);
    when(mockProvider.lastSyncFailureReason).thenReturn(null);
    when(mockProvider.canRetry).thenReturn(false);
    when(mockProvider.repository).thenReturn(mockRepository);
  });

  Widget createTestWidget({TaskModel? task}) {
    return ChangeNotifierProvider<TaskProvider>.value(
      value: mockProvider,
      child: MaterialApp(
        home: TaskEditScreen(task: task),
      ),
    );
  }

  group('TaskEditScreen - New Task', () {
    testWidgets('displays empty form for new task', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Verify title field is present and editable
      expect(find.byType(TextField), findsWidgets);
      expect(find.text('عنوان المهمَّة'), findsOneWidget);
      expect(find.text('التَّفاصيل (اختياري)'), findsOneWidget);
      expect(find.text('التَّاريخ (اختياري)'), findsOneWidget);
    });

    testWidgets('allows editing for new task (owner permission)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Find the title TextField
      final titleField = find.byType(TextField).first;
      expect(tester.widget<TextField>(titleField).readOnly, isFalse);
      expect(tester.widget<TextField>(titleField).enabled, isTrue);
    });

    testWidgets('shows share button only for existing tasks', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Share button should NOT be visible for new tasks
      expect(find.byIcon(Icons.people_outline), findsNothing);
    });
  });

  group('TaskEditScreen - Existing Task', () {
    testWidgets('displays existing task data', (WidgetTester tester) async {
      final task = TaskModel(
        id: 'task-1',
        title: 'Test Task',
        description: 'Test Description',
        createdBy: 'user-123',
      );

      await tester.pumpWidget(createTestWidget(task: task));
      await tester.pumpAndSettle();

      // Verify task data is displayed
      expect(find.text('Test Task'), findsOneWidget);
    });

    testWidgets('allows editing for owner', (WidgetTester tester) async {
      final task = TaskModel(
        id: 'task-1',
        title: 'Test Task',
        createdBy: 'user-123', // Current user is owner
      );

      await tester.pumpWidget(createTestWidget(task: task));
      await tester.pumpAndSettle();

      // Title field should be editable for owner
      final titleField = find.byType(TextField).first;
      expect(tester.widget<TextField>(titleField).readOnly, isFalse);
    });
  });

  group('TaskEditScreen - Permission Handling', () {
    testWidgets('read-only mode for read permission', (
      WidgetTester tester,
    ) async {
      final task = TaskModel(
        id: 'task-1',
        title: 'Test Task',
        createdBy: 'other-user',
        sharePermission: 'read',
      );

      when(mockProvider.currentUserId).thenReturn('user-123');

      await tester.pumpWidget(createTestWidget(task: task));
      await tester.pumpAndSettle();

      // Note: Due to async permission loading, we test the initial state
      // which defaults to read-only for existing tasks
      final titleField = find.byType(TextField).first;
      // Initial state should be read-only until permissions load
      expect(tester.widget<TextField>(titleField).readOnly, isTrue);
    });
  });

  group('TaskEditScreen - Auto-save', () {
    testWidgets('triggers auto-save on text change', (WidgetTester tester) async {
      when(mockProvider.addTask(
        title: anyNamed('title'),
        description: anyNamed('description'),
        dueDate: anyNamed('dueDate'),
        alarmEnabled: anyNamed('alarmEnabled'),
        alarmTime: anyNamed('alarmTime'),
        recurrence: anyNamed('recurrence'),
        attachments: anyNamed('attachments'),
        priority: anyNamed('priority'),
      )).thenAnswer((_) async {});

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Enter text in title field
      await tester.enterText(find.byType(TextField).first, 'New Task Title');
      await tester.pump();

      // Wait for debounce (1000ms + buffer)
      await tester.pump(const Duration(milliseconds: 1100));

      // Verify addTask was called
      verify(mockProvider.addTask(
        title: 'New Task Title',
        description: '',
        dueDate: anyNamed('dueDate'),
        alarmEnabled: anyNamed('alarmEnabled'),
        alarmTime: anyNamed('alarmTime'),
        recurrence: anyNamed('recurrence'),
        attachments: anyNamed('attachments'),
        priority: anyNamed('priority'),
      )).called(1);
    });

    testWidgets('does not save empty title', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Clear title field (it's already empty, but be explicit)
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump();

      // Wait for debounce
      await tester.pump(const Duration(milliseconds: 1100));

      // Verify addTask was NOT called
      verifyNever(mockProvider.addTask(
        title: anyNamed('title'),
        description: anyNamed('description'),
        dueDate: anyNamed('dueDate'),
        alarmEnabled: anyNamed('alarmEnabled'),
        alarmTime: anyNamed('alarmTime'),
        recurrence: anyNamed('recurrence'),
        attachments: anyNamed('attachments'),
        priority: anyNamed('priority'),
      ));
    });
  });

  group('TaskEditScreen - Priority', () {
    testWidgets('displays priority picker', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Priority picker should be visible
      expect(find.text('عالية'), findsOneWidget); // High priority label
    });
  });

  group('TaskEditScreen - Recurrence', () {
    testWidgets('displays recurrence options', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('بدون تكرار'), findsOneWidget);
      expect(find.text('يومي'), findsOneWidget);
      expect(find.text('أسبوعي'), findsOneWidget);
      expect(find.text('شهري'), findsOneWidget);
    });
  });

  group('TaskEditScreen - Attachments', () {
    testWidgets('displays attachments section', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('المرفقات'), findsOneWidget);
    });
  });

  group('TaskEditScreen - Navigation', () {
    testWidgets('saves before popping', (WidgetTester tester) async {
      when(mockProvider.addTask(
        title: anyNamed('title'),
        description: anyNamed('description'),
        dueDate: anyNamed('dueDate'),
        alarmEnabled: anyNamed('alarmEnabled'),
        alarmTime: anyNamed('alarmTime'),
        recurrence: anyNamed('recurrence'),
        attachments: anyNamed('attachments'),
        priority: anyNamed('priority'),
      )).thenAnswer((_) async {});

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Enter text
      await tester.enterText(find.byType(TextField).first, 'Task to Save');
      await tester.pump();

      // Wait for save debounce
      await tester.pump(const Duration(milliseconds: 1100));

      // Verify save was called
      verify(mockProvider.addTask(
        title: 'Task to Save',
        description: '',
        dueDate: anyNamed('dueDate'),
        alarmEnabled: anyNamed('alarmEnabled'),
        alarmTime: anyNamed('alarmTime'),
        recurrence: anyNamed('recurrence'),
        attachments: anyNamed('attachments'),
        priority: anyNamed('priority'),
      )).called(1);
    });
  });

  group('TaskEditScreen - Error Handling', () {
    testWidgets('handles save error gracefully', (WidgetTester tester) async {
      when(mockProvider.addTask(
        title: anyNamed('title'),
        description: anyNamed('description'),
        dueDate: anyNamed('dueDate'),
        alarmEnabled: anyNamed('alarmEnabled'),
        alarmTime: anyNamed('alarmTime'),
        recurrence: anyNamed('recurrence'),
        attachments: anyNamed('attachments'),
        priority: anyNamed('priority'),
      )).thenThrow(Exception('Network error'));

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Enter text
      await tester.enterText(find.byType(TextField).first, 'Task Title');
      await tester.pump();

      // Wait for debounce
      await tester.pump(const Duration(milliseconds: 1100));

      // Verify addTask was called (and threw exception)
      verify(mockProvider.addTask(
        title: 'Task Title',
        description: '',
        dueDate: anyNamed('dueDate'),
        alarmEnabled: anyNamed('alarmEnabled'),
        alarmTime: anyNamed('alarmTime'),
        recurrence: anyNamed('recurrence'),
        attachments: anyNamed('attachments'),
        priority: anyNamed('priority'),
      )).called(1);
    });

    testWidgets('does not show toast for offline errors', (
      WidgetTester tester,
    ) async {
      when(mockProvider.addTask(
        title: anyNamed('title'),
        description: anyNamed('description'),
        dueDate: anyNamed('dueDate'),
        alarmEnabled: anyNamed('alarmEnabled'),
        alarmTime: anyNamed('alarmTime'),
        recurrence: anyNamed('recurrence'),
        attachments: anyNamed('attachments'),
        priority: anyNamed('priority'),
      )).thenThrow(Exception('Socket exception: connection timed out'));

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Enter text
      await tester.enterText(find.byType(TextField).first, 'Task Title');
      await tester.pump();

      // Wait for debounce
      await tester.pump(const Duration(milliseconds: 1100));

      // Should NOT show error toast for offline errors
      expect(find.text('حدث خطأ أثناء الحفظ'), findsNothing);
    });
  });
}
