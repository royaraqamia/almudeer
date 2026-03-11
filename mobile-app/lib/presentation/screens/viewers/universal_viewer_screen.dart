import 'dart:io';

import 'package:flutter/material.dart';

import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:open_filex/open_filex.dart'; // Fallback
import 'package:path/path.dart' as p;

import '../../../core/constants/colors.dart';
import '../../../core/services/media_cache_manager.dart';
import '../inbox/image_viewer_screen.dart';
import 'pdf_viewer_screen.dart';
import 'video_player_screen.dart';
import 'text_viewer_screen.dart';
import 'audio_player_screen.dart';
import 'code_viewer_screen.dart';
import 'csv_viewer_screen.dart';
import 'excel_viewer_screen.dart';
import '../../../core/extensions/string_extension.dart';

class UniversalViewerScreen extends StatefulWidget {
  final String? url;
  final String? filePath;
  final String? fileName;
  final String? fileType;
  final String? heroTag;

  const UniversalViewerScreen({
    super.key,
    this.url,
    this.filePath,
    this.fileName,
    this.fileType,
    this.heroTag,
  }) : assert(
         url != null || filePath != null,
         'Must provide either url or filePath',
       );

  @override
  State<UniversalViewerScreen> createState() => _UniversalViewerScreenState();
}

class _UniversalViewerScreenState extends State<UniversalViewerScreen> {
  bool _isLoading = true;
  String? _localPath;
  String? _errorMessage;
  String _fileType = 'unknown';

  String? _sanitizedUrl;

  @override
  void initState() {
    super.initState();
    _sanitizedUrl = widget.url?.toFullUrl;
    _prepareFile();
  }

  Future<void> _prepareFile() async {
    try {
      String name = widget.fileName ?? 'file';

      // Initialize path and name from widget inputs immediately
      if (widget.filePath != null) {
        _localPath = widget.filePath;
        name = p.basename(widget.filePath!);
      } else if (_sanitizedUrl != null) {
        name = widget.fileName ?? p.basename(Uri.parse(_sanitizedUrl!).path);
      }

      // 1. Determine Type
      if (widget.fileType != null) {
        _fileType = widget.fileType!;
      }

      // Always do extension-based detection for generic types like 'file', 'unknown', or null
      // This ensures code files from Library/Inbox get properly routed to specialized viewers
      final needsExtensionDetection =
          _fileType == 'unknown' ||
          _fileType == 'file' ||
          _fileType == 'other' ||
          widget.fileType == null;

      if (needsExtensionDetection) {
        final String extension = p
            .extension(name)
            .toLowerCase()
            .replaceAll('.', '');

        if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(extension)) {
          _fileType = 'image';
        } else if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(extension)) {
          _fileType = 'video';
        } else if ([
          'mp3',
          'wav',
          'aac',
          'm4a',
          'flac',
          'ogg',
          'wma',
        ].contains(extension)) {
          _fileType = 'audio';
        } else if (extension == 'pdf') {
          _fileType = 'pdf';
        } else if (extension == 'csv') {
          _fileType = 'csv';
        } else if (['xlsx', 'xls'].contains(extension)) {
          _fileType = 'excel';
        } else if ([
          // Programming languages
          'dart', 'py', 'pyw', 'js', 'jsx', 'mjs', 'ts', 'tsx',
          'java', 'kt', 'kts', 'swift', 'go', 'rs', 'rb', 'php',
          'c', 'h', 'cpp', 'hpp', 'cc', 'cxx', 'm', 'mm',
          'scala', 'groovy', 'lua', 'pl', 'r',
          // Web
          'html', 'htm', 'css', 'scss', 'less', 'vue', 'svelte',
          // Shell/Scripts
          'sh', 'bash', 'zsh', 'bat', 'cmd', 'ps1',
          // Data/Config
          'json', 'yaml', 'yml', 'xml', 'toml', 'ini', 'conf', 'cfg', 'env',
          'properties', 'gradle', 'cmake', 'makefile', 'dockerfile',
          // Database
          'sql',
          // Docs
          'md', 'markdown', 'rst',
        ].contains(extension)) {
          _fileType = 'code';
        } else if (['txt', 'log'].contains(extension)) {
          _fileType = 'text';
        } else {
          if (_fileType == 'unknown') _fileType = 'other';
        }
      }

