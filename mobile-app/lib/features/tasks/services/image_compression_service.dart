import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Image compression utility for reducing upload size
class ImageCompressionService {
  static final ImageCompressionService _instance =
      ImageCompressionService._internal();
  factory ImageCompressionService() => _instance;

  ImageCompressionService._internal();

  final ImagePicker _imagePicker = ImagePicker();

  /// Compress an image file before upload
  /// Returns the compressed file path or original if compression fails
  Future<File?> compressImage(
    File imageFile, {
    int maxWidth = 1920,
    int maxHeight = 1080,
    int quality = 85,
  }) async {
    try {
      // Check file size first - if already small, no need to compress
      final fileSize = await imageFile.length();
      if (fileSize < 500 * 1024) {
        // Less than 500KB
        debugPrint(
          'ImageCompressionService: File already small ($fileSize bytes)',
        );
        return imageFile;
      }

      // Use flutter_image_compress for better compression
      final compressedFile = await FlutterImageCompress.compressAndGetFile(
        imageFile.absolute.path,
        '${imageFile.absolute.path}.compressed.jpg',
        minWidth: maxWidth,
        minHeight: maxHeight,
        quality: quality,
        format: CompressFormat.jpeg,
      );

      if (compressedFile != null) {
        final resultFile = File(compressedFile.path);
        final compressedSize = await resultFile.length();
        debugPrint(
          'ImageCompressionService: Compressed from $fileSize to $compressedSize bytes',
        );
        return resultFile;
      }

      debugPrint('ImageCompressionService: Compression returned null, using original');
      return imageFile;
    } catch (e) {
      debugPrint('ImageCompressionService: Compression failed: $e');
      return imageFile; // Return original on failure
    }
  }

  /// Pick and compress an image from gallery
  Future<File?> pickAndCompressImage({
    ImageSource source = ImageSource.gallery,
    int maxWidth = 1920,
    int maxHeight = 1080,
    int quality = 85,
  }) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: maxWidth.toDouble(),
        maxHeight: maxHeight.toDouble(),
        imageQuality: quality,
      );

      if (pickedFile == null) return null;

      return File(pickedFile.path);
    } catch (e) {
      debugPrint('ImageCompressionService: Pick and compress failed: $e');
      return null;
    }
  }

  /// Pick and compress multiple images from gallery
  Future<List<File>> pickAndCompressMultipleImages({
    ImageSource source = ImageSource.gallery,
    int maxWidth = 1920,
    int maxHeight = 1080,
    int quality = 85,
  }) async {
    try {
      final List<XFile> pickedFiles = await _imagePicker.pickMultiImage(
        maxWidth: maxWidth.toDouble(),
        maxHeight: maxHeight.toDouble(),
        imageQuality: quality,
      );

      return pickedFiles.map((xFile) => File(xFile.path)).toList();
    } catch (e) {
      debugPrint('ImageCompressionService: Pick multiple failed: $e');
      return [];
    }
  }

  /// Check if a file is an image
  bool isImageFile(File file) {
    final extension = file.path.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(extension);
  }

  /// Get file size in KB
  Future<int> getFileSizeKB(File file) async {
    final bytes = await file.length();
    return (bytes / 1024).round();
  }
}
