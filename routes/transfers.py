"""
Al-Mudeer - Transfer Management API Routes

P3-1/Nearby: File transfer management and tracking
"""

import logging
from datetime import datetime, timezone
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Request, Query
from pydantic import BaseModel, Field

from dependencies import get_license_from_header
from services.jwt_auth import get_current_user
from db_helper import get_db, execute_sql, fetch_all, fetch_one, commit_db
from rate_limiting import limiter

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/transfers", tags=["Transfers"])


class TransferHistoryResponse(BaseModel):
    """Response model for transfer history item"""
    id: int
    session_id: str
    file_name: str
    file_size: int
    file_type: str
    mime_type: str
    status: str
    direction: str
    device_name: str
    started_at: Optional[datetime]
    completed_at: Optional[datetime]
    duration_seconds: Optional[int]
    error_message: Optional[str]


class TransferStatsResponse(BaseModel):
    """Response model for transfer statistics"""
    total_transfers: int
    successful_transfers: int
    failed_transfers: int
    cancelled_transfers: int
    total_bytes_transferred: int
    success_rate: float
    average_transfer_size: float


@router.get("/history")
@limiter.limit("30/minute")
async def get_transfer_history(
    request: Request,
    license: dict = Depends(get_license_from_header),
    user: dict = Depends(get_current_user),
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    status: Optional[str] = Query(None, description="Filter by status: completed, failed, cancelled"),
    direction: Optional[str] = Query(None, description="Filter by direction: sending, receiving"),
):
    """
    Get transfer history for the current user.
    
    Returns paginated list of file transfers with optional filtering.
    """
    user_id = user.get("user_id")
    
    async with get_db() as db:
        # Build dynamic query based on filters
        base_query = """
            SELECT 
                id, session_id, file_name, file_size, file_type, mime_type,
                status, direction, 
                device_id_a, device_id_b,
                started_at, completed_at, duration_seconds, error_message
            FROM transfer_history
            WHERE license_key_id = ?
            AND deleted_at IS NULL
        """
        params = [license["license_id"]]
        
        if status:
            base_query += " AND status = ?"
            params.append(status)
        
        if direction:
            base_query += " AND direction = ?"
            params.append(direction)
        
        base_query += " ORDER BY completed_at DESC NULLS LAST, created_at DESC LIMIT ? OFFSET ?"
        params.extend([limit, offset])
        
        rows = await fetch_all(db, base_query, params)
        
        # Get device names for each transfer
        transfers = []
        for row in rows:
            row_dict = dict(row)
            # Get device name (prefer the other device, not current user's)
            device_id = row_dict['device_id_b'] if row_dict['device_id_a'] == str(user_id) else row_dict['device_id_a']
            
            device_info = await fetch_one(
                db,
                "SELECT device_name FROM device_pairing WHERE (device_id_a = ? OR device_id_b = ?) AND deleted_at IS NULL LIMIT 1",
                [device_id, device_id]
            )
            row_dict['device_name'] = device_info['device_name'] if device_info else 'Unknown Device'
            del row_dict['device_id_a']
            del row_dict['device_id_b']
            transfers.append(row_dict)
        
        # Get total count for pagination
        count_query = """
            SELECT COUNT(*) as total
            FROM transfer_history
            WHERE license_key_id = ? AND deleted_at IS NULL
        """
        count_params = [license["license_id"]]
        
        if status:
            count_query += " AND status = ?"
            count_params.append(status)
        
        if direction:
            count_query += " AND direction = ?"
            count_params.append(direction)
        
        total_row = await fetch_one(db, count_query, count_params)
        total = total_row['total'] if total_row else 0
    
    return {
        "success": True,
        "transfers": transfers,
        "total": total,
        "limit": limit,
        "offset": offset
    }


@router.get("/stats")
@limiter.limit("10/minute")
async def get_transfer_statistics(
    request: Request,
    license: dict = Depends(get_license_from_header),
    user: dict = Depends(get_current_user),
    days: int = Query(default=30, ge=1, le=365, description="Number of days to calculate stats for"),
):
    """
    Get transfer statistics for the current user.
    
    Returns aggregated statistics for the specified time period.
    """
    from datetime import timedelta
    
    cutoff_date = datetime.now(timezone.utc) - timedelta(days=days)
    
    async with get_db() as db:
        stats = await fetch_one(
            db,
            """
            SELECT
                COUNT(*) as total_transfers,
                SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as successful_transfers,
                SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed_transfers,
                SUM(CASE WHEN status = 'cancelled' THEN 1 ELSE 0 END) as cancelled_transfers,
                SUM(CASE WHEN status = 'completed' THEN bytes_transferred ELSE 0 END) as total_bytes_transferred,
                AVG(CASE WHEN status = 'completed' THEN file_size ELSE NULL END) as average_transfer_size
            FROM transfer_history
            WHERE license_key_id = ?
            AND created_at >= ?
            AND deleted_at IS NULL
            """,
            [license["license_id"], cutoff_date]
        )
        
        if not stats:
            return {
                "success": True,
                "stats": {
                    "total_transfers": 0,
                    "successful_transfers": 0,
                    "failed_transfers": 0,
                    "cancelled_transfers": 0,
                    "total_bytes_transferred": 0,
                    "success_rate": 0.0,
                    "average_transfer_size": 0.0
                }
            }
        
        total = stats['total_transfers'] or 0
        successful = stats['successful_transfers'] or 0
        success_rate = (successful / total * 100) if total > 0 else 0.0
        
        result = {
            "total_transfers": total,
            "successful_transfers": successful,
            "failed_transfers": stats['failed_transfers'] or 0,
            "cancelled_transfers": stats['cancelled_transfers'] or 0,
            "total_bytes_transferred": stats['total_bytes_transferred'] or 0,
            "success_rate": round(success_rate, 2),
            "average_transfer_size": stats['average_transfer_size'] or 0.0
        }
    
    return {
        "success": True,
        "stats": result,
        "period_days": days
    }


