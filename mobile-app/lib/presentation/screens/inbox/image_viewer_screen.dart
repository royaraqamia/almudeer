import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/services/media_service.dart';
import '../../../core/utils/premium_toast.dart';
import '../../../core/services/sharing_service.dart';

import '../../../core/constants/colors.dart';
import '../../../core/services/media_cache_manager.dart';
import '../../../core/extensions/string_extension.dart';

import 'package:path_provider/path_provider.dart';

/// Full-screen image viewer with pinch-to-zoom using PhotoView
class ImageViewerScreen extends StatefulWidget {
  final Uint8List? imageData;
  final String? imageUrl;
  final File? imageFile;
  final String heroTag;
  final String? caption;

  const ImageViewerScreen({
    super.key,
    this.imageData,
    this.imageUrl,
    this.imageFile,
    required this.heroTag,
    this.caption,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late final PhotoViewController _photoViewController;

  // ISSUE-007: Retry logic
  int _retryCount = 0;
  static const int _maxRetries = 3;
  bool _isNetworkError = false;

  // P0 FIX: Force reload by changing key
  int _reloadKey = 0;

  @override
  void initState() {
    super.initState();
    _photoViewController = PhotoViewController();
  }

  @override
  void dispose() {
    _photoViewController.dispose();
    super.dispose();
  }

  // ISSUE-007 + P0 FIX: Retry method that actually reloads
  void _retryLoad() {
    if (_retryCount < _maxRetries) {
      setState(() {
        _retryCount++;
        _reloadKey++; // Force PhotoView to rebuild with new key
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              SolarLinearIcons.arrowRight,
              color: Colors.white,
              size: 24,
            ),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                SolarLinearIcons.share,
                color: Colors.white,
                size: 20,
              ),
            ),
            onPressed: () => _shareImage(context),
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                SolarLinearIcons.download,
                color: Colors.white,
                size: 20,
              ),
            ),
            onPressed: () => _saveImage(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: GestureDetector(
        onVerticalDragEnd: (details) {
          // Dismiss on swipe down
          if (details.primaryVelocity != null &&
              details.primaryVelocity! > 300) {
            Navigator.of(context).pop();
          }
        },
        child: Center(
          child: Hero(
            tag: widget.heroTag,
            child: GestureDetector(
              onDoubleTap: () {
                _photoViewController.scale = _photoViewController.initial.scale;
              },
              child: PhotoView(
                key: ValueKey(_reloadKey), // P0 FIX: Force reload on retry
                controller: _photoViewController,
                imageProvider: widget.imageFile != null
                    ? FileImage(widget.imageFile!)
                    : widget.imageData != null
                    ? MemoryImage(widget.imageData!)
                    : CachedNetworkImageProvider(widget.imageUrl!.toFullUrl)
                          as ImageProvider,
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 3,
                backgroundDecoration: const BoxDecoration(color: Colors.black),
                loadingBuilder: (context, event) => Center(
                  child: CircularProgressIndicator(
                    value: event == null
                        ? null
                        : event.cumulativeBytesLoaded /
                              (event.expectedTotalBytes ?? 1),
                    valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
                errorBuilder: (context, error, stackTrace) {
                  _isNetworkError =
                      error is SocketException ||
                      error.toString().contains('Socket') ||
                      error.toString().contains('Network');

                  return _buildErrorView(error);
                },
              ),
            ),
          ),
        ),
      ),
      // Caption at bottom
      bottomSheet: widget.caption != null && widget.caption!.isNotEmpty
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
              ),
              child: Text(
                widget.caption!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.4,
                ),
                textDirection: widget.caption!.isArabic
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                textAlign: widget.caption!.isArabic
                    ? TextAlign.right
                    : TextAlign.left,
              ),
            )
          : null,
    );
  }

  // ISSUE-007: Error view with retry button
  Widget _buildErrorView(dynamic error) {
    final canRetry = _retryCount < _maxRetries;
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isNetworkError
                ? SolarLinearIcons.volumeCross
                : SolarLinearIcons.galleryRemove,
            size: 64,
            color: Colors.white54,
          ),
          const SizedBox(height: 16),
          Text(
            _isNetworkError ? 'خطأ في الشبكة' : 'فشل تحميل الصورة',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white54),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (canRetry) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _retryLoad,
              icon: const Icon(SolarLinearIcons.refresh),
              label: Text('إعادة المحاولة (${3 - _retryCount})'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ...

  Future<void> _shareImage(BuildContext context) async {
    String? path = widget.imageFile?.path;

    if (path == null && widget.imageData != null) {
      try {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File(
          '${tempDir.path}/shared_image_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        await tempFile.writeAsBytes(widget.imageData!);
        path = tempFile.path;
      } catch (e) {
        debugPrint('Error preparing image data for share: $e');
      }
    }

    // Is it a network image?
    if (path == null && widget.imageUrl != null) {
      final fullUrl = widget.imageUrl!.toFullUrl;
      try {
        final cachedPath = await MediaCacheManager().getLocalPath(fullUrl);
        if (cachedPath != null && await File(cachedPath).exists()) {
          path = cachedPath;
        } else {
          path = await MediaCacheManager().downloadFile(fullUrl);
        }
      } catch (e) {
        if (context.mounted) {
          PremiumToast.show(
            context,
            'فشل تجهيز الصورة للمشاركة',
            icon: SolarLinearIcons.dangerCircle,
            isError: true,
          );
        }
        return;
      }
    }

    if (path == null) {
      if (context.mounted) {
        PremiumToast.show(
          context,
          'فشل تجهيز الصورة للمشاركة',
          icon: SolarLinearIcons.dangerCircle,
          isError: true,
        );
      }
      return;
    }

    try {
      if (context.mounted) {
        SharingService().showShareMenu(context, filePath: path, type: 'image');
      }
    } catch (e) {
      if (context.mounted) {
        PremiumToast.show(
          context,
          'فشل المشاركة',
          icon: SolarLinearIcons.dangerCircle,
          isError: true,
        );
      }
    }
  }

  Future<void> _saveImage(BuildContext context) async {
    final String? path = widget.imageFile?.path ?? widget.imageUrl;

    if (path == null && widget.imageData == null) {
      if (context.mounted) {
        PremiumToast.show(
          context,
          'الصورة غير متوفرة للحفظ',
          icon: SolarLinearIcons.dangerCircle,
          isError: true,
        );
      }
      return;
    }

    try {
      final success = await MediaService.saveToGallery(
        path ?? '',
        imageData: widget.imageData,
      );
      if (context.mounted) {
        if (success) {
          PremiumToast.show(
            context,
            'تم الحفظ في المعرض',
            icon: SolarLinearIcons.checkCircle,
          );
        } else {
          PremiumToast.show(
            context,
            'فشل الحفظ',
            icon: SolarLinearIcons.dangerCircle,
            isError: true,
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        PremiumToast.show(
          context,
          'خطأ في الحفظ: ${e.toString()}',
          icon: SolarLinearIcons.dangerCircle,
          isError: true,
        );
      }
    }
  }
}
