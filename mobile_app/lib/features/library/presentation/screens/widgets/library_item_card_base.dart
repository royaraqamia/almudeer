import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:path/path.dart' as p;
import 'package:solar_icon_pack/solar_icon_pack.dart';

import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';
import 'package:almudeer_mobile_app/core/extensions/string_extension.dart';
import 'package:almudeer_mobile_app/core/services/media_cache_manager.dart';
import 'package:almudeer_mobile_app/core/localization/library_localizations.dart';
import 'package:almudeer_mobile_app/features/library/data/models/library_item.dart';
import 'package:almudeer_mobile_app/features/library/presentation/providers/library_provider.dart';
import 'package:almudeer_mobile_app/features/viewer/presentation/widgets/video_thumbnail_widget.dart';

/// Base class for library item card states
/// Extracts duplicate code for cache checking, downloading, and progress display
abstract class LibraryItemCardStateBase<T extends StatefulWidget> extends State<T> {
  String? _localPath;
  bool _isDownloading = false;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  bool _disposed = false;

  LibraryItem get item;
  LibraryProvider get provider;
  VoidCallback get onView;

  String? get localPath => _localPath;
  bool get isDownloading => _isDownloading;
  int get downloadedBytes => _downloadedBytes;
  int get totalBytes => _totalBytes;
  bool get isDisposed => _disposed;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> checkCache() async {
    if (item.type == 'note' || item.type == 'task') return;
    if (item.filePath == null) return;

    final url = item.filePath!.toFullUrl;
    final path = await MediaCacheManager().getLocalPath(
      url,
      filename: item.title,
    );
    if (!_disposed && mounted) {
      setState(() => _localPath = path);
    }
  }

  Future<void> downloadFile() async {
    if (item.filePath == null || _isDownloading) return;

    final url = item.filePath!.toFullUrl;
    if (!mounted) return;
    
    setState(() => _isDownloading = true);

    try {
      final path = await MediaCacheManager().downloadFile(
        url,
        filename: item.title,
        onProgressBytes: (received, total) {
          if (!_disposed && mounted) {
            setState(() {
              _downloadedBytes = received;
              _totalBytes = total;
            });
          }
        },
      );
      if (!_disposed && mounted) {
        setState(() {
          _localPath = path;
          _isDownloading = false;
          _downloadedBytes = 0;
          _totalBytes = 0;
        });
      }
    } catch (e) {
      if (!_disposed && mounted) {
        setState(() {
          _isDownloading = false;
          _downloadedBytes = 0;
          _totalBytes = 0;
        });
        // Show error with retry option
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LibraryLocalizations.of(context).downloadFailed(item.title)),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: LibraryLocalizations.of(context).retry,
              textColor: Colors.white,
              onPressed: downloadFile,
            ),
          ),
        );
      }
    }
  }

  /// Handle tap on card
  Future<void> handleTap() async {
    Haptics.lightTap();
    if (provider.isSelectionMode) {
      provider.toggleSelection(item.id);
    } else {
      final isMedia = item.type != 'note' && item.type != 'task';
      if (isMedia && _localPath == null) {
        await downloadFile();
        // Check mounted after async operation
        // Allow viewing even if download failed (will use streaming/remote URL)
        if (mounted && !_disposed) {
          onView();
        }
      } else {
        onView();
      }
    }
  }

  Widget buildItemPreview(LibraryItem item) {
    // Notes should always show content, even if they have attachments
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
            ? buildDetailedProgressIndicator(isDark)
            : Stack(
                alignment: Alignment.center,
                children: [
                  getTypeIcon(item, size: 32, color: isDark ? AppColors.textSecondaryDark : Colors.grey[300]!),
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(child: getTypeIcon(item, size: 40, color: isDark ? AppColors.textSecondaryDark : Colors.grey[400]!));
  }

  Widget buildDetailedProgressIndicator(bool isDark) {
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
          '${formatBytes(_downloadedBytes)} / ${formatBytes(_totalBytes)}',
          style: TextStyle(
            fontSize: 9,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
      ],
    );
  }

  String formatBytes(int bytes) {
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

  Widget getTypeIcon(LibraryItem item, {double size = 24, Color? color}) {
    final iconColor = color ?? Colors.grey;
    switch (item.type) {
      case 'note': return Icon(SolarBoldIcons.notes, size: size, color: iconColor);
      case 'image': return Icon(SolarBoldIcons.gallery, size: size, color: iconColor);
      case 'audio': return Icon(SolarBoldIcons.musicNotes, size: size, color: iconColor);
      case 'video': return Icon(SolarBoldIcons.videocamera, size: size, color: iconColor);
      default:
        final fileName = (item.filePath != null ? p.basename(item.filePath!) : item.title).toLowerCase();
        final extension = p.extension(fileName).toLowerCase().replaceAll('.', '');
        if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(extension)) {
          return Icon(SolarBoldIcons.gallery, size: size, color: iconColor);
        }
        if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(extension)) {
          return Icon(SolarBoldIcons.videocamera, size: size, color: iconColor);
        }
        if (['mp3', 'wav', 'aac', 'm4a', 'flac'].contains(extension)) {
          return Icon(SolarBoldIcons.musicNotes, size: size, color: iconColor);
        }
        return Icon(SolarBoldIcons.file, size: size, color: iconColor);
    }
  }

  IconData getPermissionIcon(String permission) {
    switch (permission) {
      case 'edit':
        return SolarLinearIcons.pen;
      case 'admin':
        return SolarLinearIcons.userHeart;
      default:
        return SolarLinearIcons.eye;
    }
  }

  String getPermissionLabel(String permission) {
    final localizations = LibraryLocalizations.of(context);
    switch (permission) {
      case 'edit':
        return localizations.permissionEdit;
      case 'admin':
        return localizations.permissionAdmin;
      default:
        return localizations.permissionRead;
    }
  }

  Color getPermissionColor(String permission) {
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
