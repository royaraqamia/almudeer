import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../../core/constants/colors.dart';
import '../../../../../core/constants/dimensions.dart';
import '../../../../../core/utils/haptics.dart';
import '../../../../../data/local/athkar_data.dart';
import '../../../../providers/athkar_provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:figma_squircle/figma_squircle.dart';
import '../../../../../presentation/widgets/custom_dialog.dart';
import '../../../../../presentation/widgets/animated_toast.dart';

class AthkarScreen extends StatefulWidget {
  const AthkarScreen({super.key});

  @override
  State<AthkarScreen> createState() => _AthkarScreenState();
}

class _AthkarScreenState extends State<AthkarScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    // Check for daily reset when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AthkarProvider>().checkAndResetIfNeeded();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Check for daily reset when app resumes
    if (state == AppLifecycleState.resumed) {
      context.read<AthkarProvider>().checkAndResetIfNeeded();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  void _showResetConfirmation(BuildContext context) {
    CustomDialog.show(
      context,
      title: 'إعادة ضبط الأذكار',
      message:
          'هل أنت متأكد من رغبتك في إعادة ضبط جميع عدادات الأذكار لهذا اليوم؟',
      type: DialogType.warning,
      confirmText: 'إعادة ضبط',
      cancelText: 'إلغاء',
      onConfirm: () {
        context.read<AthkarProvider>().resetAll();
        AnimatedToast.success(context, 'تمت إعادة ضبط العدادات بنجاح');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'أذكار الصباح والمساء',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            fontFamily: 'IBM Plex Sans Arabic',
          ),
        ),
        centerTitle: true,
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            SolarLinearIcons.altArrowRight,
            color: theme.iconTheme.color,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(SolarLinearIcons.restart, size: 22),
            onPressed: () => _showResetConfirmation(context),
            tooltip: 'إعادة ضبط العدادات',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppColors.primary,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.transparent,
          labelStyle: const TextStyle(
            fontFamily: 'IBM Plex Sans Arabic',
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          tabs: const [
            Tab(text: 'أذكار الصباح'),
            Tab(text: 'أذكار المساء'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _AthkarList(athkar: AthkarData.morningAthkar),
          _AthkarList(athkar: AthkarData.eveningAthkar),
        ],
      ),
    );
  }
}

class _AthkarList extends StatefulWidget {
  final List<AthkarItem> athkar;

  const _AthkarList({required this.athkar});

  @override
  State<_AthkarList> createState() => _AthkarListState();
}

class _AthkarListState extends State<_AthkarList> {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AthkarProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Calculate total progress
    int totalTarget = 0;
    int totalCurrent = 0;
    int cappedItemsCount = 0;

    for (var item in widget.athkar) {
      totalTarget += item.count;
      final currentCount = provider.getCount(item.id);
      if (currentCount > item.count) {
        cappedItemsCount++;
        debugPrint(
          'AthkarScreen: Item ${item.id} has count $currentCount exceeding target ${item.count} (possible server sync issue)',
        );
      }
      totalCurrent += (currentCount > item.count) ? item.count : currentCount;
    }

    if (cappedItemsCount > 0) {
      debugPrint(
        'AthkarScreen: $cappedItemsCount item(s) had counts exceeding targets. Data may be from outdated server sync.',
      );
    }

    final double totalProgress = totalTarget > 0
        ? totalCurrent / totalTarget
        : 0.0;
    final int completedCount = widget.athkar
        .where((item) => provider.isCompleted(item))
        .length;

    return Column(
      children: [
        // Progress Summary
        Container(
          padding: const EdgeInsets.all(AppDimensions.paddingMedium),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: AppDimensions.spacing12,
                offset: const Offset(0, AppDimensions.spacing8),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'إجمالي التقدم',
                          style: TextStyle(
                            fontFamily: 'IBM Plex Sans Arabic',
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        Text(
                          '${(totalProgress * 100).toInt()}%',
                          style: const TextStyle(
                            fontFamily: 'IBM Plex Sans Arabic',
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.spacing8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(
                        AppDimensions.radiusMedium,
                      ),
                      child: LinearProgressIndicator(
                        value: totalProgress,
                        backgroundColor: AppColors.primary.withValues(
                          alpha: 0.1,
                        ),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.primary,
                        ),
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacing4),
                    Text(
                      'تم إكمال $completedCount من ${widget.athkar.length} ذكراً',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'IBM Plex Sans Arabic',
                        color: Colors.grey.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.paddingMedium,
              vertical: AppDimensions.spacing10,
            ),
            physics: const BouncingScrollPhysics(),
            itemCount: widget.athkar.length,
            itemBuilder: (context, index) {
              return _AthkarCard(item: widget.athkar[index]);
            },
          ),
        ),
      ],
    );
  }
}

