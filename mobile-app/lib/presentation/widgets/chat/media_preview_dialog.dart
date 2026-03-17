import 'dart:io';
import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:path/path.dart' as p;

import '../../../core/constants/colors.dart';
import '../../../core/constants/dimensions.dart';
import '../../../core/utils/haptics.dart';
import '../../widgets/animated_toast.dart';

/// Unified media preview dialog with caption support for all media types
/// Supports: images, videos, and files
class MediaPreviewDialog extends StatefulWidget {
  final File file;
  final String mediaType; // 'image', 'video', 'file'
  final String? fileName;
  final Function(File, String?)? onConfirm;
  final VoidCallback? onCancel;

  const MediaPreviewDialog({
    super.key,
    required this.file,
    required this.mediaType,
    this.fileName,
    this.onConfirm,
    this.onCancel,
  });

  @override
  State<MediaPreviewDialog> createState() => _MediaPreviewDialogState();
}

class _MediaPreviewDialogState extends State<MediaPreviewDialog> {
  final TextEditingController _captionController = TextEditingController();
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isPlaying = false;

  static const int maxCaptionLength = 1024;

  @override
  void initState() {
    super.initState();
    if (widget.mediaType == 'video') {
      _initializeVideo();
    }
  }

  Future<void> _initializeVideo() async {
    _videoController = VideoPlayerController.file(widget.file)
      ..setLooping(true)
      ..setVolume(0.0) // Mute by default
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _isVideoInitialized = true;
          });
          _videoController?.play();
          setState(() {
            _isPlaying = true;
          });
        }
      });
  }

  @override
  void dispose() {
    _captionController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_videoController == null || !_isVideoInitialized) return;

    setState(() {
      if (_isPlaying) {
        _videoController?.pause();
      } else {
        _videoController?.play();
      }
      _isPlaying = !_isPlaying;
    });
  }

  void _confirm() {
    Haptics.mediumTap();
    final caption = _captionController.text.trim();
    
    // Validate caption length
    if (caption.length > maxCaptionLength) {
      AnimatedToast.error(
        context,
        'التعليق طويل جداً. الحد الأقصى هو $maxCaptionLength حرف',
      );
      return;
    }

    widget.onConfirm?.call(widget.file, caption.isEmpty ? null : caption);
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
            _buildHeader(theme, isDark),

            const Divider(height: 1),

            // Media preview
            Expanded(
              child: _buildMediaPreview(isDark),
            ),

            const Divider(height: 1),

            // Caption input
            _buildCaptionInput(theme, isDark),

            // Action buttons
            _buildActionButtons(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isDark) {
    String title;
    IconData icon;
    Color iconColor;

    switch (widget.mediaType) {
      case 'image':
        title = 'معاينة الصورة';
        icon = SolarLinearIcons.gallery;
        iconColor = Colors.purple;
        break;
      case 'video':
        title = 'معاينة الفيديو';
        icon = SolarLinearIcons.videocamera;
        iconColor = Colors.red;
        break;
      default:
        title = 'معاينة الملف';
        icon = SolarLinearIcons.file;
        iconColor = Colors.blue;
    }

    return Padding(
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
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // File info for non-image/video
          if (widget.mediaType == 'file' && widget.fileName != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                ext.replaceFirst('.', '').toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ] else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildMediaPreview(bool isDark) {
    switch (widget.mediaType) {
      case 'image':
        return _buildImagePreview(isDark);
      case 'video':
        return _buildVideoPreview(isDark);
      default:
        return _buildFilePreview(isDark);
    }
  }

  Widget _buildImagePreview(bool isDark) {
    return Container(
      width: double.infinity,
      color: isDark ? const Color(0xFF0A0A0A) : Colors.grey[100],
      child: PhotoView(
        imageProvider: FileImage(widget.file) as ImageProvider,
        initialScale: 1.0,
        minScale: 1.0,
        maxScale: 3.0,
        heroAttributes: const PhotoViewHeroAttributes(
          tag: 'media_preview_image',
        ),
      ),
    );
  }

  Widget _buildVideoPreview(bool isDark) {
    return Container(
      width: double.infinity,
      color: Colors.black,
      child: _isVideoInitialized
          ? Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: _videoController!.value.aspectRatio,
                  child: VideoPlayer(_videoController!),
                ),
                // Play/Pause button
                GestureDetector(
                  onTap: _togglePlayPause,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.5),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      _isPlaying
                          ? SolarLinearIcons.pause
                          : SolarBoldIcons.play,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ],
            )
          : const Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
              ),
            ),
    );
  }

  Widget _buildFilePreview(bool isDark) {
    final theme = Theme.of(context);
    final fileColor = _getFileColor(ext);
    final fileIcon = _getFileIcon(ext);

    return Container(
      width: double.infinity,
      color: isDark ? const Color(0xFF0A0A0A) : Colors.grey[100],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: fileColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                fileIcon,
                size: 80,
                color: fileColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.fileName ?? 'ملف',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              ext.toUpperCase(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaptionInput(ThemeData theme, bool isDark) {
    final captionLength = _captionController.text.length;
    final isOverLimit = captionLength > maxCaptionLength;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                SolarLinearIcons.chatRound,
                size: 18,
                color: theme.hintColor,
              ),
              const SizedBox(width: 8),
              Text(
                'أضف تعليقاً',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '$captionLength / $maxCaptionLength',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isOverLimit ? Colors.red : theme.hintColor,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _captionController,
            maxLines: 4,
            minLines: 2,
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.right,
            maxLength: maxCaptionLength + 100, // Allow slight overflow for validation
            style: TextStyle(
              fontSize: 15,
              color: isDark ? Colors.white : Colors.black,
            ),
            decoration: InputDecoration(
              hintText: 'اكتب تعليقاً على هذا الملف...',
              hintStyle: TextStyle(
                fontSize: 15,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
              filled: true,
              fillColor: isDark ? Colors.white10 : Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isOverLimit ? Colors.red : Colors.transparent,
                  width: 2,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Colors.transparent,
                  width: 2,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isOverLimit ? Colors.red : AppColors.primary,
                  width: 2,
                ),
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
          if (isOverLimit) ...[
            const SizedBox(height: 8),
            Text(
              'التعليق طويل جداً. يرجى اختصاره.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.red,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons(ThemeData theme) {
    return Padding(
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
                    'إرسال',
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
    );
  }

  String get ext => widget.fileName != null
      ? p.extension(widget.fileName!).toLowerCase()
      : '';

  Color _getFileColor(String ext) {
    switch (ext) {
      case 'pdf':
        return Colors.red;
      case 'doc':
      case 'docx':
        return Colors.blue;
      case 'ppt':
      case 'pptx':
        return Colors.orange;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Colors.green;
      case 'zip':
      case 'rar':
      case '7z':
        return Colors.amber[700]!;
      default:
        return AppColors.primary;
    }
  }

  IconData _getFileIcon(String ext) {
    switch (ext) {
      case 'pdf':
        return SolarBoldIcons.fileText;
      case 'doc':
      case 'docx':
        return SolarBoldIcons.documentText;
      case 'ppt':
      case 'pptx':
        return SolarBoldIcons.presentationGraph;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return SolarBoldIcons.chartSquare;
      case 'zip':
      case 'rar':
      case '7z':
        return SolarBoldIcons.archive;
      default:
        return SolarBoldIcons.file;
    }
  }
}
