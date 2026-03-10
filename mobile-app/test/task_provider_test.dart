import 'package:flutter_test/flutter_test.dart';

import 'package:almudeer_mobile_app/features/tasks/models/task_model.dart';
import 'package:almudeer_mobile_app/features/tasks/providers/task_provider.dart';
import 'package:almudeer_mobile_app/features/tasks/repositories/task_repository.dart';

// Simple Mock Class using Mockito (or just manual override if mockito not set up in runner)
// Since I can't run build_runner, I'll allow a manual FakeRepository
class FakeTaskRepository implements TaskRepository {
  final List<TaskModel> _db = [];

  @override
  Stream<void> get syncStream => const Stream.empty();

  @override
  Stream<Map<String, dynamic>> get typingStream => const Stream.empty();

  @override
  Future<List<TaskModel>> getTasks({
    bool triggerSync = true,
    int? limit,
    int? offset,
  }) async {
    return List.from(_db);
  }

  @override
  Future<List<TaskModel>> getSharedTasks({String? permission}) async {
    return [];  // Return empty for tests
  }

  @override
  Future<List<Map<String, dynamic>>> getCollaborators() async {
    return [];  // Return empty for tests
  }

  @override
  Future<void> insertTask(TaskModel task) async {
    _db.add(task);
  }

  @override
  Future<void> updateTask(TaskModel task) async {
    final index = _db.indexWhere((t) => t.id == task.id);
    if (index != -1) {
      _db[index] = task;
    }
  }

  @override
  Future<void> deleteTask(String id) async {
    _db.removeWhere((t) => t.id == id);
  }

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late TaskProvider provider;
  late FakeTaskRepository repository;

  setUp(() {
    // Initialize Flutter binding for tests
    TestWidgetsFlutterBinding.ensureInitialized();
    repository = FakeTaskRepository();
    provider = TaskProvider(repository: repository);
  });

  test('Filtering tasks by status', () async {
    final task1 = TaskModel(id: '1', title: 'Active Task', isCompleted: false);
    final task2 = TaskModel(id: '2', title: 'Done Task', isCompleted: true);

    await repository.insertTask(task1);
    await repository.insertTask(task2);
    await provider.loadTasks();

    // Default Filter: All (Active)
    expect(provider.filteredTasks.length, 1);

    // Filter: Completed
    provider.setFilter(TaskFilter.completed);
    expect(provider.filteredTasks.length, 1);
    expect(provider.filteredTasks.first.id, '2');
  });

  test('Filtering tasks by search query', () async {
    final t1 = TaskModel(id: '1', title: 'Buy Milk');
    final t2 = TaskModel(id: '2', title: 'Walk Dog');

    await repository.insertTask(t1);
    await repository.insertTask(t2);
    await provider.loadTasks();

    provider.setSearchQuery('Milk');
    expect(provider.filteredTasks.length, 1);
    expect(provider.filteredTasks.first.title, 'Buy Milk');
  });
}
