"""
Al-Mudeer - Admin User Approval Routes
Handles admin approval/rejection of user accounts

Endpoints:
- GET    /api/admin/users/pending      - List users awaiting approval
- GET    /api/admin/users              - List all users with filters
- POST   /api/admin/users/{user_id}/approve   - Approve a user
- POST   /api/admin/users/{user_id}/reject    - Reject a user
- GET    /api/admin/users/{user_id}    - Get user details
- PATCH  /api/admin/users/{user_id}    - Update user details
- DELETE /api/admin/users/{user_id}    - Delete user

All endpoints require admin authentication via X-Admin-Key header.
"""

import os
from fastapi import APIRouter, HTTPException, Depends, Header, Query, Body
from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime

from db_helper import get_db, fetch_one, fetch_all, execute_sql, commit_db
from logging_config import get_logger

logger = get_logger(__name__)

router = APIRouter(prefix="/api/admin/users", tags=["Admin User Management"])

# Admin authentication
ADMIN_KEY = os.getenv("ADMIN_KEY")
if not ADMIN_KEY:
    raise ValueError("ADMIN_KEY environment variable is required")


async def verify_admin_key(x_admin_key: str = Header(None, alias="X-Admin-Key")):
    """Verify admin key from header"""
    if not x_admin_key:
        raise HTTPException(status_code=403, detail="مفتاح المدير مطلوب")
    
    clean_env_key = "".join(ADMIN_KEY.split()) if ADMIN_KEY else ""
    clean_received_key = "".join(x_admin_key.split()) if x_admin_key else ""
    
    if clean_received_key != clean_env_key:
        logger.warning("Invalid admin key attempt")
        raise HTTPException(status_code=403, detail="مفتاح المدير غير صحيح")
    
    return True


# ============ Schemas ============

class UserAccountInfo(BaseModel):
    """User account information"""
    id: int
    email: str
    full_name: Optional[str] = None
    is_email_verified: bool
    is_approved_by_admin: bool
    approval_status: str
    created_at: Optional[str] = None
    last_login: Optional[str] = None


class UserListResponse(BaseModel):
    """Response for user list"""
    success: bool
    users: List[dict]
    total: int


class UserApprovalResponse(BaseModel):
    """Response for approval/rejection"""
    success: bool
    message: str
    user_id: int


class UserUpdateRequest(BaseModel):
    """Request to update user details"""
    full_name: Optional[str] = None
    is_approved_by_admin: Optional[bool] = None
    approval_status: Optional[str] = None


# ============ Endpoints ============

@router.get("/pending")
async def list_pending_users(admin: bool = Depends(verify_admin_key)):
    """
    List all users awaiting admin approval.
    Returns users with approval_status='pending'.
    """
    async with get_db() as db:
        rows = await fetch_all(
            db,
            """
            SELECT id, email, full_name, username,
                   is_email_verified, is_approved_by_admin, approval_status,
                   created_at, last_login
            FROM user_accounts
            WHERE approval_status = 'pending'
            ORDER BY created_at DESC
            """
        )

        users = []
        for row in rows:
            row_dict = dict(row)
            users.append({
                "id": row_dict.get("id"),
                "email": row_dict.get("email"),
                "full_name": row_dict.get("full_name"),
                "username": row_dict.get("username"),
                "is_email_verified": row_dict.get("is_email_verified", False),
                "is_approved_by_admin": row_dict.get("is_approved_by_admin", False),
                "approval_status": row_dict.get("approval_status", "pending"),
                "created_at": str(row_dict.get("created_at")) if row_dict.get("created_at") else None,
                "last_login": str(row_dict.get("last_login")) if row_dict.get("last_login") else None,
            })

        return {
            "success": True,
            "users": users,
            "total": len(users)
        }


