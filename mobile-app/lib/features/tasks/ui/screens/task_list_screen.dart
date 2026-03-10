import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/constants/dimensions.dart';

import '../../providers/task_provider.dart';
import '../widgets/task_list_item.dart';
import '../screens/task_edit_screen.dart';
import '../../models/task_model.dart';

import 'package:hijri/hijri_calendar.dart';
import '../../../../presentation/widgets/premium_fab.dart';
import '../../../../presentation/widgets/common_widgets.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../core/extensions/string_extension.dart';

class TaskListScreen extends StatefulWidget {
  static const routeName = '/tasks';

  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _hasHandledDeepLink = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TaskProvider>().loadTasks().then((_) {
        _checkIncomingDeepLink();
      });
    });

    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<TaskProvider>().loadMoreTasks();
    }
  }

  void _checkIncomingDeepLink() {
    if (!mounted || _hasHandledDeepLink) return;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['taskId'] != null) {
      final taskId = args['taskId'] as String;
      final provider = context.read<TaskProvider>();
      final task = provider.tasks.where((t) => t.id == taskId).firstOrNull;

      if (task != null) {
        _hasHandledDeepLink = true;

        // Open the details screen
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => TaskEditScreen(task: task)));
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _navigateToAddEditTask(BuildContext context, [TaskModel? task]) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => TaskEditScreen(task: task))).then((_) {
      // Refresh tasks when returning from edit screen to ensure latest data
      if (!context.mounted) return;
      debugPrint('[TaskListScreen] Refreshing tasks after returning from edit screen');
      context.read<TaskProvider>().loadTasks();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<TaskProvider>();

    return PopScope(
      canPop: !provider.isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && provider.isSelectionMode) {
          provider.clearSelection();
        }
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                slivers: [
                  _buildHeader(context),
                  if (provider.tasks.isNotEmpty)
                    const SliverToBoxAdapter(),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _FilterHeaderDelegate(
                      child: const _TaskFilterChips(),
                    ),
                  ),
                  _buildSliverTaskList(context),
                  if (provider.isLoadingMore)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: AppDimensions.spacing20,
                        ),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                  const SliverPadding(
                    padding: EdgeInsets.only(bottom: AppDimensions.spacing100),
                  ),
                ],
              ),
            ],
          ),
        ),
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(
            bottom: AppDimensions.bottomNavHeight + AppDimensions.spacing24,
          ),
          child: _buildFAB(context),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return SliverToBoxAdapter(child: _buildRegularHeader(context));
  }

  Widget _buildRegularHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    HijriCalendar.setLocal('ar');
    final hijriNow = HijriCalendar.now();
    final dateStr = hijriNow.toFormat('DD, dd MMMM yyyy').toEnglishNumbers;

    return Padding(
      key: const ValueKey('regular_header'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Text(
        dateStr,
        style: theme.textTheme.bodySmall?.copyWith(
          color: isDark
              ? AppColors.textSecondaryDark
              : AppColors.textSecondaryLight,
          fontSize: 14,
          fontFamily: 'IBM Plex Sans Arabic',
        ),
      ),
    );
  }

  Widget _buildFAB(BuildContext context) {
    return PremiumFAB(
      heroTag: 'task_fab',
      standalone: false,
      onPressed: () => _navigateToAddEditTask(context),
      gradientColors: [const Color(0xFF2563EB), const Color(0xFF0891B2)],
      icon: const Icon(
        SolarBoldIcons.clipboardAdd,
        color: Colors.white,
        size: 32,
      ),
    );
  }

  Widget _buildSliverTaskList(BuildContext context) {
    return Consumer<TaskProvider>(
      builder: (context, provider, _) {
        // Show cached data immediately - no skeleton loader
        if (provider.tasks.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: EmptyStateWidget(
                icon: SolarLinearIcons.notes,
              ),
            ),
          );
        }

        final tasks = provider.filteredTasks;

        if (tasks.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: EmptyStateWidget(
                icon: SolarLinearIcons.notes,
              ),
            ),
          );
        }

        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        final overdue = tasks
            .where(
              (t) =>
                  !t.isCompleted &&
                  t.dueDate != null &&
                  DateUtils.dateOnly(t.dueDate!).isBefore(today),
            )
            .toList();
        final todayTasksList = tasks
            .where(
              (t) =>
                  !t.isCompleted &&
                  (t.dueDate == null ||
                      DateUtils.dateOnly(t.dueDate!).isAtSameMomentAs(today)),
            )
            .toList();
        final laterTasks = tasks
            .where(
              (t) =>
                  !t.isCompleted &&
                  (t.dueDate != null &&
                      DateUtils.dateOnly(t.dueDate!).isAfter(today)),
            )
            .toList();
        final completedTasks = tasks.where((t) => t.isCompleted).toList();

        if (provider.filter != TaskFilter.all || provider.isSelectionMode) {
          return SliverMainAxisGroup(
            slivers: [
              if (overdue.isNotEmpty)
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final task = overdue[index];
                    return StaggeredAnimatedItem(
                      index: index,
                      child: TaskListItem(
                        task: task,
                        isSelectionMode: provider.isSelectionMode,
                        isSelected: provider.selectedIds.contains(task.id),
                        onSelectionChanged: (_) =>
                            provider.toggleSelection(task.id),
                        onComplete: () => showConfetti(context),
                      ),
                    );
                  }, childCount: overdue.length),
                ),
              if (todayTasksList.isNotEmpty)
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final task = todayTasksList[index];
                    return StaggeredAnimatedItem(
                      index: index + overdue.length,
                      child: TaskListItem(
                        task: task,
                        isSelectionMode: provider.isSelectionMode,
                        isSelected: provider.selectedIds.contains(task.id),
                        onSelectionChanged: (_) =>
                            provider.toggleSelection(task.id),
                        onComplete: () => showConfetti(context),
                      ),
                    );
                  }, childCount: todayTasksList.length),
                ),
              if (laterTasks.isNotEmpty)
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final task = laterTasks[index];
                    return StaggeredAnimatedItem(
                      index: index + overdue.length + todayTasksList.length,
                      child: TaskListItem(
                        task: task,
                        isSelectionMode: provider.isSelectionMode,
                        isSelected: provider.selectedIds.contains(task.id),
                        onSelectionChanged: (_) =>
                            provider.toggleSelection(task.id),
                        onComplete: () => showConfetti(context),
                      ),
                    );
                  }, childCount: laterTasks.length),
                ),
              if (completedTasks.isNotEmpty)
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final task = completedTasks[index];
                    return StaggeredAnimatedItem(
                      index:
                          index +
                          overdue.length +
                          todayTasksList.length +
                          laterTasks.length,
                      child: TaskListItem(
                        task: task,
                        isSelectionMode: provider.isSelectionMode,
                        isSelected: provider.selectedIds.contains(task.id),
                        onSelectionChanged: (_) =>
                            provider.toggleSelection(task.id),
                        onComplete: () => showConfetti(context),
                      ),
                    );
                  }, childCount: completedTasks.length),
                ),
            ],
          );
        }

        // Custom ordered list for 'All' filter
        return SliverReorderableList(
          itemCount: tasks.length,
          onReorder: provider.reorderTasks,
          itemBuilder: (context, index) {
            final task = tasks[index];
            return ReorderableDelayedDragStartListener(
              key: ValueKey(task.id),
              index: index,
              child: TaskListItem(
                task: task,
                isSelectionMode: provider.isSelectionMode,
                isSelected: provider.selectedIds.contains(task.id),
                onSelectionChanged: (_) => provider.toggleSelection(task.id),
                onComplete: () => showConfetti(context),
              ),
            );
          },
        );
      },
    );
  }
}

