import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

// Wrapper for static FilePicker to enable mocking
class FilePickerWrapper {
  Future<FilePickerResult?> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool allowMultiple = false,
  }) {
    return FilePicker.platform.pickFiles(
      type: type,
      allowedExtensions: allowedExtensions,
      allowMultiple: allowMultiple,
    );
  }
}

class FileService {
  static FileService? _instance;
  factory FileService() => _instance ??= FileService._internal();

  @visibleForTesting
  factory FileService.test({required FilePickerWrapper picker}) {
    return FileService._internal(picker: picker);
  }

  FileService._internal({FilePickerWrapper? picker})
    : _picker = picker ?? FilePickerWrapper();

  final FilePickerWrapper _picker;

  Future<List<File>?> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool allowMultiple = false,
  }) async {
    final result = await _picker.pickFiles(
      type: type,
      allowedExtensions: allowedExtensions,
      allowMultiple: allowMultiple,
    );

    if (result != null && result.files.isNotEmpty) {
      return result.paths
          .where((path) => path != null)
          .map((path) => File(path!))
          .toList();
    }
    return null;
  }

  Future<File?> pickSingleFile({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) async {
    final files = await pickFiles(
      type: type,
      allowedExtensions: allowedExtensions,
      allowMultiple: false,
    );
    return files?.firstOrNull;
  }
}
