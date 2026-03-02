"""
Al-Mudeer - Subscription Key Management Routes
Easy subscription key generation and management for clients
"""

import os
from fastapi import APIRouter, HTTPException, Depends, Header, UploadFile, File
from pydantic import BaseModel, Field, EmailStr
from typing import Optional, List
from datetime import datetime, timedelta
from dotenv import load_dotenv

from database import generate_license_key, validate_license_key
from security import validate_license_key_format

# Load environment variables
load_dotenv()

router = APIRouter(prefix="/api/admin/subscription", tags=["Subscription Management"])

# Admin authentication
ADMIN_KEY = os.getenv("ADMIN_KEY")
if not ADMIN_KEY:
    raise ValueError("ADMIN_KEY environment variable is required")


async def verify_admin(
    x_admin_key: str = Header(None, alias="X-Admin-Key"),
    x_license_key: str = Header(None, alias="X-License-Key")
):
    """
    Verify authentication level.
    Returns a dict with session info for use in endpoint handlers.
    """
    # 1. Check for Admin Key
    if x_admin_key:
        clean_env_key = "".join(ADMIN_KEY.split()) if ADMIN_KEY else ""
        clean_received_key = "".join(x_admin_key.split()) if x_admin_key else ""
        
        if clean_received_key and clean_received_key == clean_env_key:
            return {"is_admin": True, "license_id": None}

    # 2. Check for License Key (Regular User Access)
    if x_license_key:
        from database import validate_license_key
        result = await validate_license_key(x_license_key)
        if result.get("valid"):
            return {"is_admin": False, "license_id": result["license_id"]}

    # 3. Both failed - Log and Reject
    from logging_config import get_logger
    logger = get_logger(__name__)
    logger.warning(
        f"Authentication failed for {x_admin_key[:5] if x_admin_key else 'None'} / {x_license_key[:5] if x_license_key else 'None'}. "
        f"Function: verify_admin"
    )
    raise HTTPException(status_code=403, detail="غير مصرح - مفتاح المدير أو مفتاح الاشتراك مطلوب")


# ============ Schemas ============

class SubscriptionCreate(BaseModel):
    """Request to create a new subscription"""
    full_name: str = Field(..., description="الاسم الكامل", min_length=2, max_length=200)
    days_valid: int = Field(365, description="مدة الصلاحية بالأيام", ge=1, le=3650)
    is_trial: bool = Field(False, description="هل هذا اشتراك تجريبي؟")
    referred_by_code: Optional[str] = Field(None, description="كود الإحالة (اختياري)")
    username: str = Field(..., description="اسم المستخدم الفريد", min_length=2, max_length=50)


class SubscriptionResponse(BaseModel):
    """Response with subscription details"""
    success: bool
    subscription_key: str
    full_name: str
    expires_at: str
    message: str


class SubscriptionListResponse(BaseModel):
    """Response for subscription list"""
    subscriptions: List[dict]
    total: int


class SubscriptionUpdate(BaseModel):
    """Request to update subscription"""
    full_name: Optional[str] = Field(None, description="الاسم الكامل الجديد", min_length=2, max_length=200)
    is_active: Optional[bool] = None
    days_valid_extension: Optional[int] = Field(None, description="زيادة أو تقليل أيام الصلاحية")
    profile_image_url: Optional[str] = None
    notes: Optional[str] = Field(None, max_length=500)
    username: Optional[str] = Field(None, description="اسم المستخدم الجديد", min_length=2, max_length=50)


# ============ Routes ============

@router.get("/check-username/{username}")
async def check_username_availability(username: str):
    """Check if a username exists and return user info"""
    from db_helper import get_db, fetch_one
    async with get_db() as db:
        row = await fetch_one(db, "SELECT full_name FROM license_keys WHERE username = ?", [username])
        if row:
            return {"exists": True, "full_name": row["full_name"]}
        return {"exists": False}

