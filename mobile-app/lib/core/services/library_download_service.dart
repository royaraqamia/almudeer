import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

/// P1-5: Library download service with resume capability
///
/// Supports:
/// - HTTP Range Requests for resuming interrupted downloads
/// - Progress tracking
/// - Persistent download state across app restarts
/// - Concurrent download management
/// - FIX #13: Automatic retry with exponential backoff for transient failures
class LibraryDownloadService {
  static final LibraryDownloadService _instance = LibraryDownloadService._internal();
  static Database? _database;

  factory LibraryDownloadService() => _instance;

  LibraryDownloadService._internal();

  // FIX #13: Retry configuration
  static const int _maxRetries = 3;
  static const Duration _initialRetryDelay = Duration(seconds: 1);
  static const Duration _maxRetryDelay = Duration(seconds: 30);

  // Active downloads tracking
  final Map<int, _DownloadTask> _activeDownloads = {};
  
  // FIX #13: Track retry counts per download
  final Map<int, int> _retryCounts = {};

  // Download status stream controller
  final _statusController = StreamController<LibraryDownloadStatus>.broadcast();

  Stream<LibraryDownloadStatus> get statusStream => _statusController.stream;

  Future<Database> get _db async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final db = await openDatabase(
      path.join(dbPath, 'library_downloads.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE download_tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id INTEGER,
            url TEXT,
            file_path TEXT,
            filename TEXT,
            total_bytes INTEGER,
            downloaded_bytes INTEGER DEFAULT 0,
            status TEXT DEFAULT 'pending',
            created_at TEXT,
            updated_at TEXT,
            temp_file_path TEXT,
            UNIQUE(item_id)
          )
        ''');
        
        await db.execute('''
          CREATE INDEX idx_download_status ON download_tasks(status)
        ''');
      },
    );
    return db;
  }

  /// Start or resume a download
  Future<int> startDownload({
    required int itemId,
    required String url,
    required String filename,
    String? fileType,
  }) async {
    final db = await _db;
    
    // Check if download already exists
    final existing = await db.query(
      'download_tasks',
      where: 'item_id = ?',
      whereArgs: [itemId],
    );
    
    if (existing.isNotEmpty) {
      final status = existing.first['status'];
      if (status == 'completed') {
        return existing.first['id'] as int;
      } else if (status == 'downloading') {
        return existing.first['id'] as int;
      } else {
        await _resumeDownload(existing.first);
        return existing.first['id'] as int;
      }
    }
    
    // Create new download task
    final now = DateTime.now().toIso8601String();
    final tempFilePath = await _getTempPath(filename);
    
    final taskId = await db.insert('download_tasks', {
      'item_id': itemId,
      'url': url,
      'file_path': await _getFinalPath(filename),
      'filename': filename,
      'total_bytes': 0,
      'downloaded_bytes': 0,
      'status': 'pending',
      'created_at': now,
      'updated_at': now,
      'temp_file_path': tempFilePath,
    });
    
    _executeDownload(taskId, itemId, url, tempFilePath, filename, 0);
    
    return taskId;
  }

  /// Resume a paused/failed download
  Future<void> _resumeDownload(Map<String, dynamic> task) async {
    final taskId = task['id'] as int;
    final itemId = task['item_id'] as int;
    final url = task['url'] as String;
    final tempFilePath = task['temp_file_path'] as String;
    final filename = task['filename'] as String;
    final downloadedBytes = task['downloaded_bytes'] as int? ?? 0;
    
    final tempFile = File(tempFilePath);
    if (!await tempFile.exists()) {
      await _startFreshDownload(taskId, itemId, url, tempFilePath, filename);
      return;
    }
    
    _executeDownload(taskId, itemId, url, tempFilePath, filename, downloadedBytes);
  }

  /// Execute download with resume support using HTTP Range Requests
  Future<void> _executeDownload(
    int taskId,
    int itemId,
    String url,
    String tempFilePath,
    String filename,
    int startByte,
  ) async {
    final db = await _db;
    
    try {
      await db.update(
        'download_tasks',
        {
          'status': 'downloading',
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [taskId],
      );
      
      _statusController.add(LibraryDownloadStatus(
        itemId: itemId,
        status: LibraryDownloadStatusType.downloading,
        progress: startByte > 0 ? 0.5 : 0.0,
        downloadedBytes: startByte,
        totalBytes: 0,
      ));
      
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      
      // P1-5: Add Range header for resume support
      if (startByte > 0) {
        request.headers['Range'] = 'bytes=$startByte-';
        debugPrint('[LibraryDownloadService] Resuming download at byte $startByte');
      }
      
      final response = await client.send(request);
      
      int totalBytes;
      int downloadedBytes = startByte;
      
      if (response.headers.containsKey('content-range')) {
        final contentRange = response.headers['content-range']!;
        final match = RegExp(r'bytes \d+-\d+/(\d+)').firstMatch(contentRange);
        totalBytes = match != null ? int.parse(match.group(1)!) : 0;
      } else {
        totalBytes = int.parse(response.headers['content-length'] ?? '0');
      }
      
      await db.update(
        'download_tasks',
        {
          'total_bytes': totalBytes,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [taskId],
      );
      
      final tempFile = File(tempFilePath);
      final sink = tempFile.openWrite(
        mode: startByte > 0 ? FileMode.append : FileMode.write,
      );
      
      await response.stream.forEach((chunk) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        
        final progress = totalBytes > 0 ? downloadedBytes / totalBytes : 0.0;
        _statusController.add(LibraryDownloadStatus(
          itemId: itemId,
          status: LibraryDownloadStatusType.downloading,
          progress: progress,
          downloadedBytes: downloadedBytes,
          totalBytes: totalBytes,
        ));
        
        if (downloadedBytes % (1024 * 1024) < chunk.length) {
          db.update(
            'download_tasks',
            {
              'downloaded_bytes': downloadedBytes,
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [taskId],
          );
        }
      });
      
      await sink.close();
      
      final finalPath = await _getFinalPath(filename);
      await tempFile.copy(finalPath);
      await tempFile.delete();
      
      await db.update(
        'download_tasks',
        {
          'status': 'completed',
          'downloaded_bytes': totalBytes,
          'file_path': finalPath,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [taskId],
      );
      
      _statusController.add(LibraryDownloadStatus(
        itemId: itemId,
        status: LibraryDownloadStatusType.completed,
        progress: 1.0,
        downloadedBytes: totalBytes,
        totalBytes: totalBytes,
        localPath: finalPath,
      ));
      
      debugPrint('[LibraryDownloadService] Download completed: $filename');

    } catch (e) {
      debugPrint('[LibraryDownloadService] Download failed: $e');
      
      // FIX #13: Implement retry logic with exponential backoff for transient errors
      final retryCount = _retryCounts[itemId] ?? 0;
      final isTransientError = _isTransientError(e);
      
      if (isTransientError && retryCount < _maxRetries) {
        final delay = _calculateRetryDelay(retryCount);
        debugPrint('[LibraryDownloadService] Will retry download in ${delay.inSeconds}s (attempt ${retryCount + 1}/$_maxRetries)');
        
        // Update task status to pending for retry
        await db.update(
          'download_tasks',
          {
            'status': 'pending',
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [taskId],
        );
        
        // Increment retry count
        _retryCounts[itemId] = retryCount + 1;
        
        // Schedule retry after delay
        await Future.delayed(delay);
        
        // Retry the download
        await _executeDownload(taskId, itemId, url, tempFilePath, filename, startByte);
        return;
      }
      
      // Max retries exceeded or non-transient error - mark as failed
      _retryCounts.remove(itemId); // Clear retry count
      
      await db.update(
        'download_tasks',
        {
          'status': 'failed',
          'updated_at': DateTime.now().toIso8601String(),
          'error': e.toString(),
        },
        where: 'id = ?',
        whereArgs: [taskId],
      );

      _statusController.add(LibraryDownloadStatus(
        itemId: itemId,
        status: LibraryDownloadStatusType.failed,
        progress: 0.0,
        downloadedBytes: startByte,
        totalBytes: 0,
        error: e.toString(),
      ));
    }
  }

  /// FIX #13: Check if error is transient (retryable)
  bool _isTransientError(Object error) {
    final errorStr = error.toString().toLowerCase();
    // Retry on network-related errors
    return errorStr.contains('socket') ||
           errorStr.contains('connection') ||
           errorStr.contains('timeout') ||
           errorStr.contains('network') ||
           error is TimeoutException;
  }
  
  /// FIX #13: Calculate retry delay with exponential backoff
  Duration _calculateRetryDelay(int retryCount) {
    // Exponential backoff: 1s, 2s, 4s, ...
    final delay = _initialRetryDelay * (1 << retryCount);
    // Cap at max delay
    return delay > _maxRetryDelay ? _maxRetryDelay : delay;
  }
  
  /// FIX #13: Manual retry method for user-initiated retries
  Future<void> retryDownload(int itemId) async {
    final db = await _db;
    
    final task = await db.query(
      'download_tasks',
      where: 'item_id = ?',
      whereArgs: [itemId],
    );
    
    if (task.isEmpty) {
      throw Exception('Download task not found');
    }
    
    final t = task.first;
    final status = t['status'] as String;
    
    if (status != 'failed' && status != 'cancelled') {
      throw Exception('Can only retry failed or cancelled downloads');
    }
    
    // Reset retry count for manual retry
    _retryCounts.remove(itemId);
    
    // Reset status to pending
    await db.update(
      'download_tasks',
      {
        'status': 'pending',
        'error': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [t['id']],
    );
    
    // Restart download
    await _executeDownload(
      t['id'] as int,
      itemId,
      t['url'] as String,
      t['temp_file_path'] as String,
      t['filename'] as String,
      0, // Start from beginning
    );
  }

  Future<void> _startFreshDownload(
    int taskId,
    int itemId,
    String url,
    String tempFilePath,
    String filename,
  ) async {
    final db = await _db;
    await db.update(
      'download_tasks',
      {
        'downloaded_bytes': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [taskId],
    );
    
    _executeDownload(taskId, itemId, url, tempFilePath, filename, 0);
  }

  /// Pause a download
  Future<void> pauseDownload(int itemId) async {
    final db = await _db;
    await db.update(
      'download_tasks',
      {
        'status': 'paused',
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'item_id = ?',
      whereArgs: [itemId],
    );
    
    _activeDownloads.remove(itemId);
    
    _statusController.add(LibraryDownloadStatus(
      itemId: itemId,
      status: LibraryDownloadStatusType.paused,
      progress: 0.0,
      downloadedBytes: 0,
      totalBytes: 0,
    ));
  }

  /// Cancel and delete a download
  Future<void> cancelDownload(int itemId) async {
    final db = await _db;
    
    final task = await db.query(
      'download_tasks',
      where: 'item_id = ?',
      whereArgs: [itemId],
    );
    
    if (task.isNotEmpty) {
      final tempPath = task.first['temp_file_path'] as String?;
      final finalPath = task.first['file_path'] as String?;
      
      if (tempPath != null) {
        final tempFile = File(tempPath);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
      
      if (finalPath != null) {
        final finalFile = File(finalPath);
        if (await finalFile.exists()) {
          await finalFile.delete();
        }
      }
      
      await db.delete(
        'download_tasks',
        where: 'item_id = ?',
        whereArgs: [itemId],
      );
    }
    
    _activeDownloads.remove(itemId);
    
    _statusController.add(LibraryDownloadStatus(
      itemId: itemId,
      status: LibraryDownloadStatusType.cancelled,
      progress: 0.0,
      downloadedBytes: 0,
      totalBytes: 0,
    ));
  }

  /// Get download status for an item
  Future<LibraryDownloadStatus?> getDownloadStatus(int itemId) async {
    final db = await _db;
    
    final task = await db.query(
      'download_tasks',
      where: 'item_id = ?',
      whereArgs: [itemId],
      limit: 1,
    );
    
    if (task.isEmpty) return null;
    
    final t = task.first;
    final status = t['status'] as String;
    final downloadedBytes = t['downloaded_bytes'] as int? ?? 0;
    final totalBytes = t['total_bytes'] as int? ?? 0;
    
    return LibraryDownloadStatus(
      itemId: itemId,
      status: LibraryDownloadStatusType.values.firstWhere(
        (s) => s.name == status,
        orElse: () => LibraryDownloadStatusType.pending,
      ),
      progress: totalBytes > 0 ? downloadedBytes / totalBytes : 0.0,
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
      localPath: t['file_path'] as String?,
    );
  }

  /// Get local path for downloaded file
  Future<String?> getDownloadedFilePath(int itemId) async {
    final db = await _db;
    
    final task = await db.query(
      'download_tasks',
      where: 'item_id = ? AND status = ?',
      whereArgs: [itemId, 'completed'],
      limit: 1,
    );
    
    if (task.isEmpty) return null;
    
    return task.first['file_path'] as String?;
  }

  /// Check if file is downloaded
  Future<bool> isDownloaded(int itemId) async {
    final path = await getDownloadedFilePath(itemId);
    if (path == null) return false;
    
    return await File(path).exists();
  }

  Future<String> _getTempPath(String filename) async {
    final dir = await getTemporaryDirectory();
    return path.join(dir.path, 'library_downloads', 'temp_$filename');
  }

  Future<String> _getFinalPath(String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    return path.join(dir.path, 'library_downloads', filename);
  }

  /// Clear completed downloads
  Future<void> clearCompleted() async {
    final db = await _db;
    await db.delete(
      'download_tasks',
      where: 'status = ?',
      whereArgs: ['completed'],
    );
  }
}

/// Download status types
enum LibraryDownloadStatusType {
  pending,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}

/// Download status data class
class LibraryDownloadStatus {
  final int itemId;
  final LibraryDownloadStatusType status;
  final double progress;
  final int downloadedBytes;
  final int totalBytes;
  final String? localPath;
  final String? error;

  LibraryDownloadStatus({
    required this.itemId,
    required this.status,
    required this.progress,
    required this.downloadedBytes,
    required this.totalBytes,
    this.localPath,
    this.error,
  });

  double get percentage => progress * 100;
  
  String get formattedProgress {
    if (totalBytes == 0) return '0%';
    return '${percentage.toStringAsFixed(1)}%';
  }
  
  String get formattedSize {
    if (totalBytes == 0) return '';
    if (totalBytes < 1024) return '$totalBytes B';
    if (totalBytes < 1024 * 1024) {
      return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Internal download task tracking
class _DownloadTask {
  final int taskId;
  final int itemId;
  final http.Client client;
  final Completer<void> completer = Completer();

  _DownloadTask({
    required this.taskId,
    required this.itemId,
    required this.client,
  });
}