class _AthkarCard extends StatelessWidget {
  final AthkarItem item;

  const _AthkarCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final provider = context.watch<AthkarProvider>();
    final count = provider.getCount(item.id);
    final isCompleted = count >= item.count;
    final remainingCount = item.count - count;
    final progress = count / item.count;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: AppDimensions.spacing20),
      decoration: ShapeDecoration(
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusXXLarge,
            cornerSmoothing: 0.6,
          ),
          side: isCompleted
              ? BorderSide(
                  color: Colors.green.withValues(alpha: 0.3),
                  width: 1.5,
                )
              : BorderSide.none,
        ),
        color: isCompleted
            ? (isDark
                  ? Colors.green.withValues(alpha: 0.08)
                  : Colors.green.withValues(alpha: 0.04))
            : theme.cardColor,
        shadows: [
          if (!isCompleted && !isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: AppDimensions.spacing24,
              offset: const Offset(0, AppDimensions.spacing12),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimensions.radiusXXLarge),
        child: Stack(
          children: [
            if (isCompleted)
              Positioned(
                top: -20,
                left: -20,
                child: Icon(
                  SolarBoldIcons.checkCircle,
                  size: 100,
                  color: Colors.green.withValues(alpha: 0.05),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(AppDimensions.paddingLarge),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    item.text,
                    textAlign: TextAlign.justify,
                    textDirection: TextDirection.rtl,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 19,
                      height: 1.8,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'IBM Plex Sans Arabic',
                      color: isCompleted
                          ? theme.textTheme.bodyLarge?.color?.withValues(
                              alpha: 0.6,
                            )
                          : theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                  if (item.reward != null) ...[
                    const SizedBox(height: AppDimensions.spacing16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimensions.spacing12,
                        vertical: AppDimensions.spacing10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(
                          AppDimensions.radiusLarge,
                        ),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            SolarLinearIcons.stars,
                            size: 18,
                            color: AppColors.primary.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: AppDimensions.spacing8),
                          Expanded(
                            child: Text(
                              item.reward!,
                              textDirection: TextDirection.rtl,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.primary.withValues(alpha: 0.8),
                                fontFamily: 'IBM Plex Sans Arabic',
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (item.source != null) ...[
                    const SizedBox(height: AppDimensions.spacing12),
                    Text(
                      item.source!,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.withValues(alpha: 0.8),
                        fontFamily: 'IBM Plex Sans Arabic',
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppDimensions.spacing24),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        if (!isCompleted) {
                          Haptics.lightTap();
                          provider.increment(item);
                          if (provider.isCompleted(item)) {
                            Haptics.mediumTap();
                          }
                        }
                      },
                      onLongPress: () {
                        if (count > 0) {
                          Haptics.mediumTap();
                          provider.decrement(item);
                        }
                      },
                      borderRadius: BorderRadius.circular(
                        AppDimensions.radiusLarge,
                      ),
                      child: Container(
                        height: 56,
                        decoration: BoxDecoration(
                          color: isCompleted
                              ? Colors.green
                              : (isDark
                                    ? theme.scaffoldBackgroundColor.withValues(
                                        alpha: 0.5,
                                      )
                                    : const Color(0xFFF8FAFC)),
                          borderRadius: BorderRadius.circular(
                            AppDimensions.radiusLarge,
                          ),
                          border: isCompleted
                              ? null
                              : Border.all(
                                  color: theme.dividerColor.withValues(
                                    alpha: 0.1,
                                  ),
                                ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (!isCompleted && progress > 0)
                              Positioned.fill(
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerRight,
                                  widthFactor: progress,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        AppDimensions.radiusLarge,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (isCompleted) ...[
                                  const Icon(
                                    SolarBoldIcons.checkCircle,
                                    color: Colors.white,
                                    size: AppDimensions.iconXLarge,
                                  ),
                                  const SizedBox(width: AppDimensions.spacing8),
                                  const Text(
                                    'تمت القراءة',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontFamily: 'IBM Plex Sans Arabic',
                                    ),
                                  ),
                                ] else ...[
                                  Text(
                                    '$remainingCount',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                      fontFamily: 'IBM Plex Sans Arabic',
                                    ),
                                  ),
                                  const SizedBox(width: AppDimensions.spacing8),
                                  Text(
                                    'مرات متبقية',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade600,
                                      fontFamily: 'IBM Plex Sans Arabic',
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppDimensions.spacing12,
                                      vertical: AppDimensions.spacing4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(
                                        AppDimensions.radiusFull,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.05,
                                          ),
                                          blurRadius: AppDimensions.spacing4,
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      '${item.count} الكل',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey.shade700,
                                        fontFamily: 'IBM Plex Sans Arabic',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(
                                    width: AppDimensions.spacing16,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
