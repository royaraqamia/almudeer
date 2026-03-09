"""
Al-Mudeer - System & Account Routes
Health checks, worker status, AI usage, and unified account management
"""

import os
from fastapi import APIRouter, HTTPException, Depends, Request
from typing import List, Optional
from pydantic import BaseModel, Field

from models import (
    get_email_config,
    get_telegram_config,
    get_telegram_phone_session,
    get_whatsapp_config,
    update_email_config_settings,
    update_telegram_config_settings,
    update_telegram_phone_session_settings,
    update_whatsapp_config_settings,
)
from services import GmailOAuthService
from workers import get_worker_status
from dependencies import get_license_from_header
from db_helper import get_db, execute_sql, commit_db

router = APIRouter(prefix="/api/integrations", tags=["System & Accounts"])

class IntegrationAccount(BaseModel):
    id: str
    channel_type: str
    display_name: str
    is_active: bool
    details: Optional[str] = None

class WorkerStatusResponse(BaseModel):
    email_polling: dict
    telegram_polling: dict

@router.get("/debug")
def debug_integrations():
    return {"status": "ok", "message": "System & Accounts router is loaded"}

@router.get("/workers/status", response_model=WorkerStatusResponse)
async def worker_status_v1():
    """Operational status of background workers"""
    return get_worker_status()

# Specialized endpoint with license dependency (v2)
@router.get("/workers/status/detail")
async def worker_status_v2(license: dict = Depends(get_license_from_header)):
    """Detailed worker status for a specific license"""
    return {"workers": get_worker_status()}

@router.get("/accounts")
async def list_integration_accounts(license: dict = Depends(get_license_from_header)):
    """Unified view of all connected channels/accounts"""
    license_id = license["license_id"]
    accounts: List[IntegrationAccount] = []

    # Email
    email_cfg = await get_email_config(license_id, include_inactive=False)
    if email_cfg and isinstance(email_cfg, dict):
        accounts.append(
            IntegrationAccount(
                id="email",
                channel_type="email",
                display_name=str(email_cfg.get("email_address") or "Gmail"),
                is_active=bool(email_cfg.get("is_active")),
                details="Gmail OAuth"
            )
        )

    # Telegram bot
    telegram_cfg = await get_telegram_config(license_id, include_inactive=False)
    if telegram_cfg and isinstance(telegram_cfg, dict):
        display = telegram_cfg.get("bot_username") or "Telegram Bot"
        accounts.append(
            IntegrationAccount(
                id="telegram_bot",
                channel_type="telegram_bot",
                display_name=str(display),
                is_active=bool(telegram_cfg.get("is_active")),
                details=str(telegram_cfg.get("bot_token_masked") or "")
            )
        )

    # Telegram phone
    phone_cfg = await get_telegram_phone_session(license_id)
    if phone_cfg and isinstance(phone_cfg, dict):
        display = phone_cfg.get("phone_number_masked") or phone_cfg.get("phone_number") or "Telegram Phone"
        accounts.append(
            IntegrationAccount(
                id="telegram_phone",
                channel_type="telegram_phone",
                display_name=str(display),
                is_active=bool(phone_cfg.get("is_active", True)),
                details=str(phone_cfg.get("user_username") or "")
            )
        )

    # WhatsApp
    whatsapp_cfg = await get_whatsapp_config(license_id)
    if whatsapp_cfg and isinstance(whatsapp_cfg, dict):
        display = whatsapp_cfg.get("phone_number_id") or "WhatsApp Business"
        accounts.append(
            IntegrationAccount(
                id="whatsapp",
                channel_type="whatsapp",
                display_name=str(display),
                is_active=bool(whatsapp_cfg.get("is_active")),
                details=str(whatsapp_cfg.get("business_account_id") or "")
            )
        )

    return {"accounts": accounts}

