"""
Al-Mudeer - Feature Routes
Customers, Analytics, Preferences, Voice Transcription
"""

from fastapi import APIRouter, HTTPException, Depends, UploadFile, File
from pydantic import BaseModel, Field
from typing import Optional, List, Union
from datetime import datetime, timedelta

from models import (
    get_customers,
    get_customer,
    update_customer,
    delete_customer,
    get_or_create_customer,
    get_preferences,
    update_preferences,
    get_notifications,
    get_unread_count,
    mark_notification_read,
    mark_all_notifications_read,
    create_notification,
)
# from services.voice_service import ... (Removed)
# from services.auto_categorization import categorize_message_dict, categorize_messages_batch (AI removed)
from security import sanitize_email, sanitize_phone, sanitize_string
from dependencies import get_license_from_header, get_optional_license_from_header
from db_helper import get_db, fetch_all

router = APIRouter(prefix="/api", tags=["Features"])


# ============ Customers Schemas ============

class CustomerUpdate(BaseModel):
    name: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    company: Optional[str] = None
    notes: Optional[str] = None
    tags: Optional[str] = None
    is_vip: Optional[bool] = None
    has_whatsapp: Optional[bool] = None
    has_telegram: Optional[bool] = None
    username: Optional[str] = None


class CustomerCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=200)
    phone: Optional[str] = None
    email: Optional[str] = None
    company: Optional[str] = None
    notes: Optional[str] = None
    has_whatsapp: bool = False
    has_telegram: bool = False
    username: Optional[str] = None


# ============ Customers Routes ============

@router.post("/customers")
async def add_customer(
    data: CustomerCreate,
    license: dict = Depends(get_license_from_header)
):
    """Add a new customer or get existing one"""
    customer = await get_or_create_customer(
        license["license_id"],
        name=sanitize_string(data.name, max_length=200),
        phone=sanitize_phone(data.phone) if data.phone else None,
        email=sanitize_email(data.email) if data.email else None,
        username=sanitize_string(data.username, max_length=100) if data.username else None,
        has_whatsapp=data.has_whatsapp,
        has_telegram=data.has_telegram,
        is_manual=True
    )
    
    # If customer was created or found, update notes/company if provided
    if customer.get("id") and (data.notes or data.company):
        await update_customer(
            license["license_id"],
            customer["id"],
            notes=sanitize_string(data.notes, max_length=1000) if data.notes else customer.get("notes"),
            company=sanitize_string(data.company, max_length=200) if data.company else customer.get("company")
        )
        # Fetch updated customer
        customer = await get_customer(license["license_id"], customer["id"])
        
    return {"success": True, "customer": customer}


@router.get("/customers")
async def list_customers(
    page: int = 1,
    page_size: int = 20,
    search: Optional[str] = None,
    license: dict = Depends(get_license_from_header)
):
    """Get all customers (paginated)"""
    from services.pagination import paginate_customers
    return await paginate_customers(license["license_id"], page, page_size, search)


@router.get("/customers/{customer_id}")
async def get_customer_detail(
    customer_id: int,
    license: dict = Depends(get_license_from_header)
):
    """Get customer details"""
    customer = await get_customer(license["license_id"], customer_id)
    if not customer:
        raise HTTPException(status_code=404, detail="العميل غير موجود")
    
    return {"customer": customer}


@router.patch("/customers/{customer_id}")
async def update_customer_detail(
    customer_id: int,
    data: CustomerUpdate,
    license: dict = Depends(get_license_from_header)
):
    """Update customer details"""
    # Sanitize and normalize incoming data without changing the response shape
    raw_data = data.dict(exclude_unset=True)

    if "email" in raw_data:
        sanitized_email = sanitize_email(raw_data["email"])
        if not sanitized_email and raw_data["email"]:
            raise HTTPException(status_code=400, detail="البريد الإلكتروني غير صالح")
        raw_data["email"] = sanitized_email

    if "phone" in raw_data:
        sanitized_phone = sanitize_phone(raw_data["phone"])
        if not sanitized_phone and raw_data["phone"]:
            raise HTTPException(status_code=400, detail="رقم الهاتف غير صالح")
        raw_data["phone"] = sanitized_phone

    # Light sanitization for free-text fields (notes/tags/company/name)
    for field_name in ("name", "company", "notes", "tags"):
        if field_name in raw_data and raw_data[field_name] is not None:
            raw_data[field_name] = sanitize_string(str(raw_data[field_name]), max_length=1000)

    success = await update_customer(
        license["license_id"],
        customer_id,
        **raw_data
    )
    if not success:
        raise HTTPException(status_code=404, detail="العميل غير موجود")
    
    # Fetch and return the updated customer object for frontend sync
    from models.customers import get_customer
    updated_customer = await get_customer(license["license_id"], customer_id)
    
    return {
        "success": True, 
        "message": "تم تحديث بيانات العميل",
        "customer": updated_customer
    }


