import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../../../core/constants/colors.dart';
import '../../../core/constants/viewer_constants.dart';
import '../../../core/services/media_cache_manager.dart';
import '../../../core/services/network_connectivity_service.dart';
import '../../../core/utils/premium_toast.dart';
import '../inbox/image_viewer_screen.dart';
import 'pdf_viewer_screen.dart';
import 'video_player_screen.dart';
import 'text_viewer_screen.dart';
import 'audio_player_screen.dart';
import 'code_viewer_screen.dart';
import 'csv_viewer_screen.dart';
import 'excel_viewer_screen.dart';
import '../../../core/extensions/string_extension.dart';

/// Global download queue to prevent concurrent downloads
class _DownloadQueue {
  static final _DownloadQueue _instance = _DownloadQueue._internal();
  factory _DownloadQueue() => _instance;
  _DownloadQueue._internal();

  final Set<String> _downloadingUrls = {};
  final Map<String, String> _downloadedPaths = {};

  bool isDownloading(String url) => _downloadingUrls.contains(url);
  String? getCachedPath(String url) => _downloadedPaths[url];

  void startDownload(String url) {
    _downloadingUrls.add(url);
  }

  void completeDownload(String url, String path) {
    _downloadingUrls.remove(url);
    _downloadedPaths[url] = path;
  }

  void failDownload(String url) {
    _downloadingUrls.remove(url);
  }

  void clear() {
    _downloadingUrls.clear();
    _downloadedPaths.clear();
  }
}

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

