"""
Shared utilities for task/library sharing functionality.

Centralized helpers to ensure consistent behavior across share operations.
"""
from typing import Optional, Tuple
from db_helper import get_db, fetch_one, DB_TYPE


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
    Resolve a username to a user_id (license_id) using provided DB connection.
    
    This is the actual implementation that uses an existing DB connection
    to avoid creating multiple connections.
    
    Args:
        username: Either a username (string) or license_id (numeric string)
        db: Database connection
        
    Returns:
        Tuple of (user_id, was_resolved)
        
    Raises:
        ValueError: If username is not found in the database
    """
    # Check if it's already a numeric license_id
    if username.isdigit():
        return username, False
    
    # Look up the license_id by username
    is_active_value = "TRUE" if DB_TYPE == "postgresql" else "1"
    license_row = await fetch_one(
        db,
        f"SELECT id FROM license_keys WHERE username = ? AND is_active = {is_active_value}",
        [username]
    )
    
    if not license_row:
        raise ValueError(f"User '{username}' not found")
    
    return str(license_row['id']), True


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