@router.post("/create", response_model=SubscriptionResponse)
async def create_subscription(
    subscription: SubscriptionCreate,
    auth: dict = Depends(verify_admin)
):
    """
    Create a new subscription key for a client (Admin Only).
    """
    if not auth["is_admin"]:
        raise HTTPException(status_code=403, detail="هذا الإجراء متاح لمدير النظام فقط")
    import os
    from logging_config import get_logger
    
    logger = get_logger(__name__)
    
    try:
        from db_helper import get_db, fetch_one
        # Check if username is already taken
        async with get_db() as db:
            existing = await fetch_one(db, "SELECT id FROM license_keys WHERE username = ?", [subscription.username])
            if existing:
                raise HTTPException(status_code=400, detail="اسم المستخدم هذا مستخدم بالفعل")

        # Find referrer if code is provided
        referred_by_id = None
        if subscription.referred_by_code:
            async with get_db() as db:
                ref_row = await fetch_one(db, "SELECT id FROM license_keys WHERE referral_code = ?", [subscription.referred_by_code])
                if ref_row:
                    referred_by_id = ref_row["id"]

        # Generate the subscription key
        key = await generate_license_key(
            full_name=subscription.full_name,
            days_valid=subscription.days_valid,
            is_trial=subscription.is_trial,
            referred_by_id=referred_by_id,
            username=subscription.username
        )
        
        # Calculate expiration date
        expires_at = datetime.now() + timedelta(days=subscription.days_valid)
        
        logger.info(f"Created subscription for {subscription.full_name}: {key[:20]}...")
        
        return SubscriptionResponse(
            success=True,
            subscription_key=key,
            full_name=subscription.full_name,
            expires_at=expires_at.isoformat(),
            message=f"تم إنشاء اشتراك بنجاح لـ {subscription.full_name}"
        )
    
    except Exception as e:
        logger.error(f"Error creating subscription: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"حدث خطأ أثناء إنشاء الاشتراك: {str(e)}"
        )


