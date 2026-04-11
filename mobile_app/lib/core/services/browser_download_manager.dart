import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:background_downloader/background_downloader.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import '../models/download_task.dart' as model;
import 'package:flutter/foundation.dart';

/// Pending download request for queue management
class _PendingDownload {
  final String url;
  final String? fileName;

  _PendingDownload({required this.url, this.fileName});
}

class BrowserDownloadManager {
  static final BrowserDownloadManager _instance =
      BrowserDownloadManager._internal();
  factory BrowserDownloadManager() => _instance;
  BrowserDownloadManager._internal();

  static const int _maxConcurrentDownloads = 5; // Limit concurrent downloads
  late Box<model.DownloadTask> _tasksBox;
  final StreamController<List<model.DownloadTask>> _tasksController =
      StreamController<List<model.DownloadTask>>.broadcast();
  int _activeDownloadCount = 0;
  final Queue<_PendingDownload> _pendingQueue = Queue();

  Stream<List<model.DownloadTask>> get tasksStream => _tasksController.stream;
  List<model.DownloadTask> get currentTasks =>
      _tasksBox.isOpen ? _tasksBox.values.toList() : [];

  Future<void> init() async {
    // Skip initialization on web - background_downloader uses dart:isolate
    if (kIsWeb) {
      debugPrint('[BrowserDownloadManager] Skipped on web - background downloads not supported');
      return;
    }

    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(model.DownloadStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(model.DownloadTaskAdapter());
    }

    _tasksBox = await Hive.openBox<model.DownloadTask>('browser_downloads');
    _tasksController.add(_tasksBox.values.toList());

    // Configure background downloader
    FileDownloader().configureNotification(
      running: const TaskNotification(
        'تحميل جاري...',
        'قيد التحميل: {filename}',
      ),
      complete: const TaskNotification('اكتمل التحميل ✓', '{filename}'),
      error: const TaskNotification('فشل التحميل ✗', '{filename}'),
      progressBar: true,
    );

    // Listen to background downloader updates
    FileDownloader().updates.listen((update) {
      if (update is TaskStatusUpdate) {
        _handleStatusUpdate(update);
      } else if (update is TaskProgressUpdate) {
        _handleProgressUpdate(update);
      }
    });

    // Resume tracking from background downloader
    final allBackgroundTasks = await FileDownloader().allTasks();
    final backgroundTaskIds = allBackgroundTasks.map((e) => e.taskId).toSet();

    for (var task in _tasksBox.values) {
      if (task.status == model.DownloadStatus.downloading) {
        if (!backgroundTaskIds.contains(task.id)) {
          // Task is no longer tracked by background downloader
          task.status = model.DownloadStatus.failed;
          task.error = 'Interrupted or lost';
          await _tasksBox.put(task.id, task);
        }
      }
    }
  }

  Future<void> _handleStatusUpdate(TaskStatusUpdate update) async {
    final task = _tasksBox.get(update.task.taskId);
    if (task == null) return;

    switch (update.status) {
      case TaskStatus.enqueued:
      case TaskStatus.running:
        task.status = model.DownloadStatus.downloading;
        break;
      case TaskStatus.complete:
        task.status = model.DownloadStatus.completed;
        task.progress = 1.0;
        await _handlePostDownload(task);
        // Decrement active count and process queue
        if (_activeDownloadCount > 0) _activeDownloadCount--;
        await _processNextQueuedDownload();
        break;
      case TaskStatus.failed:
        task.status = model.DownloadStatus.failed;
        task.error = 'Download failed';
        // Decrement active count and process queue
        if (_activeDownloadCount > 0) _activeDownloadCount--;
        await _processNextQueuedDownload();
        break;
      case TaskStatus.canceled:
        task.status = model.DownloadStatus.canceled;
        // Decrement active count and process queue
        if (_activeDownloadCount > 0) _activeDownloadCount--;
        await _processNextQueuedDownload();
        break;
      case TaskStatus.paused:
        task.status = model.DownloadStatus.paused;
        // Decrement active count (paused doesn't use active slot)
        if (_activeDownloadCount > 0) _activeDownloadCount--;
        await _processNextQueuedDownload();
        break;
      default:
        break;
    }

    await _tasksBox.put(task.id, task);
    _tasksController.add(_tasksBox.values.toList());
  }

  Future<void> _handleProgressUpdate(TaskProgressUpdate update) async {
    final task = _tasksBox.get(update.task.taskId);
    if (task == null) return;

    task.progress = update.progress;
    task.networkSpeed = update.networkSpeed; // From background_downloader
    task.timeRemaining = update.timeRemaining;

    // Attempt to get sizes if available
    // Note: background_downloader updates usually have these but it depends on the task type
    // If not directly available, we just keep the progress as primary.

    await _tasksBox.put(task.id, task);
    _tasksController.add(_tasksBox.values.toList());
  }

  /// Sanitize filename to prevent path traversal and invalid characters
  String _sanitizeFileName(String name) {
    // Remove or replace path traversal sequences
    name = name.replaceAll('../', '').replaceAll('..\\', '');

    // Remove null bytes and other control characters
    name = name.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '');

    // Replace invalid filename characters with underscore
    // Windows: < > : " / \ | ? *
    // Also remove leading/trailing dots and spaces (Windows issue)
    name = name.replaceAll(RegExp(r'[<>:"/\\\\|?*]'), '_');
    name = name.trim();

    // Remove leading/trailing dots (problematic on Windows and Unix)
    name = name.replaceAll(RegExp(r'^\.+|\.+$'), '');

