"""
Permission Helpers for Task/Library Sharing

Defines exact permission levels and actions for shared resources.

Permission Levels:
- read: Can VIEW content only. Cannot edit, share, or delete.
- edit: Can VIEW and EDIT content. Can SHARE with others. Cannot DELETE.
- admin: Full access - can VIEW, EDIT, SHARE, and DELETE (same as owner).
- owner: Creator of the resource - has all permissions implicitly.
"""
from typing import Optional, Set


# ============================================================================
# Permission Constants
# ============================================================================

class PermissionLevel:
    """Valid permission levels for shared resources"""
    READ = 'read'
    EDIT = 'edit'
    ADMIN = 'admin'
    OWNER = 'owner'  # Implicit - the creator


class ResourceAction:
    """Actions that can be performed on resources"""
    VIEW = 'view'
    EDIT = 'edit'
    SHARE = 'share'
    DELETE = 'delete'
    MANAGE_SHARES = 'manage_shares'  # Add/remove shares (admin only)


# ============================================================================
# Permission Matrix
# ============================================================================

# Maps permission level to allowed actions
PERMISSION_ACTIONS: dict[str, Set[str]] = {
    PermissionLevel.READ: {
        ResourceAction.VIEW,
    },
    PermissionLevel.EDIT: {
        ResourceAction.VIEW,
        ResourceAction.EDIT,
        ResourceAction.SHARE,
    },
    PermissionLevel.ADMIN: {
        ResourceAction.VIEW,
        ResourceAction.EDIT,
        ResourceAction.SHARE,
        ResourceAction.DELETE,
        ResourceAction.MANAGE_SHARES,
    },
    PermissionLevel.OWNER: {
        ResourceAction.VIEW,
        ResourceAction.EDIT,
        ResourceAction.SHARE,
        ResourceAction.DELETE,
        ResourceAction.MANAGE_SHARES,
    },
}


def get_effective_permission(
    share_permission: Optional[str],
    is_owner: bool
) -> str:
    """
    Get the effective permission level for a user.
    
    Args:
        share_permission: The permission from the share record (read/edit/admin)
        is_owner: Whether the user is the resource owner
        
    Returns:
        Effective permission level (owner/read/edit/admin)
    """
    if is_owner:
        return PermissionLevel.OWNER
    return share_permission or PermissionLevel.READ


def can_perform_action(
    action: str,
    permission_level: str
) -> bool:
    """
    Check if a permission level allows a specific action.
    
    Args:
        action: The action to check (view/edit/share/delete/manage_shares)
        permission_level: The user's permission level (owner/read/edit/admin)
        
    Returns:
        True if the action is allowed, False otherwise
    """
    allowed_actions = PERMISSION_ACTIONS.get(permission_level, set())
    return action in allowed_actions


def can_view(permission_level: str) -> bool:
    """Check if user can view the resource"""
    return can_perform_action(ResourceAction.VIEW, permission_level)


def can_edit(permission_level: str) -> bool:
    """Check if user can edit the resource"""
    return can_perform_action(ResourceAction.EDIT, permission_level)


def can_share(permission_level: str) -> bool:
    """Check if user can share the resource with others"""
    return can_perform_action(ResourceAction.SHARE, permission_level)


def can_delete(permission_level: str) -> bool:
    """Check if user can delete the resource"""
    return can_perform_action(ResourceAction.DELETE, permission_level)


def can_manage_shares(permission_level: str) -> bool:
    """Check if user can manage shares (add/remove shares)"""
    return can_perform_action(ResourceAction.MANAGE_SHARES, permission_level)


def get_permission_description(permission_level: str) -> dict[str, str]:
    """
    Get human-readable description of what a permission level allows.
    
    Args:
        permission_level: The permission level
        
    Returns:
        Dict with Arabic and English descriptions
    """
    descriptions = {
        PermissionLevel.READ: {
            'ar': 'قراءة فقط - يمكنه عرض المحتوى دون تعديل أو مشاركة أو حذف',
            'en': 'Read only - Can view content without editing, sharing, or deleting'
        },
        PermissionLevel.EDIT: {
            'ar': 'تعديل - يمكنه العرض والتعديل والمشاركة دون حذف',
            'en': 'Edit - Can view, edit, and share without deleting'
        },
        PermissionLevel.ADMIN: {
            'ar': 'مدير - يمكنه العرض والتعديل والمشاركة والحذف (كالمالك)',
            'en': 'Admin - Can view, edit, share, and delete (like owner)'
        },
        PermissionLevel.OWNER: {
            'ar': 'مالك - صلاحيات كاملة',
            'en': 'Owner - Full access'
        },
    }
    return descriptions.get(permission_level, {
        'ar': 'غير معروف',
        'en': 'Unknown'
    })


def validate_permission_for_action(
    action: str,
    permission_level: str,
    resource_type: str = 'resource'
) -> tuple[bool, Optional[str]]:
    """
    Validate if a permission level allows an action, with error message.
    
    Args:
        action: The action to validate
        permission_level: The user's permission level
        resource_type: Type of resource (for error messages)
        
    Returns:
        Tuple of (is_valid, error_message)
        - is_valid: True if action is allowed
        - error_message: Error message if action is not allowed (None if valid)
    """
    if can_perform_action(action, permission_level):
        return True, None
    
    # Generate appropriate error message
    error_messages = {
        PermissionLevel.READ: {
            'ar': f'ليس لديك صلاحية {action} لهذا {resource_type}. صلاحيك مقصورة على العرض فقط.',
            'en': f'You do not have permission to {action} this {resource_type}. Your access is read-only.'
        },
        PermissionLevel.EDIT: {
            'ar': f'ليس لديك صلاحية {action} لهذا {resource_type}. يمكن للمحررين العرض والتعديل والمشاركة فقط.',
            'en': f'You do not have permission to {action} this {resource_type}. Editors can only view, edit, and share.'
        },
    }
    
    msg = error_messages.get(permission_level, {
        'ar': f'ليس لديك صلاحية {action} لهذا {resource_type}',
        'en': f'You do not have permission to {action} this {resource_type}'
    })
    
    return False, msg
