/// Share Error Codes
/// 
/// Standardized error codes for share operations.
/// These match the backend error codes in backend/utils/share_utils.py
/// 
/// Mobile app should match on these codes instead of error message strings
/// for more robust error handling.
library;

/// Error codes for share operations
class ShareErrorCode {
  // Task share errors
  static const String taskNotFound = 'TASK_NOT_FOUND';
  static const String taskOwnerOnly = 'TASK_OWNER_ONLY';
  static const String selfShare = 'SELF_SHARE';
  static const String shareRevoked = 'SHARE_REVOKED';
  static const String userNotFound = 'USER_NOT_FOUND';
  static const String invalidPermission = 'INVALID_PERMISSION';
  
  // Library share errors
  static const String itemNotFound = 'ITEM_NOT_FOUND';
  static const String itemOwnerOnly = 'ITEM_OWNER_ONLY';
  static const String selfItemShare = 'SELF_ITEM_SHARE';
  static const String itemShareRevoked = 'ITEM_SHARE_REVOKED';
  
  // General errors
  static const String invalidShare = 'INVALID_SHARE';
  static const String shareFailed = 'SHARE_FAILED';
  static const String permissionDenied = 'PERMISSION_DENIED';
  static const String storageLimitExceeded = 'STORAGE_LIMIT_EXCEEDED';
  static const String internalError = 'INTERNAL_ERROR';
  
  // Special case: share already exists (backend updated it, not really an error)
  static const String shareAlreadyExists = 'SHARE_ALREADY_EXISTS';
}

/// Helper to extract error code from exception
/// 
/// Backend returns errors in format:
/// {
///   "code": "ERROR_CODE",
///   "message_ar": "...",
///   "message_en": "..."
/// }
class ShareErrorHelper {
  /// Extract error code from exception
  /// Returns null if no code found
  static String? extractErrorCode(dynamic error) {
    if (error == null) return null;
    
    final errorStr = error.toString();
    
    // Try to parse as JSON first
    try {
      if (errorStr.contains('{') && errorStr.contains('}')) {
        // Extract JSON-like part
        final jsonStart = errorStr.indexOf('{');
        final jsonEnd = errorStr.lastIndexOf('}') + 1;
        if (jsonStart >= 0 && jsonEnd > jsonStart) {
          final jsonStr = errorStr.substring(jsonStart, jsonEnd);
          // Simple parsing without dart:convert to avoid import issues
          final codeMatch = RegExp(r'"code"\s*:\s*"([^"]+)"').firstMatch(jsonStr);
          if (codeMatch != null && codeMatch.groupCount >= 1) {
            return codeMatch.group(1);
          }
        }
      }
    } catch (_) {
      // Fall back to string matching
    }
    
    // Fallback: match on common patterns in error messages
    final errorLower = errorStr.toLowerCase();
    if (errorLower.contains('yourself')) {
      return ShareErrorCode.selfShare;
    }
    if (errorLower.contains('task') && errorLower.contains('not found')) {
      return ShareErrorCode.taskNotFound;
    }
    if (errorLower.contains('item') && errorLower.contains('not found')) {
      return ShareErrorCode.itemNotFound;
    }
    if (errorLower.contains('not found')) {
      return ShareErrorCode.userNotFound;
    }
    if (errorLower.contains('permission') || errorLower.contains('privilege')) {
      return ShareErrorCode.permissionDenied;
    }
    if (errorLower.contains('revoked')) {
      return ShareErrorCode.shareRevoked;
    }
    if (errorLower.contains('owner')) {
      return ShareErrorCode.taskOwnerOnly;
    }
    if (errorLower.contains('already') || errorLower.contains('existing')) {
      return ShareErrorCode.shareAlreadyExists;
    }
    
    return ShareErrorCode.invalidShare;
  }
  
  /// Check if error is a "soft" error that should be treated as success
  /// (e.g., share already exists - backend updated it)
  static bool isSoftError(String? errorCode) {
    return errorCode == ShareErrorCode.shareAlreadyExists;
  }
  
  /// Get user-friendly message for error code
  static Map<String, String> getErrorMessage(String errorCode) {
    switch (errorCode) {
      case ShareErrorCode.selfShare:
        return {
          'ar': 'لا يمكنك المشاركة مع نفسك',
          'en': 'Cannot share with yourself',
        };
      case ShareErrorCode.taskNotFound:
        return {
          'ar': 'المهمة غير موجودة',
          'en': 'Task not found',
        };
      case ShareErrorCode.itemNotFound:
        return {
          'ar': 'العنصر غير موجود',
          'en': 'Item not found',
        };
      case ShareErrorCode.userNotFound:
        return {
          'ar': 'المستخدم غير موجود',
          'en': 'User not found',
        };
      case ShareErrorCode.permissionDenied:
        return {
          'ar': 'ليس لديك صلاحية المشاركة',
          'en': 'Permission denied',
        };
      case ShareErrorCode.shareRevoked:
        return {
          'ar': 'تم إلغاء هذه المشاركة سابقاً',
          'en': 'Share was previously revoked',
        };
      case ShareErrorCode.shareAlreadyExists:
        return {
          'ar': 'تم تحديث المشاركة الموجودة',
          'en': 'Existing share updated',
        };
      default:
        return {
          'ar': 'حدث خطأ في المشاركة',
          'en': 'Share failed',
        };
    }
  }
}