class _TaskFilterChips extends StatelessWidget {
  const _TaskFilterChips();

  @override
  Widget build(BuildContext context) {
    final filters = [
      {'label': 'اليوم', 'value': TaskFilter.today},
      {'label': 'القادمة', 'value': TaskFilter.upcoming},
      {'label': 'المكتملة', 'value': TaskFilter.completed},
    ];

    return Selector<TaskProvider, TaskFilter>(
      selector: (_, provider) => provider.filter,
      builder: (context, currentFilter, _) {
        return Container(
          height: 60,
          color: Theme.of(context).scaffoldBackgroundColor,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: filters.length,
            itemBuilder: (context, index) {
              final theme = Theme.of(context);
              final filter = filters[index];
              final value = filter['value'] as TaskFilter;
              final isSelected = currentFilter == value;
              return Padding(
                padding: const EdgeInsets.only(left: 8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  constraints: const BoxConstraints(
                    minHeight: AppDimensions.touchTargetMin,
                  ),
                  height: 44,
                  child: Material(
                    color: isSelected
                        ? (theme.brightness == Brightness.dark
                              ? AppColors.primary.withValues(alpha: 0.2)
                              : AppColors.primary.withValues(alpha: 0.1))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(
                      AppDimensions.radiusFull,
                    ),
                    child: InkWell(
                      onTap: () {
                        Haptics.selection();
                        context.read<TaskProvider>().setFilter(value);
                      },
                      onFocusChange: (hasFocus) {
                        if (hasFocus) {
                          Haptics.lightTap();
                        }
                      },
                      borderRadius: BorderRadius.circular(
                        AppDimensions.radiusFull,
                      ),
                      focusColor: AppColors.primary.withValues(alpha: 0.12),
                      hoverColor: AppColors.primary.withValues(alpha: 0.04),
                      highlightColor: AppColors.primary.withValues(alpha: 0.08),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.center,
                        child: Semantics(
                          label: 'تصفية: ${filter['label'] as String}',
                          selected: isSelected,
                          button: true,
                          child: Text(
                            filter['label'] as String,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isSelected
                                  ? (theme.brightness == Brightness.dark
                                        ? AppColors.primaryLight
                                        : AppColors.primary)
                                  : (theme.brightness == Brightness.dark
                                        ? AppColors.textSecondaryDark
                                        : AppColors.textSecondaryLight),
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              fontFamily: 'IBM Plex Sans Arabic',
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _FilterHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _FilterHeaderDelegate({required this.child});

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          if (overlapsContent &&
              Theme.of(context).brightness != Brightness.dark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: child,
    );
  }

  @override
  double get maxExtent => 60;

  @override
  double get minExtent => 60;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      true;
}
