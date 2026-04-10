import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:almudeer_mobile_app/core/services/media_service.dart';
import 'package:almudeer_mobile_app/core/utils/premium_toast.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/services/media_cache_manager.dart';
import 'package:almudeer_mobile_app/core/extensions/string_extension.dart';
import 'package:almudeer_mobile_app/core/services/sharing_service.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/animated_toast.dart';

/// Full screen video player using Chewie and VideoPlayer
class VideoPlayerScreen extends StatefulWidget {
  final String? videoUrl;
  final File? videoFile;
  final String? heroTag;

  const VideoPlayerScreen({
    super.key,
    this.videoUrl,
    this.videoFile,
    this.heroTag,
  }) : assert(
         videoUrl != null || videoFile != null,
         'Must provide either videoUrl or videoFile',
       );

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  String? _errorMessage;

  // Retry logic
  int _retryCount = 0;
  static const int _maxRetries = 3;
  bool _isNetworkError = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    // Re-enable system UI just in case
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  Future<void> _initializePlayer({bool isRetry = false}) async {
    if (isRetry) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _retryCount++;
      });
    }

    try {
      if (widget.videoFile != null) {
        _videoPlayerController = VideoPlayerController.file(widget.videoFile!);
      } else {
        _videoPlayerController = VideoPlayerController.networkUrl(
          Uri.parse(widget.videoUrl!),
        );
      }

      await _videoPlayerController.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: true,
        looping: false,
        aspectRatio: _videoPlayerController.value.aspectRatio,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Text(
              errorMessage,
              style: const TextStyle(color: Colors.white),
            ),
          );
        },
        cupertinoProgressColors: ChewieProgressColors(
          playedColor: AppColors.primary,
          handleColor: AppColors.primary,
          backgroundColor: Colors.grey,
          bufferedColor: Colors.white.withValues(alpha: 0.5),
        ),
        materialProgressColors: ChewieProgressColors(
          playedColor: AppColors.primary,
          handleColor: AppColors.primary,
          backgroundColor: Colors.grey,
          bufferedColor: Colors.white.withValues(alpha: 0.5),
        ),
      );

      setState(() {
        _isLoading = false;
        _errorMessage = null;
        _retryCount = 0;  // Reset on success
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isNetworkError = e is SocketException ||
                         e.toString().contains('Socket') ||
                         e.toString().contains('Network');
        _errorMessage = 'ظپط´ظ„ طھط­ظ…ظٹظ„ ط§ظ„ظپظٹط¯ظٹظˆ: ${e.toString()}';
      });
    }
  }

  // Retry with exponential backoff
  Future<void> _retryInitialization() async {
    if (_retryCount >= _maxRetries) {
      // Max retries reached, show permanent error
      return;
    }

    // Exponential backoff: 1s, 2s, 4s
    final delay = Duration(seconds: 1 << _retryCount);

    await Future.delayed(delay);

    if (mounted) {
      await _initializePlayer(isRetry: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(SolarLinearIcons.arrowRight, size: 24),
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
            onPressed: () => _shareVideo(context),
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
            onPressed: () => _saveVideo(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onDoubleTapDown: (details) {
            if (_videoPlayerController.value.isInitialized) {
              final screenWidth = MediaQuery.of(context).size.width;
              if (details.globalPosition.dx < screenWidth / 2) {
                // Seek backward
                final newPos =
                    _videoPlayerController.value.position -
                    const Duration(seconds: 10);
                _videoPlayerController.seekTo(
                  newPos < Duration.zero ? Duration.zero : newPos,
                );
              } else {
                // Seek forward
                final newPos =
                    _videoPlayerController.value.position +
                    const Duration(seconds: 10);
                final maxPos = _videoPlayerController.value.duration;
                _videoPlayerController.seekTo(
                  newPos > maxPos ? maxPos : newPos,
                );
              }
            }
          },
          child: Center(
            child: _isLoading
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: AppColors.primary),
                      if (_retryCount > 0) ...[
                        const SizedBox(height: 16),
                        Text(
                          'ظ…ط­ط§ظˆظ„ط© $_retryCount ظ…ظ† $_maxRetries...',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ],
                  )
                : _errorMessage != null
                ? _buildErrorView()
                : Hero(
                    tag: widget.heroTag ?? 'video_player',
                    child: Chewie(controller: _chewieController!),
                  ),
          ),
        ),
      ),
    );
  }

  // Error view with retry button
  Widget _buildErrorView() {
    final canRetry = _retryCount < _maxRetries;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          _isNetworkError ? SolarLinearIcons.volumeCross : SolarLinearIcons.dangerCircle,
          size: 64,
          color: Colors.white54,
        ),
        const SizedBox(height: 16),
        Text(
          _isNetworkError ? 'ط®ط·ط£ ظپظٹ ط§ظ„ط´ط¨ظƒط©' : 'ظپط´ظ„ طھط­ظ…ظٹظ„ ط§ظ„ظپظٹط¯ظٹظˆ',
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          _errorMessage!.replaceFirst('ظپط´ظ„ طھط­ظ…ظٹظ„ ط§ظ„ظپظٹط¯ظٹظˆ: ', ''),
          style: const TextStyle(color: Colors.white54, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        if (canRetry) ...[
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _retryInitialization,
            icon: const Icon(SolarLinearIcons.refresh),
            label: Text('ط¥ط¹ط§ط¯ط© ط§ظ„ظ…ط­ط§ظˆظ„ط© (${3 - _retryCount})'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _shareVideo(BuildContext context) async {
    String? path = widget.videoFile?.path;

    // If no local file, try to get from cache or download
    if (path == null && widget.videoUrl != null) {
      final fullUrl = widget.videoUrl!.toFullUrl;
      try {
        final cachedPath = await MediaCacheManager().getLocalPath(fullUrl);
        if (cachedPath != null && await File(cachedPath).exists()) {
          path = cachedPath;
        } else {
          path = await MediaCacheManager().downloadFile(fullUrl);
        }
      } catch (e) {
        debugPrint('Error preparing video for share: $e');
      }
    }

    if (path == null) {
      if (context.mounted) {
        AnimatedToast.error(context, 'ظپط´ظ„ طھط¬ظ‡ظٹط² ط§ظ„ظپظٹط¯ظٹظˆ ظ„ظ„ظ…ط´ط§ط±ظƒط©');
      }
      return;
    }

    if (context.mounted) {
      SharingService().showShareMenu(context, filePath: path, type: 'video');
    }
  }

  Future<void> _saveVideo(BuildContext context) async {
    final String? path = widget.videoFile?.path ?? widget.videoUrl;
    if (path == null) return;

    try {
      final success = await MediaService.saveToGallery(path, isVideo: true);
      if (context.mounted) {
        if (success) {
          PremiumToast.show(
            context,
            'طھظ… ط§ظ„ط­ظپط¸ ظپظٹ ط§ظ„ظ…ط¹ط±ط¶',
            icon: SolarLinearIcons.checkCircle,
          );
        } else {
          PremiumToast.show(
            context,
            'ظپط´ظ„ ط§ظ„ط­ظپط¸',
            icon: SolarLinearIcons.dangerCircle,
            isError: true,
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        PremiumToast.show(
          context,
          'ط®ط·ط£: $e',
          icon: SolarLinearIcons.dangerCircle,
          isError: true,
        );
      }
    }
  }
}