@router.get("")
async def list_all_users(
    approval_status: Optional[str] = Query(None, description="Filter by approval status: pending, approved, rejected"),
    is_email_verified: Optional[bool] = Query(None, description="Filter by email verification"),
    search: Optional[str] = Query(None, description="Search by email or full name"),
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    admin: bool = Depends(verify_admin_key)
):
    """
    List all user accounts with optional filters.
    """
    async with get_db() as db:
        # Build dynamic query
        where_clauses = []
        params = []

        if approval_status:
            where_clauses.append("approval_status = ?")
            params.append(approval_status)

        if is_email_verified is not None:
            where_clauses.append("is_email_verified = ?")
            params.append(is_email_verified)

        if search:
            where_clauses.append("(email LIKE ? OR full_name LIKE ?)")
            search_param = f"%{search}%"
            params.extend([search_param, search_param])

        where_sql = " AND ".join(where_clauses) if where_clauses else "1=1"

        # Get total count
        count_sql = f"SELECT COUNT(*) as total FROM user_accounts WHERE {where_sql}"
        count_row = await fetch_one(db, count_sql, params)
        total = count_row["total"] if count_row else 0

        # Get paginated results
        data_sql = f"""
            SELECT id, email, full_name, username,
                   is_email_verified, is_approved_by_admin, approval_status,
                   created_at, last_login
            FROM user_accounts
            WHERE {where_sql}
            ORDER BY created_at DESC
            LIMIT ? OFFSET ?
        """
        params.extend([limit, offset])
        rows = await fetch_all(db, data_sql, params)

        users = []
        for row in rows:
            row_dict = dict(row)
            users.append({
                "id": row_dict.get("id"),
                "email": row_dict.get("email"),
                "full_name": row_dict.get("full_name"),
                "username": row_dict.get("username"),
                "is_email_verified": row_dict.get("is_email_verified", False),
                "is_approved_by_admin": row_dict.get("is_approved_by_admin", False),
                "approval_status": row_dict.get("approval_status", "pending"),
                "created_at": str(row_dict.get("created_at")) if row_dict.get("created_at") else None,
                "last_login": str(row_dict.get("last_login")) if row_dict.get("last_login") else None,
            })

        return {
            "success": True,
            "users": users,
            "total": total,
            "limit": limit,
            "offset": offset
        }


@router.get("/{user_id}")
async def get_user_details(
    user_id: int,
    admin: bool = Depends(verify_admin_key)
):
    """
    Get detailed information about a specific user.
    """
    async with get_db() as db:
        user = await fetch_one(
            db,
            """
            SELECT *
            FROM user_accounts
            WHERE id = ?
            """,
            [user_id]
        )

        if not user:
            raise HTTPException(status_code=404, detail="المستخدم غير موجود")

        user_dict = dict(user)

        return {
            "success": True,
            "user": {
                "id": user_dict.get("id"),
                "email": user_dict.get("email"),
                "full_name": user_dict.get("full_name"),
                "username": user_dict.get("username"),
                "is_email_verified": user_dict.get("is_email_verified", False),
                "is_approved_by_admin": user_dict.get("is_approved_by_admin", False),
                "approval_status": user_dict.get("approval_status", "pending"),
                "created_at": str(user_dict.get("created_at")) if user_dict.get("created_at") else None,
                "last_login": str(user_dict.get("last_login")) if user_dict.get("last_login") else None,
                "updated_at": str(user_dict.get("updated_at")) if user_dict.get("updated_at") else None,
            }
        }


