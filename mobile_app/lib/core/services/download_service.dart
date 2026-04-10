import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';

/// Service for downloading files with progress tracking
///
/// Features:
/// - Download with progress tracking
/// - SHA256 verification (optional)
/// - Auto-trigger install
class DownloadService {
  static DownloadService? _instance;
  factory DownloadService() {
    return _instance ??= DownloadService._internal();
  }

  @visibleForTesting
  factory DownloadService.test({required Dio dio}) {
    return DownloadService._internal(dio: dio);
  }

  DownloadService._internal({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  // Download state
  bool _isDownloading = false;
  double _progress = 0.0;
  String? _downloadPath;
  CancelToken? _cancelToken;

  /// Whether a download is in progress
  bool get isDownloading => _isDownloading;

  /// Current download progress (0.0 to 1.0)
  double get progress => _progress;

  /// Path to downloaded file
  String? get downloadPath => _downloadPath;

  /// Download APK with progress tracking
  ///
  /// Returns a stream of download progress (0.0 to 1.0).
  /// When complete, the stream closes and the APK is saved.
  ///
  /// [url] - URL to download APK from
  /// [expectedSha256] - Optional SHA256 hash for verification
  Stream<double> downloadApk(String url, {String? expectedSha256}) async* {
    if (_isDownloading) {
      throw Exception('Download already in progress');
    }

    _isDownloading = true;
    _progress = 0.0;
    _cancelToken = CancelToken();

    try {
      // Get download directory - Use external cache/temp for better FileProvider compatibility on Android 14+
      Directory? dir;
      if (Platform.isAndroid) {
        dir = (await getExternalCacheDirectories())?.first;
      }
      dir ??= await getTemporaryDirectory();

      _downloadPath = '${dir.path}/almudeer_update.apk';

      // Start download with progress
      final response = await _dio.download(
        url,
        _downloadPath!,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            _progress = received / total;
          }
        },
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
        ),
      );

      if (response.statusCode == 200) {
        _progress = 1.0;
        yield 1.0;

        // Verify SHA256 if provided
        if (expectedSha256 != null && expectedSha256.isNotEmpty) {
          final isValid = await _verifySha256(_downloadPath!, expectedSha256);
          if (!isValid) {
            throw Exception('SHA256 verification failed');
          }
        }
      } else {
        throw Exception('Download failed with status ${response.statusCode}');
      }
    } catch (e) {
      _progress = 0.0;
      rethrow;
    } finally {
      _isDownloading = false;
      _cancelToken = null;
    }
  }

  /// Download with progress callback (resumable)
  Future<String> downloadApkWithCallback(
    String url, {
    required void Function(double progress, int received, int total) onProgress,
    String? expectedSha256,
  }) async {
    if (_isDownloading) {
      throw Exception('Download already in progress');
    }

    _isDownloading = true;
    _cancelToken = CancelToken();

    try {
      Directory? dir;
      if (Platform.isAndroid) {
        dir = (await getExternalCacheDirectories())?.first;
      }
      dir ??= await getTemporaryDirectory();

      _downloadPath = '${dir.path}/almudeer_update.apk';
      final file = File(_downloadPath!);

      int downloaded = 0;
      if (await file.exists()) {
        downloaded = await file.length();
      }

      // Request download with Range header
      final response = await _dio.get(
        url,
        cancelToken: _cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          headers: downloaded > 0 ? {'Range': 'bytes=$downloaded-'} : null,
        ),
      );

      final total =
          int.tryParse(response.headers.value('content-length') ?? '0') ?? 0;
      final fullSize = downloaded + total;

      final raf = await file.open(mode: FileMode.append);

      await response.data.stream
          .listen(
            (List<int> chunk) {
              raf.writeFromSync(chunk);
              downloaded += chunk.length;
              if (fullSize > 0) {
                _progress = downloaded / fullSize;
                onProgress(_progress, downloaded, fullSize);
              }
            },
            onDone: () {
              raf.close();
            },
            onError: (e) {
              raf.close();
              throw e;
            },
            cancelOnError: true,
          )
          .asFuture();

      _progress = 1.0;
      onProgress(1.0, fullSize, fullSize);

      // Verify SHA256 if provided
      if (expectedSha256 != null && expectedSha256.isNotEmpty) {
        final isValid = await _verifySha256(_downloadPath!, expectedSha256);
        if (!isValid) {
          throw Exception('SHA256 verification failed');
        }
      }

      return _downloadPath!;
    } catch (e) {
      _progress = 0.0;
      rethrow;
    } finally {
      _isDownloading = false;
      _cancelToken = null;
    }
  }

  /// Cancel ongoing download
  void cancelDownload() {
    _cancelToken?.cancel('User cancelled');
    _isDownloading = false;
    _progress = 0.0;
  }

  /// Verify SHA256 hash of downloaded file
  Future<bool> _verifySha256(String filePath, String expectedHash) async {
    try {
      final digest = await _calculateSha256(filePath);
      return digest.toLowerCase() == expectedHash.toLowerCase();
    } catch (e) {
      return false;
    }
  }

  /// Calculate SHA256 hash of file using chunked reading for memory efficiency
  Future<String> _calculateSha256(String filePath) async {
    final file = File(filePath);

    // Use chunked conversion for memory efficiency with large APK files
    var output = sha256.convert([]);
    final sink = sha256.startChunkedConversion(
      ChunkedConversionSink.withCallback((chunks) {
        output = chunks.single;
      }),
    );

    // Read file in chunks to avoid loading entire APK into memory
    final stream = file.openRead();
    await for (final chunk in stream) {
      sink.add(chunk);
    }
    sink.close();

    return output.toString();
  }

  /// Delete downloaded APK
  Future<void> cleanup() async {
    // Wait a bit to ensure system installer has opened the file
    await Future.delayed(const Duration(seconds: 3));

    if (_downloadPath != null) {
      try {
        final file = File(_downloadPath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        // Ignore cleanup errors
      }
      _downloadPath = null;
    }
  }
}