@router.get("/list", response_model=SubscriptionListResponse)
async def list_subscriptions(
    active_only: bool = False,
    limit: int = 100,
    auth: dict = Depends(verify_admin)
):
    """
    List subscriptions with appropriate access level.
    Admins see all, users see only their own.
    """
    import os
    from database import DB_TYPE, DATABASE_PATH, DATABASE_URL, POSTGRES_AVAILABLE
    from datetime import datetime
    
    try:
        subscriptions = []
        
        from db_helper import get_db, fetch_all
        async with get_db() as db:
            query = "SELECT id, full_name, contact_email, username, is_active, created_at, expires_at, last_request_date, is_trial, referral_code, referral_count, profile_image_url FROM license_keys"
            params = []
            
            if active_only:
                if DB_TYPE == "postgresql":
                    query += " WHERE is_active = TRUE"
                else:
                    query += " WHERE is_active = 1"
            
            query += " ORDER BY created_at DESC LIMIT ?"
            params.append(limit)
            
            rows = await fetch_all(db, query, params)
            
            for row in rows:
                row_dict = dict(row)
                # Calculate days remaining
                if row_dict.get("expires_at"):
                    if isinstance(row_dict["expires_at"], str):
                        try:
                            expires = datetime.fromisoformat(row_dict["expires_at"].replace('Z', '+00:00'))
                        except ValueError:
                            expires = datetime.now() # Fallback
                    else:
                        expires = row_dict["expires_at"]
                    days_remaining = (expires - datetime.now()).days
                    row_dict["days_remaining"] = max(0, days_remaining)
                else:
                    row_dict["days_remaining"] = None
                
                subscriptions.append(row_dict)
        
        # Filter for non-admin users: only show their own subscription
        if not auth["is_admin"]:
            subscriptions = [s for s in subscriptions if s["id"] == auth["license_id"]]
        
        return SubscriptionListResponse(
            subscriptions=subscriptions,
            total=len(subscriptions)
        )
    
    except Exception as e:
        from logging_config import get_logger
        logger = get_logger(__name__)
        logger.error(f"Error listing subscriptions: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="حدث خطأ أثناء جلب الاشتراكات")


@router.get("/{license_id}")
async def get_subscription(
    license_id: int,
    auth: dict = Depends(verify_admin)
):
    """Get details of a specific subscription"""
    if not auth["is_admin"] and license_id != auth["license_id"]:
        raise HTTPException(status_code=403, detail="غير مصرح لك بالوصول إلى بيانات هذا الاشتراك")
    from database import get_license_key_by_id, DB_TYPE
    from db_helper import get_db, fetch_one
    
    try:
        async with get_db() as db:
            # Use fetch_one which handles SQL conversion automatically
            row = await fetch_one(db, "SELECT * FROM license_keys WHERE id = ?", [license_id])
            
            if not row:
                raise HTTPException(status_code=404, detail="الاشتراك غير موجود")
            
            subscription = dict(row)
            
            # Get the original license key (decrypted)
            try:
                license_key = await get_license_key_by_id(license_id)
                subscription["license_key"] = license_key
                if not license_key:
                    # Log why key is not available
                    from logging_config import get_logger
                    logger = get_logger(__name__)
                    logger.warning(f"License key not found for subscription {license_id} - may be an old subscription created before encryption was added")
            except Exception as e:
                # If key retrieval fails, set to None and log
                from logging_config import get_logger
                logger = get_logger(__name__)
                logger.error(f"Error retrieving license key for subscription {license_id}: {e}", exc_info=True)
                subscription["license_key"] = None
            
            # Calculate days remaining
            if subscription.get("expires_at"):
                if isinstance(subscription["expires_at"], str):
                    expires = datetime.fromisoformat(subscription["expires_at"])
                else:
                    expires = subscription["expires_at"]
                days_remaining = (expires - datetime.now()).days
                subscription["days_remaining"] = max(0, days_remaining)
            else:
                subscription["days_remaining"] = None
            
            # Legacy field removal from response
            subscription.pop("requests_today", None)
            subscription.pop("max_requests_per_day", None)
            
            return {"subscription": subscription}
    
    except HTTPException:
        raise
    except Exception as e:
        from logging_config import get_logger
        logger = get_logger(__name__)
        logger.error(f"Error getting subscription: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="حدث خطأ أثناء جلب الاشتراك")


@router.patch("/{license_id}")
async def update_subscription(
    license_id: int,
    update: SubscriptionUpdate,
    auth: dict = Depends(verify_admin)
):
    """Update subscription settings (Admin Only)"""
    if not auth["is_admin"]:
        raise HTTPException(status_code=403, detail="هذا الإجراء متاح لمدير النظام فقط")
    from database import DB_TYPE, DATABASE_PATH, DATABASE_URL, POSTGRES_AVAILABLE
    from db_helper import get_db, fetch_one, execute_sql, commit_db
    from logging_config import get_logger
    from services.websocket_manager import broadcast_subscription_updated
    
    logger = get_logger(__name__)
    
    try:
        async with get_db() as db:
            # Get current subscription
            row = await fetch_one(db, "SELECT * FROM license_keys WHERE id = ?", [license_id])
            
            if not row:
                raise HTTPException(status_code=404, detail="الاشتراك غير موجود")
            
            current = dict(row)
            
            # Build update query
            updates = []
            params = []
            param_index = 1
            
            if update.full_name is not None:
                if DB_TYPE == "postgresql":
                    updates.append(f"full_name = ${param_index}")
                else:
                    updates.append("full_name = ?")
                params.append(update.full_name)
                param_index += 1

            if update.is_active is not None:
                if DB_TYPE == "postgresql":
                    updates.append(f"is_active = ${param_index}")
                else:
                    updates.append("is_active = ?")
                params.append(update.is_active)
                param_index += 1
            
            if update.days_valid_extension is not None and update.days_valid_extension != 0:
                # Add/subtract days to the existing expiration date
                current_expires = current.get("expires_at")
                if current_expires:
                    if isinstance(current_expires, str):
                        try:
                            current_expires = datetime.fromisoformat(current_expires.replace('Z', '+00:00'))
                        except ValueError:
                            current_expires = datetime.now()
                    new_expires = current_expires + timedelta(days=update.days_valid_extension)
                else:
                    new_expires = datetime.now() + timedelta(days=update.days_valid_extension)
                
                if DB_TYPE == "postgresql":
                    updates.append(f"expires_at = ${param_index}")
                    params.append(new_expires)
                else:
                    updates.append("expires_at = ?")
                    params.append(new_expires.isoformat())
                param_index += 1
                
                # Capture for broadcast
                expires_at_str = new_expires.isoformat()
            
            if update.profile_image_url is not None:
                if DB_TYPE == "postgresql":
                    updates.append(f"profile_image_url = ${param_index}")
                else:
                    updates.append("profile_image_url = ?")
                params.append(update.profile_image_url)
                param_index += 1
            
            old_username = None
            if update.username is not None:
                # Store old username for customer table update
                old_username = current.get("username")
                if DB_TYPE == "postgresql":
                    updates.append(f"username = ${param_index}")
                else:
                    updates.append("username = ?")
                params.append(update.username)
                param_index += 1

            if not updates:
                raise HTTPException(status_code=400, detail="لا توجد تحديثات لتطبيقها")

            # Execute update
            if DB_TYPE == "postgresql":
                query = f"UPDATE license_keys SET {', '.join(updates)} WHERE id = ${param_index}"
            else:
                query = f"UPDATE license_keys SET {', '.join(updates)} WHERE id = ?"
            params.append(license_id)

            await execute_sql(db, query, params)
            
            # If username changed, update customers table to maintain consistency
            # IMPORTANT: Only update customers that reference THIS license's username
            # Do NOT update WhatsApp/Telegram/Email contacts (they have different contact formats)
            if old_username and update.username and old_username != update.username:
                try:
                    # Update customers.contact and customers.username where they reference the old username
                    # This only affects Almudeer users (other license holders), NOT WhatsApp/Telegram contacts
                    if DB_TYPE == "postgresql":
                        await execute_sql(db, """
                            UPDATE customers
                            SET contact = $1, username = $1
                            WHERE license_key_id = $2 
                            AND (contact = $3 OR username = $3)
                            AND (
                                -- Only update if contact looks like a username (not phone, email, or ID)
                                contact NOT LIKE '+%' 
                                AND contact NOT LIKE '%@%'
                                AND contact NOT LIKE 'tg:%'
                                AND contact NOT LIKE 'unknown_%'
                                AND contact !~ '^[0-9]+$'
                            )
                        """, [update.username, license_id, old_username])
                    else:
                        # SQLite: simpler pattern matching (no regex support by default)
                        await execute_sql(db, """
                            UPDATE customers
                            SET contact = ?, username = ?
                            WHERE license_key_id = ? 
                            AND (contact = ? OR username = ?)
                            AND (
                                -- Only update if contact looks like a username
                                contact NOT LIKE '+%' 
                                AND contact NOT LIKE '%@%'
                                AND contact NOT LIKE 'tg:%'
                                AND contact NOT LIKE 'unknown_%'
                            )
                        """, [update.username, update.username, license_id, old_username, old_username])
                    await commit_db(db)
                    logger.info(f"Updated customers table for username change: {old_username} -> {update.username}")
                except Exception as e:
                    logger.warning(f"Failed to update customers table: {e}")
                    await commit_db(db)  # Still commit the main update
            else:
                await commit_db(db)

            logger.info(f"Updated subscription {license_id}")
            
            if update.is_active is False:
                try:
                    from services.account_service import trigger_account_logout
                    await trigger_account_logout(license_id)
                except Exception as e:
                    logger.warning(f"Failed to trigger account logout for {license_id}: {e}")

            # 3. Trigger WebSocket broadcast for real-time UI updates
            # Find updated fields for the broadcast
            broadcast_data = {}
            if update.full_name is not None: broadcast_data["full_name"] = update.full_name
            if update.username is not None: 
                broadcast_data["username"] = update.username
                # Include old username for migration
                if old_username:
                    broadcast_data["old_username"] = old_username
            if update.profile_image_url is not None: broadcast_data["profile_image_url"] = update.profile_image_url

            # Handle expiry update for broadcast
            if update.days_valid_extension is not None and update.days_valid_extension != 0:
                try:
                    # 'expires_at_str' was defined in the if block above
                    broadcast_data["expires_at"] = expires_at_str
                except NameError:
                    pass

            if broadcast_data:
                try:
                    import asyncio
                    asyncio.create_task(broadcast_subscription_updated(license_id, broadcast_data))
                except Exception as e:
                    logger.warning(f"Failed to broadcast subscription update: {e}")

            return {
                "success": True,
                "message": "تم تحديث الاشتراك بنجاح"
            }
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error updating subscription: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="حدث خطأ أثناء تحديث الاشتراك")


@router.post("/{license_id}/regenerate-key")
async def regenerate_subscription_key(
    license_id: int,
    auth: dict = Depends(verify_admin)
):
    """Regenerate and save license key (Admin Only)"""
    if not auth["is_admin"]:
        raise HTTPException(status_code=403, detail="هذا الإجراء متاح لمدير النظام فقط")
    from database import DB_TYPE, hash_license_key
    from db_helper import get_db, fetch_one, execute_sql, commit_db
    from security import encrypt_sensitive_data
    from logging_config import get_logger
    import secrets
    
    logger = get_logger(__name__)
    
    try:
        async with get_db() as db:
            # Check if subscription exists
            row = await fetch_one(db, "SELECT * FROM license_keys WHERE id = ?", [license_id])
            
            if not row:
                raise HTTPException(status_code=404, detail="الاشتراك غير موجود")
            
            subscription = dict(row)
            
            # Check if key already exists
            if subscription.get('license_key_encrypted'):
                raise HTTPException(
                    status_code=400, 
                    detail="هذا الاشتراك يحتوي بالفعل على مفتاح مشفر. لا يمكن إعادة إنشاء المفتاح."
                )
            
            # Generate new key with same format
            raw_key = f"MUDEER-{secrets.token_hex(4).upper()}-{secrets.token_hex(4).upper()}-{secrets.token_hex(4).upper()}"
            key_hash = hash_license_key(raw_key)
            encrypted_key = encrypt_sensitive_data(raw_key)
            
            # Update the subscription with new key hash and encrypted key
            if DB_TYPE == "postgresql":
                await execute_sql(db, """
                    UPDATE license_keys 
                    SET key_hash = $1, license_key_encrypted = $2 
                    WHERE id = $3
                """, [key_hash, encrypted_key, license_id])
            else:
                await execute_sql(db, """
                    UPDATE license_keys 
                    SET key_hash = ?, license_key_encrypted = ? 
                    WHERE id = ?
                """, [key_hash, encrypted_key, license_id])
            
            await commit_db(db)
            
            logger.info(f"Regenerated license key for subscription {license_id}")
            
            return {
                "success": True,
                "license_key": raw_key,
                "message": "تم إعادة إنشاء المفتاح بنجاح"
            }
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error regenerating license key: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="حدث خطأ أثناء إعادة إنشاء المفتاح")


