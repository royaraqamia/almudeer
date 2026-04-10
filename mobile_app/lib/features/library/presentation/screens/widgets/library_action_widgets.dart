import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/constants/dimensions.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';

/// âœ… P2: Selection Toolbar Component
/// - Shows when items are selected
/// - Provides batch actions (delete, share, select all)
/// - P0: Proper Semantics and touch targets
class SelectionToolbar extends StatelessWidget {
  final int selectedCount;
  final int totalCount;
  final VoidCallback onDelete;
  final VoidCallback onShare;
  final VoidCallback onSelectAll;
  final VoidCallback onClearSelection;
  final bool hasSelectAll;

  const SelectionToolbar({
    super.key,
    required this.selectedCount,
    required this.totalCount,
    required this.onDelete,
    required this.onShare,
    required this.onSelectAll,
    required this.onClearSelection,
    this.hasSelectAll = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAllSelected = selectedCount == totalCount;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingMedium,
            vertical: AppDimensions.spacing8,
          ),
          child: Row(
            children: [
              // Count and Clear
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$selectedCount ظ…ظ† $totalCount ظ…ط­ط¯ط¯ط©',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontFamily: 'IBM Plex Sans Arabic',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton(
                      onPressed: onClearSelection,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(44, 44),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'ط¥ظ„ط؛ط§ط، ط§ظ„طھط­ط¯ظٹط¯',
                        style: TextStyle(
                          fontFamily: 'IBM Plex Sans Arabic',
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Select All
              if (hasSelectAll) ...[
                Semantics(
                  label: isAllSelected ? 'ط¥ظ„ط؛ط§ط، طھط­ط¯ظٹط¯ ط§ظ„ظƒظ„' : 'طھط­ط¯ظٹط¯ ط§ظ„ظƒظ„',
                  button: true,
                  child: Material(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(
                      AppDimensions.radiusFull,
                    ),
                    child: InkWell(
                      onTap: () {
                        Haptics.lightTap();
                        onSelectAll();
                      },
                      borderRadius: BorderRadius.circular(
                        AppDimensions.radiusFull,
                      ),
                      focusColor: AppColors.primary.withValues(alpha: 0.2),
                      hoverColor: AppColors.primary.withValues(alpha: 0.15),
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimensions.spacing12,
                          vertical: AppDimensions.spacing8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isAllSelected
                                  ? SolarLinearIcons.closeSquare
                                  : SolarLinearIcons.checkSquare,
                              color: AppColors.primary,
                              size: AppDimensions.iconMedium,
                            ),
                            const SizedBox(width: AppDimensions.spacing4),
                            Text(
                              isAllSelected ? 'ط¥ظ„ط؛ط§ط، ط§ظ„ظƒظ„' : 'ط§ظ„ظƒظ„',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'IBM Plex Sans Arabic',
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppDimensions.spacing8),
              ],

              // Share
              Semantics(
                label: 'ظ…ط´ط§ط±ظƒط© ط§ظ„ظ…ط­ط¯ط¯',
                button: true,
                child: Material(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                  child: InkWell(
                    onTap: () {
                      Haptics.lightTap();
                      onShare();
                    },
                    borderRadius: BorderRadius.circular(
                      AppDimensions.radiusFull,
                    ),
                    focusColor: AppColors.accent.withValues(alpha: 0.2),
                    hoverColor: AppColors.accent.withValues(alpha: 0.15),
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      padding: const EdgeInsets.all(AppDimensions.spacing8),
                      child: const Icon(
                        SolarLinearIcons.share,
                        color: AppColors.accent,
                        size: AppDimensions.iconMedium,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppDimensions.spacing8),

              // Delete
              Semantics(
                label: 'ط­ط°ظپ ط§ظ„ظ…ط­ط¯ط¯',
                button: true,
                child: Material(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                  child: InkWell(
                    onTap: () {
                      Haptics.lightTap();
                      onDelete();
                    },
                    borderRadius: BorderRadius.circular(
                      AppDimensions.radiusFull,
                    ),
                    focusColor: AppColors.error.withValues(alpha: 0.2),
                    hoverColor: AppColors.error.withValues(alpha: 0.15),
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      padding: const EdgeInsets.all(AppDimensions.spacing8),
                      child: const Icon(
                        SolarLinearIcons.trashBinMinimalistic,
                        color: AppColors.error,
                        size: AppDimensions.iconMedium,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// âœ… P1: Upload Progress Dialog
/// - Shows upload progress with cancel option
/// - P0: Proper Semantics
/// - P2: Design token compliance
class UploadProgressDialog extends StatelessWidget {
  final double progress;
  final String fileName;
  final bool isCancelable;
  final VoidCallback? onCancel;

  const UploadProgressDialog({
    super.key,
    required this.progress,
    required this.fileName,
    this.isCancelable = true,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusXXLarge),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.paddingLarge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppDimensions.spacing12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(
                      AppDimensions.radiusLarge,
                    ),
                  ),
                  child: Icon(
                    progress >= 1.0
                        ? SolarBoldIcons.checkCircle
                        : SolarLinearIcons.upload,
                    color: progress >= 1.0
                        ? AppColors.success
                        : AppColors.primary,
                    size: AppDimensions.iconXLarge,
                  ),
                ),
                const SizedBox(width: AppDimensions.spacing12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        progress >= 1.0 ? 'طھظ… ط§ظ„ط±ظپط¹' : 'ط¬ط§ط±ظٹ ط§ظ„ط±ظپط¹...',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontFamily: 'IBM Plex Sans Arabic',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: AppDimensions.spacing4),
                      Text(
                        fileName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'IBM Plex Sans Arabic',
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (isCancelable && progress < 1.0)
                  Semantics(
                    label: 'ط¥ظ„ط؛ط§ط، ط§ظ„ط±ظپط¹',
                    button: true,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onCancel,
                        borderRadius: BorderRadius.circular(
                          AppDimensions.radiusFull,
                        ),
                        focusColor: AppColors.error.withValues(alpha: 0.12),
                        hoverColor: AppColors.error.withValues(alpha: 0.04),
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 44,
                            minHeight: 44,
                          ),
                          padding: const EdgeInsets.all(AppDimensions.spacing8),
                          child: Icon(
                            SolarLinearIcons.closeCircle,
                            color: theme.colorScheme.onSurfaceVariant,
                            size: AppDimensions.iconMedium,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppDimensions.spacing16),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(
                  progress >= 1.0 ? AppColors.success : AppColors.primary,
                ),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: AppDimensions.spacing8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(progress * 100).toInt()}%',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'IBM Plex Sans Arabic',
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (progress >= 1.0)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimensions.paddingMedium,
                        vertical: AppDimensions.spacing8,
                      ),
                      minimumSize: const Size(44, 44),
                    ),
                    child: const Text(
                      'طھظ…',
                      style: TextStyle(
                        fontFamily: 'IBM Plex Sans Arabic',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// âœ… P2: Error State Widget with Retry
/// - P0: Proper Semantics
/// - P2: Design token compliance
class LibraryErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const LibraryErrorState({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            SolarLinearIcons.forbiddenCircle,
            size: 64,
            color: AppColors.error.withValues(alpha: 0.5),
          ),
          const SizedBox(height: AppDimensions.paddingLarge),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.paddingLarge,
            ),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontFamily: 'IBM Plex Sans Arabic',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppDimensions.paddingLarge),
            Semantics(
              button: true,
              label: 'ط¥ط¹ط§ط¯ط© ط§ظ„ظ…ط­ط§ظˆظ„ط©',
              child: Material(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                child: InkWell(
                  onTap: onRetry,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                  focusColor: AppColors.primaryDark,
                  hoverColor: AppColors.primaryLight,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimensions.paddingLarge,
                      vertical: AppDimensions.spacing12,
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          SolarLinearIcons.refresh,
                          color: Colors.white,
                          size: AppDimensions.iconMedium,
                        ),
                        SizedBox(width: AppDimensions.spacing8),
                        Text(
                          'ط¥ط¹ط§ط¯ط© ط§ظ„ظ…ط­ط§ظˆظ„ط©',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'IBM Plex Sans Arabic',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// âœ… P2: Skeleton Loader for Library
/// - P2: Design token compliance
class LibrarySkeletonLoader extends StatelessWidget {
  final bool isGridView;

  const LibrarySkeletonLoader({super.key, this.isGridView = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isGridView) {
      return GridView.builder(
        padding: const EdgeInsets.all(AppDimensions.paddingMedium),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: AppDimensions.spacing10,
          mainAxisSpacing: AppDimensions.spacing10,
          childAspectRatio: 0.85,
        ),
        itemCount: 6,
        itemBuilder: (context, index) {
          return Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(AppDimensions.spacing12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outline.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(
                        AppDimensions.radiusLarge,
                      ),
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.spacing12,
                    vertical: AppDimensions.spacing8,
                  ),
                  height: 16,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(
                      AppDimensions.radiusSmall,
                    ),
                  ),
                ),
                const SizedBox(height: AppDimensions.spacing12),
              ],
            ),
          );
        },
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppDimensions.paddingMedium),
      itemCount: 6,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: AppDimensions.spacing12),
          height: 72,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
          ),
          child: Row(
            children: [
              Container(
                margin: const EdgeInsets.all(AppDimensions.spacing12),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(
                    AppDimensions.radiusMedium,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppDimensions.spacing12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 16,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.outline.withValues(
                            alpha: 0.1,
                          ),
                          borderRadius: BorderRadius.circular(
                            AppDimensions.radiusSmall,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppDimensions.spacing8),
                      Container(
                        height: 12,
                        width: 100,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.outline.withValues(
                            alpha: 0.1,
                          ),
                          borderRadius: BorderRadius.circular(
                            AppDimensions.radiusSmall,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
