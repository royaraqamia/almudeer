"""
Al-Mudeer - Pydantic Schemas
Request and Response models for the API
"""

from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime


# ============ License Key Schemas ============

class LicenseKeyValidation(BaseModel):
    """Request to validate a license key"""
    key: str = Field(..., description="مفتاح الاشتراك", min_length=10)


class LicenseKeyResponse(BaseModel):
    """Response for license key validation"""
    valid: bool
    full_name: Optional[str] = None
    created_at: Optional[str] = None
    expires_at: Optional[str] = None
    error: Optional[str] = None


class LicenseKeyCreate(BaseModel):
    """Request to create a new license key (admin only)"""
    full_name: str = Field(..., description="الاسم الكامل")
    contact_email: Optional[str] = Field(None, description="البريد الإلكتروني")
    days_valid: int = Field(365, description="مدة الصلاحية بالأيام")


# ============ Message Processing Schemas ============

class MessageInput(BaseModel):
    """Input for message processing"""
    message: str = Field(..., description="نص الرسالة", min_length=10)
    message_type: Optional[str] = Field(None, description="نوع الرسالة: email, whatsapp, general")
    sender_name: Optional[str] = Field(None, description="اسم المرسل")
    sender_contact: Optional[str] = Field(None, description="بيانات التواصل")


class ProcessingResponse(BaseModel):
    """Response for message processing"""
    success: bool
    error: Optional[str] = None


# ============ CRM Schemas ============

class CRMEntryCreate(BaseModel):
    """Request to save a CRM entry"""
    sender_name: Optional[str] = Field(None, description="اسم المرسل")
    sender_contact: Optional[str] = Field(None, description="بيانات التواصل")
    message_type: str = Field("general", description="نوع الرسالة")
    intent: str = Field(..., description="النية")
    extracted_data: str = Field("", description="البيانات المستخرجة")
    original_message: str = Field(..., description="الرسالة الأصلية")
    draft_response: str = Field("", description="الرد المقترح")


class CRMEntry(BaseModel):
    """CRM entry response"""
    id: int
    sender_name: Optional[str]
    sender_contact: Optional[str]
    message_type: str
    intent: str
    extracted_data: str
    original_message: str
    draft_response: str
    status: str
    created_at: str
    updated_at: Optional[str]


class CRMListResponse(BaseModel):
    """Response for CRM entries list"""
    entries: List[CRMEntry]
    total: int


# ============ Health Check ============

class HealthCheck(BaseModel):
    """Health check response"""
    status: str = Field("healthy", description="Service status: healthy, degraded, unhealthy")
    timestamp: Optional[float] = Field(None, description="Unix timestamp of health check")
    database: str = Field("connected", description="Database connection status")
    cache: str = Field("available", description="Cache availability status")
    version: str = Field("1.0.0", description="API version")
    service: str = Field("Al-Mudeer API", description="Service name")
