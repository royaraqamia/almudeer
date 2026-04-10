import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'caption_text.dart';
import 'package:almudeer_mobile_app/core/extensions/string_extension.dart';
import 'package:almudeer_mobile_app/features/viewer/presentation/screens/universal_viewer_screen.dart';

import 'package:almudeer_mobile_app/core/services/media_cache_manager.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/animated_toast.dart';

class FileMessageBubble extends StatefulWidget {
  final Map<String, dynamic> attachment;
  final bool isOutgoing;
  final Color color;

  const FileMessageBubble({
    super.key,
    required this.attachment,
    required this.isOutgoing,
    required this.color,
  });

  @override
  State<FileMessageBubble> createState() => _FileMessageBubbleState();
}

class _FileMessageBubbleState extends State<FileMessageBubble> {
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
    // 1. Prioritize local path from attachment (Optimistic/Local Send)
    if (widget.attachment['path'] != null) {
      final String path = widget.attachment['path'];
      // Verify it exists just in case
      // (Optional: use io.File(path).exists())
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
        AnimatedToast.error(context, 'ظپط´ظ„ طھط­ظ…ظٹظ„ ط§ظ„ظ…ظ„ظپ: $e');
      }
    }
  }

  Future<void> _openFile(BuildContext context) async {
    // 1. Try local path directly
    if (_localPath != null) {
      _navigateToViewer(context, _localPath!);
      return;
    }

    // 2. If not local but has URL, download it
    if (!_isDownloading) {
      // Check if we have a path in attachment first (sync issue?)
      if (widget.attachment['path'] != null) {
        _navigateToViewer(context, widget.attachment['path']);
        return;
      }
      await _download();
      // After download, _localPath should be set if successful
      if (_localPath != null && context.mounted) {
        _navigateToViewer(context, _localPath!);
      }
      return;
    }
  }

  void _navigateToViewer(BuildContext context, String path) {
    final filename =
        widget.attachment['filename'] as String? ??
        widget.attachment['file_name'] as String? ??
        'file';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            UniversalViewerScreen(filePath: path, fileName: filename),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final caption = widget.attachment['caption'] as String?;
    final filename =
        widget.attachment['filename'] as String? ??
        widget.attachment['file_name'] as String? ??
        'ظ…ظ„ظپ';
    final size = widget.attachment['file_size'];

    final ext = filename.split('.').last.toLowerCase();
    final fileColor = _getFileColor(ext);
    final fileIcon = _getFileIcon(ext);

    return GestureDetector(
      onTap: () => _openFile(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // File bubble
          Container(
            width: 240,
            padding: const EdgeInsets.all(12),
            margin: caption != null && caption.isNotEmpty
                ? const EdgeInsets.only(bottom: 4)
                : const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: widget.isOutgoing
                  ? widget.color.withValues(alpha: 0.15)
                  : Theme.of(
                      context,
                    ).cardColor,
              borderRadius: caption != null && caption.isNotEmpty
                  ? const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    )
                  : BorderRadius.circular(16),
              border: Border.all(
                color: widget.isOutgoing
                    ? widget.color.withValues(alpha: 0.3)
                    : Theme.of(
                        context,
                      ).dividerColor,
              ),
              boxShadow: [
                if (!widget.isOutgoing &&
                    Theme.of(context).brightness == Brightness.light)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: widget.isOutgoing
                        ? Colors.white.withValues(alpha: 0.2)
                        : fileColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _isDownloading
                      ? _buildDetailedProgressIndicator()
                      : Icon(
                          _localPath != null ? fileIcon : SolarLinearIcons.download,
                          size: 28,
                          color: widget.isOutgoing ? Colors.white : fileColor,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        filename,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.normal,
                          fontSize: 14,
                          height: 1.2,
                          color: widget.isOutgoing ? Colors.white : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr, // Filenames often LTR
                      ),
                      if (size != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _formatBytes(size),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: widget.isOutgoing
                                ? Colors.white.withValues(alpha: 0.8)
                                : Theme.of(context).hintColor,
                            fontSize: 10,
                          ),
                          textDirection: TextDirection.ltr,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Caption
          if (caption != null && caption.isNotEmpty)
            CaptionText(
              caption: caption,
              isOutgoing: widget.isOutgoing,
              theme: Theme.of(context),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailedProgressIndicator() {
    final percentage = _totalBytes > 0
        ? (_downloadedBytes / _totalBytes * 100)
        : 0;
    final progress = _totalBytes > 0 ? (_downloadedBytes / _totalBytes) : 0.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                backgroundColor: isDark ? Colors.white24 : Colors.black12,
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
            color: widget.isOutgoing
                ? Colors.white70
                : Theme.of(context).hintColor,
          ),
        ),
      ],
    );
  }

  Color _getFileColor(String ext) {
    switch (ext) {
      // Documents
      case 'pdf':
        return Colors.red;
      case 'doc':
      case 'docx':
        return Colors.blue;
      case 'ppt':
      case 'pptx':
        return Colors.orange;

      // Spreadsheets
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Colors.green;

      // Archives
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Colors.amber[700]!;

      // Android
      case 'apk':
      case 'aab':
        return Colors.teal;

      // Code - Dart/Flutter
      case 'dart':
        return const Color(0xFF0175C2); // Dart blue

      // Code - Python
      case 'py':
      case 'pyw':
        return const Color(0xFF3776AB); // Python blue

      // Code - JavaScript/TypeScript
      case 'js':
      case 'jsx':
      case 'mjs':
        return const Color(0xFFF7DF1E); // JS yellow
      case 'ts':
      case 'tsx':
        return const Color(0xFF3178C6); // TS blue

      // Code - Web
      case 'html':
      case 'htm':
        return const Color(0xFFE34F26); // HTML orange
      case 'css':
      case 'scss':
      case 'less':
        return const Color(0xFF1572B6); // CSS blue

      // Code - JVM
      case 'java':
        return const Color(0xFFB07219); // Java brown
      case 'kt':
      case 'kts':
        return const Color(0xFF7F52FF); // Kotlin purple

      // Code - Apple
      case 'swift':
        return const Color(0xFFFA7343); // Swift orange

      // Code - Systems
      case 'go':
        return const Color(0xFF00ADD8); // Go cyan
      case 'rs':
        return const Color(0xFFDEA584); // Rust orange
      case 'c':
      case 'h':
        return const Color(0xFF555555); // C gray
      case 'cpp':
      case 'hpp':
        return const Color(0xFF00599C); // C++ blue

      // Code - Ruby/PHP
      case 'rb':
        return const Color(0xFFCC342D); // Ruby red
      case 'php':
        return const Color(0xFF777BB4); // PHP purple

      // Shell
      case 'sh':
      case 'bash':
      case 'zsh':
      case 'bat':
      case 'cmd':
      case 'ps1':
        return Colors.grey[700]!;

      // Data/Config
      case 'json':
        return const Color(0xFF292929);
      case 'yaml':
      case 'yml':
        return const Color(0xFFCB171E);
      case 'xml':
        return const Color(0xFF0060AC);
      case 'sql':
        return const Color(0xFFCC7A00);

      // Markdown
      case 'md':
      case 'markdown':
        return const Color(0xFF083FA1);

      // Plain text
      case 'txt':
      case 'log':
        return Colors.grey[600]!;

      default:
        return AppColors.primary;
    }
  }

  IconData _getFileIcon(String ext) {
    switch (ext) {
      // Documents
      case 'pdf':
        return SolarBoldIcons.fileText;
      case 'doc':
      case 'docx':
        return SolarBoldIcons.documentText;
      case 'ppt':
      case 'pptx':
        return SolarBoldIcons.presentationGraph;

      // Spreadsheets
      case 'xls':
      case 'xlsx':
      case 'csv':
        return SolarBoldIcons.chartSquare;

      // Archives
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return SolarBoldIcons.archive;

      // Android/Mobile
      case 'apk':
      case 'aab':
        return SolarBoldIcons.smartphone;

      // Code files
      case 'dart':
      case 'py':
      case 'pyw':
      case 'js':
      case 'jsx':
      case 'mjs':
      case 'ts':
      case 'tsx':
      case 'java':
      case 'kt':
      case 'kts':
      case 'swift':
      case 'go':
      case 'rs':
      case 'c':
      case 'h':
      case 'cpp':
      case 'hpp':
      case 'rb':
      case 'php':
      case 'scala':
      case 'groovy':
      case 'lua':
      case 'r':
        return SolarBoldIcons.code2;

      // Web
      case 'html':
      case 'htm':
      case 'css':
      case 'scss':
      case 'less':
      case 'vue':
      case 'svelte':
        return SolarBoldIcons.code;

      // Shell/Scripts
      case 'sh':
      case 'bash':
      case 'zsh':
      case 'bat':
      case 'cmd':
      case 'ps1':
        return SolarBoldIcons.code2;

      // Data/Config
      case 'json':
      case 'yaml':
      case 'yml':
      case 'xml':
      case 'toml':
      case 'ini':
      case 'conf':
      case 'cfg':
      case 'env':
        return SolarBoldIcons.settings;

      // Database
      case 'sql':
        return SolarBoldIcons.database;

      // Markdown/Docs
      case 'md':
      case 'markdown':
      case 'txt':
      case 'log':
        return SolarBoldIcons.notebook;

      default:
        return SolarBoldIcons.file;
    }
  }

  String _formatBytes(dynamic size) {
    if (size == null) return '';
    try {
      final int bytes = size is int ? size : int.parse(size.toString());
      if (bytes <= 0) return '0 B';
      const suffixes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];
      // rough log1000 calculation removed, using loop below
      // Actually implementing proper loop is safer
      int iSafety = 0;
      double dBytes = bytes.toDouble();
      while (dBytes >= 1024 && iSafety < suffixes.length - 1) {
        dBytes /= 1024;
        iSafety++;
      }
      return '${dBytes.toStringAsFixed(1)} ${suffixes[iSafety]}';
    } catch (e) {
      return '';
    }
  }
}