@router.get("/{session_id}")
@limiter.limit("30/minute")
async def get_transfer_details(
    request: Request,
    session_id: str,
    license: dict = Depends(get_license_from_header),
    user: dict = Depends(get_current_user),
):
    """
    Get details of a specific transfer by session ID.
    """
    user_id = user.get("user_id")
    
    async with get_db() as db:
        transfer = await fetch_one(
            db,
            """
            SELECT 
                id, session_id, file_name, file_size, file_type, mime_type, file_hash,
                status, direction, device_id_a, device_id_b,
                started_at, completed_at, duration_seconds, error_message,
                retry_count, bytes_transferred
            FROM transfer_history
            WHERE session_id = ?
            AND license_key_id = ?
            AND deleted_at IS NULL
            """,
            [session_id, license["license_id"]]
        )
        
        if not transfer:
            raise HTTPException(
                status_code=404,
                detail={
                    "code": "TRANSFER_NOT_FOUND",
                    "message_ar": "التحويل غير موجود",
                    "message_en": "Transfer not found"
                }
            )
        
        # Verify user has access to this transfer
        transfer_dict = dict(transfer)
        if (str(transfer_dict['device_id_a']) != str(user_id) and 
            str(transfer_dict['device_id_b']) != str(user_id)):
            raise HTTPException(
                status_code=403,
                detail={
                    "code": "FORBIDDEN",
                    "message_ar": "ليس لديك صلاحية الوصول لهذا التحويل",
                    "message_en": "You don't have access to this transfer"
                }
            )
        
        # Get device name
        device_id = transfer_dict['device_id_b'] if transfer_dict['device_id_a'] == str(user_id) else transfer_dict['device_id_a']
        device_info = await fetch_one(
            db,
            "SELECT device_name FROM device_pairing WHERE (device_id_a = ? OR device_id_b = ?) AND deleted_at IS NULL LIMIT 1",
            [device_id, device_id]
        )
        transfer_dict['device_name'] = device_info['device_name'] if device_info else 'Unknown Device'
        del transfer_dict['device_id_a']
        del transfer_dict['device_id_b']
    
    return {
        "success": True,
        "transfer": transfer_dict
    }


@router.post("/report/{transfer_id}")
@limiter.limit("10/minute")
async def report_transfer_issue(
    request: Request,
    transfer_id: int,
    issue_type: str = Query(..., description="Type of issue: failed, incomplete, corrupted"),
    description: Optional[str] = Query(None, description="Additional details"),
    license: dict = Depends(get_license_from_header),
    user: dict = Depends(get_current_user),
):
    """
    Report an issue with a transfer for investigation.
    
    This is useful for tracking problematic transfers and improving the system.
    """
    user_id = user.get("user_id")
    now = datetime.now(timezone.utc)
    
    async with get_db() as db:
        # Verify transfer exists and belongs to user
        transfer = await fetch_one(
            db,
            """
            SELECT * FROM transfer_history
            WHERE id = ?
            AND license_key_id = ?
            AND (device_id_a = ? OR device_id_b = ?)
            AND deleted_at IS NULL
            """,
            [transfer_id, license["license_id"], user_id, user_id]
        )
        
        if not transfer:
            raise HTTPException(
                status_code=404,
                detail={
                    "code": "TRANSFER_NOT_FOUND",
                    "message_ar": "التحويل غير موجود",
                    "message_en": "Transfer not found"
                }
            )
        
        # Log the issue (could be stored in a separate issues table for tracking)
        logger.warning(
            f"Transfer issue reported: transfer_id={transfer_id}, "
            f"issue_type={issue_type}, user_id={user_id}, description={description}"
        )
        
        # Update transfer with issue flag (add a column in future migration)
        # For now, just log it
    
    return {
        "success": True,
        "message": "تم الإبلاغ عن المشكلة بنجاح",
        "message_en": "Issue reported successfully"
    }
