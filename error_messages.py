"""
Al-Mudeer - Centralized Error Messages
Bilingual error messages (English/Arabic) for consistent API responses.
"""

from typing import Optional, Dict, Any
from dataclasses import dataclass, asdict


@dataclass
class ErrorMessage:
    """Bilingual error message structure"""
    message_en: str
    message_ar: str
    error_code: str
    http_status: int = 400
    
    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


# ============ Authentication Errors ============

class AuthErrors:
    LICENSE_KEY_MISSING = ErrorMessage(
        message_en="License key required",
        message_ar="مفتاح الاشتراك مطلوب للمتابعة",
        error_code="AUTH_LICENSE_MISSING",
        http_status=401
    )
    
    LICENSE_KEY_INVALID = ErrorMessage(
        message_en="Invalid or expired license key",
        message_ar="مفتاح الاشتراك غير صالح أو منتهي الصلاحية",
        error_code="AUTH_LICENSE_INVALID",
        http_status=401
    )
    
    LICENSE_KEY_DISABLED = ErrorMessage(
        message_en="Account has been disabled",
        message_ar="تم تعطيل الحساب",
        error_code="AUTH_ACCOUNT_DISABLED",
        http_status=403
    )
    
    TOKEN_EXPIRED = ErrorMessage(
        message_en="Authentication token has expired",
        message_ar="انتهت صلاحية رمز المصادقة",
        error_code="AUTH_TOKEN_EXPIRED",
        http_status=401
    )
    
    TOKEN_INVALID = ErrorMessage(
        message_en="Invalid authentication token",
        message_ar="رمز المصادقة غير صالح",
        error_code="AUTH_TOKEN_INVALID",
        http_status=401
    )


# ============ Validation Errors ============

class ValidationErrors:
    MESSAGE_EMPTY = ErrorMessage(
        message_en="Message cannot be empty",
        message_ar="الرسالة فارغة",
        error_code="VALIDATION_MESSAGE_EMPTY",
        http_status=400
    )
    
    MESSAGE_TOO_LONG = ErrorMessage(
        message_en="Message exceeds maximum length",
        message_ar="الرسالة تتجاوز الحد الأقصى للطول",
        error_code="VALIDATION_MESSAGE_TOO_LONG",
        http_status=400
    )
    
    INVALID_CHANNEL = ErrorMessage(
        message_en="Invalid channel specified",
        message_ar="القناة المحددة غير صالحة",
        error_code="VALIDATION_INVALID_CHANNEL",
        http_status=400
    )
    
    CONVERSATION_NOT_FOUND = ErrorMessage(
        message_en="Conversation not found",
        message_ar="المحادثة غير موجودة",
        error_code="VALIDATION_CONVERSATION_NOT_FOUND",
        http_status=404
    )
    
    MESSAGE_NOT_FOUND = ErrorMessage(
        message_en="Message not found",
        message_ar="الرسالة غير موجودة",
        error_code="VALIDATION_MESSAGE_NOT_FOUND",
        http_status=404
    )
    
    INVALID_ATTACHMENT = ErrorMessage(
        message_en="Invalid or unsupported attachment",
        message_ar="مرفق غير صالح أو غير مدعوم",
        error_code="VALIDATION_INVALID_ATTACHMENT",
        http_status=400
    )
    
    ATTACHMENT_TOO_LARGE = ErrorMessage(
        message_en="Attachment exceeds maximum size",
        message_ar="المرفق يتجاوز الحد الأقصى للحجم",
        error_code="VALIDATION_ATTACHMENT_TOO_LARGE",
        http_status=400
    )


# ============ Authorization Errors ============

class AuthorizationErrors:
    ACCESS_DENIED = ErrorMessage(
        message_en="Access denied",
        message_ar="عذراً، هذا الإجراء غير مصرح به",
        error_code="AUTHZ_ACCESS_DENIED",
        http_status=403
    )
    
    ADMIN_ONLY = ErrorMessage(
        message_en="Admin access required",
        message_ar="عذراً، هذا الإجراء مخصص للمسؤولين فقط",
        error_code="AUTHZ_ADMIN_ONLY",
        http_status=403
    )
    
    RESOURCE_NOT_OWNED = ErrorMessage(
        message_en="You don't have permission to access this resource",
        message_ar="ليس لديك صلاحية الوصول إلى هذا المورد",
        error_code="AUTHZ_NOT_OWNED",
        http_status=403
    )


# ============ Rate Limit Errors ============

class RateLimitErrors:
    RATE_LIMIT_EXCEEDED = ErrorMessage(
        message_en="Rate limit exceeded. Please try again later",
        message_ar="تم تجاوز الحد المسموح. حاول مرة أخرى لاحقاً",
        error_code="RATE_LIMIT_EXCEEDED",
        http_status=429
    )
    
    TOO_MANY_REQUESTS = ErrorMessage(
        message_en="Too many requests. Please slow down",
        message_ar="طلبات كثيرة جداً. يرجى التباطؤ",
        error_code="TOO_MANY_REQUESTS",
        http_status=429
    )


# ============ Message Errors ============

