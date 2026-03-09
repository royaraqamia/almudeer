import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

class MediaCacheManager {
  static final MediaCacheManager _instance = MediaCacheManager._internal();
  static MediaCacheManager? _mockInstance;
  static set mockInstance(MediaCacheManager? mock) => _mockInstance = mock;
  factory MediaCacheManager() => _mockInstance ?? _instance;
  MediaCacheManager._internal();

  // Issue #25: Cache size limits
  static const int maxCacheSizeBytes = 100 * 1024 * 1024; // 100MB default
  static const int cacheCleanupThreshold = 80; // Cleanup when 80% full
  
  // P0 FIX: Maximum individual file size to prevent storage exhaustion
  static const int maxFileSizeBytes = 100 * 1024 * 1024; // 100MB per file

  final _dio = Dio();
  final _imageCacheManager = DefaultCacheManager();
  bool _isCleaningUp = false;

  /// Checks if an image is cached in `flutter_cache_manager`
  Future<bool> isImageCached(String url) async {
    final fileInfo = await _imageCacheManager.getFileFromCache(url);
    return fileInfo != null;
  }

  /// Generates a stable, unique filename for a given URL
  String _generateFileName(String url, {String? filename}) {
    if (url.isEmpty) return 'unknown_file';

    // 1. Get extension from URL or explicit filename
    String extension = '';
    final parsedUri = Uri.parse(url);
    final urlPath = parsedUri.path;

    if (filename != null && filename.contains('.')) {
      extension = p.extension(filename);
    } else if (urlPath.contains('.')) {
      extension = p.extension(urlPath);
    }

    // 2. Generate a stable hash to prevent collisions.
    // We use the URL without query parameters to handle dynamic tokens/timestamps,
    // assuming the base path is unique enough.
    final stableUrlPart =
        '${parsedUri.scheme}://${parsedUri.host}${parsedUri.path}';
    final hash = sha256
        .convert(utf8.encode(stableUrlPart))
        .toString()
        .substring(0, 16);

    // 3. Combine hash with extension
    return 'media_$hash$extension';
  }

  /// Gets the path where a file would be stored (even if it doesn't exist yet)
  Future<String> getPredictedPath(String url, {String? filename}) async {
    final name = _generateFileName(url, filename: filename);
    final dir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory('${dir.path}/media');
    return '${mediaDir.path}/$name';
  }

  /// Checks if a file exists locally in the app's persistent storage
  Future<String?> getLocalPath(String url, {String? filename}) async {
    if (url.isEmpty) return null;

    final name = _generateFileName(url, filename: filename);
    final dir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory('${dir.path}/media');

    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }

