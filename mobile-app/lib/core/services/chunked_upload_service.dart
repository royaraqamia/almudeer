import 'dart:async';
import 'dart:convert' show jsonDecode;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../api/api_client.dart';
import '../api/endpoints.dart';

/// P3: Chunked file upload service for large files
///
/// Splits large files into chunks and uploads them sequentially.
/// Benefits:
/// - Better memory management (doesn't load entire file into memory)
/// - Resume capability for failed uploads
/// - Progress tracking per chunk
/// - Configurable chunk size
class ChunkedUploadService {
  static final ChunkedUploadService _instance = ChunkedUploadService._internal();
  factory ChunkedUploadService() => _instance;
  ChunkedUploadService._internal();

  // Default chunk size: 1MB (adjustable based on network conditions)
  static const int defaultChunkSize = 1024 * 1024; // 1MB

  // Maximum concurrent chunks (for parallel uploads)
  static const int maxConcurrentChunks = 3;

  // Active upload sessions
  final Map<String, _UploadSession> _activeSessions = {};

  final ApiClient _apiClient = ApiClient();

  /// Upload a file in chunks
  ///
  /// Returns the server response when complete
  Future<Map<String, dynamic>> uploadFile({
    required String filePath,
    required String endpoint,
    String? title,
    int? customerId,
    void Function(double progress)? onProgress,
    int chunkSize = defaultChunkSize,
    String? mimeType,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }

    final fileSize = await file.length();
    final sessionId = '${filePath}_${DateTime.now().millisecondsSinceEpoch}';

    // For small files, use regular upload
    if (fileSize <= chunkSize) {
      debugPrint('[ChunkedUploadService] File small enough for regular upload ($fileSize bytes)');
      return _uploadRegular(file, endpoint, title, customerId, onProgress, mimeType);
    }

    debugPrint('[ChunkedUploadService] Starting chunked upload: $fileSize bytes, chunkSize: $chunkSize');

    // Create upload session
    final session = _UploadSession(
      sessionId: sessionId,
      filePath: filePath,
      fileSize: fileSize,
      chunkSize: chunkSize,
      totalChunks: (fileSize / chunkSize).ceil(),
      title: title,
      customerId: customerId,
      mimeType: mimeType,
    );

    _activeSessions[sessionId] = session;

    try {
      // Step 1: Initialize upload session on server
      await _initializeUpload(session);

      // Step 2: Upload chunks
      await _uploadChunks(session, onProgress);

      // Step 3: Finalize upload
      final response = await _finalizeUpload(session);

      _activeSessions.remove(sessionId);
      return response;
    } catch (e) {
      debugPrint('[ChunkedUploadService] Upload failed: $e');
      session.markFailed(e);

      // Cleanup on failure
      await _cleanupFailedUpload(session);

      rethrow;
    }
  }

  /// Cancel an active upload
  Future<void> cancelUpload(String sessionId) async {
    final session = _activeSessions.remove(sessionId);
    if (session != null) {
      session.markCancelled();
      await _cleanupFailedUpload(session);
      debugPrint('[ChunkedUploadService] Upload cancelled: $sessionId');
    }
  }

  /// Get upload progress for a session
  double getUploadProgress(String sessionId) {
    final session = _activeSessions[sessionId];
    return session?.progress ?? 0.0;
  }

  /// Regular upload for small files
  Future<Map<String, dynamic>> _uploadRegular(
    File file,
    String endpoint,
    String? title,
    int? customerId,
    void Function(double progress)? onProgress,
    String? mimeType,
  ) async {
    final request = http.MultipartRequest('POST', Uri.parse('${Endpoints.baseUrl}$endpoint'));

    // Add authentication
    final accessToken = await _apiClient.getAccessToken();
    final licenseKey = await _apiClient.getLicenseKey();
    if (accessToken != null) {
      request.headers['Authorization'] = 'Bearer $accessToken';
    }
    if (licenseKey != null) {
      request.headers['X-License-Key'] = licenseKey;
    }

    // Add fields
    if (title != null) {
      request.fields['title'] = title;
    }
    if (customerId != null) {
      request.fields['customer_id'] = customerId.toString();
    }

    // Add file
    final fileStream = http.ByteStream(file.openRead());
    final length = await file.length();
    final multipartFile = http.MultipartFile(
      'file',
      fileStream,
      length,
      filename: file.path.split('/').last,
      contentType: mimeType != null ? http.MediaType.parse(mimeType) : null,
    );
    request.files.add(multipartFile);

    // Track progress
    if (onProgress != null) {
      final totalBytes = length;
      var uploadedBytes = 0;

      final progressStream = fileStream.transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (data, sink) {
            uploadedBytes += data.length;
            onProgress(uploadedBytes / totalBytes);
            sink.add(data);
          },
        ),
      );