@router.delete("/customers/{customer_id}")
async def delete_customer_endpoint(
    customer_id: int,
    license: dict = Depends(get_license_from_header)
):
    """Delete a customer and related records"""
    success = await delete_customer(license["license_id"], customer_id)
    if not success:
        raise HTTPException(status_code=404, detail="العميل غير موجود")
    
    return {"success": True, "message": "تم حذف العميل بنجاح"}


class BulkDeleteRequest(BaseModel):
    customer_ids: List[int]


@router.post("/customers/bulk-delete")
async def bulk_delete_customers_endpoint(
    req: BulkDeleteRequest,
    license: dict = Depends(get_license_from_header)
):
    """Delete multiple customers and related records"""
    from models.customers import delete_customers
    success = await delete_customers(license["license_id"], req.customer_ids)
    if not success:
        raise HTTPException(status_code=400, detail="لم يتم العثور على العملاء أو فشل الحذف")
    
    return {"success": True, "message": "تم حذف العملاء بنجاح"}

# ============ Preferences Schemas ============

class PreferencesUpdate(BaseModel):
    dark_mode: Optional[bool] = None
    notifications_enabled: Optional[bool] = None
    notification_sound: Optional[bool] = None
    onboarding_completed: Optional[bool] = None
    
    # AI / Tone Settings
    tone: Optional[str] = None
    custom_tone_guidelines: Optional[str] = None
    preferred_languages: Optional[Union[str, List[str]]] = None
    formality_level: Optional[str] = None


# ============ Preferences Routes ============

# ============ Preferences Routes ============

@router.get("/preferences")
async def get_user_preferences(license: dict = Depends(get_license_from_header)):
    """Get user preferences"""
    prefs = await get_preferences(license["license_id"])
    return {"preferences": prefs}


@router.get("/quran/progress")
async def get_quran_progress(license: dict = Depends(get_license_from_header)):
    """Get Quran reading progress for cross-device sync"""
    prefs = await get_preferences(license["license_id"])
    quran_progress = prefs.get('quran_progress')
    
    if quran_progress:
        import json
        try:
            data = json.loads(quran_progress) if isinstance(quran_progress, str) else quran_progress
            return {"success": True, "progress": data}
        except:
            return {"success": True, "progress": None}
    
    return {"success": True, "progress": None}


@router.get("/athkar/progress")
async def get_athkar_progress(license: dict = Depends(get_license_from_header)):
    """Get Athkar counts and misbaha for cross-device sync"""
    prefs = await get_preferences(license["license_id"])
    athkar_stats = prefs.get('athkar_stats')
    
    if athkar_stats:
        import json
        try:
            data = json.loads(athkar_stats) if isinstance(athkar_stats, str) else athkar_stats
            return {"success": True, "athkar": data}
        except:
            return {"success": True, "athkar": None}
    
    return {"success": True, "athkar": None}


@router.patch("/preferences")
async def update_user_preferences(
    data: PreferencesUpdate,
    license: dict = Depends(get_license_from_header)
):
    """Update user preferences"""
    await update_preferences(
        license["license_id"],
        **data.dict(exclude_none=True)
    )
    return {"success": True, "message": "تم حفظ التفضيلات"}


# ============ Voice Transcription Schemas Removed ============


# ============ Voice Transcription Routes Removed ============

# AI Categorization Check endpoint removed
# ============ Notifications Routes ============


# AI Categorization Check endpoint removed
# ============ Notifications Routes ============

@router.get("/notifications")
async def list_notifications(
    unread_only: bool = False,
    limit: int = 50,
    license: dict = Depends(get_optional_license_from_header)
):
    """Get user notifications"""
    if not license:
        # When there is no valid license key, return empty notifications instead of 401
        return {
            "notifications": [],
            "unread_count": 0,
            "total": 0
        }

    notifications = await get_notifications(license["license_id"], unread_only, limit)
    unread = await get_unread_count(license["license_id"])
    
    return {
        "notifications": notifications,
        "unread_count": unread,
        "total": len(notifications)
    }


@router.get("/notifications/count")
async def get_notification_count(license: dict = Depends(get_optional_license_from_header)):
    """Get unread notification count.

    If the license key is missing or invalid we return 0 instead of an error
    so the dashboard badge doesn't break for unauthenticated or pre-rendered views.
    """
    if not license:
        return {"unread_count": 0}

    count = await get_unread_count(license["license_id"])
    return {"unread_count": count}


@router.post("/notifications/{notification_id}/read")
async def read_notification(
    notification_id: int,
    license: dict = Depends(get_license_from_header)
):
    """Mark notification as read"""
    await mark_notification_read(license["license_id"], notification_id)
    return {"success": True, "message": "تم تحديث الإشعار"}


@router.post("/notifications/read-all")
async def read_all_notifications(license: dict = Depends(get_license_from_header)):
    """Mark all notifications as read"""
    await mark_all_notifications_read(license["license_id"])
    return {"success": True, "message": "تم تحديث جميع الإشعارات"}


# Auto-categorization routes removed