@router.post("/{license_id}/upload-avatar")
async def upload_subscription_avatar(
    license_id: int,
    file: UploadFile = File(...),
    auth: dict = Depends(verify_admin)
):
    """Upload avatar for a subscription user (Admin Only)"""
    if not auth["is_admin"]:
        raise HTTPException(status_code=403, detail="هذا الإجراء متاح لمدير النظام فقط")
    from services.file_storage_service import get_file_storage
    from db_helper import get_db, execute_sql, commit_db, fetch_one
    from database import DB_TYPE
    from logging_config import get_logger
    
    logger = get_logger(__name__)
    file_storage = get_file_storage()
    
    try:
        async with get_db() as db:
            # Check if subscription exists
            row = await fetch_one(db, "SELECT * FROM license_keys WHERE id = ?", [license_id])
            if not row:
                raise HTTPException(status_code=404, detail="الاشتراك غير موجود")
            
            # Read file content
            content = await file.read()
            content_type = file.content_type or "image/jpeg"
            
            if not content_type.startswith("image/"):
                raise HTTPException(status_code=400, detail="يجب أن يكون الملف المرفوع صورة")
                
            # Upload using storage service
            relative_path, public_url = file_storage.save_file(
                content=content,
                filename=file.filename,
                mime_type=content_type,
                subfolder="avatars"
            )
            
            # Update database
            if DB_TYPE == "postgresql":
                await execute_sql(db, "UPDATE license_keys SET profile_image_url = $1 WHERE id = $2", [public_url, license_id])
            else:
                await execute_sql(db, "UPDATE license_keys SET profile_image_url = ? WHERE id = ?", [public_url, license_id])
                
            await commit_db(db)
            
            return {
                "success": True,
                "profile_image_url": public_url,
                "message": "تم رفع الصورة بنجاح"
            }
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error uploading avatar: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"حدث خطأ أثناء رفع الصورة: {str(e)}")