@router.post("/accounts")
async def create_integration_account(
    request: dict,
    license: dict = Depends(get_license_from_header)
):
    """Create/link a new integration account"""
    license_id = license["license_id"]
    channel_type = request.get("channel_type")
    
    if not channel_type:
        raise HTTPException(status_code=400, detail="channel_type مطلوب")
    
    if channel_type == "email":
        oauth_service = GmailOAuthService()
        state = GmailOAuthService.encode_state(license_id)
        auth_url = oauth_service.get_authorization_url(state)
        return {
            "success": True,
            "action": "oauth_redirect",
            "authorization_url": auth_url,
            "message": "يرجى فتح هذا الرابط وتسجيل الدخول بحساب Google الخاص بك"
        }
    elif channel_type == "telegram_bot":
        bot_token = request.get("bot_token")
        if not bot_token:
            raise HTTPException(status_code=400, detail="bot_token مطلوب لربط Telegram Bot")
        
        from models import save_telegram_config
        await save_telegram_config(
            license_id=license_id,
            bot_token=bot_token
        )
        return {
            "success": True,
            "message": "تم ربط Telegram Bot بنجاح",
            "account_id": "telegram_bot"
        }
    elif channel_type == "whatsapp":
        phone_number_id = request.get("phone_number_id")
        access_token = request.get("access_token")
        if not phone_number_id or not access_token:
            raise HTTPException(status_code=400, detail="phone_number_id و access_token مطلوبان لربط WhatsApp")
        
        from services.whatsapp_service import save_whatsapp_config as save_wa_config
        verify_token = os.urandom(16).hex()
        
        await save_wa_config(
            license_id=license_id,
            phone_number_id=phone_number_id,
            access_token=access_token,
            business_account_id=request.get("business_account_id"),
            verify_token=verify_token
        )
        return {
            "success": True,
            "message": "تم ربط WhatsApp Business بنجاح",
            "account_id": "whatsapp",
            "verify_token": verify_token
        }
    elif channel_type == "telegram_phone":
        return {
            "success": True,
            "action": "multi_step",
            "message": "استخدم /telegram-phone/start لبدء عملية ربط Telegram Phone",
            "steps": [
                "استدعي POST /api/integrations/telegram-phone/start مع رقم الهاتف",
                "استلم رمز التحقق من Telegram",
                "استدعي POST /api/integrations/telegram-phone/verify مع الرمز"
            ]
        }
    else:
        raise HTTPException(status_code=400, detail=f"نوع القناة غير مدعوم: {channel_type}")

@router.delete("/accounts/{account_id}")
async def delete_integration_account(
    account_id: str,
    license: dict = Depends(get_license_from_header)
):
    """Delete/disconnect an integration account"""
    license_id = license["license_id"]
    
    if account_id == "email":
        email_cfg = await get_email_config(license_id)
        if email_cfg:
            async with get_db() as db:
                await execute_sql(
                    db,
                    "DELETE FROM email_configs WHERE license_key_id = ?",
                    [license_id]
                )
                await commit_db(db)
            return {"success": True, "message": "تم إلغاء تفعيل حساب البريد الإلكتروني"}
        else:
            raise HTTPException(status_code=404, detail="لا يوجد حساب بريد إلكتروني مرتبط")
    
    elif account_id == "telegram_bot":
        telegram_cfg = await get_telegram_config(license_id)
        if telegram_cfg:
            async with get_db() as db:
                await execute_sql(
                    db,
                    "DELETE FROM telegram_configs WHERE license_key_id = ?",
                    [license_id]
                )
                await commit_db(db)
            return {"success": True, "message": "تم إلغاء تفعيل Telegram Bot"}
        else:
            raise HTTPException(status_code=404, detail="لا يوجد Telegram Bot مرتبط")
    
    elif account_id == "telegram_phone":
        from models import deactivate_telegram_phone_session
        await deactivate_telegram_phone_session(license_id)
        return {"success": True, "message": "تم قطع الاتصال بـ Telegram Phone"}
    
    elif account_id == "whatsapp":
        whatsapp_cfg = await get_whatsapp_config(license_id)
        if whatsapp_cfg:
            async with get_db() as db:
                await execute_sql(
                    db,
                    "DELETE FROM whatsapp_configs WHERE license_key_id = ?",
                    [license_id]
                )
                await commit_db(db)
            return {"success": True, "message": "تم إلغاء تفعيل WhatsApp Business"}
        else:
            raise HTTPException(status_code=404, detail="لا يوجد WhatsApp Business مرتبط")
    
    else:
        raise HTTPException(status_code=400, detail=f"معرف الحساب غير صالح: {account_id}")

@router.patch("/accounts/{account_id}")
async def update_integration_account(
    account_id: str,
    request: dict,
    license: dict = Depends(get_license_from_header)
):
    """Update integration account settings"""
    license_id = license["license_id"]
    is_active = request.get("is_active")
    
    if is_active is None:
        raise HTTPException(status_code=400, detail="لا توجد إعدادات للتحديث")
    
    # Unified update logic for activation/deactivation if needed
    # For now, we only support deletion in delete endpoint, but this could be used for toggling
    return {"success": True, "message": "تم تحديث الإعدادات"}

