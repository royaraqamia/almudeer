import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../core/services/library_download_service.dart';

class LibraryItem {
  final int id;
  final int licenseKeyId;
  final int? customerId;
  final String type; // 'note', 'image', 'file', 'audio', 'video'
  final String title;
  final String? content;
  final String? filePath;
  final int? fileSize;
  final String? mimeType;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isUploading;
  final double? uploadProgress;
  final int? uploadedBytes;
  final int? totalUploadBytes;
  final bool hasError;
  // Issue #23: Download state tracking
  final bool isDownloading;
  final double? downloadProgress;
  final String? localPath;
  // Issue #26: Trash support
  final DateTime? deletedAt;
  // P3-13: Version history support
  final int? version;
  // P1-5: Download resume support
  final LibraryDownloadStatusType? downloadStatus;
  final int? downloadedBytes;
  final int? totalBytes;
  // P3-14: Sharing support
  final String? userId;
  final bool isShared;
  final String? sharedWith;
  final String? sharePermission;
  // FIX: Store original file path for retry on failed uploads
  final String? originalFilePath;

  LibraryItem({
    required this.id,
    required this.licenseKeyId,
    this.customerId,
    required this.type,
    required this.title,
    this.content,
    this.filePath,
    this.fileSize,
    this.mimeType,
    required this.createdAt,
    required this.updatedAt,
    this.isUploading = false,
    this.uploadProgress,
    this.uploadedBytes,
    this.totalUploadBytes,
    this.hasError = false,
    this.isDownloading = false,
    this.downloadProgress,
    this.localPath,
    this.deletedAt,
    this.version,
    this.downloadStatus,
    this.downloadedBytes,
    this.totalBytes,
    this.userId,
    this.isShared = false,
    this.sharedWith,
    this.sharePermission,
    this.originalFilePath,
  });

  factory LibraryItem.fromJson(Map<String, dynamic> json) {
    // Issue #16: Add null safety and error handling for DateTime parsing
    DateTime parseDateSafe(String? dateStr, DateTime defaultValue) {
      if (dateStr == null || dateStr.isEmpty) {
        return defaultValue;
      }
      try {
        return DateTime.parse(dateStr);
      } catch (e) {
        // Log error but don't crash
        debugPrint('Failed to parse date: $dateStr, using default');
        return defaultValue;
      }
    }

    return LibraryItem(
      id: json['id'] ?? 0,
      licenseKeyId: json['license_key_id'] ?? 0,
      customerId: json['customer_id'],
      type: json['type'] ?? 'file',
      title: json['title'] ?? 'بدون عنوان',
      content: json['content'],
      filePath: json['file_path'],
      fileSize: json['file_size'],
      mimeType: json['mime_type'],
      createdAt: parseDateSafe(json['created_at'], DateTime.now()),
      updatedAt: parseDateSafe(json['updated_at'], DateTime.now()),
      isUploading: json['is_uploading'] == 1 || (json['is_uploading'] == true),
      uploadProgress: json['upload_progress'] != null
          ? (json['upload_progress'] as num).toDouble()
          : null,
      hasError: json['has_error'] == 1 || (json['has_error'] == true),
      // Issue #23: Download state (not persisted from API, only local)
      isDownloading: false,
      downloadProgress: null,
      localPath: json['local_path'],
      // P3-14: Sharing fields from API
      userId: json['user_id'],
      isShared: json['is_shared'] == 1 || (json['is_shared'] == true),
      sharedWith: json['shared_with'],
      // Backend consistently returns 'share_permission' for all endpoints
      sharePermission: json['share_permission'],
      // P1-5: Download resume fields (local only)
      downloadStatus: null,
      downloadedBytes: null,
      totalBytes: null,
      // FIX: Original file path for retry
      originalFilePath: json['original_file_path'],
      // Issue #26: Trash support
      deletedAt: json['deleted_at'] != null ? DateTime.parse(json['deleted_at']) : null,
      // P3-13: Version history support
      version: json['version'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'license_key_id': licenseKeyId,
      'customer_id': customerId,
      'type': type,
      'title': title,
      'content': content,
      'file_path': filePath,
      'file_size': fileSize,
      'mime_type': mimeType,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_uploading': isUploading ? 1 : 0,
      'upload_progress': uploadProgress,
      'has_error': hasError ? 1 : 0,
      // Issue #23: Download state (local only)
      'is_downloading': isDownloading ? 1 : 0,
      'download_progress': downloadProgress,
      'local_path': localPath,
      // P3-14: Sharing fields
      'user_id': userId,
      'is_shared': isShared ? 1 : 0,
      'shared_with': sharedWith,
      'share_permission': sharePermission,
      'permission': sharePermission, // Also include 'permission' for compatibility
      // FIX: Original file path for retry
      'original_file_path': originalFilePath,
      // Issue #26: Trash support
      'deleted_at': deletedAt?.toIso8601String(),
      // P3-13: Version history support
      'version': version,
    };
  }

  String get formattedSize {
    if (fileSize == null || fileSize == 0) return '';
    if (fileSize! < 1024) return '$fileSize B';
    if (fileSize! < 1024 * 1024) {
      return '${(fileSize! / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get formattedDate {
    return DateFormat('yyyy/MM/dd HH:mm').format(createdAt);
  }

  LibraryItem copyWith({
    int? id,
    int? licenseKeyId,
    int? customerId,
    String? type,
    String? title,
    String? content,
    String? filePath,
    int? fileSize,
    String? mimeType,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isUploading,
    double? uploadProgress,
    int? uploadedBytes,
    int? totalUploadBytes,
    bool? hasError,
    bool? isDownloading,
    double? downloadProgress,
    String? localPath,
    LibraryDownloadStatusType? downloadStatus,
    int? downloadedBytes,
    int? totalBytes,
    String? originalFilePath,
    String? userId,
    bool? isShared,
    String? sharedWith,
    String? sharePermission,
    DateTime? deletedAt,
    int? version,
  }) {
    return LibraryItem(
      id: id ?? this.id,
      licenseKeyId: licenseKeyId ?? this.licenseKeyId,
      customerId: customerId ?? this.customerId,
      type: type ?? this.type,
      title: title ?? this.title,
      content: content ?? this.content,
      filePath: filePath ?? this.filePath,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isUploading: isUploading ?? this.isUploading,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      uploadedBytes: uploadedBytes ?? this.uploadedBytes,
      totalUploadBytes: totalUploadBytes ?? this.totalUploadBytes,
      hasError: hasError ?? this.hasError,
      isDownloading: isDownloading ?? this.isDownloading,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      localPath: localPath ?? this.localPath,
      downloadStatus: downloadStatus ?? this.downloadStatus,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      originalFilePath: originalFilePath ?? this.originalFilePath,
      userId: userId ?? this.userId,
      isShared: isShared ?? this.isShared,
      sharedWith: sharedWith ?? this.sharedWith,
      sharePermission: sharePermission ?? this.sharePermission,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
    );
  }
}
