/// @deprecated Use `LibraryLocalizations` from `package:almudeer_mobile_app/core/localization/library_localizations.dart` instead.
///
/// This class is kept for backward compatibility.
/// Example migration:
/// ```dart
/// // Old: LibraryLocalization.errorOpeningItem
/// // New: LibraryLocalizations.of(context).errorOpeningItem
/// ```
@Deprecated('Use LibraryLocalizations from core/localization/library_localizations.dart')
class LibraryLocalization {
  static const String _locale = 'ar'; // Current app locale

  // Library Screen - Error Messages
  @Deprecated('Use LibraryLocalizations.of(context).errorOpeningItem')
  static String get errorOpeningItem => _locale == 'ar'
      ? 'حدث خطأ أثناء فتح العنصر'
      : 'Error opening item';

  @Deprecated('Use LibraryLocalizations.of(context).fileNotFound')
  static String get fileNotFound => _locale == 'ar'
      ? 'الملف غير موجود'
      : 'File not found';

  @Deprecated('Use LibraryLocalizations.of(context).fileAccessError')
  static String get fileAccessError => _locale == 'ar'
      ? 'تعذر الوصول إلى الملف'
      : 'Unable to access file';

  @Deprecated('Use LibraryLocalizations.of(context).fileSelectedError')
  static String get fileSelectedError => _locale == 'ar'
      ? 'تعذر الوصول إلى الملف المحدد'
      : 'Unable to access selected file';

  @Deprecated('Use LibraryLocalizations.of(context).uploadFailed')
  static String get uploadFailed => _locale == 'ar'
      ? 'فشل رفع الملف'
      : 'Upload failed';

  @Deprecated('Use LibraryLocalizations.of(context).retry')
  static String get retry => _locale == 'ar'
      ? 'إعادة المحاولة'
      : 'Retry';

  @Deprecated('Use LibraryLocalizations.of(context).addNewContent')
  static String get addNewContent => _locale == 'ar'
      ? 'إضافة محتوى جديد'
      : 'Add new content';

  @Deprecated('Use LibraryLocalizations.of(context).noteOption')
  static String get noteOption => _locale == 'ar'
      ? 'ملاحظة نصية'
      : 'Note';

  @Deprecated('Use LibraryLocalizations.of(context).writeNewNote')
  static String get writeNewNote => _locale == 'ar'
      ? 'اكتب ملاحظة جديدة'
      : 'Write a new note';

  @Deprecated('Use LibraryLocalizations.of(context).uploadFile')
  static String get uploadFile => _locale == 'ar'
      ? 'رفع ملف'
      : 'Upload file';

  @Deprecated('Use LibraryLocalizations.of(context).selectFromFile')
  static String get selectFromFile => _locale == 'ar'
      ? 'اختر ملفاً من جهازك'
      : 'Select a file from your device';

  @Deprecated('Use LibraryLocalizations.of(context).uploadSuccess(fileName)')
  static String uploadSuccess(String fileName) => _locale == 'ar'
      ? 'تم رفع "$fileName" بنجاح'
      : '"$fileName" uploaded successfully';

  @Deprecated('Use LibraryLocalizations.of(context).uploadFailedWithName(fileName, error)')
  static String uploadFailedWithName(String fileName, String error) => _locale == 'ar'
      ? 'فشل رفع "$fileName": $error'
      : 'Failed to upload "$fileName": $error';
}