class MessageErrors:
    SEND_FAILED = ErrorMessage(
        message_en="Failed to send message. Please try again",
        message_ar="فشل إرسال الرسالة. يرجى المحاولة مرة أخرى",
        error_code="MESSAGE_SEND_FAILED",
        http_status=500
    )
    
    EDIT_NOT_ALLOWED = ErrorMessage(
        message_en="Message can no longer be edited",
        message_ar="لم يعد من الممكن تعديل الرسالة",
        error_code="MESSAGE_EDIT_NOT_ALLOWED",
        http_status=400
    )
    
    DELETE_NOT_ALLOWED = ErrorMessage(
        message_en="Message can no longer be deleted",
        message_ar="لم يعد من الممكن حذف الرسالة",
        error_code="MESSAGE_DELETE_NOT_ALLOWED",
        http_status=400
    )
    
    ALREADY_DELETED = ErrorMessage(
        message_en="Message already deleted",
        message_ar="الرسالة محذوفة مسبقاً",
        error_code="MESSAGE_ALREADY_DELETED",
        http_status=400
    )
    
    REPLY_NOT_FOUND = ErrorMessage(
        message_en="Original message not found for reply",
        message_ar="الرسالة الأصلية للرد غير موجودة",
        error_code="MESSAGE_REPLY_NOT_FOUND",
        http_status=404
    )


# ============ Conversation Errors ============

class ConversationErrors:
    CLEAR_FAILED = ErrorMessage(
        message_en="Failed to clear conversation",
        message_ar="فشل مسح المحادثة",
        error_code="CONVERSATION_CLEAR_FAILED",
        http_status=500
    )
    
    DELETE_FAILED = ErrorMessage(
        message_en="Failed to delete conversation",
        message_ar="فشل حذف المحادثة",
        error_code="CONVERSATION_DELETE_FAILED",
        http_status=500
    )
    
    BATCH_TOO_LARGE = ErrorMessage(
        message_en="Batch size exceeds maximum (50 conversations)",
        message_ar="الحد الأقصى لعدد المحادثات التي يمكن حذفها دفعة واحدة هو 50",
        error_code="CONVERSATION_BATCH_TOO_LARGE",
        http_status=400
    )
    
    EMPTY_BATCH = ErrorMessage(
        message_en="Conversation list is empty",
        message_ar="قائمة المحادثات فارغة",
        error_code="CONVERSATION_EMPTY_BATCH",
        http_status=400
    )


# ============ Integration Errors ============

class IntegrationErrors:
    WHATSAPP_FAILED = ErrorMessage(
        message_en="WhatsApp integration error",
        message_ar="خطأ في تكامل واتساب",
        error_code="INTEGRATION_WHATSAPP_FAILED",
        http_status=500
    )
    
    TELEGRAM_FAILED = ErrorMessage(
        message_en="Telegram integration error",
        message_ar="خطأ في تكامل تيليجرام",
        error_code="INTEGRATION_TELEGRAM_FAILED",
        http_status=500
    )
    
    EMAIL_FAILED = ErrorMessage(
        message_en="Email integration error",
        message_ar="خطأ في تكامل البريد الإلكتروني",
        error_code="INTEGRATION_EMAIL_FAILED",
        http_status=500
    )
    
    SERVICE_UNAVAILABLE = ErrorMessage(
        message_en="Service temporarily unavailable",
        message_ar="الخدمة غير متاحة مؤقتاً",
        error_code="SERVICE_UNAVAILABLE",
        http_status=503
    )


# ============ Database Errors ============

class DatabaseErrors:
    CONNECTION_FAILED = ErrorMessage(
        message_en="Database connection failed",
        message_ar="فشل الاتصال بقاعدة البيانات",
        error_code="DB_CONNECTION_FAILED",
        http_status=500
    )
    
    QUERY_FAILED = ErrorMessage(
        message_en="Database query failed",
        message_ar="فشل استعلام قاعدة البيانات",
        error_code="DB_QUERY_FAILED",
        http_status=500
    )
    
    DUPLICATE_ENTRY = ErrorMessage(
        message_en="Duplicate entry detected",
        message_ar="تم اكتشاف إدخال مكرر",
        error_code="DB_DUPLICATE_ENTRY",
        http_status=409
    )


# ============ File/Storage Errors ============

class StorageErrors:
    FILE_NOT_FOUND = ErrorMessage(
        message_en="File not found",
        message_ar="الملف غير موجود",
        error_code="STORAGE_FILE_NOT_FOUND",
        http_status=404
    )
    
    UPLOAD_FAILED = ErrorMessage(
        message_en="File upload failed",
        message_ar="فشل رفع الملف",
        error_code="STORAGE_UPLOAD_FAILED",
        http_status=500
    )
    
    DELETE_FAILED = ErrorMessage(
        message_en="File deletion failed",
        message_ar="فشل حذف الملف",
        error_code="STORAGE_DELETE_FAILED",
        http_status=500
    )
    
    STORAGE_FULL = ErrorMessage(
        message_en="Storage quota exceeded",
        message_ar="تم تجاوز حصة التخزين",
        error_code="STORAGE_FULL",
        http_status=413
    )


# ============ Helper Functions ============

def get_error_response(error: ErrorMessage, details: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """
    Create standardized error response.
    
    Args:
        error: ErrorMessage instance
        details: Optional additional details
    
    Returns:
        Standardized error response dict
    """
    response = {
        "error": True,
        "error_code": error.error_code,
        "message": error.message_en,
        "message_ar": error.message_ar,
        "status_code": error.http_status,
    }
    
    if details:
        response["details"] = details
    
    return response


def create_error_json(
    error_code: str,
    message_en: str,
    message_ar: str,
    http_status: int = 400,
    details: Optional[Dict[str, Any]] = None
) -> Dict[str, Any]:
    """
    Create custom error response.
    
    Args:
        error_code: Unique error code
        message_en: English message
        message_ar: Arabic message
        http_status: HTTP status code
        details: Optional additional details
    
    Returns:
        Error response dict
    """
    return get_error_response(
        ErrorMessage(
            message_en=message_en,
            message_ar=message_ar,
            error_code=error_code,
            http_status=http_status
        ),
        details
    )