    // Limit filename length (most filesystems support 255 chars)
    if (name.length > 200) {
      // Preserve extension
      final lastDot = name.lastIndexOf('.');
      if (lastDot > 0 && lastDot < name.length - 1) {
        final ext = name.substring(lastDot);
        name = name.substring(0, 200 - ext.length) + ext;
      } else {
        name = name.substring(0, 200);
      }
    }

    // If empty after sanitization, generate a safe default
    if (name.isEmpty || name == '.' || name == '..') {
      return 'download_${DateTime.now().millisecondsSinceEpoch}';
    }

    return name;
  }

  Future<void> startDownload(String url, {String? fileName}) async {
    // Check if we've reached the concurrent download limit
    if (_activeDownloadCount >= _maxConcurrentDownloads) {
      // Queue the download for later
      debugPrint(
        '[DownloadManager] Queueing download (limit: $_maxConcurrentDownloads)',
      );
      _pendingQueue.add(_PendingDownload(url: url, fileName: fileName));
      return;
    }

    _activeDownloadCount++;
    final id = DateTime.now().millisecondsSinceEpoch.toString();

    // Extract filename from URL or use provided one
    var name = fileName ?? url.split('/').last;

    // Sanitize filename to prevent path traversal and invalid characters
    name = _sanitizeFileName(name);

    // Ensure filename has valid format
    if (name.isEmpty || !name.contains('.')) {
      name = 'download_${DateTime.now().millisecondsSinceEpoch}.bin';
    }

    // We don't need broad storage permissions here since we save to app documents
    // by default, and Gal handles its own permissions for gallery saving.

    // Determine directory (background_downloader handles its own storage patterns,
    // but we'll try to keep our Al-Mudeer subfolder if possible or use standard Downloads)
    const subDirectory = 'Almudeer';

    final downloadTask = DownloadTask(
      taskId: id,
      url: url,
      filename: name,
      directory: subDirectory,
      baseDirectory: BaseDirectory
          .applicationDocuments, // Downloads within app scope for reliability
      updates: Updates.statusAndProgress,
      allowPause: true,
    );

    // We store the relative path for persistence, background_downloader handles the rest
    final savedPath = 'Almudeer/$name';

    final task = model.DownloadTask(
      id: id,
      url: url,
      fileName: name,
      savedPath: savedPath, // Store relative path
      timestamp: DateTime.now(),
    );

    await _tasksBox.put(id, task);
    _tasksController.add(_tasksBox.values.toList());

    await FileDownloader().enqueue(downloadTask);
  }

  /// Process next queued download if capacity is available
  Future<void> _processNextQueuedDownload() async {
    if (_pendingQueue.isEmpty ||
        _activeDownloadCount >= _maxConcurrentDownloads) {
      return;
    }

    final pending = _pendingQueue.removeFirst();
    debugPrint('[DownloadManager] Processing queued download: ${pending.url}');

    try {
      // Decrement count first since startDownload will increment it
      _activeDownloadCount--;
      await startDownload(pending.url, fileName: pending.fileName);
    } catch (e) {
      // If startDownload fails after incrementing, decrement to correct the count
      _activeDownloadCount--;
      debugPrint('[DownloadManager] Queued download failed: $e');
      // Try processing next queued download
      await _processNextQueuedDownload();
      rethrow;
    }
  }

  Future<void> pauseDownload(String id) async {
    final task = _tasksBox.get(id);
    if (task != null) {
      final downloadTasks = await FileDownloader().allTasks();
      final dt =
          downloadTasks.where((e) => e.taskId == id).firstOrNull
              as DownloadTask?;
      if (dt != null) {
        await FileDownloader().pause(dt);
      }
    }
  }

  Future<void> resumeDownload(String id) async {
    final task = _tasksBox.get(id);
    if (task != null) {
      final downloadTasks = await FileDownloader().allTasks();
      final dt =
          downloadTasks.where((e) => e.taskId == id).firstOrNull
              as DownloadTask?;
      if (dt != null) {
        await FileDownloader().resume(dt);
      }
    }
  }

  Future<void> cancelDownload(String id) async {
    final task = _tasksBox.get(id);
    if (task != null) {
      final downloadTasks = await FileDownloader().allTasks();
      final dt =
          downloadTasks.where((e) => e.taskId == id).firstOrNull
              as DownloadTask?;
      if (dt != null) {
        await FileDownloader().cancelTasksWithIds([id]);
      }

      // Fix: Use absolute path for file deletion
      final appDocDir = await getApplicationDocumentsDirectory();
      final filePath = '${appDocDir.path}/${task.savedPath}';
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }

      await _tasksBox.delete(id);
      _tasksController.add(_tasksBox.values.toList());
    }
  }

  Future<void> _handlePostDownload(model.DownloadTask task) async {
    final fileName = task.fileName.toLowerCase();
    final isMedia =
        fileName.endsWith('.jpg') ||
        fileName.endsWith('.jpeg') ||
        fileName.endsWith('.png') ||
        fileName.endsWith('.gif') ||
        fileName.endsWith('.webp') ||
        fileName.endsWith('.mp4') ||
        fileName.endsWith('.mov') ||
        fileName.endsWith('.avi');

    if (isMedia) {
      try {
        final hasAccess = await Gal.hasAccess();
        if (!hasAccess) {
          await Gal.requestAccess();
        }

        final appDocDir = await getApplicationDocumentsDirectory();
        final filePath = '${appDocDir.path}/${task.savedPath}';

        if (fileName.endsWith('.mov') || fileName.endsWith('.avi')) {
          await Gal.putVideo(filePath);
        } else {
          await Gal.putImage(filePath);
        }
      } catch (e) {
        debugPrint('Error saving media to gallery: $e');
      }
    }
  }

  void dispose() {
    _tasksController.close();
  }
}