      // 2. Check Cache / Download if needed
      if (_localPath == null && _sanitizedUrl != null) {
        final cachedPath = await MediaCacheManager().getLocalPath(
          _sanitizedUrl!,
          filename: name,
        );
        if (cachedPath != null) {
          _localPath = cachedPath;
        } else {
          // Download if it's a type that requires local access or if we want it persistent
          final typesNeedingDownload = ['pdf', 'code', 'csv', 'text', 'other'];
          if (typesNeedingDownload.contains(_fileType)) {
            await _downloadFile(_sanitizedUrl!, name);
          }
        }
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error preparing file: $e';
        });
      }
    }
  }

  Future<void> _downloadFile(String url, String fileName) async {
    try {
      final path = await MediaCacheManager().downloadFile(
        url,
        filename: fileName,
      );

      if (mounted) {
        setState(() {
          _localPath = path;
        });
      }
    } catch (e) {
      throw Exception('Download failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(
              SolarLinearIcons.arrowRight,
              color: Colors.white,
              size: 24,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                SolarLinearIcons.dangerCircle,
                color: AppColors.error,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white70, fontSize: 20),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
              const SizedBox(height: 24),
              Text(
                'جاري تحضير الملف...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontFamily: 'IBM Plex Sans Arabic',
                  fontSize: 24,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Centralized Immersive Wrapper
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      child: _buildViewer(),
    );
  }

  Widget _buildViewer() {
    switch (_fileType) {
      case 'image':
        return ImageViewerScreen(
          imageUrl: _sanitizedUrl,
          imageFile: _localPath != null ? File(_localPath!) : null,
          heroTag: widget.heroTag ?? 'file_viewer_${DateTime.now()}',
        );

      case 'video':
        return VideoPlayerScreen(
          videoUrl: _sanitizedUrl,
          videoFile: _localPath != null ? File(_localPath!) : null,
        );

      case 'pdf':
        if (_localPath != null) {
          return PdfViewerScreen(
            filePath: _localPath!,
            fileName: widget.fileName ?? 'PDF',
          );
        }
        return const Scaffold(body: Center(child: Text('Could not load PDF')));

      case 'text':
        if (_localPath != null) {
          return TextViewerScreen(
            filePath: _localPath!,
            fileName: widget.fileName ?? 'Text File',
          );
        }
        return const Scaffold(
          body: Center(child: Text('Could not load text file')),
        );

      case 'audio':
        return AudioPlayerScreen(
          audioUrl: _sanitizedUrl,
          filePath: _localPath,
          fileName: widget.fileName ?? 'Audio',
        );

      case 'code':
        if (_localPath != null) {
          return CodeViewerScreen(
            filePath: _localPath!,
            fileName: widget.fileName ?? 'Code',
          );
        }
        return const Scaffold(
          body: Center(child: Text('Could not load code file')),
        );

      case 'csv':
        if (_localPath != null) {
          return CsvViewerScreen(
            filePath: _localPath!,
            fileName: widget.fileName ?? 'CSV',
          );
        }
        return const Scaffold(
          body: Center(child: Text('Could not load CSV file')),
        );

      case 'excel':
        if (_localPath != null) {
          return ExcelViewerScreen(
            filePath: _localPath!,
            fileName: widget.fileName ?? 'Excel',
          );
        }
        return const Scaffold(
          body: Center(child: Text('Could not load Excel file')),
        );

      default:
        return _buildFallbackViewer();
    }
  }

  Widget _buildFallbackViewer() {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName ?? 'File'),
        leading: IconButton(
          icon: const Icon(SolarLinearIcons.arrowRight, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(SolarLinearIcons.file, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('No internal viewer for this file type.'),
            const SizedBox(height: 16),
            if (_localPath != null)
              ElevatedButton(
                onPressed: () {
                  OpenFilex.open(_localPath!);
                },
                child: const Text('Open with External App'),
              ),
          ],
        ),
      ),
    );
  }
}
