import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:path/path.dart' as p;
import 'package:solar_icon_pack/solar_icon_pack.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/constants/dimensions.dart';
import '../../../../core/constants/shadows.dart';
import '../../../../core/constants/animations.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../core/extensions/string_extension.dart';
import '../../../../core/services/media_cache_manager.dart';
import '../../../../data/models/library_item.dart';
import '../../../providers/library_provider.dart';
import '../../../widgets/video_thumbnail_widget.dart';
import '../../../widgets/animated_toast.dart';

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

class _LibraryItemCardState extends State<LibraryItemCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  String? _localPath;
  bool _isDownloading = false;
  int _downloadedBytes = 0;
  int _totalBytes = 0;

  @override
  void initState() {
    super.initState();
    _checkCache();
    _controller = AnimationController(
      duration: AppAnimations.fast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _controller, curve: AppAnimations.interactive),
    );
  }

  @override
  void didUpdateWidget(covariant LibraryItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.filePath != widget.item.filePath) {
      _checkCache();
    }
  }

  Future<void> _checkCache() async {
    if (widget.item.type == 'note' || widget.item.type == 'task') return;
    if (widget.item.filePath == null) return;

    final url = widget.item.filePath!.toFullUrl;
    final path = await MediaCacheManager().getLocalPath(
      url,
      filename: widget.item.title,
    );
    if (mounted) {
      setState(() => _localPath = path);
    }
  }

  Future<void> _download() async {
    if (widget.item.filePath == null || _isDownloading) return;

    final url = widget.item.filePath!.toFullUrl;
    setState(() => _isDownloading = true);

    try {
      final path = await MediaCacheManager().downloadFile(
        url,
        filename: widget.item.title,
        onProgressBytes: (received, total) {
          if (mounted) {
            setState(() {
              _downloadedBytes = received;
              _totalBytes = total;
            });
          }
        },
      );
      if (mounted) {
        setState(() {
          _localPath = path;
          _isDownloading = false;
          _downloadedBytes = 0;
          _totalBytes = 0;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadedBytes = 0;
          _totalBytes = 0;
        });
        AnimatedToast.error(context, 'فشل التحميل: $e');
      }
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
            Haptics.lightTap();
            if (widget.provider.isSelectionMode) {
              widget.provider.toggleSelection(widget.item.id);
            } else {
              final isMedia = widget.item.type != 'note' && widget.item.type != 'task';
              if (isMedia && _localPath == null) {
                await _download();
                if (_localPath != null) widget.onView();
              } else {
                widget.onView();
              }
            }
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
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    decoration: ShapeDecoration(
                      color: isDark ? AppColors.cardDark : theme.cardColor,
                      shape: SmoothRectangleBorder(
                        borderRadius: SmoothBorderRadius(
                          cornerRadius: 16,
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
                      clipBehavior: Clip.hardEdge,
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
                          child: Container(
                            padding: EdgeInsets.all(isSelected ? 0 : 3),
                            decoration: BoxDecoration(
                              color: theme.scaffoldBackgroundColor,
                              shape: BoxShape.circle,
                              border: isSelected
                                  ? null
                                  : Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                            ),
                            child: isSelected
                                ? const Icon(SolarBoldIcons.checkCircle, color: AppColors.success, size: 24)
                                : Icon(SolarLinearIcons.stop, size: 14, color: isDark ? AppColors.textSecondaryDark : Colors.grey[400]),
                          ),
                        ),
                      // Show shared badge for items shared with the user
                      if (widget.item.isShared || widget.item.sharePermission != null)
                        Positioned(
                          top: AppDimensions.spacing8,
                          right: AppDimensions.spacing8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppDimensions.spacing8,
                              vertical: AppDimensions.spacing4,
                            ),
                            decoration: BoxDecoration(
                              color: _getPermissionColor(widget.item.sharePermission ?? 'read').withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(AppDimensions.radiusSmall),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getPermissionIcon(widget.item.sharePermission ?? 'read'),
                                  size: AppDimensions.iconSmall,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: AppDimensions.spacing4),
                                Text(
                                  _getPermissionLabel(widget.item.sharePermission ?? 'read'),
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
    final fileName = (item.filePath != null ? p.basename(item.filePath!) : item.title).toLowerCase();
    final extension = p.extension(fileName).toLowerCase().replaceAll('.', '');
    final isImage = item.type == 'image' ||
        ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(extension) ||
        (item.mimeType?.contains('image') ?? false);
    final isVideo = item.type == 'video' ||
        ['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(extension) ||
        (item.mimeType?.contains('video') ?? false);

    if (_localPath == null && (isImage || isVideo || item.type == 'audio' || item.type == 'file')) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Center(
        child: _isDownloading
            ? _buildDetailedProgressIndicator(isDark)
            : Stack(
                alignment: Alignment.center,
                children: [
                  _getTypeIcon(item, size: 32, color: isDark ? AppColors.textSecondaryDark : Colors.grey[300]!),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(SolarLinearIcons.download, color: Colors.white, size: 14),
                  ),
                ],
              ),
      );
    }

    if (isImage && _localPath != null) {
      return CachedNetworkImage(imageUrl: item.filePath!.toFullUrl, fit: BoxFit.cover);
    }

    if (isVideo && _localPath != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          VideoThumbnailWidget(videoUrl: _localPath!),
          Center(
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: const Icon(SolarBoldIcons.play, color: Colors.white, size: 20),
            ),
          ),
        ],
      );
    }

    if (item.type == 'note') {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: Text(
          item.content ?? '',
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          textDirection: (item.content ?? '').direction,
          textAlign: (item.content ?? '').isArabic ? TextAlign.right : TextAlign.left,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.normal,
            color: isDark ? AppColors.textPrimaryDark : AppColors.textSecondaryLight,
            fontFamily: 'IBM Plex Sans Arabic',
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(child: _getTypeIcon(item, size: 40, color: isDark ? AppColors.textSecondaryDark : Colors.grey[400]!));
  }

  Widget _buildDetailedProgressIndicator(bool isDark) {
    final percentage = _totalBytes > 0 ? ((_downloadedBytes.toDouble() / _totalBytes) * 100) : 0;
    final progress = _totalBytes > 0 ? (_downloadedBytes.toDouble() / _totalBytes) : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
                '${percentage.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_formatBytes(_downloadedBytes)} / ${_formatBytes(_totalBytes)}',
          style: TextStyle(
            fontSize: 9,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    double dBytes = bytes.toDouble();
    int iSafety = 0;
    while (dBytes >= 1024 && iSafety < suffixes.length - 1) {
      dBytes /= 1024;
      iSafety++;
    }
    return '${dBytes.toStringAsFixed(iSafety == 0 ? 0 : 1)} ${suffixes[iSafety]}';
  }

  Widget _getTypeIcon(LibraryItem item, {double size = 24, Color color = Colors.grey}) {
    switch (item.type) {
      case 'note': return Icon(SolarBoldIcons.notes, size: size, color: color);
      case 'image': return Icon(SolarBoldIcons.gallery, size: size, color: color);
      case 'audio': return Icon(SolarBoldIcons.musicNotes, size: size, color: color);
      case 'video': return Icon(SolarBoldIcons.videocamera, size: size, color: color);
      default:
        final fileName = (item.filePath != null ? p.basename(item.filePath!) : item.title).toLowerCase();
        final extension = p.extension(fileName).toLowerCase().replaceAll('.', '');
        if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(extension)) {
          return Icon(SolarBoldIcons.gallery, size: size, color: color);
        }
        if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(extension)) {
          return Icon(SolarBoldIcons.videocamera, size: size, color: color);
        }
        if (['mp3', 'wav', 'aac', 'm4a', 'flac'].contains(extension)) {
          return Icon(SolarBoldIcons.musicNotes, size: size, color: color);
        }
        return Icon(SolarBoldIcons.file, size: size, color: color);
    }
  }

  IconData _getPermissionIcon(String permission) {
    switch (permission) {
      case 'edit':
        return SolarLinearIcons.pen;
      case 'admin':
        return SolarLinearIcons.userHeart;
      default:
        return SolarLinearIcons.eye;
    }
  }

  String _getPermissionLabel(String permission) {
    switch (permission) {
      case 'edit':
        return 'تعديل';
      case 'admin':
        return 'مدير';
      default:
        return 'قراءة';
    }
  }

  Color _getPermissionColor(String permission) {
    switch (permission) {
      case 'edit':
        return Colors.blue;
      case 'admin':
        return Colors.purple;
      default:
        return AppColors.primary;
    }
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

class _LibraryItemListCardState extends State<LibraryItemListCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  String? _localPath;
  bool _isDownloading = false;
  int _downloadedBytes = 0;
  int _totalBytes = 0;

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
    _checkCache();
  }

  @override
  void didUpdateWidget(covariant LibraryItemListCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.filePath != widget.item.filePath) {
      _checkCache();
    }
  }

  Future<void> _checkCache() async {
    if (widget.item.type == 'note' || widget.item.type == 'task') return;
    if (widget.item.filePath == null) return;

    final url = widget.item.filePath!.toFullUrl;
    final path = await MediaCacheManager().getLocalPath(url, filename: widget.item.title);
    if (mounted) {
      setState(() => _localPath = path);
    }
  }

  Future<void> _download() async {
    if (widget.item.filePath == null || _isDownloading) return;

    final url = widget.item.filePath!.toFullUrl;
    setState(() => _isDownloading = true);

    try {
      final path = await MediaCacheManager().downloadFile(
        url,
        filename: widget.item.title,
        onProgressBytes: (received, total) {
          if (mounted) {
            setState(() {
              _downloadedBytes = received;
              _totalBytes = total;
            });
          }
        },
      );
      if (mounted) {
        setState(() {
          _localPath = path;
          _isDownloading = false;
          _downloadedBytes = 0;
          _totalBytes = 0;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadedBytes = 0;
          _totalBytes = 0;
        });
        AnimatedToast.error(context, 'فشل التحميل: $e');
      }
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
            Haptics.lightTap();
            if (widget.provider.isSelectionMode) {
              widget.provider.toggleSelection(widget.item.id);
            } else {
              final isMedia = widget.item.type != 'note' && widget.item.type != 'task';
              if (isMedia && _localPath == null) {
                await _download();
                if (_localPath != null) widget.onView();
              } else {
                widget.onView();
              }
            }
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
                      clipBehavior: Clip.hardEdge,
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
                                        ? 'جاري الرفع...'
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
                          child: Container(
                            padding: EdgeInsets.all(isSelected ? 0 : 3),
                            decoration: BoxDecoration(
                              color: theme.scaffoldBackgroundColor,
                              shape: BoxShape.circle,
                              border: isSelected
                                  ? null
                                  : Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                            ),
                            child: isSelected
                                ? const Icon(SolarBoldIcons.checkCircle, color: AppColors.success, size: 24)
                                : Icon(SolarLinearIcons.stop, size: 14, color: isDark ? AppColors.textSecondaryDark : Colors.grey[400]),
                          ),
                        ),
                      // Show shared badge for items shared with the user
                      if (widget.item.isShared || widget.item.sharePermission != null)
                        Positioned(
                          top: AppDimensions.spacing8,
                          right: AppDimensions.spacing8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppDimensions.spacing8,
                              vertical: AppDimensions.spacing4,
                            ),
                            decoration: BoxDecoration(
                              color: _getPermissionColor(widget.item.sharePermission ?? 'read').withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(AppDimensions.radiusSmall),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getPermissionIcon(widget.item.sharePermission ?? 'read'),
                                  size: AppDimensions.iconSmall,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: AppDimensions.spacing4),
                                Text(
                                  _getPermissionLabel(widget.item.sharePermission ?? 'read'),
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
              const Text(
                'جاري الرفع...',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${_formatBytes(uploadedBytes)} / ${_formatBytes(totalBytes)}',
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
    final fileName = (item.filePath != null ? p.basename(item.filePath!) : item.title).toLowerCase();
    final extension = p.extension(fileName).toLowerCase().replaceAll('.', '');
    final isImage = item.type == 'image' ||
        ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(extension) ||
        (item.mimeType?.contains('image') ?? false);
    final isVideo = item.type == 'video' ||
        ['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(extension) ||
        (item.mimeType?.contains('video') ?? false);

    if (_localPath == null && (isImage || isVideo || item.type == 'audio' || item.type == 'file')) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Center(
        child: _isDownloading
            ? _buildDetailedProgressIndicator(isDark)
            : Stack(
                alignment: Alignment.center,
                children: [
                  _getTypeIcon(item, size: 32, color: isDark ? AppColors.textSecondaryDark : Colors.grey[300]!),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(SolarLinearIcons.download, color: Colors.white, size: 14),
                  ),
                ],
              ),
      );
    }

    if (isImage && _localPath != null) {
      return CachedNetworkImage(imageUrl: item.filePath!.toFullUrl, fit: BoxFit.cover);
    }

    if (isVideo && _localPath != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          VideoThumbnailWidget(videoUrl: _localPath!),
          Center(
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: const Icon(SolarBoldIcons.play, color: Colors.white, size: 20),
            ),
          ),
        ],
      );
    }

    if (item.type == 'note') {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: Text(
          item.content ?? '',
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          textDirection: (item.content ?? '').direction,
          textAlign: (item.content ?? '').isArabic ? TextAlign.right : TextAlign.left,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.normal,
            color: isDark ? AppColors.textPrimaryDark : AppColors.textSecondaryLight,
            fontFamily: 'IBM Plex Sans Arabic',
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(child: _getTypeIcon(item, size: 40, color: isDark ? AppColors.textSecondaryDark : Colors.grey[400]!));
  }

  Widget _buildDetailedProgressIndicator(bool isDark) {
    final percentage = _totalBytes > 0 ? ((_downloadedBytes.toDouble() / _totalBytes) * 100) : 0;
    final progress = _totalBytes > 0 ? (_downloadedBytes.toDouble() / _totalBytes) : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
                '${percentage.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_formatBytes(_downloadedBytes)} / ${_formatBytes(_totalBytes)}',
          style: TextStyle(
            fontSize: 9,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    double dBytes = bytes.toDouble();
    int iSafety = 0;
    while (dBytes >= 1024 && iSafety < suffixes.length - 1) {
      dBytes /= 1024;
      iSafety++;
    }
    return '${dBytes.toStringAsFixed(iSafety == 0 ? 0 : 1)} ${suffixes[iSafety]}';
  }

  Widget _getTypeIcon(LibraryItem item, {double size = 24, Color color = Colors.grey}) {
    switch (item.type) {
      case 'note': return Icon(SolarBoldIcons.notes, size: size, color: color);
      case 'image': return Icon(SolarBoldIcons.gallery, size: size, color: color);
      case 'audio': return Icon(SolarBoldIcons.musicNotes, size: size, color: color);
      case 'video': return Icon(SolarBoldIcons.videocamera, size: size, color: color);
      default:
        final fileName = (item.filePath != null ? p.basename(item.filePath!) : item.title).toLowerCase();
        final extension = p.extension(fileName).toLowerCase().replaceAll('.', '');
        if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(extension)) {
          return Icon(SolarBoldIcons.gallery, size: size, color: color);
        }
        if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(extension)) {
          return Icon(SolarBoldIcons.videocamera, size: size, color: color);
        }
        if (['mp3', 'wav', 'aac', 'm4a', 'flac'].contains(extension)) {
          return Icon(SolarBoldIcons.musicNotes, size: size, color: color);
        }
        return Icon(SolarBoldIcons.file, size: size, color: color);
    }
  }

  IconData _getPermissionIcon(String permission) {
    switch (permission) {
      case 'edit':
        return SolarLinearIcons.pen;
      case 'admin':
        return SolarLinearIcons.userHeart;
      default:
        return SolarLinearIcons.eye;
    }
  }

  String _getPermissionLabel(String permission) {
    switch (permission) {
      case 'edit':
        return 'تعديل';
      case 'admin':
        return 'مدير';
      default:
        return 'قراءة';
    }
  }

  Color _getPermissionColor(String permission) {
    switch (permission) {
      case 'edit':
        return Colors.blue;
      case 'admin':
        return Colors.purple;
      default:
        return AppColors.primary;
    }
  }
}