@router.delete("/{license_id}")
async def delete_subscription(
    license_id: int,
    auth: dict = Depends(verify_admin)
):
    """Delete a subscription permanently (Admin Only)"""
    if not auth["is_admin"]:
        raise HTTPException(status_code=403, detail="هذا الإجراء متاح لمدير النظام فقط")
    from db_helper import get_db, fetch_one, execute_sql, commit_db
    from database import DB_TYPE
    from models import delete_preferences
    from logging_config import get_logger
    
    logger = get_logger(__name__)
    
    try:
        async with get_db() as db:
            # Check if subscription exists
            row = await fetch_one(db, "SELECT * FROM license_keys WHERE id = ?", [license_id])
            
            if not row:
                raise HTTPException(status_code=404, detail="الاشتراك غير موجود")
            
            # Hard delete: Delete related records first (CASCADE should handle this, but being explicit)
            # Delete usage logs
            # Delete logs and related data
            if DB_TYPE == "postgresql":
                async with db.transaction():
                    # Delete deep dependencies first: Orders -> Customers
                    try:
                        await execute_sql(db, "DELETE FROM orders WHERE customer_contact IN (SELECT contact FROM customers WHERE license_key_id = $1)", [license_id])
                    except Exception as e:
                        logger.warning(f"Note: Could not delete from orders for subscription {license_id}: {e}")
                        
                    try:
                        await execute_sql(db, "DELETE FROM customers WHERE license_key_id = $1", [license_id])
                    except Exception as e:
                        logger.warning(f"Note: Could not delete from customers for subscription {license_id}: {e}")
                    
                    # Delete service configs and logs
                    try:
                        await execute_sql(db, "DELETE FROM usage_logs WHERE license_key_id = $1", [license_id])
                        await execute_sql(db, "DELETE FROM crm_entries WHERE license_key_id = $1", [license_id])
                        await execute_sql(db, "DELETE FROM email_configs WHERE license_key_id = $1", [license_id])
                        await execute_sql(db, "DELETE FROM telegram_configs WHERE license_key_id = $1", [license_id])
                    except Exception as e:
                        logger.warning(f"Note: Could not delete some dependent records for subscription {license_id}: {e}")
                    
                    # Fix: Delete user preferences to avoid FK violation
                    try:
                        await delete_preferences(license_id, db=db)
                    except Exception as e:
                        logger.warning(f"Note: Could not delete preferences for subscription {license_id}: {e}")
                    
                    # Finally delete the subscription
                    await execute_sql(db, "DELETE FROM license_keys WHERE id = $1", [license_id])
            else:
                # SQLite (no async transaction context manager in the same way, rely on final commit)
                # Delete deep dependencies
                try:
                    await execute_sql(db, "DELETE FROM orders WHERE customer_contact IN (SELECT contact FROM customers WHERE license_key_id = ?)", [license_id])
                except Exception as e:
                    logger.warning(f"Note: Could not delete from orders for subscription {license_id}: {e}")

                try:
                    await execute_sql(db, "DELETE FROM customers WHERE license_key_id = ?", [license_id])
                except Exception as e:
                    logger.warning(f"Note: Could not delete from customers for subscription {license_id}: {e}")
                
                try:
                    await execute_sql(db, "DELETE FROM usage_logs WHERE license_key_id = ?", [license_id])
                    await execute_sql(db, "DELETE FROM crm_entries WHERE license_key_id = ?", [license_id])
                    await execute_sql(db, "DELETE FROM email_configs WHERE license_key_id = ?", [license_id])
                    await execute_sql(db, "DELETE FROM telegram_configs WHERE license_key_id = ?", [license_id])
                except Exception as e:
                    logger.warning(f"Note: Could not delete some dependent records for subscription {license_id}: {e}")

                # Fix: Delete user preferences to avoid FK violation
                try:
                    await delete_preferences(license_id, db=db)
                except Exception as e:
                    logger.warning(f"Note: Could not delete preferences for subscription {license_id}: {e}")

                await execute_sql(db, "DELETE FROM license_keys WHERE id = ?", [license_id])
            
            await commit_db(db)
            
            # Trigger real-time logout BEFORE deleting the record
            try:
                from services.account_service import trigger_account_logout
                await trigger_account_logout(license_id)
            except Exception as e:
                logger.warning(f"Failed to trigger account logout for {license_id} during deletion: {e}")

            logger.info(f"Permanently deleted subscription {license_id}")
            
            return {
                "success": True,
                "message": "تم حذف الاشتراك نهائياً"
            }
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error deleting subscription: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="حدث خطأ أثناء حذف الاشتراك")


