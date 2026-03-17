/// Centralized constants for all file viewers
/// Ensures consistent behavior across PDF, Code, CSV, Text, Excel, etc.
class ViewerConstants {
  ViewerConstants._();

  // File size limits (in bytes)
  static const int maxTextFileSize = 5 * 1024 * 1024; // 5MB
  static const int maxCodeFileSize = 5 * 1024 * 1024; // 5MB
  static const int maxCsvFileSize = 5 * 1024 * 1024; // 5MB
  static const int maxPdfFileSize = 50 * 1024 * 1024; // 50MB
  static const int maxExcelFileSize = 10 * 1024 * 1024; // 10MB (hard limit)
  static const int maxExcelFileSizeWarning = 8 * 1024 * 1024; // 8MB (warning threshold)

  // Pagination
  static const int defaultRowsPerPage = 100;

  // Retry configuration
  static const int maxRetries = 3;
  static const Duration retryBaseDelay = Duration(seconds: 1);

  // Timeouts
  static const Duration fileReadTimeout = Duration(seconds: 30);
  static const Duration downloadTimeout = Duration(minutes: 2);

  // Font sizes
  static const double minFontSize = 8.0;
  static const double maxFontSize = 48.0;
  static const double defaultTextFontSize = 14.0;
  static const double defaultCodeFontSize = 13.0;

  // Cell dimensions for tabular data
  static const double cellWidth = 150.0;
}

/// Base error types for viewer operations
enum ViewerErrorType {
  fileNotFound,
  fileSizeExceeded,
  networkError,
  parseError,
  unknown,
  emptyFile,
  corruptedFile,
  timeout,
  permissionDenied,
}

/// Extension to get user-friendly error messages
extension ViewerErrorTypeExtension on ViewerErrorType {
  String get message {
    switch (this) {
      case ViewerErrorType.fileNotFound:
        return 'الملف غير موجود';
      case ViewerErrorType.fileSizeExceeded:
        return 'حجم الملف كبير جداً';
      case ViewerErrorType.networkError:
        return 'خطأ في الشبكة';
      case ViewerErrorType.parseError:
        return 'فشل تحليل الملف';
      case ViewerErrorType.unknown:
        return 'حدث خطأ غير معروف';
      case ViewerErrorType.emptyFile:
        return 'الملف فارغ';
      case ViewerErrorType.corruptedFile:
        return 'الملف تالف أو غير صالح';
      case ViewerErrorType.timeout:
        return 'انتهت مهلة العملية';
      case ViewerErrorType.permissionDenied:
        return 'تم رفض الإذن';
    }
  }
}
