import 'dart:io';
import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/constants/dimensions.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/animated_toast.dart';

/// Multi-image preview dialog with carousel and caption support
class MultiImagePreviewDialog extends StatefulWidget {
  final List<File> images;
  final Function(List<File>, Map<int, String>)? onConfirm;
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
      AnimatedToast.error(context, 'ط§ظ„ط±ط¬ط§ط، ط§ط®طھظٹط§ط± طµظˆط±ط© ظˆط§ط­ط¯ط© ط¹ظ„ظ‰ ط§ظ„ط£ظ‚ظ„');
      return;
    }

    // Build captions map for remaining images only
    final Map<int, String> remainingCaptions = {};
    int newIndex = 0;
    for (int i = 0; i < widget.images.length; i++) {
      if (!_removedIndices.contains(i)) {
        if (_captions.containsKey(i) && _captions[i]!.isNotEmpty) {
          remainingCaptions[newIndex] = _captions[i]!;
        }
        newIndex++;
      }
    }

    Haptics.mediumTap();
    widget.onConfirm?.call(remainingImages, remainingCaptions);
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
                      'ظ…ط¹ط§ظٹظ†ط© ${activeImages.length} ظ…ظ† ${widget.images.length}',
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
                            'طھظ… ط¥ط²ط§ظ„ط© ط¬ظ…ظٹط¹ ط§ظ„طµظˆط±',
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
                            label: 'ط¥ط²ط§ظ„ط© ط§ظ„طµظˆط±ط©',
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
                                hintText: 'ط£ط¶ظپ طھط¹ظ„ظٹظ‚ط§ظ‹...',
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
                      child: const Text('ط¥ظ„ط؛ط§ط،'),
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
                            'ط¥ط±ط³ط§ظ„ ${activeImages.length} طµظˆط±',
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

/// Single image preview dialog with caption input
class SingleImagePreviewDialog extends StatefulWidget {
  final File image;
  final Function(File, String?)? onConfirm;
  final VoidCallback? onCancel;

  const SingleImagePreviewDialog({
    super.key,
    required this.image,
    this.onConfirm,
    this.onCancel,
  });

  @override
  State<SingleImagePreviewDialog> createState() =>
      _SingleImagePreviewDialogState();
}

class _SingleImagePreviewDialogState extends State<SingleImagePreviewDialog> {
  final TextEditingController _captionController = TextEditingController();

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  void _confirm() {
    Haptics.mediumTap();
    final caption = _captionController.text.trim();
    widget.onConfirm?.call(widget.image, caption.isEmpty ? null : caption);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
                      'ظ…ط¹ط§ظٹظ†ط© ط§ظ„طµظˆط±ط©',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            const Divider(height: 1),

            // Image preview
            Expanded(
              child: Container(
                width: double.infinity,
                color: isDark ? const Color(0xFF0A0A0A) : Colors.grey[100],
                child: PhotoView(
                  imageProvider: FileImage(widget.image) as ImageProvider,
                  initialScale: 1.0,
                  minScale: 1.0,
                  maxScale: 3.0,
                  heroAttributes: const PhotoViewHeroAttributes(
                    tag: 'single_image_preview',
                  ),
                ),
              ),
            ),

            const Divider(height: 1),

            // Caption input
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _captionController,
                maxLines: 3,
                minLines: 1,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 15,
                  color: isDark ? Colors.white : Colors.black,
                ),
                decoration: InputDecoration(
                  hintText: 'ط£ط¶ظپ طھط¹ظ„ظٹظ‚ط§ظ‹...',
                  hintStyle: TextStyle(
                    fontSize: 15,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                  filled: true,
                  fillColor: isDark ? Colors.white10 : Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  suffixIcon: _captionController.text.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _captionController.clear();
                          },
                          icon: const Icon(
                            SolarLinearIcons.closeCircle,
                            color: Colors.grey,
                            size: 20,
                          ),
                        )
                      : null,
                ),
              ),
            ),

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
                      child: const Text('ط¥ظ„ط؛ط§ط،'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Send button
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _confirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            SolarBoldIcons.plain2,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'ط¥ط±ط³ط§ظ„',
                            style: TextStyle(
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