class ValidateKeyRequest(BaseModel):
    """Request to validate a subscription key"""
    key: str = Field(..., description="Subscription key to validate")


@router.post("/validate-key")
async def validate_subscription_key(
    request: ValidateKeyRequest
):
    """
    Validate a subscription key (public endpoint, no admin required).
    Useful for clients to check their key status.
    """
    if not validate_license_key_format(request.key):
        return {
            "valid": False,
            "error": "تنسيق المفتاح غير صحيح"
        }
    
    result = await validate_license_key(request.key)
    return result


@router.get("/usage/{license_id}")
async def get_subscription_usage(
    license_id: int,
    days: int = 30,
    auth: dict = Depends(verify_admin)
):
    """Get usage statistics for a subscription"""
    if not auth["is_admin"] and license_id != auth["license_id"]:
        raise HTTPException(status_code=403, detail="غير مصرح لك بالوصول إلى إحصائيات هذا الاشتراك")
    from database import DB_TYPE
    from db_helper import get_db, fetch_all, fetch_one
    
    try:
        async with get_db() as db:
            if DB_TYPE == "postgresql":
                # PostgreSQL query - use parameterized queries with proper INTERVAL syntax
                usage_query = f"""
                    SELECT 
                        DATE(created_at) as date,
                        action_type,
                        COUNT(*) as count
                    FROM usage_logs
                    WHERE license_key_id = $1 
                    AND created_at >= NOW() - INTERVAL '{days} days'
                    GROUP BY DATE(created_at), action_type
                    ORDER BY date DESC
                """
                
                totals_query = f"""
                    SELECT 
                        COUNT(*) as total_requests,
                        COUNT(DISTINCT DATE(created_at)) as active_days
                    FROM usage_logs
                    WHERE license_key_id = $1 
                    AND created_at >= NOW() - INTERVAL '{days} days'
                """
                
                usage_stats = await fetch_all(db, usage_query, [license_id])
                totals_row = await fetch_one(db, totals_query, [license_id])
                totals = totals_row if totals_row else {"total_requests": 0, "active_days": 0}
            else:
                # SQLite query
                usage_query = """
                    SELECT 
                        DATE(created_at) as date,
                        action_type,
                        COUNT(*) as count
                    FROM usage_logs
                    WHERE license_key_id = ? 
                    AND created_at >= datetime('now', '-' || ? || ' days')
                    GROUP BY DATE(created_at), action_type
                    ORDER BY date DESC
                """
                
                totals_query = """
                    SELECT 
                        COUNT(*) as total_requests,
                        COUNT(DISTINCT DATE(created_at)) as active_days
                    FROM usage_logs
                    WHERE license_key_id = ? 
                    AND created_at >= datetime('now', '-' || ? || ' days')
                """
                
                usage_stats = await fetch_all(db, usage_query, [license_id, days])
                totals_row = await fetch_one(db, totals_query, [license_id, days])
                totals = totals_row if totals_row else {"total_requests": 0, "active_days": 0}
            
            return {
                "license_id": license_id,
                "period_days": days,
                "usage_stats": usage_stats,
                "totals": totals
            }
    
    except Exception as e:
        from logging_config import get_logger
        logger = get_logger(__name__)
        logger.error(f"Error getting usage stats: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="حدث خطأ أثناء جلب إحصائيات الاستخدام")

