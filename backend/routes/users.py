"""
Al-Mudeer - Users Routes
Search and manage Almudeer users
"""

from fastapi import APIRouter, HTTPException, status, Depends, Request
from typing import Optional, List
from database import get_db, fetch_all
from services.jwt_auth import get_current_user
from logging_config import get_logger

logger = get_logger(__name__)
router = APIRouter(prefix="/api/users", tags=["Users"])


@router.get("/search")
async def search_users(
    request: Request,
    q: str,
    limit: Optional[int] = 20,
    current_user: dict = Depends(get_current_user),
):
    """
    Search for Almudeer users by username or name.
    Only returns users that exist in the license_keys table.

    Args:
        q: Search query string
        limit: Maximum number of results to return (max 100)
        current_user: Current authenticated user

    Returns:
        List of matching users with basic profile information
    """
    # FIX: Enforce max limit to prevent abuse
    limit = min(max(1, limit or 20), 100)  # Max 100 results
    
    # Validate search query
    if not q or len(q.strip()) < 2:
        return {
            "results": [],
            "count": 0,
            "query": q,
        }

    license_id = current_user.get("license_id")
    search_query = f"%{q.strip()}%"
    
    async with get_db() as db:
        # Search in license_keys table for Almudeer users
        # Search by username or full_name
        rows = await fetch_all(
            db,
            """
            SELECT
                id,
                username,
                full_name as name,
                profile_image_url as image,
                is_active,
                created_at,
                last_seen_at
            FROM license_keys
            WHERE (
                username LIKE ?
                OR full_name LIKE ?
            )
            AND is_active IS TRUE
            ORDER BY
                CASE
                    WHEN username LIKE ? THEN 0
                    WHEN full_name LIKE ? THEN 1
                    ELSE 2
                END,
                last_seen_at DESC
            LIMIT ?
            """,
            [
                search_query, search_query, search_query,
                search_query,
                limit,
            ],
        )
        
        users = [dict(row) for row in rows]
        
        # Also search in customers who are Almudeer users
        customer_rows = await fetch_all(
            db,
            """
            SELECT
                c.id,
                c.username,
                c.name,
                NULL as image,
                c.is_vip,
                c.created_at,
                c.last_contact_at as last_seen_at
            FROM customers c
            WHERE c.license_key_id = ?
            AND EXISTS (SELECT 1 FROM license_keys l WHERE l.username = c.username AND c.username IS NOT NULL)
            AND (
                c.username LIKE ?
                OR c.name LIKE ?
            )
            ORDER BY
                CASE
                    WHEN c.username LIKE ? THEN 0
                    WHEN c.name LIKE ? THEN 1
                    ELSE 2
                END,
                c.last_contact_at DESC
            LIMIT ?
            """,
            [
                license_id,
                search_query, search_query, search_query,
                search_query, search_query,
                limit,
            ],
        )
        
        # Merge results, avoiding duplicates by username
        existing_usernames = {user.get("username") for user in users if user.get("username")}
        
        for customer in customer_rows:
            customer_dict = dict(customer)
            username = customer_dict.get("username")
            
            # Only add if not already in results and has a username
            if username and username not in existing_usernames:
                customer_dict["is_customer"] = True
                users.append(customer_dict)
                existing_usernames.add(username)
        
        # Limit total results
        users = users[:limit]
        
        return {
            "results": users,
            "count": len(users),
            "query": q,
        }


@router.get("/me")
async def get_current_user_profile(
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    """
    Get current user's profile information.

    Returns:
        Current user's profile data
    """
    license_id = current_user.get("license_id")

    async with get_db() as db:
        row = await fetch_all(
            db,
            """
            SELECT 
                id,
                username,
                full_name as name,
                profile_image_url as image,
                is_active,
                created_at,
                last_seen_at,
                referral_code,
                referral_count
            FROM license_keys
            WHERE id = ?
            """,
            [license_id],
        )
        
        if not row:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found",
            )
        
        return dict(row[0])


@router.get("/{username}")
async def get_user_by_username(
    username: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    """
    Get a specific user's profile by username.
    
    Args:
        username: The username to look up
        current_user: Current authenticated user
        
    Returns:
        User profile data
    """
    async with get_db() as db:
        row = await fetch_all(
            db,
            """
            SELECT 
                id,
                username,
                full_name as name,
                profile_image_url as image,
                is_active,
                created_at,
                last_seen_at
            FROM license_keys
            WHERE username = ?
            AND is_active IS TRUE
            """,
            [username],
        )
        
        if not row:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found",
            )
        
        return dict(row[0])
