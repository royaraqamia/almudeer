import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

import '../../../core/extensions/string_extension.dart';
import '../../screens/viewers/universal_viewer_screen.dart';
import '../video_thumbnail_widget.dart';

import '../../../core/services/media_cache_manager.dart';
import '../../widgets/animated_toast.dart';

class VideoMessageBubble extends StatefulWidget {
  final Map<String, dynamic> attachment;
  final bool isOutgoing;
  final Color color;

  const VideoMessageBubble({
    super.key,
    required this.attachment,
    required this.isOutgoing,
    required this.color,
  });

  @override
  State<VideoMessageBubble> createState() => _VideoMessageBubbleState();
}

class _VideoMessageBubbleState extends State<VideoMessageBubble> {
  bool _isDownloading = false;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  String? _localPath;

  @override
  void initState() {
    super.initState();
    _checkCache();
  }

  Future<void> _checkCache() async {
    // 1. Prioritize local path
    if (widget.attachment['path'] != null) {
      final String path = widget.attachment['path'];
      if (mounted) {
        setState(() {
          _localPath = path;
        });
      }
      return;
    }

    // 2. Fallback to URL/Cache
    final url = (widget.attachment['url'] as String?)?.toFullUrl;
    if (url != null) {
      final filename =
          widget.attachment['filename'] as String? ??
          widget.attachment['file_name'] as String?;
      final path = await MediaCacheManager().getLocalPath(
        url,
        filename: filename,
      );
      if (mounted) {
        setState(() {
          _localPath = path;
        });
      }
    }
  }

  Future<void> _download() async {
    final url = (widget.attachment['url'] as String?)?.toFullUrl;
    if (url == null) return;

    setState(() {
      _isDownloading = true;
    });

    try {
      final filename =
          widget.attachment['filename'] as String? ??
          widget.attachment['file_name'] as String?;
      final path = await MediaCacheManager().downloadFile(
        url,
        filename: filename,
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
        AnimatedToast.error(context, 'فشل تحميل الفيديو: $e');
      }
    }
  }

  Future<void> _openVideo(BuildContext context) async {
    // 1. Try local path directly
    if (_localPath != null) {
      _navigateToViewer(context, _localPath!);
      return;
    }

    // 2. If not local but has URL, download it
    if (!_isDownloading) {
      if (widget.attachment['path'] != null) {
        _navigateToViewer(context, widget.attachment['path']);
        return;
      }

      await _download();
      if (_localPath != null && context.mounted) {
        _navigateToViewer(context, _localPath!);
      }
      return;
    }
  }

  void _navigateToViewer(BuildContext context, String path) {
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UniversalViewerScreen(
            filePath: path,
            fileName: widget.attachment['filename'] as String? ?? 'video.mp4',
            fileType: 'video',
          ),
        ),
      );
    } catch (e) {
      AnimatedToast.error(context, 'فشل فتح الفيديو: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openVideo(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 220,
          height: 140, // Slightly taller for better aspect
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.8), // Base
            border: Border.all(
              color: widget.isOutgoing
                  ? widget.color.withValues(alpha: 0.3)
                  : Theme.of(context).dividerColor,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 1. Video Thumbnail (if local path available)
              if (_localPath != null)
                Positioned.fill(
                  child: VideoThumbnailWidget(
                    videoUrl: _localPath!,
                    fit: BoxFit.cover,
                  ),
                ),

              // 2. Dark Gradient Overlay
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black54,
                      Colors.transparent,
                      Colors.black54,
                    ],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
              ),

              // 2. Play Button / Download with Glassmorphism
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: _isDownloading
                      ? _buildDetailedProgressIndicator()
                      : Icon(
                          _localPath != null
                              ? SolarBoldIcons.play
                              : SolarLinearIcons.download,
                          color: Colors.white,
                          size: 24,
                        ),
                ),
              ),

              // 3. Label / Size Badge
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        SolarBoldIcons.videocamera,
                        color: Colors.white,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'فيديو',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontSize: 11,
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
  }

  Widget _buildDetailedProgressIndicator() {
    final percentage = _totalBytes > 0 ? (_downloadedBytes / _totalBytes * 100) : 0;
    final progress = _totalBytes > 0 ? (_downloadedBytes / _totalBytes) : 0.0;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 2.5,
                color: Colors.white,
                backgroundColor: Colors.white24,
              ),
            ),
            Text(
              '${percentage.toStringAsFixed(0)}%',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${_formatBytes(_downloadedBytes)} / ${_formatBytes(_totalBytes)}',
          style: const TextStyle(
            fontSize: 8,
            color: Colors.white70,
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
}
