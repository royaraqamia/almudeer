/// Permission helpers for task/library sharing
/// 
/// Permission Levels:
/// - read: Can VIEW only. Cannot edit, share, or delete.
/// - edit: Can VIEW, EDIT, and SHARE. Cannot DELETE.
/// - admin: Full access - VIEW, EDIT, SHARE, DELETE (same as owner).
/// - owner: Creator of the resource - has all permissions implicitly.
library;

/// Valid permission levels
class PermissionLevel {
  static const String read = 'read';
  static const String edit = 'edit';
  static const String admin = 'admin';
  static const String owner = 'owner';
}

/// Get effective permission level for a user
/// 
/// [sharePermission] - The permission from the share record (read/edit/admin)
/// [isOwner] - Whether the user is the resource owner
String getEffectivePermission(String? sharePermission, bool isOwner) {
  if (isOwner) {
    return PermissionLevel.owner;
  }
  return sharePermission ?? PermissionLevel.read;
}

/// Check if user can view the resource
bool canView(String permissionLevel) {
  return true; // All permission levels can view
}

/// Check if user can edit the resource
bool canEdit(String permissionLevel) {
  return permissionLevel == PermissionLevel.owner ||
      permissionLevel == PermissionLevel.admin ||
      permissionLevel == PermissionLevel.edit;
}

/// Check if user can share the resource with others
bool canShare(String permissionLevel) {
  return permissionLevel == PermissionLevel.owner ||
      permissionLevel == PermissionLevel.admin ||
      permissionLevel == PermissionLevel.edit;
}

/// Check if user can delete the resource
bool canDelete(String permissionLevel) {
  return permissionLevel == PermissionLevel.owner ||
      permissionLevel == PermissionLevel.admin;
}

/// Check if user can manage shares (add/remove shares)
bool canManageShares(String permissionLevel) {
  return permissionLevel == PermissionLevel.owner ||
      permissionLevel == PermissionLevel.admin;
}

/// Get human-readable description of permission level
Map<String, String> getPermissionDescription(String permissionLevel) {
  switch (permissionLevel) {
    case PermissionLevel.read:
      return {
        'ar': 'قراءة فقط - يمكنه عرض المحتوى دون تعديل أو مشاركة أو حذف',
        'en': 'Read only - Can view content without editing, sharing, or deleting',
        'label_ar': 'قراءة فقط',
        'label_en': 'Read Only',
      };
    case PermissionLevel.edit:
      return {
        'ar': 'تعديل - يمكنه العرض والتعديل والمشاركة دون حذف',
        'en': 'Edit - Can view, edit, and share without deleting',
        'label_ar': 'تعديل',
        'label_en': 'Edit',
      };
    case PermissionLevel.admin:
      return {
        'ar': 'مدير - يمكنه العرض والتعديل والمشاركة والحذف (كالمالك)',
        'en': 'Admin - Can view, edit, share, and delete (like owner)',
        'label_ar': 'مدير',
        'label_en': 'Admin',
      };
    case PermissionLevel.owner:
      return {
        'ar': 'مالك - صلاحيات كاملة',
        'en': 'Owner - Full access',
        'label_ar': 'مالك',
        'label_en': 'Owner',
      };
    default:
      return {
        'ar': 'غير معروف',
        'en': 'Unknown',
        'label_ar': 'غير معروف',
        'label_en': 'Unknown',
      };
  }
}

/// Extension on TaskModel for permission checks
extension TaskPermissionExtension on Map<String, dynamic> {
  /// Get effective permission for this task
  String get effectivePermission {
    final isOwner = this['is_owner'] as bool? ?? false;
    final sharePermission = this['share_permission'] as String?;
    return getEffectivePermission(sharePermission, isOwner);
  }

  /// Check if current user can edit this task
  bool get canEditTask => canEdit(effectivePermission);

  /// Check if current user can share this task
  bool get canShareTask => canShare(effectivePermission);

  /// Check if current user can delete this task
  bool get canDeleteTask => canDelete(effectivePermission);

  /// Check if current user can manage shares for this task
  bool get canManageTaskShares => canManageShares(effectivePermission);
}

/// Extension on LibraryItem for permission checks
extension LibraryItemPermissionExtension on Map<String, dynamic> {
  /// Get effective permission for this library item
  String get effectivePermission {
    final isOwner = this['is_owner'] as bool? ?? false;
    final sharePermission = this['share_permission'] as String?;
    return getEffectivePermission(sharePermission, isOwner);
  }

  /// Check if current user can edit this item
  bool get canEditItem => canEdit(effectivePermission);

  /// Check if current user can share this item
  bool get canShareItem => canShare(effectivePermission);

  /// Check if current user can delete this item
  bool get canDeleteItem => canDelete(effectivePermission);

  /// Check if current user can manage shares for this item
  bool get canManageItemShares => canManageShares(effectivePermission);
}
