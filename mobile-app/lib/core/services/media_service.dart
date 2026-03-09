import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:video_compress/video_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:gal/gal.dart';
import 'browser_download_manager.dart';

class MediaService {
  /// Compresses an image and returns the new file
  static Future<File?> compressImage(File file, {int quality = 70}) async {
    try {
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      final tempDir = await getTemporaryDirectory();
      final targetPath = p.join(
        tempDir.path,
        "compressed_${p.basename(file.path)}",
      );

      final compressedBytes = img.encodeJpg(image, quality: quality);
      final compressedFile = File(targetPath)
        ..writeAsBytesSync(compressedBytes);

      return compressedFile;
    } catch (e) {
      debugPrint("Image compression error: $e");
      return file; // Return original on error
    }
  }

  /// Compresses a video and returns the new file
  static Future<File?> compressVideo(File file) async {
    try {
      final info = await VideoCompress.compressVideo(
        file.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
      );

      if (info != null && info.file != null) {
        return info.file;
      }
      return file;
    } catch (e) {
      debugPrint("Video compression error: $e");
      return file;
    }
  }

  /// Cleans up temporary compression files
  static Future<void> cleanup() async {
    await VideoCompress.deleteAllCache();
  }

  /// Saves a file to the device gallery (Images/Videos)
  static Future<bool> saveToGallery(
    String path, {
    bool isVideo = false,
    Uint8List? imageData,
  }) async {
    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) return false;
      }

      if (imageData != null) {
        // Save bytes to temp file then gallery
        final tempDir = await getTemporaryDirectory();
        final tempFile = File(
          '${tempDir.path}/temp_image_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        await tempFile.writeAsBytes(imageData);
        await Gal.putImage(tempFile.path);
        await tempFile.delete();
      } else if (isVideo) {
        await Gal.putVideo(path);
      } else {
        await Gal.putImage(path);
      }
      return true;
    } catch (e) {
      debugPrint("Save to gallery error: $e");
      return false;
    }
  }

  /// Saves a file to the device storage
  static Future<bool> saveToFile(String path, String fileName) async {
    try {
      // Check if path is a URL
      if (path.startsWith('http://') || path.startsWith('https://')) {
        await BrowserDownloadManager().startDownload(path, fileName: fileName);
        return true;
      }

      // If it's a local file, copy it to downloads directory via BrowserDownloadManager logic
      final file = File(path);
      if (!await file.exists()) return false;

      Directory? dir;
      if (Platform.isAndroid) {
        dir = Directory('/storage/emulated/0/Download/Almudeer');
        if (!await dir.exists()) {
          try {
            await dir.create(recursive: true);
          } catch (e) {
            dir = Directory('/storage/emulated/0/Download');
          }
        }
      } else {
        dir = await getApplicationDocumentsDirectory();
      }

      final targetPath = '${dir.path}/$fileName';
      await file.copy(targetPath);

      return true;
    } catch (e) {
      debugPrint("Save to file error: $e");
      return false;
    }
  }
}
