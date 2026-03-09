/// Simple localization for library screen strings
/// 
/// TODO: Replace with full flutter_localizations when implemented
class LibraryLocalization {
  static const String _locale = 'ar'; // Current app locale

  // Library Screen - Error Messages
  static String get errorOpeningItem => _locale == 'ar' 
      ? 'حدث خطأ أثناء فتح العنصر' 
      : 'Error opening item';
  
  static String get fileNotFound => _locale == 'ar'
      ? 'الملف غير موجود'
      : 'File not found';
  
  static String get fileAccessError => _locale == 'ar'
      ? 'تعذر الوصول إلى الملف'
      : 'Unable to access file';
  
  static String get fileSelectedError => _locale == 'ar'
      ? 'تعذر الوصول إلى الملف المحدد'
      : 'Unable to access selected file';
  
  static String get uploadFailed => _locale == 'ar'
      ? 'فشل رفع الملف'
      : 'Upload failed';
  
  static String get retry => _locale == 'ar'
      ? 'إعادة المحاولة'
      : 'Retry';
  
  static String get addNewContent => _locale == 'ar'
      ? 'إضافة محتوى جديد'
      : 'Add new content';
  
  static String get noteOption => _locale == 'ar'
      ? 'ملاحظة نصية'
      : 'Note';
  
  static String get writeNewNote => _locale == 'ar'
      ? 'اكتب ملاحظة جديدة'
      : 'Write a new note';
  
  static String get uploadFile => _locale == 'ar'
      ? 'رفع ملف'
      : 'Upload file';
  
  static String get selectFromFile => _locale == 'ar'
      ? 'اختر ملفاً من جهازك'
      : 'Select a file from your device';
  
  static String uploadSuccess(String fileName) => _locale == 'ar'
      ? 'تم رفع "$fileName" بنجاح'
      : '"$fileName" uploaded successfully';
  
  static String uploadFailedWithName(String fileName, String error) => _locale == 'ar'
      ? 'فشل رفع "$fileName": $error'
      : 'Failed to upload "$fileName": $error';
}