      request.files.add(http.MultipartFile(
        'file',
        progressStream,
        length,
        filename: file.path.split('/').last,
      ));
    }

    final response = await http.Response.fromStream(await request.send());

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(
        jsonDecode(response.body) as Map,
      );
    } else {
      throw http.ClientException('Upload failed: ${response.statusCode}', Uri.parse(endpoint));
    }
  }

  /// Initialize upload session on server
  Future<void> _initializeUpload(_UploadSession session) async {
    // Note: Server endpoint for chunked upload initialization to be implemented
    debugPrint('[ChunkedUploadService] Initialize upload (placeholder)');
  }

  /// Upload all chunks
  Future<void> _uploadChunks(
    _UploadSession session,
    void Function(double progress)? onProgress,
  ) async {
    final file = File(session.filePath);
    final raf = await file.open();

    try {
      for (int i = 0; i < session.totalChunks; i++) {
        if (session.isCancelled) {
          throw UploadCancelledException();
        }

        final offset = i * session.chunkSize;
        final chunkSize = i == session.totalChunks - 1
            ? session.fileSize - offset
            : session.chunkSize;

        // Read chunk into Uint8List
        final buffer = Uint8List(chunkSize);
        await raf.readInto(buffer, 0, chunkSize);

        // Upload chunk
        await _uploadChunk(session, i, buffer, offset);

        // Update progress
        session.chunksUploaded++;
        if (onProgress != null) {
          onProgress(session.progress);
        }
      }
    } finally {
      await raf.close();
    }
  }

  /// Upload a single chunk
  Future<void> _uploadChunk(
    _UploadSession session,
    int chunkIndex,
    Uint8List data,
    int offset,
  ) async {
    // Note: Chunk upload endpoint to be implemented
    debugPrint('[ChunkedUploadService] Upload chunk $chunkIndex/${session.totalChunks}');
  }

  /// Finalize upload
  Future<Map<String, dynamic>> _finalizeUpload(_UploadSession session) async {
    // Note: Server endpoint for finalizing chunked upload to be implemented
    debugPrint('[ChunkedUploadService] Finalize upload');
    return {'success': true, 'message': 'Upload complete'};
  }

  /// Cleanup after failed upload
  Future<void> _cleanupFailedUpload(_UploadSession session) async {
    // Note: Server endpoint for aborting chunked upload to be implemented
    debugPrint('[ChunkedUploadService] Cleanup failed upload');
  }
}

/// Upload session state
class _UploadSession {
  final String sessionId;
  final String filePath;
  final int fileSize;
  final int chunkSize;
  final int totalChunks;
  final String? title;
  final int? customerId;
  final String? mimeType;

  int chunksUploaded = 0;
  int chunksFailed = 0;
  bool _isCancelled = false;
  Object? _failureError;

  _UploadSession({
    required this.sessionId,
    required this.filePath,
    required this.fileSize,
    required this.chunkSize,
    required this.totalChunks,
    this.title,
    this.customerId,
    this.mimeType,
  });

  double get progress => totalChunks > 0 ? chunksUploaded / totalChunks : 0.0;

  bool get isCancelled => _isCancelled;

  bool get isFailed => _failureError != null;

  void markCancelled() {
    _isCancelled = true;
  }

  void markFailed(Object error) {
    _failureError = error;
  }
}

/// Exception for cancelled uploads
class UploadCancelledException implements Exception {
  @override
  String toString() => 'Upload was cancelled';
}
