import 'package:flutter/material.dart';
import 'app_localizations.dart';

/// Library screen localizations
/// 
/// Provides localized strings for the library screen
class LibraryLocalizations {
  final Locale locale;

  LibraryLocalizations(this.locale);

  static LibraryLocalizations of(BuildContext context) {
    return AppLocalizations.of(context).library;
  }

  bool get _isArabic => locale.languageCode == 'ar';

  // Library Screen - Error Messages
  String get errorOpeningItem => _isArabic
      ? 'حدث خطأ أثناء فتح العنصر'
      : 'Error opening item';

  String get fileNotFound => _isArabic
      ? 'الملف غير موجود'
      : 'File not found';

  String get fileAccessError => _isArabic
      ? 'تعذر الوصول إلى الملف'
      : 'Unable to access file';

  String get fileSelectedError => _isArabic
      ? 'تعذر الوصول إلى الملف المحدد'
      : 'Unable to access selected file';

  String get uploadFailed => _isArabic
      ? 'فشل رفع الملف'
      : 'Upload failed';

  String get retry => _isArabic
      ? 'إعادة المحاولة'
      : 'Retry';

  String get addNewContent => _isArabic
      ? 'إضافة محتوى جديد'
      : 'Add new content';

  String get noteOption => _isArabic
      ? 'ملاحظة نصية'
      : 'Note';

  String get writeNewNote => _isArabic
      ? 'اكتب ملاحظة جديدة'
      : 'Write a new note';

  String get uploadFile => _isArabic
      ? 'رفع ملف'
      : 'Upload file';

  String get selectFromFile => _isArabic
      ? 'اختر ملفاً من جهازك'
      : 'Select a file from your device';

  String uploadSuccess(String fileName) => _isArabic
      ? 'تم رفع "$fileName" بنجاح'
      : '"$fileName" uploaded successfully';

  String uploadFailedWithName(String fileName, String error) => _isArabic
      ? 'فشل رفع "$fileName": $error'
      : 'Failed to upload "$fileName": $error';

  String get uploading => _isArabic
      ? 'جاري الرفع...'
      : 'Uploading...';

  String get selected => _isArabic
      ? 'محدد'
      : 'Selected';

  String get notSelected => _isArabic
      ? 'غير محدد'
      : 'Not selected';

  String get permissionEdit => _isArabic
      ? 'تعديل'
      : 'Edit';

  String get permissionAdmin => _isArabic
      ? 'مدير'
      : 'Admin';

  String get permissionRead => _isArabic
      ? 'قراءة'
      : 'Read';

  String downloadFailed(String fileName) => _isArabic
      ? 'فشل تحميل "$fileName"'
      : 'Failed to download "$fileName"';

  // P1-7: Conflict resolution
  String get conflictDetected => _isArabic
      ? 'تم اكتشاف تعارض'
      : 'Conflict Detected';

  String get conflictDescription => _isArabic
      ? 'يوجد إصدار أحدث على الخادم. ماذا تريد أن تفعل؟'
      : 'A newer version exists on the server. What would you like to do?';

  String get localVersion => _isArabic
      ? 'الإصدار المحلي'
      : 'Local Version';

  String get serverVersion => _isArabic
      ? 'إصدار الخادم'
      : 'Server Version';

  String get current => _isArabic
      ? 'حالي'
      : 'Current';

  String get keepLocalVersion => _isArabic
      ? 'الاحتفاظ بالإصدار المحلي'
      : 'Keep Local Version';

  String get useServerVersion => _isArabic
      ? 'استخدام إصدار الخادم'
      : 'Use Server Version';

  String get mergeVersions => _isArabic
      ? 'دمج الإصدارين'
      : 'Merge Versions';
}
