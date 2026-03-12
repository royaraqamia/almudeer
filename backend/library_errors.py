"""
FIX #6: Centralized Library Error Codes
Standardized error codes for consistent error handling across library endpoints.

Usage:
    from errors import LibraryErrorCode, raise_library_error
    
    raise_library_error(
        error_code=LibraryErrorCode.STORAGE_LIMIT_EXCEEDED,
        status_code=400
    )
"""

from fastapi import HTTPException
from typing import Optional, Dict, Any


class LibraryErrorCode:
    """Standardized error codes for library operations"""
    
    # Storage errors (400)
    STORAGE_LIMIT_EXCEEDED = "STORAGE_LIMIT_EXCEEDED"
    FILE_TOO_LARGE = "FILE_TOO_LARGE"
    INVALID_FILE_TYPE = "INVALID_FILE_TYPE"
    FILE_UPLOAD_FAILED = "FILE_UPLOAD_FAILED"
    FILE_NOT_FOUND = "FILE_NOT_FOUND"
    
    # Item errors (404)
    ITEM_NOT_FOUND = "ITEM_NOT_FOUND"
    ATTACHMENT_NOT_FOUND = "ATTACHMENT_NOT_FOUND"
    
    # Permission errors (403)
    UNAUTHORIZED = "UNAUTHORIZED"
    FORBIDDEN = "FORBIDDEN"
    PERMISSION_DENIED = "PERMISSION_DENIED"
    CUSTOMER_ACCESS_DENIED = "CUSTOMER_ACCESS_DENIED"
    
    # Validation errors (400)
    NOTE_TOO_LONG = "NOTE_TOO_LONG"
    SEARCH_TERM_TOO_LONG = "SEARCH_TERM_TOO_LONG"
    INVALID_PARAMETER = "INVALID_PARAMETER"
    VALIDATION_ERROR = "VALIDATION_ERROR"
    
    # Share errors (400/403)
    SHARE_NOT_FOUND = "SHARE_NOT_FOUND"
    SHARE_PERMISSION_DENIED = "SHARE_PERMISSION_DENIED"
    SELF_SHARE_NOT_ALLOWED = "SELF_SHARE_NOT_ALLOWED"
    PERMISSION_ESCALATION_NOT_ALLOWED = "PERMISSION_ESCALATION_NOT_ALLOWED"
    
    # Version errors (400/404)
    VERSION_NOT_FOUND = "VERSION_NOT_FOUND"
    VERSION_RESTORE_FAILED = "VERSION_RESTORE_FAILED"
    
    # System errors (500)
    INTERNAL_ERROR = "INTERNAL_ERROR"
    DATABASE_ERROR = "DATABASE_ERROR"
    FILE_STORAGE_ERROR = "FILE_STORAGE_ERROR"
    NOTIFICATION_FAILED = "NOTIFICATION_FAILED"


