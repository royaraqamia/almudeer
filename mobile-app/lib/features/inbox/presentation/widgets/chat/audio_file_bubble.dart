import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/features/viewer/presentation/screens/universal_viewer_screen.dart';

import 'package:almudeer_mobile_app/core/services/media_cache_manager.dart';
import 'package:almudeer_mobile_app/core/extensions/string_extension.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/animated_toast.dart';

class AudioFileBubble extends StatefulWidget {
  final Map<String, dynamic> attachment;
  final bool isOutgoing;
  final Color color;

  const AudioFileBubble({
    super.key,
    required this.attachment,
    required this.isOutgoing,
    required this.color,
  });

  @override
  State<AudioFileBubble> createState() => _AudioFileBubbleState();
}

class _AudioFileBubbleState extends State<AudioFileBubble> {
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
        AnimatedToast.error(context, 'ظپط´ظ„ طھط­ظ…ظٹظ„ ط§ظ„ظ…ظ„ظپ ط§ظ„طµظˆطھظٹ: $e');
      }
    }
  }

  Future<void> _openAudio(BuildContext context) async {
    if (_localPath == null && !_isDownloading) {
      await _download();
      return;
    }

    if (_localPath == null) return;

    final filename =
        widget.attachment['filename'] as String? ??
        widget.attachment['file_name'] as String? ??
        'audio_track';

    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UniversalViewerScreen(
            filePath: _localPath,
            fileName: filename,
            fileType: 'audio',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filename =
        widget.attachment['filename'] as String? ??
        widget.attachment['file_name'] as String? ??
        'ظ…ظ„ظپ طµظˆطھظٹ';

    final durationSec = widget.attachment['duration_seconds'] as int?;
    final durationMs = widget.attachment['duration_ms'] as int?;
    String? durationStr;

    if (durationMs != null) {
      durationStr = _formatDuration(Duration(milliseconds: durationMs));
    } else if (durationSec != null) {
      durationStr = _formatDuration(Duration(seconds: durationSec));
    }

    return GestureDetector(
      onTap: () => _openAudio(context),
      child: Container(
        width: 240,
        height: 70,
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          gradient: widget.isOutgoing
              ? LinearGradient(
                  colors: [
                    widget.color.withValues(alpha: 0.2),
                    widget.color.withValues(alpha: 0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: widget.isOutgoing ? null : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.isOutgoing
                ? widget.color.withValues(alpha: 0.3)
                : Theme.of(context).dividerColor,
          ),
        ),
        child: Row(
          children: [
            Container(
              margin: const EdgeInsets.all(8),
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: widget.isOutgoing
                    ? Colors.white.withValues(alpha: 0.2)
                    : AppColors.primary.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: _isDownloading
                    ? _buildDetailedProgressIndicator()
                    : Icon(
                        _localPath != null
                            ? SolarBoldIcons.musicNote
                            : SolarLinearIcons.download,
                        color: widget.isOutgoing
                            ? Colors.white
                            : AppColors.primary,
                        size: 24,
                      ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      filename,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.normal,
                        fontSize: 14,
                        color: widget.isOutgoing ? Colors.white : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      durationStr ?? 'ظ…ظ„ظپ طµظˆطھظٹ',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: widget.isOutgoing
                            ? Colors.white.withValues(alpha: 0.8)
                            : Theme.of(context).hintColor,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: Icon(
                _localPath != null
                    ? SolarBoldIcons.playCircle
                    : SolarLinearIcons.download,
                color: widget.isOutgoing
                    ? Colors.white.withValues(alpha: 0.7)
                    : Theme.of(context).hintColor.withValues(alpha: 0.5),
                size: 20,
              ),
            ),
          ],
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
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 2.5,
                color: widget.isOutgoing ? Colors.white : AppColors.primary,
                backgroundColor: widget.isOutgoing ? Colors.white24 : AppColors.primary.withValues(alpha: 0.2),
              ),
            ),
            Text(
              '${percentage.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: widget.isOutgoing ? Colors.white : AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${_formatBytes(_downloadedBytes)} / ${_formatBytes(_totalBytes)}',
          style: TextStyle(
            fontSize: 8,
            color: widget.isOutgoing ? Colors.white70 : Theme.of(context).hintColor,
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

  String _formatDuration(Duration duration) {
    final mins = duration.inMinutes.toString().padLeft(2, '0');
    final secs = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }
}
