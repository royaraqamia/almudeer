import 'dart:io';
import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/dimensions.dart';
import '../../../core/utils/haptics.dart';
import '../../widgets/animated_toast.dart';

/// Multi-image preview dialog with carousel and caption support
class MultiImagePreviewDialog extends StatefulWidget {
  final List<File> images;
  final Function(List<File>)? onConfirm;
  final VoidCallback? onCancel;

  const MultiImagePreviewDialog({
    super.key,
    required this.images,
    this.onConfirm,
    this.onCancel,
  });

  @override
  State<MultiImagePreviewDialog> createState() =>
      _MultiImagePreviewDialogState();
}

class _MultiImagePreviewDialogState extends State<MultiImagePreviewDialog> {
  late PageController _pageController;
  int _currentIndex = 0;
  final Map<int, String> _captions = {};
  final Set<int> _removedIndices = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _removeCurrentImage() {
    if (widget.images.length <= 1) return;

    Haptics.lightTap();
    setState(() {
      _removedIndices.add(_currentIndex);
    });

    // Navigate to next available image
    if (_currentIndex < widget.images.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _confirmSelection() {
    final remainingImages = widget.images
        .asMap()
        .entries
        .where((e) => !_removedIndices.contains(e.key))
        .map((e) => e.value)
        .toList();

    if (remainingImages.isEmpty) {
      AnimatedToast.error(context, 'الرجاء اختيار صورة واحدة على الأقل');
      return;
    }

    Haptics.mediumTap();
    widget.onConfirm?.call(remainingImages);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final activeImages = widget.images
        .asMap()
        .entries
        .where((e) => !_removedIndices.contains(e.key))
        .toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusXXLarge,
            cornerSmoothing: 1.0,
          ),
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      Haptics.lightTap();
                      Navigator.pop(context);
                      widget.onCancel?.call();
                    },
                    icon: const Icon(SolarLinearIcons.closeCircle),
                    color: theme.hintColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'معاينة ${activeImages.length} من ${widget.images.length}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48), // Balance the close button
                ],
              ),
            ),

            const Divider(height: 1),

            // Image carousel
            Expanded(
              child: activeImages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            SolarLinearIcons.gallery,
                            size: 64,
                            color: theme.hintColor.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'تم إزالة جميع الصور',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.hintColor,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Stack(
                      children: [
                        PhotoViewGallery.builder(
                          pageController: _pageController,
                          itemCount: activeImages.length,
                          builder: (context, index) {
                            final actualIndex = activeImages[index].key;
                            return PhotoViewGalleryPageOptions(
                              imageProvider: FileImage(
                                activeImages[index].value,
                              ) as ImageProvider,
                              initialScale: 1.0,
                              minScale: 1.0,
                              maxScale: 3.0,
                              heroAttributes: PhotoViewHeroAttributes(
                                tag: 'image_$actualIndex',
                              ),
                            );
                          },
                          onPageChanged: (index) {
                            setState(() {
                              _currentIndex = index;
                            });
                          },
                          scrollPhysics: const BouncingScrollPhysics(),
                          backgroundDecoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF0A0A0A)
                                : Colors.grey[100],
                          ),
                        ),

                        // Remove button overlay
                        Positioned(
                          top: 16,
                          right: 16,
                          child: Semantics(
                            label: 'إزالة الصورة',
                            button: true,
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: IconButton(
                                onPressed: _removeCurrentImage,
                                icon: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    SolarLinearIcons.trashBinMinimalistic,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Caption input
                        Positioned(
                          bottom: 16,
                          left: 16,
                          right: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: SmoothBorderRadius(
                                cornerRadius: AppDimensions.radiusLarge,
                                cornerSmoothing: 1.0,
                              ),
                            ),
                            child: TextField(
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'أضف تعليقاً...',
                                hintStyle: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                ),
                                border: InputBorder.none,
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _captions[_currentIndex] = '';
                                    });
                                  },
                                  icon: const Icon(
                                    SolarLinearIcons.closeCircle,
                                    color: Colors.white70,
                                    size: 20,
                                  ),
                                ),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _captions[_currentIndex] = value;
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
            ),

            // Page indicator
            if (activeImages.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    activeImages.length,
                    (index) => Container(
                      width: index == _currentIndex ? 24 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: index == _currentIndex
                            ? AppColors.primary
                            : theme.dividerColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),

            const Divider(height: 1),

            // Action buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Cancel button
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Haptics.lightTap();
                        Navigator.pop(context);
                        widget.onCancel?.call();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.hintColor,
                        side: BorderSide(color: theme.dividerColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('إلغاء'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Send button
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: activeImages.isEmpty ? null : _confirmSelection,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: theme.dividerColor,
                        disabledForegroundColor: theme.hintColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            SolarBoldIcons.plain2,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'إرسال ${activeImages.length} صور',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
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
