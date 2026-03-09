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
}
