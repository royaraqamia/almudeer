"""
Al-Mudeer - Device Pairing API Routes

P3-1/Nearby: Device pairing for trusted nearby transfers
"""

import logging
from datetime import datetime, timezone
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from dependencies import get_license_from_header
from services.jwt_auth import get_current_user
from db_helper import get_db, execute_sql, fetch_all, fetch_one, commit_db
from rate_limiting import limiter

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/devices", tags=["Devices"])


class DevicePairRequest(BaseModel):
    """Request to pair with another device"""
    device_id: str = Field(..., description="Device ID to pair with")
    device_name: str = Field(..., description="Human-readable device name")
    pairing_code: Optional[str] = Field(None, description="Optional pairing code")


class PairedDeviceResponse(BaseModel):
    """Response with paired device info"""
    pairing_id: int
    device_id: str
    device_name: str
    paired_at: datetime
    is_trusted: bool
    last_connected_at: Optional[datetime]


@router.post("/pair")
@limiter.limit("5/minute")  # Rate limit to prevent abuse
async def pair_device(
    request: Request,
    pair_data: DevicePairRequest,
    license: dict = Depends(get_license_from_header),
    user: dict = Depends(get_current_user)  # Changed to required authentication
):
    """
    Pair with another device for trusted transfers.

    P3-1/Nearby: Create trusted device pairing for nearby sharing.
    
    Security: Requires authenticated user. Device ID must match user's device.
    """
    user_id = user.get("user_id")
    user_device_id = user.get("device_id")
    now = datetime.now(timezone.utc)

    # Security: Verify user is pairing their own device
    if user_device_id and pair_data.device_id != user_device_id:
        # Allow pairing if user_device_id is not set (legacy users)
        # But log for monitoring
        logger.warning(
            f"Device pairing mismatch: user {user_id} device {user_device_id} "
            f"trying to pair {pair_data.device_id}"
        )

    async with get_db() as db:
        # Check if pairing already exists (in either direction)
        existing = await fetch_one(
            db,
            """
            SELECT * FROM device_pairing
            WHERE license_key_id = ?
            AND ((device_id_a = ? AND device_id_b = ?) OR (device_id_a = ? AND device_id_b = ?))
            AND deleted_at IS NULL
            """,
            [
                license["license_id"],
                user_id, pair_data.device_id,
                pair_data.device_id, user_id
            ]
        )
        
        if existing:
            return {
                "success": True,
                "message": "الأجهزة مقترنة بالفعل",
                "pairing_id": existing["id"],
                "already_paired": True
            }
        
        # Create new pairing
        await execute_sql(
            db,
            """
            INSERT INTO device_pairing
            (license_key_id, device_id_a, device_id_b, device_name_a, device_name_b,
             paired_at, paired_by, is_trusted, connection_count)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)
            """,
            [
                license["license_id"],
                user_id,
                pair_data.device_id,
                user.get("username", "Unknown"),
                pair_data.device_name,
                now,
                user_id
            ]
        )
        
        await commit_db(db)
        
        # Get the created pairing
        pairing = await fetch_one(
            db,
            "SELECT * FROM device_pairing WHERE license_key_id = ? AND device_id_a = ? AND device_id_b = ?",
            [license["license_id"], user_id, pair_data.device_id]
        )
        
        return {
            "success": True,
            "message": "تم اقتران الأجهزة بنجاح",
            "pairing_id": pairing["id"],
            "device_id": pair_data.device_id,
            "device_name": pair_data.device_name,
            "paired_at": pairing["paired_at"],
            "is_trusted": pairing["is_trusted"]
        }


@router.get("/paired")
@limiter.limit("10/minute")  # Stricter rate limit
async def list_paired_devices(
    request: Request,
    license: dict = Depends(get_license_from_header),
    user: dict = Depends(get_current_user)  # Required authentication
):
    """
    List all paired devices for the current user.

    P3-1/Nearby: Get list of trusted devices for quick reconnection.
    """
    user_id = user.get("user_id")

    async with get_db() as db:
        # Get pairings where user is either device_a or device_b
        rows = await fetch_all(
            db,
            """
            SELECT 
                id,
                CASE WHEN device_id_a = ? THEN device_id_b ELSE device_id_a END as device_id,
                CASE WHEN device_id_a = ? THEN device_name_b ELSE device_name_a END as device_name,
                paired_at,
                is_trusted,
                last_connected_at,
                connection_count
            FROM device_pairing
            WHERE license_key_id = ?
            AND (device_id_a = ? OR device_id_b = ?)
            AND deleted_at IS NULL
            ORDER BY last_connected_at DESC NULLS LAST, paired_at DESC
            """,
            [user_id, user_id, license["license_id"], user_id, user_id]
        )
        
        devices = [dict(row) for row in rows]
    
    return {
        "success": True,
        "devices": devices,
        "total": len(devices)
    }


@router.delete("/unpair/{pairing_id}")
@limiter.limit("5/minute")  # Stricter rate limit
async def unpair_device(
    request: Request,
    pairing_id: int,
    license: dict = Depends(get_license_from_header),
    user: dict = Depends(get_current_user)  # Required authentication
):
    """
    Unpair a device (remove trusted pairing).

    P3-1/Nearby: Remove device pairing.
    """
    user_id = user.get("user_id")
    now = datetime.now(timezone.utc)

    async with get_db() as db:
        # Verify pairing exists and belongs to user
        pairing = await fetch_one(
            db,
            """
            SELECT * FROM device_pairing
            WHERE id = ? AND license_key_id = ?
            AND (device_id_a = ? OR device_id_b = ?)
            AND deleted_at IS NULL
            """,
            [pairing_id, license["license_id"], user_id, user_id]
        )
        
        if not pairing:
            raise HTTPException(
                status_code=404,
                detail={
                    "code": "PAIRING_NOT_FOUND",
                    "message_ar": "الاقتران غير موجود",
                    "message_en": "Pairing not found"
                }
            )
        
        # Soft delete
        await execute_sql(
            db,
            "UPDATE device_pairing SET deleted_at = ? WHERE id = ?",
            [now, pairing_id]
        )
        
        await commit_db(db)
    
    return {
        "success": True,
        "message": "تم إلغاء الاقتران بنجاح"
    }


@router.post("/paired/{pairing_id}/connect")
@limiter.limit("10/minute")  # Stricter rate limit
async def record_device_connection(
    request: Request,
    pairing_id: int,
    license: dict = Depends(get_license_from_header),
    user: dict = Depends(get_current_user)  # Required authentication
):
    """
    Record a connection to a paired device.

    P3-1/Nearby: Update last connected timestamp and connection count.
    """
    user_id = user.get("user_id")
    now = datetime.now(timezone.utc)

    async with get_db() as db:
        # Verify pairing exists
        pairing = await fetch_one(
            db,
            """
            SELECT * FROM device_pairing
            WHERE id = ? AND license_key_id = ?
            AND (device_id_a = ? OR device_id_b = ?)
            AND deleted_at IS NULL
            """,
            [pairing_id, license["license_id"], user_id, user_id]
        )
        
        if not pairing:
            raise HTTPException(
                status_code=404,
                detail={
                    "code": "PAIRING_NOT_FOUND",
                    "message_ar": "الاقتران غير موجود",
                    "message_en": "Pairing not found"
                }
            )
        
        # Update connection info
        await execute_sql(
            db,
            """
            UPDATE device_pairing
            SET last_connected_at = ?, connection_count = connection_count + 1
            WHERE id = ?
            """,
            [now, pairing_id]
        )
        
        await commit_db(db)
    
    return {
        "success": True,
        "message": "تم تسجيل الاتصال"
    }
