"""
Shared utilities for task/library sharing functionality.

Centralized helpers to ensure consistent behavior across share operations.
"""
from typing import Optional, Tuple
from db_helper import get_db, fetch_one, DB_TYPE


# ============================================================================
# SHARE ERROR CODES
# ============================================================================
# Error codes for consistent error handling between backend and mobile
# Mobile app should match on these codes instead of error message strings

class ShareErrorCode:
    """Error codes for share operations"""
    # Task share errors
    TASK_NOT_FOUND = "TASK_NOT_FOUND"
    TASK_OWNER_ONLY = "TASK_OWNER_ONLY"
    SELF_SHARE = "SELF_SHARE"
    SHARE_REVOKED = "SHARE_REVOKED"
    USER_NOT_FOUND = "USER_NOT_FOUND"
    INVALID_PERMISSION = "INVALID_PERMISSION"
    
    # Library share errors
    ITEM_NOT_FOUND = "ITEM_NOT_FOUND"
    ITEM_OWNER_ONLY = "ITEM_OWNER_ONLY"
    SELF_ITEM_SHARE = "SELF_ITEM_SHARE"
    ITEM_SHARE_REVOKED = "ITEM_SHARE_REVOKED"
    
    # General errors
    INVALID_SHARE = "INVALID_SHARE"
    SHARE_FAILED = "SHARE_FAILED"
    PERMISSION_DENIED = "PERMISSION_DENIED"


# ============================================================================
# SHARING UTILITIES
# ============================================================================

async def resolve_username_to_user_id(username: str) -> Tuple[str, bool]:
    """
    Resolve a username to a user_id (license_id).
    
    If the input is already numeric (license_id), return it as-is.
    If the input is a username, look up the license_id.
    
    Args:
        username: Either a username (string) or license_id (numeric string)
        
    Returns:
        Tuple of (user_id, was_resolved):
        - user_id: The resolved license_id as string
        - was_resolved: True if we did a DB lookup, False if input was already numeric
        
    Raises:
        ValueError: If username is not found in the database
    """
    # Check if it's already a numeric license_id
    if username.isdigit():
        return username, False
    
    # Look up the license_id by username
    is_active_value = "TRUE" if DB_TYPE == "postgresql" else "1"
    license_row = await fetch_one(
        get_db().__aenter__() if hasattr(get_db(), '__aenter__') else None,
        f"SELECT id FROM license_keys WHERE username = ? AND is_active = {is_active_value}",
        [username]
    )
    
    # Note: The actual DB connection will be provided by the caller
    # This is a simplified version - see usage in task_shares.py and library_advanced.py
    
    if not license_row:
        raise ValueError(f"User '{username}' not found")
    
    return str(license_row['id']), True


async def resolve_username_to_user_id_with_db(username: str, db) -> Tuple[str, bool]:
    """
    Resolve a username to a user_id using provided DB connection.

    FIX: Support both legacy license_keys auth and new email/password auth.
    First checks license_keys (legacy), then falls back to user_accounts (new auth).

    Args:
        username: Either a username (string) or user_id (numeric string)
        db: Database connection

    Returns:
        Tuple of (user_id, was_resolved)

    Raises:
        ValueError: If username is not found in the database
    """
    # Check if it's already a numeric user_id/license_id
    if username.isdigit():
        return username, False

    is_active_value = "TRUE" if DB_TYPE == "postgresql" else "1"

    # FIX: First try legacy license_keys table
    license_row = await fetch_one(
        db,
        f"SELECT id FROM license_keys WHERE username = ? AND is_active = {is_active_value}",
        [username]
    )

    if license_row:
        return str(license_row['id']), True

    # FIX: Fall back to new user_accounts table for email-auth users
    user_row = await fetch_one(
        db,
        f"SELECT id FROM user_accounts WHERE username = ? AND is_active = {is_active_value}",
        [username]
    )

    if user_row:
        return str(user_row['id']), True

    raise ValueError(f"User '{username}' not found")


def validate_share_permission(permission: str) -> bool:
    """
    Validate that a permission level is valid.
    
    Args:
        permission: Permission level to validate
        
    Returns:
        True if valid, False otherwise
    """
    return permission in ('read', 'edit', 'admin')


def normalize_permission(permission: Optional[str]) -> str:
    """
    Normalize permission to a valid default if invalid.

    Args:
        permission: Permission level to normalize

    Returns:
        Valid permission level (defaults to 'read')
    """
    if permission and validate_share_permission(permission):
        return permission
    return 'read'


def get_share_error_code(error_message: str) -> str:
    """
    Map an error message to a standardized error code.
    
    Args:
        error_message: The error message string
        
    Returns:
        A standardized error code from ShareErrorCode
    """
    error_lower = error_message.lower()
    
    if 'yourself' in error_lower:
        return ShareErrorCode.SELF_SHARE
    elif 'task' in error_lower and 'not found' in error_lower:
        return ShareErrorCode.TASK_NOT_FOUND
    elif 'item' in error_lower and 'not found' in error_lower:
        return ShareErrorCode.ITEM_NOT_FOUND
    elif 'not found' in error_lower:
        return ShareErrorCode.USER_NOT_FOUND
    elif 'permission' in error_lower or 'privilege' in error_lower:
        return ShareErrorCode.PERMISSION_DENIED
    elif 'revoked' in error_lower:
        return ShareErrorCode.SHARE_REVOKED
    elif 'owner' in error_lower:
        return ShareErrorCode.TASK_OWNER_ONLY
    elif 'user' in error_lower and 'not found' in error_lower:
        return ShareErrorCode.USER_NOT_FOUND
    else:
        return ShareErrorCode.INVALID_SHARE