# Error message templates (Arabic)
ERROR_MESSAGES_AR = {
    LibraryErrorCode.STORAGE_LIMIT_EXCEEDED: "تجاوزت حد التخزين المسموح به",
    LibraryErrorCode.FILE_TOO_LARGE: "حجم الملف كبير جداً",
    LibraryErrorCode.INVALID_FILE_TYPE: "نوع الملف غير مدعوم",
    LibraryErrorCode.FILE_UPLOAD_FAILED: "فشل رفع الملف",
    LibraryErrorCode.FILE_NOT_FOUND: "الملف غير موجود",
    LibraryErrorCode.ITEM_NOT_FOUND: "العنصر غير موجود",
    LibraryErrorCode.ATTACHMENT_NOT_FOUND: "المرفق غير موجود",
    LibraryErrorCode.UNAUTHORIZED: "غير مصرح",
    LibraryErrorCode.FORBIDDEN: "محظور",
    LibraryErrorCode.PERMISSION_DENIED: "تم رفض الإذن",
    LibraryErrorCode.CUSTOMER_ACCESS_DENIED: "لا يمكنك الوصول إلى عميل لا يتبع رخصتك",
    LibraryErrorCode.NOTE_TOO_LONG: "الملاحظة طويلة جداً",
    LibraryErrorCode.SEARCH_TERM_TOO_LONG: "كلمة البحث طويلة جداً",
    LibraryErrorCode.INVALID_PARAMETER: "معلمة غير صالحة",
    LibraryErrorCode.VALIDATION_ERROR: "خطأ في التحقق من الصحة",
    LibraryErrorCode.SHARE_NOT_FOUND: "المشاركة غير موجودة",
    LibraryErrorCode.SHARE_PERMISSION_DENIED: "تم رفض إذن المشاركة",
    LibraryErrorCode.SELF_SHARE_NOT_ALLOWED: "لا يمكنك مشاركة عنصر مع نفسك",
    LibraryErrorCode.PERMISSION_ESCALATION_NOT_ALLOWED: "لا يمكنك منح إذن أعلى من مستوى إذنك",
    LibraryErrorCode.VERSION_NOT_FOUND: "الإصدار غير موجود",
    LibraryErrorCode.VERSION_RESTORE_FAILED: "فشل استعادة الإصدار",
    LibraryErrorCode.INTERNAL_ERROR: "خطأ داخلي في الخادم",
    LibraryErrorCode.DATABASE_ERROR: "خطأ في قاعدة البيانات",
    LibraryErrorCode.FILE_STORAGE_ERROR: "خطأ في تخزين الملفات",
    LibraryErrorCode.NOTIFICATION_FAILED: "فشل الإشعار",
}

# Error message templates (English)
ERROR_MESSAGES_EN = {
    LibraryErrorCode.STORAGE_LIMIT_EXCEEDED: "Storage limit exceeded",
    LibraryErrorCode.FILE_TOO_LARGE: "File size exceeds maximum limit",
    LibraryErrorCode.INVALID_FILE_TYPE: "Unsupported file type",
    LibraryErrorCode.FILE_UPLOAD_FAILED: "File upload failed",
    LibraryErrorCode.FILE_NOT_FOUND: "File not found",
    LibraryErrorCode.ITEM_NOT_FOUND: "Item not found",
    LibraryErrorCode.ATTACHMENT_NOT_FOUND: "Attachment not found",
    LibraryErrorCode.UNAUTHORIZED: "Unauthorized",
    LibraryErrorCode.FORBIDDEN: "Forbidden",
    LibraryErrorCode.PERMISSION_DENIED: "Permission denied",
    LibraryErrorCode.CUSTOMER_ACCESS_DENIED: "You cannot access a customer that doesn't belong to your license",
    LibraryErrorCode.NOTE_TOO_LONG: "Note content exceeds maximum length",
    LibraryErrorCode.SEARCH_TERM_TOO_LONG: "Search term too long",
    LibraryErrorCode.INVALID_PARAMETER: "Invalid parameter",
    LibraryErrorCode.VALIDATION_ERROR: "Validation error",
    LibraryErrorCode.SHARE_NOT_FOUND: "Share not found",
    LibraryErrorCode.SHARE_PERMISSION_DENIED: "Share permission denied",
    LibraryErrorCode.SELF_SHARE_NOT_ALLOWED: "Cannot share an item with yourself",
    LibraryErrorCode.PERMISSION_ESCALATION_NOT_ALLOWED: "Cannot grant permission higher than your own",
    LibraryErrorCode.VERSION_NOT_FOUND: "Version not found",
    LibraryErrorCode.VERSION_RESTORE_FAILED: "Failed to restore version",
    LibraryErrorCode.INTERNAL_ERROR: "Internal server error",
    LibraryErrorCode.DATABASE_ERROR: "Database error",
    LibraryErrorCode.FILE_STORAGE_ERROR: "File storage error",
    LibraryErrorCode.NOTIFICATION_FAILED: "Notification failed",
}