@router.post("/{user_id}/approve", response_model=UserApprovalResponse)
async def approve_user(
    user_id: int,
    admin: bool = Depends(verify_admin_key)
):
    """
    Approve a user account.

    Flow:
    1. Update user_accounts: is_approved_by_admin=TRUE, approval_status='approved'
    2. Send approval notification email
    """
    from services.email_service import get_email_service

    async with get_db() as db:
        # Check if user exists
        user = await fetch_one(
            db,
            "SELECT id, email, full_name, is_approved_by_admin FROM user_accounts WHERE id = ?",
            [user_id]
        )

        if not user:
            raise HTTPException(status_code=404, detail="المستخدم غير موجود")

        if user.get("is_approved_by_admin"):
            return UserApprovalResponse(
                success=True,
                message="المستخدم معتمد بالفعل",
                user_id=user_id
            )

        # Approve user
        await execute_sql(
            db,
            """
            UPDATE user_accounts
            SET is_approved_by_admin = TRUE, approval_status = 'approved', updated_at = NOW()
            WHERE id = ?
            """,
            [user_id]
        )

        await commit_db(db)

    # Send approval notification email
    try:
        email_service = get_email_service()
        await email_service.send_approval_notification_email(
            user["email"],
            user.get("full_name", "مستخدم")
        )
    except Exception as e:
        logger.error(f"Failed to send approval notification to {user['email']}: {e}")
        # Don't fail the approval if email fails

    logger.info(f"User {user_id} approved by admin")

    return UserApprovalResponse(
        success=True,
        message=f"تم اعتماد المستخدم {user.get('email')}",
        user_id=user_id
    )


@router.post("/{user_id}/reject", response_model=UserApprovalResponse)
async def reject_user(
    user_id: int,
    reason: Optional[str] = Query(None, description="Reason for rejection"),
    admin: bool = Depends(verify_admin_key)
):
    """
    Reject a user account.

    Flow:
    1. Update user_accounts: approval_status='rejected'
    """
    async with get_db() as db:
        # Check if user exists
        user = await fetch_one(
            db,
            "SELECT id, email, full_name FROM user_accounts WHERE id = ?",
            [user_id]
        )

        if not user:
            raise HTTPException(status_code=404, detail="المستخدم غير موجود")

        # Reject user
        await execute_sql(
            db,
            """
            UPDATE user_accounts
            SET approval_status = 'rejected', updated_at = NOW()
            WHERE id = ?
            """,
            [user_id]
        )

        await commit_db(db)

    logger.info(f"User {user_id} rejected by admin. Reason: {reason or 'Not specified'}")

    return UserApprovalResponse(
        success=True,
        message=f"تم رفض المستخدم {user.get('email')}",
        user_id=user_id
    )


@router.patch("/{user_id}")
async def update_user(
    user_id: int,
    data: UserUpdateRequest,
    admin: bool = Depends(verify_admin_key)
):
    """
    Update user account details.
    """
    async with get_db() as db:
        # Check if user exists
        user = await fetch_one(
            db,
            "SELECT id FROM user_accounts WHERE id = ?",
            [user_id]
        )

        if not user:
            raise HTTPException(status_code=404, detail="المستخدم غير موجود")

        # Build update query dynamically
        updates = []
        params = []

        if data.full_name is not None:
            updates.append("full_name = ?")
            params.append(data.full_name)

        if data.is_approved_by_admin is not None:
            updates.append("is_approved_by_admin = ?")
            params.append(data.is_approved_by_admin)

        if data.approval_status is not None:
            updates.append("approval_status = ?")
            params.append(data.approval_status)

        if not updates:
            return {"success": True, "message": "لا توجد تغييرات"}

        updates.append("updated_at = NOW()")
        params.append(user_id)

        await execute_sql(
            db,
            f"UPDATE user_accounts SET {', '.join(updates)} WHERE id = ?",
            params
        )
        await commit_db(db)

    return {"success": True, "message": "تم تحديث المستخدم"}


@router.delete("/{user_id}")
async def delete_user(
    user_id: int,
    admin: bool = Depends(verify_admin_key)
):
    """
    Delete a user account.
    
    WARNING: This is a destructive operation.
    """
    async with get_db() as db:
        # Check if user exists
        user = await fetch_one(
            db,
            "SELECT id, email FROM user_accounts WHERE id = ?",
            [user_id]
        )

        if not user:
            raise HTTPException(status_code=404, detail="المستخدم غير موجود")

        # Delete user (cascade will handle related records if configured)
        await execute_sql(
            db,
            "DELETE FROM user_accounts WHERE id = ?",
            [user_id]
        )
        await commit_db(db)

    logger.warning(f"User {user_id} ({user.get('email')}) deleted by admin")

    return {"success": True, "message": f"تم حذف المستخدم {user.get('email')}"}