    final file = File('${mediaDir.path}/$name');
    if (await file.exists()) {
      return file.path;
    }
    return null;
  }

  /// Downloads a file to the local media directory
  Future<String> downloadFile(
    String url, {
    String? filename,
    Function(double)? onProgress,
    Function(int received, int total)? onProgressBytes,
  }) async {
    final name = _generateFileName(url, filename: filename);
    final dir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory('${dir.path}/media');

    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }

    final savePath = '${mediaDir.path}/$name';

    // Check if already downloaded (race condition safety)
    if (await File(savePath).exists()) {
      return savePath;
    }

    // P0 FIX: Check file size before downloading
    int totalBytes = 0;
    try {
      final response = await _dio.head(url);
      final contentLength = response.headers.value('content-length');
      if (contentLength != null) {
        totalBytes = int.tryParse(contentLength) ?? 0;
        if (totalBytes > maxFileSizeBytes) {
          throw Exception(
            'حجم الملف كبير جداً (${(totalBytes / 1024 / 1024).toStringAsFixed(1)} ميجابايت). '
            'الحد الأقصى هو ${maxFileSizeBytes ~/ 1024 ~/ 1024} ميجابايت',
          );
        }
      }
    } catch (e) {
      if (e.toString().contains('حجم الملف')) {
        rethrow; // Re-throw size errors
      }
      // Continue if we can't get content-length (some servers don't provide it)
    }

    final tempPath = '$savePath.part';

    try {
      await _dio.download(
        url,
        tempPath,
        onReceiveProgress: (received, total) {
          if (total != -1 && onProgress != null) {
            // P0 FIX: Check if we exceed size during download
            if (total > maxFileSizeBytes) {
              throw Exception(
                'حجم الملف كبير جداً (${(total / 1024 / 1024).toStringAsFixed(1)} ميجابايت)',
              );
            }
            onProgress(received / total);
          }
          // P0: Provide bytes-level progress callback
          if (onProgressBytes != null) {
            onProgressBytes(received, total);
          }
        },
      );

      // Atomically move the file to its final destination
      final tempFile = File(tempPath);
      if (await tempFile.exists()) {
        await tempFile.rename(savePath);
      }
      return savePath;
    } catch (e) {
      // Cleanup partial file on error
      final tempFile = File(tempPath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      rethrow;
    }
  }

  /// Specialized image download into `flutter_cache_manager`
  Future<void> downloadImage(String url) async {
    await _imageCacheManager.downloadFile(url);
  }

  /// Manually place a file in the cache (e.g. after uploading)
  /// Issue #25: Checks cache size and triggers cleanup if needed
  Future<File> putFile(String url, File sourceFile, {String? filename}) async {
    final name = _generateFileName(url, filename: filename);
    final dir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory('${dir.path}/media');

    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }

    final savePath = '${mediaDir.path}/$name';
    
    // Check cache size before adding new file
    await _checkAndCleanupCache();
    
    final newFile = await sourceFile.copy(savePath);
    return newFile;
  }

  /// Issue #25: Check cache size and cleanup if threshold exceeded
  Future<void> _checkAndCleanupCache() async {
    if (_isCleaningUp) return; // Prevent concurrent cleanups

    try {
      final currentSize = await getCacheSize();
      final thresholdBytes = (maxCacheSizeBytes * cacheCleanupThreshold / 100).round();

      if (currentSize >= thresholdBytes) {
        debugPrint(
          '[MediaCacheManager] Cache size ($currentSize bytes) exceeds threshold ($thresholdBytes bytes). Cleaning up...',
        );
        await _cleanupCacheByAge();
      }
    } catch (e) {
      debugPrint('[MediaCacheManager] Error checking cache size: $e');
    }
  }

  /// Issue #25: Cleanup oldest files when cache is full
  Future<void> _cleanupCacheByAge() async {
    if (_isCleaningUp) return;
    _isCleaningUp = true;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory('${dir.path}/media');

      if (!await mediaDir.exists()) return;

      // Get all files with their modification dates
      final files = <File, DateTime>{};
      await for (var entity in mediaDir.list(recursive: true)) {
        if (entity is File) {
          files[entity] = await entity.lastModified();
        }
      }

      if (files.isEmpty) return;

      // Sort by modification date (oldest first)
      final sortedFiles = files.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      int currentSize = await getCacheSize();
      final targetSize = (maxCacheSizeBytes * 0.5).round(); // Reduce to 50%

      int deletedCount = 0;
      for (var entry in sortedFiles) {
        if (currentSize <= targetSize) break;

        try {
          final fileSize = await entry.key.length();
          await entry.key.delete();
          currentSize -= fileSize;
          deletedCount++;
        } catch (e) {
          debugPrint('Error deleting old cache file: $e');
        }
      }

      debugPrint('[MediaCacheManager] Cleaned up $deletedCount old files. New size: $currentSize bytes');
    } catch (e) {
      debugPrint('[MediaCacheManager] Error during age-based cleanup: $e');
    } finally {
      _isCleaningUp = false;
    }
  }

  /// Get total cache size in bytes
  Future<int> getCacheSize() async {
    final dir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory('${dir.path}/media');

    if (!await mediaDir.exists()) {
      return 0;
    }

    int totalSize = 0;
    await for (var entity in mediaDir.list(recursive: true)) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }
    return totalSize;
  }

  /// P3-15 FIX: Startup cache cleanup - runs when app initializes
  /// Ensures cache doesn't grow unbounded even if app is force-closed frequently
  Future<void> performStartupCleanup() async {
    if (_isCleaningUp) return; // Prevent concurrent cleanups
    
    try {
      debugPrint('[MediaCacheManager] Performing startup cache cleanup...');

      final currentSize = await getCacheSize();
      final thresholdBytes = (maxCacheSizeBytes * cacheCleanupThreshold / 100).round();
      
      if (currentSize >= thresholdBytes) {
        debugPrint(
          '[MediaCacheManager] Cache size ($currentSize bytes) exceeds threshold ($thresholdBytes bytes). Cleaning up...',
        );
        await _cleanupCacheByAge();
      } else {
        debugPrint(
          '[MediaCacheManager] Cache size ($currentSize bytes) is within limits. No cleanup needed.',
        );
      }
      
      // P3-15 FIX: Also cleanup orphaned files older than 30 days regardless of size
      await _cleanupOrphanedFiles();
      
    } catch (e) {
      debugPrint('[MediaCacheManager] Error during startup cleanup: $e');
    }
  }

  /// P3-15 FIX: Cleanup orphaned files (files without database references)
  /// This handles cases where messages were deleted but attachments remain
  Future<void> _cleanupOrphanedFiles() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory('${dir.path}/media');

      if (!await mediaDir.exists()) return;

      int deletedCount = 0;
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));

      await for (var entity in mediaDir.list(recursive: true)) {
        if (entity is File) {
          final lastModified = await entity.lastModified();
          if (lastModified.isBefore(thirtyDaysAgo)) {
            try {
              await entity.delete();
              deletedCount++;
            } catch (e) {
              debugPrint('Error deleting orphaned file: $e');
            }
          }
        }
      }

      if (deletedCount > 0) {
        debugPrint('[MediaCacheManager] Deleted $deletedCount orphaned files older than 30 days');
      }
    } catch (e) {
      debugPrint('[MediaCacheManager] Error during orphaned file cleanup: $e');
    }
  }

  /// Clean up old cached files (older than specified days)
  Future<int> cleanupOldCache({int olderThanDays = 7}) async {
    final dir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory('${dir.path}/media');

    if (!await mediaDir.exists()) {
      return 0;
    }

    final cutoffDate = DateTime.now().subtract(Duration(days: olderThanDays));
    int deletedCount = 0;

    await for (var entity in mediaDir.list(recursive: true)) {
      if (entity is File) {
        final modifiedDate = await entity.lastModified();
        if (modifiedDate.isBefore(cutoffDate)) {
          try {
            await entity.delete();
            deletedCount++;
          } catch (e) {
            debugPrint('Error deleting cached file: $e');
          }
        }
      }
    }

    return deletedCount;
  }

  /// Clear all cached media files
  Future<int> clearCache() async {
    final dir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory('${dir.path}/media');

    if (!await mediaDir.exists()) {
      return 0;
    }

    int deletedCount = 0;
    await for (var entity in mediaDir.list(recursive: true)) {
      if (entity is File) {
        try {
          await entity.delete();
          deletedCount++;
        } catch (e) {
          debugPrint('Error deleting cached file: $e');
        }
      }
    }

    return deletedCount;
  }

  /// Clear flutter_cache_manager image cache
  Future<void> clearImageCache() async {
    await _imageCacheManager.emptyCache();
  }
}