# Default HTTP status codes for each error
ERROR_STATUS_CODES = {
    # 400 Bad Request
    LibraryErrorCode.STORAGE_LIMIT_EXCEEDED: 400,
    LibraryErrorCode.FILE_TOO_LARGE: 400,
    LibraryErrorCode.INVALID_FILE_TYPE: 400,
    LibraryErrorCode.FILE_UPLOAD_FAILED: 400,
    LibraryErrorCode.NOTE_TOO_LONG: 400,
    LibraryErrorCode.SEARCH_TERM_TOO_LONG: 400,
    LibraryErrorCode.INVALID_PARAMETER: 400,
    LibraryErrorCode.VALIDATION_ERROR: 400,
    LibraryErrorCode.SHARE_PERMISSION_DENIED: 400,
    LibraryErrorCode.SELF_SHARE_NOT_ALLOWED: 400,
    LibraryErrorCode.PERMISSION_ESCALATION_NOT_ALLOWED: 400,
    LibraryErrorCode.VERSION_RESTORE_FAILED: 400,
    
    # 403 Forbidden
    LibraryErrorCode.FORBIDDEN: 403,
    LibraryErrorCode.PERMISSION_DENIED: 403,
    LibraryErrorCode.CUSTOMER_ACCESS_DENIED: 403,
    
    # 404 Not Found
    LibraryErrorCode.FILE_NOT_FOUND: 404,
    LibraryErrorCode.ITEM_NOT_FOUND: 404,
    LibraryErrorCode.ATTACHMENT_NOT_FOUND: 404,
    LibraryErrorCode.SHARE_NOT_FOUND: 404,
    LibraryErrorCode.VERSION_NOT_FOUND: 404,
    
    # 401 Unauthorized
    LibraryErrorCode.UNAUTHORIZED: 401,
    
    # 500 Internal Server Error
    LibraryErrorCode.INTERNAL_ERROR: 500,
    LibraryErrorCode.DATABASE_ERROR: 500,
    LibraryErrorCode.FILE_STORAGE_ERROR: 500,
    LibraryErrorCode.NOTIFICATION_FAILED: 500,
}


def raise_library_error(
    error_code: str,
    status_code: Optional[int] = None,
    message_ar: Optional[str] = None,
    message_en: Optional[str] = None,
    details: Optional[Dict[str, Any]] = None
) -> None:
    """
    Raise a standardized library error.
    
    Args:
        error_code: Error code from LibraryErrorCode
        status_code: Optional HTTP status code (uses default if not provided)
        message_ar: Optional custom Arabic message
        message_en: Optional custom English message
        details: Optional additional details to include
    
    Raises:
        HTTPException: With standardized error format
    """
    code = status_code or ERROR_STATUS_CODES.get(error_code, 400)
    
    detail = {
        "code": error_code,
        "message_ar": message_ar or ERROR_MESSAGES_AR.get(error_code, "حدث خطأ"),
        "message_en": message_en or ERROR_MESSAGES_EN.get(error_code, "An error occurred"),
    }
    
    if details:
        detail["details"] = details
    
    raise HTTPException(status_code=code, detail=detail)


def create_error_response(
    error_code: str,
    status_code: Optional[int] = None,
    message_ar: Optional[str] = None,
    message_en: Optional[str] = None,
    details: Optional[Dict[str, Any]] = None
) -> Dict[str, Any]:
    """
    Create a standardized error response dictionary.
    
    Args:
        error_code: Error code from LibraryErrorCode
        status_code: Optional HTTP status code
        message_ar: Optional custom Arabic message
        message_en: Optional custom English message
        details: Optional additional details
    
    Returns:
        Dict with standardized error format
    """
    code = status_code or ERROR_STATUS_CODES.get(error_code, 400)
    
    response = {
        "success": False,
        "error": {
            "code": error_code,
            "message_ar": message_ar or ERROR_MESSAGES_AR.get(error_code, "حدث خطأ"),
            "message_en": message_en or ERROR_MESSAGES_EN.get(error_code, "An error occurred"),
            "status_code": code,
        }
    }
    
    if details:
        response["error"]["details"] = details
    
    return response
