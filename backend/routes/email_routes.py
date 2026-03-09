"""
Al-Mudeer - Email (Gmail) Routes
Gmail OAuth 2.0 configuration and message fetching
"""

import os
import html
from datetime import datetime, timedelta
from fastapi import APIRouter, HTTPException, Depends, BackgroundTasks
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field

from models import (
    save_email_config,
    get_email_config,
    get_email_oauth_tokens,
    update_email_config_settings,
    save_inbox_message,
)
from services import GmailOAuthService, GmailAPIService, EMAIL_PROVIDERS
from dependencies import get_license_from_header

router = APIRouter(prefix="/api/integrations/email", tags=["Email"])

class EmailConfigRequest(BaseModel):
    provider: str = Field(..., description="gmail (OAuth 2.0 only)")
    email_address: str  # Will be set from OAuth token
    check_interval_minutes: int = 5

@router.get("/providers")
async def get_email_providers():
    """Get list of supported email providers (Gmail only)"""
    return {"providers": EMAIL_PROVIDERS}

@router.get("/oauth/authorize")
async def authorize_gmail(license: dict = Depends(get_license_from_header)):
    """Get OAuth 2.0 authorization URL for Gmail"""
    try:
        oauth_service = GmailOAuthService()
        state = GmailOAuthService.encode_state(license["license_id"])
        auth_url = oauth_service.get_authorization_url(state)
        
        return {
            "authorization_url": auth_url,
            "state": state,
            "message": "يرجى فتح هذا الرابط وتسجيل الدخول بحساب Google الخاص بك"
        }
    except ValueError as e:
        raise HTTPException(status_code=500, detail=f"خطأ في إعداد OAuth: {str(e)}")

@router.get("/oauth/callback")
async def gmail_oauth_callback(
    code: str,
    state: str
):
    """Handle OAuth 2.0 callback from Google"""
    frontend_url = os.getenv("FRONTEND_URL", "https://almudeer.royaraqamia.com")
    frontend_origin = frontend_url.rstrip('/')
    
    try:
        state_data = GmailOAuthService.decode_state(state)
        license_id = state_data.get("license_id")
        
        if not license_id:
            raise HTTPException(status_code=400, detail="حالة غير صالحة")
        
        oauth_service = GmailOAuthService()
        tokens = await oauth_service.exchange_code_for_tokens(code)
        
        access_token = tokens["access_token"]
        refresh_token = tokens.get("refresh_token")
        expires_in = tokens.get("expires_in", 3600)
        token_expires_at = datetime.now() + timedelta(seconds=expires_in)
        
        token_info = await oauth_service.get_token_info(access_token)
        email_address = token_info.get("email")
        
        if not email_address:
            raise HTTPException(status_code=400, detail="تعذر الحصول على عنوان البريد الإلكتروني")
        
        config_id = await save_email_config(
            license_id=license_id,
            email_address=email_address,
            access_token=access_token,
            refresh_token=refresh_token,
            token_expires_at=token_expires_at,
            check_interval=5
        )
        
        html_content = f"""
        <!DOCTYPE html>
        <html dir="rtl" lang="ar">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>تم ربط Gmail بنجاح</title>
            <style>
                body {{ font-family: sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; text-align: center; }}
            </style>
        </head>
        <body>
            <div>
                <h1>✅ تم ربط حساب Gmail بنجاح!</h1>
                <p>{email_address}</p>
                <script>
                    if (window.opener) {{
                        window.opener.postMessage({{ type: 'GMAIL_OAUTH_SUCCESS', email: '{email_address}', config_id: {config_id} }}, '{frontend_origin}');
                        setTimeout(() => window.close(), 1500);
                    }} else {{
                        setTimeout(() => window.location.href = '{frontend_origin}/dashboard/integrations', 2000);
                    }}
                </script>
            </div>
        </body>
        </html>
        """
        return HTMLResponse(content=html_content)
        
    except Exception as e:
        error_html = f"<html><body><h1>❌ فشل ربط حساب Gmail</h1><p>{html.escape(str(e))}</p></body></html>"
        return HTMLResponse(content=error_html, status_code=400)

@router.post("/config")
async def configure_email(
    config: EmailConfigRequest,
    license: dict = Depends(get_license_from_header)
):
    """Update email configuration settings"""
    if config.provider != "gmail":
        raise HTTPException(status_code=400, detail="يتم دعم Gmail فقط عبر OAuth 2.0")
    
    existing_config = await get_email_config(license["license_id"])
    if not existing_config:
        raise HTTPException(status_code=404, detail="لم يتم ربط حساب Gmail بعد")
    
    await update_email_config_settings(
        license_id=license["license_id"],
        check_interval=config.check_interval_minutes
    )
    
    return {"success": True, "message": "تم تحديث إعدادات البريد الإلكتروني بنجاح"}

@router.get("/config")
async def get_email_configuration(license: dict = Depends(get_license_from_header)):
    """Get current email configuration"""
    config = await get_email_config(license["license_id"], include_inactive=False)
    return {"config": config}

@router.post("/test")
async def test_email_connection(license: dict = Depends(get_license_from_header)):
    """Test Gmail connection"""
    tokens = await get_email_oauth_tokens(license["license_id"])
    if not tokens or not tokens.get("access_token"):
        raise HTTPException(status_code=404, detail="لم يتم ربط حساب Gmail بعد")
    
    try:
        oauth_service = GmailOAuthService()
        gmail_service = GmailAPIService(tokens["access_token"], tokens.get("refresh_token"), oauth_service)
        profile = await gmail_service.get_profile()
        return {"success": True, "message": f"الاتصال ناجح مع {profile.get('emailAddress')}"}
    except Exception as e:
        return {"success": False, "message": f"فشل الاتصال: {str(e)}"}

@router.post("/fetch")
async def fetch_emails(
    background_tasks: BackgroundTasks,
    license: dict = Depends(get_license_from_header)
):
    """Manually trigger email fetch"""
    config = await get_email_config(license["license_id"])
    if not config:
        raise HTTPException(status_code=400, detail="لم يتم تكوين البريد الإلكتروني")
    
    tokens = await get_email_oauth_tokens(license["license_id"])
    if not tokens or not tokens.get("access_token"):
        raise HTTPException(status_code=400, detail="لم يتم ربط حساب Gmail بعد")
    
    try:
        oauth_service = GmailOAuthService()
        gmail_service = GmailAPIService(tokens["access_token"], tokens.get("refresh_token"), oauth_service)
        
        # Simple fetch logic for manual trigger
        emails = await gmail_service.fetch_new_emails(since_hours=1, limit=50)
        
        
        processed = 0
        for email_data in emails:
            # Attachments are already handled by GmailAPIService (downloaded & stored)
            # email_data["attachments"] contains URLs and paths.
            
            msg_id = await save_inbox_message(
                license_id=license["license_id"],
                channel="email",
                body=email_data["body"],
                sender_name=email_data["sender_name"],
                sender_contact=email_data["sender_contact"],
                subject=email_data.get("subject", ""),
                channel_message_id=email_data["channel_message_id"],
                received_at=email_data["received_at"],
                attachments=email_data["attachments"]
            )
            
            processed += 1
        
        return {"success": True, "message": f"تم جلب {processed} رسالة جديدة", "count": processed}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"خطأ في جلب الرسائل: {str(e)}")