class _UniversalViewerScreenState extends State<UniversalViewerScreen>
    with RestorationMixin {
  bool _isLoading = true;
  String? _localPath;
  String? _errorMessage;
  String _fileType = 'unknown';
  String? _sanitizedUrl;
  double _downloadProgress = 0.0;
  bool _isDownloading = false;
  bool _isPreparing = false; // Prevent duplicate preparation

  // Restorable properties
  final RestorableStringN _restorableLocalPath = RestorableStringN(null);
  final RestorableStringN _restorableErrorMessage = RestorableStringN(null);
  final RestorableString _restorableFileType = RestorableString('unknown');
  final RestorableBool _restorableIsLoading = RestorableBool(true);
  final RestorableBool _restorableIsDownloading = RestorableBool(false);
  final RestorableDouble _restorableDownloadProgress = RestorableDouble(0.0);

  @override
  String? get restorationId => 'universal_viewer_${widget.hashCode}';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_restorableLocalPath, 'local_path');
    registerForRestoration(_restorableErrorMessage, 'error_message');
    registerForRestoration(_restorableFileType, 'file_type');
    registerForRestoration(_restorableIsLoading, 'is_loading');
    registerForRestoration(_restorableIsDownloading, 'is_downloading');
    registerForRestoration(_restorableDownloadProgress, 'download_progress');

    // Restore state
    if (_restorableLocalPath.value != null) {
      _localPath = _restorableLocalPath.value;
    }
    _errorMessage = _restorableErrorMessage.value;
    _fileType = _restorableFileType.value;
    _isLoading = _restorableIsLoading.value;
    _isDownloading = _restorableIsDownloading.value;
    _downloadProgress = _restorableDownloadProgress.value;
  }

  @override
  void dispose() {
    // Clean up download state if widget is disposed during download
    if (_sanitizedUrl != null && _isDownloading) {
      _DownloadQueue().failDownload(_sanitizedUrl!);
    }
    _restorableLocalPath.dispose();
    _restorableErrorMessage.dispose();
    _restorableFileType.dispose();
    _restorableIsLoading.dispose();
    _restorableIsDownloading.dispose();
    _restorableDownloadProgress.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _sanitizedUrl = widget.url?.toFullUrl;
    // Don't call _prepareFile() here - it will be called after restoreState
    // to ensure correct state restoration
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    debugPrint('[UniversalViewer] didChangeDependencies: _isPreparing=$_isPreparing, _sanitizedUrl=$_sanitizedUrl');
    
    // Call _prepareFile() after restoration is complete
    // This ensures we don't overwrite restored state
    if (!_isPreparing && (_sanitizedUrl != null || widget.filePath != null)) {
      debugPrint('[UniversalViewer] Calling _prepareFile from didChangeDependencies');
      _isPreparing = true;
      _prepareFile();
    }
  }

  // Helper to update state and persist it
  void _updateState({
    String? localPath,
    String? errorMessage,
    String? fileType,
    bool? isLoading,
    bool? isDownloading,
    double? downloadProgress,
  }) {
    setState(() {
      if (localPath != null) {
        _localPath = localPath;
        _restorableLocalPath.value = localPath;
      }
      if (errorMessage != null) {
        _errorMessage = errorMessage;
        _restorableErrorMessage.value = errorMessage;
      }
      if (fileType != null) {
        _fileType = fileType;
        _restorableFileType.value = fileType;
      }
      if (isLoading != null) {
        _isLoading = isLoading;
        _restorableIsLoading.value = isLoading;
      }
      if (isDownloading != null) {
        _isDownloading = isDownloading;
        _restorableIsDownloading.value = isDownloading;
      }
      if (downloadProgress != null) {
        _downloadProgress = downloadProgress;
        _restorableDownloadProgress.value = downloadProgress;
      }
    });
  }

  Future<void> _prepareFile() async {
    debugPrint('[UniversalViewer] _prepareFile started');
    debugPrint('[UniversalViewer] _isPreparing=$_isPreparing, widget.filePath=${widget.filePath}, widget.url=${widget.url}');
    
    try {
      String name = widget.fileName ?? 'file';

      // Initialize path and name from widget inputs immediately
      if (widget.filePath != null) {
        _localPath = widget.filePath;
        name = p.basename(widget.filePath!);
      } else if (_sanitizedUrl != null) {
        // Extract filename from URL if not provided
        final urlPath = Uri.parse(_sanitizedUrl!).path;
        final urlFilename = p.basename(urlPath);
        // Use URL filename if it has an extension and widget.fileName doesn't
        if (p.extension(urlFilename).isNotEmpty && 
            (widget.fileName == null || p.extension(widget.fileName!).isEmpty)) {
          name = urlFilename;
        } else if (widget.fileName != null) {
          name = widget.fileName!;
        } else {
          name = urlFilename;
        }
      }

      // Debug logging
      debugPrint('[UniversalViewer] Initial state:');
      debugPrint('  - fileName: $name');
      debugPrint('  - filePath: ${widget.filePath}');
      debugPrint('  - url: ${widget.url}');
      debugPrint('  - fileType: ${widget.fileType}');
      debugPrint('  - sanitizedUrl: $_sanitizedUrl');

      // 1. Determine Type
      if (widget.fileType != null) {
        _fileType = widget.fileType!;
      }

      debugPrint('[UniversalViewer] After initial type assignment: $_fileType');

      // Always do extension-based detection for generic types
      // Also detect specific types from extension for better accuracy
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

        debugPrint('[UniversalViewer] Extension detected: $extension');

        if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(extension)) {
          _fileType = 'image';
        } else if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(extension)) {
          _fileType = 'video';
        } else if ([
          'mp3', 'wav', 'aac', 'm4a', 'flac', 'ogg', 'wma',
        ].contains(extension)) {
          _fileType = 'audio';
        } else if (extension == 'pdf') {
          _fileType = 'pdf';
        } else if (extension == 'csv') {
          _fileType = 'csv';
        } else if (['xlsx', 'xls'].contains(extension)) {
          _fileType = 'excel';
        } else if ([
          'dart', 'py', 'pyw', 'js', 'jsx', 'mjs', 'ts', 'tsx',
          'java', 'kt', 'kts', 'swift', 'go', 'rs', 'rb', 'php',
          'c', 'h', 'cpp', 'hpp', 'cc', 'cxx', 'm', 'mm',
          'scala', 'groovy', 'lua', 'pl', 'r',
          'html', 'htm', 'css', 'scss', 'less', 'vue', 'svelte',
          'sh', 'bash', 'zsh', 'bat', 'cmd', 'ps1',
          'json', 'yaml', 'yml', 'xml', 'toml', 'ini', 'conf', 'cfg', 'env',
          'properties', 'gradle', 'cmake', 'makefile', 'dockerfile',
          'sql', 'md', 'markdown', 'rst',
        ].contains(extension)) {
          _fileType = 'code';
        } else if (['txt', 'log'].contains(extension)) {
          _fileType = 'text';
        } else {
          // Unknown extension - set to 'other' for external viewer
          _fileType = 'other';
        }

        debugPrint('[UniversalViewer] After extension detection: $_fileType');
      } else {
        debugPrint('[UniversalViewer] Skipping extension detection for type: $_fileType');
      }

      // 2. Check Cache / Download if needed
      debugPrint('[UniversalViewer] Checking cache/download: _localPath=$_localPath, _sanitizedUrl=$_sanitizedUrl');
      
      if (_localPath == null && _sanitizedUrl != null) {
        debugPrint('[UniversalViewer] Getting cached path for: $_sanitizedUrl');
        
        final cachedPath = await MediaCacheManager().getLocalPath(
          _sanitizedUrl!,
          filename: name,
        );
        
        debugPrint('[UniversalViewer] Cached path result: $cachedPath');
        
        if (cachedPath != null) {
          _localPath = cachedPath;
          debugPrint('[UniversalViewer] Using cached path: $_localPath');
        } else {
          debugPrint('[UniversalViewer] No cache, checking if needs download. fileType=$_fileType');
          
          // Download if it's a type that requires local access
          // Include 'file' for generic files from backend
          final typesNeedingDownload = [
            'pdf', 'code', 'csv', 'text', 'other', 'excel', 'file'
          ];
          
          if (typesNeedingDownload.contains(_fileType)) {
            debugPrint('[UniversalViewer] Starting download for: $_sanitizedUrl');
            await _downloadFileWithProgress(_sanitizedUrl!, name);
            debugPrint('[UniversalViewer] Download completed');
          } else {
            debugPrint('[UniversalViewer] Type $_fileType does not need download');
          }
        }
      } else {
        debugPrint('[UniversalViewer] Skipping cache/download check');
      }

      debugPrint('[UniversalViewer] About to update state, isLoading=false');
      
      if (mounted) {
        _updateState(
          isLoading: false,
          isDownloading: false,
          downloadProgress: 0.0,
        );
        // Update restorable file type after successful preparation
        _restorableFileType.value = _fileType;
        debugPrint('[UniversalViewer] State updated successfully');
      } else {
        debugPrint('[UniversalViewer] Widget not mounted, skipping state update');
      }
    } catch (e) {
      debugPrint('[UniversalViewer] Error in _prepareFile: $e');
      if (mounted) {
        _updateState(
          isLoading: false,
          isDownloading: false,
          downloadProgress: 0.0,
          errorMessage: 'Error preparing file: $e',
        );
      }
    }
  }

  Future<void> _downloadFileWithProgress(String url, String fileName) async {
    final queue = _DownloadQueue();

    // Check if already downloading
    if (queue.isDownloading(url)) {
      // Wait for existing download to complete
      while (queue.isDownloading(url)) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          _updateState(isDownloading: true);
        }
      }
      // Check if download succeeded
      final cachedPath = queue.getCachedPath(url);
      if (cachedPath != null) {
        _updateState(localPath: cachedPath);
        return;
      }
    }

    // Check connectivity before starting download
    final connectivity = NetworkConnectivityService();
    final isConnected = await connectivity.isConnected;
    if (!isConnected) {
      throw Exception('لا يوجد اتصال بالإنترنت. يرجى التحقق من اتصالك والمحاولة مرة أخرى.');
    }

    // Warn if using mobile data for large files
    final isWifi = await connectivity.isWifiConnected;
    if (!isWifi && mounted) {
      // Show warning but continue
      PremiumToast.show(
        context,
        'جاري التحميل باستخدام بيانات الجوال',
        icon: SolarLinearIcons.cloud,
      );
    }

    // Start download with queue management
    queue.startDownload(url);
    _updateState(isDownloading: true, downloadProgress: 0.0);

    try {
      // Download with progress tracking (simplified - actual implementation would use Dio with progress)
      final path = await MediaCacheManager().downloadFile(
        url,
        filename: fileName,
      ).timeout(
        ViewerConstants.downloadTimeout,
        onTimeout: () {
          throw TimeoutException(
            'Download timed out after ${ViewerConstants.downloadTimeout.inSeconds} seconds',
          );
        },
      );

      if (mounted) {
        _updateState(
          localPath: path,
          isDownloading: false,
          downloadProgress: 1.0,
        );
        queue.completeDownload(url, path);
      }
    } catch (e) {
      queue.failDownload(url);
      if (mounted) {
        _updateState(isDownloading: false, downloadProgress: 0.0);
      }
      rethrow;
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
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _errorMessage = null;
                  });
                  _prepareFile();
                },
                icon: const Icon(SolarLinearIcons.refresh),
                label: const Text('إعادة المحاولة'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading || _isDownloading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isDownloading) ...[
                SizedBox(
                  width: 200,
                  child: Column(
                    children: [
                      CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 4,
                        value: _downloadProgress > 0 ? _downloadProgress : null,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _downloadProgress > 0
                            ? '${(_downloadProgress * 100).toInt()}%'
                            : 'جاري التحميل...',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontFamily: 'IBM Plex Sans Arabic',
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'جاري تحضير الملف...',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontFamily: 'IBM Plex Sans Arabic',
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
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
    debugPrint('[UniversalViewer] _buildViewer called:');
    debugPrint('  - fileType: $_fileType');
    debugPrint('  - _localPath: $_localPath');
    debugPrint('  - fileName: ${widget.fileName}');
    debugPrint('  - url: ${widget.url}');
    
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
        return _buildErrorState('Could not load PDF');

      case 'text':
        if (_localPath != null) {
          return TextViewerScreen(
            filePath: _localPath!,
            fileName: widget.fileName ?? 'Text File',
          );
        }
        return _buildErrorState('Could not load text file');

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
        return _buildErrorState('Could not load code file');

      case 'csv':
        if (_localPath != null) {
          return CsvViewerScreen(
            filePath: _localPath!,
            fileName: widget.fileName ?? 'CSV',
          );
        }
        return _buildErrorState('Could not load CSV file');

      case 'excel':
        if (_localPath != null) {
          return ExcelViewerScreen(
            filePath: _localPath!,
            fileName: widget.fileName ?? 'Excel',
          );
        }
        return _buildErrorState('Could not load Excel file');

      // Treat 'file' and 'unknown' as 'other' for external viewer
      case 'file':
      case 'unknown':
      default:
        return _buildFallbackViewer();
    }
  }

  Widget _buildErrorState(String message) {
    return Scaffold(
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
              color: Colors.white54,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackViewer() {
    return Scaffold(
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
        title: Text(widget.fileName ?? 'File'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(SolarLinearIcons.file, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _localPath == null
                  ? 'Unable to load file. Please check your connection and try again.'
                  : 'No internal viewer for this file type.',
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (_localPath != null)
              ElevatedButton.icon(
                onPressed: () {
                  OpenFilex.open(_localPath!);
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open with External App'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              )
            else if (widget.url != null)
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _errorMessage = null;
                  });
                  _prepareFile();
                },
                icon: const Icon(SolarLinearIcons.refresh),
                label: const Text('Retry Download'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
