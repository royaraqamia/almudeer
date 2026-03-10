import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/constants/dimensions.dart';
import '../../../../core/constants/shadows.dart';
import '../../../../core/constants/animations.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../core/extensions/string_extension.dart';
import '../../../../core/localization/library_localizations.dart';
import '../../../../data/models/library_item.dart';
import '../../../providers/library_provider.dart';
import 'library_item_card_base.dart';

/// ✅ P0: Accessible Library Item Card
/// - P0: Proper Semantics labels
/// - P0: 44px minimum touch targets
/// - P0: Focus/hover indicators
/// - P2: Design token compliance
class LibraryItemCard extends StatefulWidget {
  final LibraryItem item;
  final LibraryProvider provider;
  final VoidCallback onView;

  const LibraryItemCard({
    super.key,
    required this.item,
    required this.provider,
    required this.onView,
  });

  @override
  State<LibraryItemCard> createState() => _LibraryItemCardState();
}

class _LibraryItemCardState extends LibraryItemCardStateBase<LibraryItemCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  LibraryItem get item => widget.item;
  
  @override
  LibraryProvider get provider => widget.provider;
  
  @override
  VoidCallback get onView => widget.onView;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppAnimations.fast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _controller, curve: AppAnimations.interactive),
    );
    checkCache();
  }

  @override
  void didUpdateWidget(covariant LibraryItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.filePath != widget.item.filePath) {
      checkCache();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.provider.selectedIds.contains(widget.item.id);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return RepaintBoundary(
      child: Semantics(
        label: '${widget.item.type} ${widget.item.title}',
        button: true,
        selected: isSelected,
        child: GestureDetector(
          onTapDown: (_) => _controller.forward(),
          onTapUp: (_) async {
            _controller.reverse();
            await handleTap();
          },
          onTapCancel: () => _controller.reverse(),
          onLongPress: () {
            Haptics.mediumTap();
            widget.provider.toggleSelection(widget.item.id);
          },
          child: AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
                  child: Container(
                    decoration: ShapeDecoration(
                      color: isDark ? AppColors.cardDark : theme.cardColor,
                      shape: SmoothRectangleBorder(
                        borderRadius: SmoothBorderRadius(
                          cornerRadius: AppDimensions.radiusCard,
                          cornerSmoothing: 1.0,
                        ),
                        side: isSelected
                            ? const BorderSide(color: AppColors.primary, width: 2)
                            : BorderSide.none,
                      ),
                      shadows: [
                        if (theme.brightness != Brightness.dark) AppShadows.premiumShadow,
                      ],
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                      Column(
                        crossAxisAlignment: widget.item.type == 'note'
                            ? CrossAxisAlignment.stretch
                            : CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppDimensions.spacing12,
                              AppDimensions.spacing12,
                              AppDimensions.spacing12,
                              AppDimensions.spacing4,
                            ),
                            child: Text(
                              widget.item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textDirection: widget.item.title.direction,
                              textAlign: widget.item.type == 'note'
                                  ? (widget.item.title.isArabic ? TextAlign.right : TextAlign.left)
                                  : TextAlign.right,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                fontFamily: 'IBM Plex Sans Arabic',
                              ),
                            ),
                          ),
                          Expanded(
                            // Disable Hero animation to prevent flash when switching between grid/list layouts
                            child: _buildItemPreview(widget.item),
                          ),
                        ],
                      ),
                      if (widget.provider.isSelectionMode)
                        Positioned(
                          bottom: -4,
                          left: -4,
                          child: Semantics(
                            label: isSelected
                                ? LibraryLocalizations.of(context).selected
                                : LibraryLocalizations.of(context).notSelected,
                            child: InkWell(
                              onTap: () {
                                Haptics.lightTap();
                                widget.provider.toggleSelection(widget.item.id);
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: theme.scaffoldBackgroundColor,
                                  shape: BoxShape.circle,
                                  border: isSelected
                                      ? null
                                      : Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                                ),
                                child: isSelected
                                    ? const Icon(SolarBoldIcons.checkCircle, color: AppColors.success, size: 32)
                                    : Icon(SolarLinearIcons.stop, size: 20, color: isDark ? AppColors.textSecondaryDark : Colors.grey[400]),
                              ),
                            ),
                          ),
                        ),
                      // Show shared badge for items shared with the user
                      if (widget.item.isShared && widget.item.sharePermission != null)
                        Positioned(
                          top: AppDimensions.spacing8,
                          right: AppDimensions.spacing8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppDimensions.spacing8,
                              vertical: AppDimensions.spacing4,
                            ),
                            decoration: BoxDecoration(
                              color: getPermissionColor(widget.item.sharePermission!).withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(AppDimensions.radiusSmall),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  getPermissionIcon(widget.item.sharePermission!),
                                  size: AppDimensions.iconSmall,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: AppDimensions.spacing4),
                                Text(
                                  getPermissionLabel(widget.item.sharePermission!),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildItemPreview(LibraryItem item) {
    return buildItemPreview(item);
  }
}

/// ✅ P0: Accessible Library Item List Card (for files view)
/// - P0: Proper Semantics labels
/// - P0: 44px minimum touch targets
/// - P0: Focus/hover indicators
/// - P2: Design token compliance
class LibraryItemListCard extends StatefulWidget {
  final LibraryItem item;
  final LibraryProvider provider;
  final VoidCallback onView;

  const LibraryItemListCard({
    super.key,
    required this.item,
    required this.provider,
    required this.onView,
  });

  @override
  State<LibraryItemListCard> createState() => _LibraryItemListCardState();
}

class _LibraryItemListCardState extends LibraryItemCardStateBase<LibraryItemListCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  LibraryItem get item => widget.item;
  
  @override
  LibraryProvider get provider => widget.provider;
  
  @override
  VoidCallback get onView => widget.onView;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppAnimations.fast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _controller, curve: AppAnimations.interactive),
    );
    checkCache();
  }

  @override
  void didUpdateWidget(covariant LibraryItemListCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.filePath != widget.item.filePath) {
      checkCache();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.provider.selectedIds.contains(widget.item.id);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return RepaintBoundary(
      child: Semantics(
        label: '${widget.item.type} ${widget.item.title}',
        button: true,
        selected: isSelected,
        child: GestureDetector(
          onTapDown: (_) => _controller.forward(),
          onTapUp: (_) async {
            _controller.reverse();
            await handleTap();
          },
          onTapCancel: () => _controller.reverse(),
          onLongPress: () {
            Haptics.mediumTap();
            widget.provider.toggleSelection(widget.item.id);
          },
          child: AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
                  child: Container(
                    height: 72,
                    decoration: ShapeDecoration(
                      color: isDark ? AppColors.cardDark : theme.cardColor,
                      shape: SmoothRectangleBorder(
                        borderRadius: SmoothBorderRadius(
                          cornerRadius: AppDimensions.radiusCard,
                          cornerSmoothing: 1.0,
                        ),
                        side: isSelected
                            ? const BorderSide(color: AppColors.primary, width: 2)
                            : BorderSide.none,
                      ),
                      shadows: [
                        if (theme.brightness != Brightness.dark) AppShadows.premiumShadow,
                      ],
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 72,
                              height: 72,
                              // Disable Hero animation to prevent flash when switching between grid/list layouts
                              child: _buildItemPreview(widget.item),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: widget.item.type == 'note'
                                    ? CrossAxisAlignment.stretch
                                    : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textDirection: widget.item.title.direction,
                                    textAlign: widget.item.type == 'note'
                                        ? (widget.item.title.isArabic ? TextAlign.right : TextAlign.left)
                                        : TextAlign.right,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      fontFamily: 'IBM Plex Sans Arabic',
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.item.isUploading
                                        ? LibraryLocalizations.of(context).uploading
                                        : '${widget.item.formattedSize}${widget.item.formattedSize.isNotEmpty ? ' • ' : ''}${widget.item.formattedDate}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.brightness == Brightness.dark
                                          ? AppColors.textSecondaryDark
                                          : AppColors.textSecondaryLight,
                                      fontSize: 11,
                                      fontFamily: 'IBM Plex Sans Arabic',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                        ),
                      ),
                      if (widget.provider.isSelectionMode)
                        Positioned(
                          bottom: -4,
                          left: -4,
                          child: Semantics(
                            label: isSelected
                                ? LibraryLocalizations.of(context).selected
                                : LibraryLocalizations.of(context).notSelected,
                            child: InkWell(
                              onTap: () {
                                Haptics.lightTap();
                                widget.provider.toggleSelection(widget.item.id);
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: theme.scaffoldBackgroundColor,
                                  shape: BoxShape.circle,
                                  border: isSelected
                                      ? null
                                      : Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                                ),
                                child: isSelected
                                    ? const Icon(SolarBoldIcons.checkCircle, color: AppColors.success, size: 32)
                                    : Icon(SolarLinearIcons.stop, size: 20, color: isDark ? AppColors.textSecondaryDark : Colors.grey[400]),
                              ),
                            ),
                          ),
                        ),
                      // Show shared badge for items shared with the user
                      if (widget.item.isShared && widget.item.sharePermission != null)
                        Positioned(
                          top: AppDimensions.spacing8,
                          right: AppDimensions.spacing8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppDimensions.spacing8,
                              vertical: AppDimensions.spacing4,
                            ),
                            decoration: BoxDecoration(
                              color: getPermissionColor(widget.item.sharePermission!).withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(AppDimensions.radiusSmall),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  getPermissionIcon(widget.item.sharePermission!),
                                  size: AppDimensions.iconSmall,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: AppDimensions.spacing4),
                                Text(
                                  getPermissionLabel(widget.item.sharePermission!),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (widget.item.isUploading)
                        Positioned(
                          bottom: 8,
                          left: 8,
                          right: 8,
                          child: _buildUploadProgressIndicator(),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildUploadProgressIndicator() {
    final uploadedBytes = widget.item.uploadedBytes ?? 0;
    final totalBytes = widget.item.totalUploadBytes ?? 0;
    final progress = widget.item.uploadProgress ?? 0.0;
    final percentage = (progress * 100).toStringAsFixed(0);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? Colors.black87.withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Circular Progress
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 3,
                    color: AppColors.primary,
                    backgroundColor: isDark ? Colors.white24 : Colors.black12,
                  ),
                ),
                Text(
                  '$percentage%',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Bytes info
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                LibraryLocalizations.of(context).uploading,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${formatBytes(uploadedBytes)} / ${formatBytes(totalBytes)}',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemPreview(LibraryItem item) {
    return buildItemPreview(item);
  }
}
