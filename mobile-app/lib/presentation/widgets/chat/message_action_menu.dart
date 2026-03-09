import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

import '../../../core/constants/colors.dart';
import '../../../core/extensions/string_extension.dart';
import '../../../core/utils/haptics.dart';
import '../../../data/models/inbox_message.dart';
import '../animated_toast.dart';

import '../premium_bottom_sheet.dart';

/// Context menu for message actions (edit, delete, copy, reply, forward)
///
/// Refactored to use PremiumBottomSheet.
class MessageActionMenu extends StatelessWidget {
  final InboxMessage message;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onCopy;
  final VoidCallback? onReply;
  final VoidCallback? onForward;
  final bool isSelectionMode;
  final int? selectedCount;

  const MessageActionMenu({
    super.key,
    required this.message,
    this.onEdit,
    this.onDelete,
    this.onCopy,
    this.onReply,
    this.onForward,
    this.isSelectionMode = false,
    this.selectedCount,
  });

  /// Check if message can be edited
  bool get canEdit => message.canEdit;

  /// Check if message can be deleted
  bool get canDelete {
    return !message.isDeleted;
  }

  /// Check if message can be forwarded
  bool get canForward => !message.isDeleted && (message.body.isNotEmpty || (message.attachments?.isNotEmpty ?? false));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Selection Mode Header
        if (isSelectionMode) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Text(
              '${selectedCount ?? 0} رسالة محددة',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
        ]
        // Message Preview (only in single-select mode)
        else if (message.body.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: (isDark ? Colors.white : Colors.black).withValues(
                    alpha: 0.05,
                  ),
                ),
              ),
              child: Text(
                message.body.safeUtf16,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.textTheme.bodyLarge?.color?.withValues(
                    alpha: 0.8,
                  ),
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                textDirection:
                    RegExp(r'[\u0600-\u06FF]').hasMatch(message.body.safeUtf16)
                    ? TextDirection.rtl
                    : TextDirection.ltr,
              ),
            ),
          ),

        // Actions List
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              // Selection Mode Actions
              if (isSelectionMode) ...[
                _buildMenuItem(
                  context,
                  icon: SolarLinearIcons.copy,
                  label: 'نسخ الرسائل',
                  onTap: () {
                    Haptics.lightTap();
                    Navigator.pop(context);
                    onCopy?.call();
                  },
                ),
                const Divider(height: 1, thickness: 0.5, indent: 56),
                _buildMenuItem(
                  context,
                  icon: SolarLinearIcons.share,
                  label: 'إعادة إرسال',
                  onTap: () {
                    Haptics.lightTap();
                    Navigator.pop(context);
                    onForward?.call();
                  },
                ),
                const Divider(height: 1, thickness: 0.5, indent: 56),
                _buildMenuItem(
                  context,
                  icon: SolarLinearIcons.trashBinMinimalistic,
                  label: 'حذف الرسائل',
                  isDestructive: true,
                  onTap: () {
                    Haptics.lightTap();
                    Navigator.pop(context);
                    onDelete?.call();
                  },
                ),
              ]
              // Single Message Actions
              else ...[
                // Reply
                if (onReply != null) ...[
                  _buildMenuItem(
                    context,
                    icon: SolarLinearIcons.reply,
                    label: 'رد',
                    onTap: () {
                      Haptics.lightTap();
                      Navigator.pop(context);
                      onReply!();
                    },
                  ),
                  const Divider(height: 1, thickness: 0.5, indent: 56),
                ],

                // Forward
                if (canForward && onForward != null)
                  _buildMenuItem(
                    context,
                    icon: SolarLinearIcons.share,
                    label: 'إعادة إرسال',
                    onTap: () {
                      Haptics.lightTap();
                      Navigator.pop(context);
                      onForward!();
                    },
                  ),

                if (canForward && onForward != null)
                  const Divider(height: 1, thickness: 0.5, indent: 56),

                // Copy
                _buildMenuItem(
                  context,
                  icon: SolarLinearIcons.copy,
                  label: 'نسخ',
                  onTap: () {
                    Clipboard.setData(
                      ClipboardData(text: message.body.safeUtf16),
                    );
                    Haptics.lightTap();
                    Navigator.pop(context);
                    AnimatedToast.info(context, 'تم نسخ الرسالة');
                  },
                ),

                const Divider(height: 1, thickness: 0.5, indent: 56),

                // Edit
                if (canEdit && onEdit != null) ...[
                  _buildMenuItem(
                    context,
                    icon: SolarLinearIcons.pen,
                    label: 'تعديل',
                    onTap: () {
                      Navigator.pop(context);
                      onEdit!();
                    },
                  ),
                  const Divider(height: 1, thickness: 0.5, indent: 56),
                ],

                // Delete
                if (canDelete && onDelete != null)
                  _buildMenuItem(
                    context,
                    icon: SolarLinearIcons.trashBinMinimalistic,
                    label: 'حذف',
                    isDestructive: true,
                    onTap: () {
                      Navigator.pop(context);
                      onDelete!();
                    },
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final theme = Theme.of(context);
    final color = isDestructive ? AppColors.error : theme.colorScheme.onSurface;

    return Semantics(
      label: label,
      button: true,
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        title: Text(
          label,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: isDestructive
            ? null
            : Icon(
                SolarLinearIcons.altArrowLeft,
                size: 16,
                color: theme.hintColor.withValues(alpha: 0.3),
              ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// Helper to show message action menu as bottom sheet
class MessageActionHelper {
  static bool _isMenuShowing = false;
  static DateTime? _lastMenuShowTime;
  static const _debounceDuration = Duration(milliseconds: 500);

  static void showMenu({
    required BuildContext context,
    required InboxMessage message,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
    VoidCallback? onReply,
    VoidCallback? onForward,
    VoidCallback? onCopy,
  }) {
    // Debounce rapid menu opens
    final now = DateTime.now();
    if (_isMenuShowing) return;

    if (_lastMenuShowTime != null &&
        now.difference(_lastMenuShowTime!) < _debounceDuration) {
      return;
    }

    _lastMenuShowTime = now;
    _isMenuShowing = true;

    Haptics.selection();

    PremiumBottomSheet.show(
      context: context,
      title: 'خيارات الرسالة',
      child: MessageActionMenu(
        message: message,
        onEdit: onEdit,
        onDelete: onDelete,
        onReply: onReply,
        onForward: onForward,
        onCopy: onCopy,
      ),
    );

    // Reset flag after menu is dismissed
    Future.delayed(const Duration(milliseconds: 300), () {
      _isMenuShowing = false;
    });
  }

  /// Show selection mode action menu for bulk operations
  static void showSelectionMenu({
    required BuildContext context,
    required int selectedCount,
    VoidCallback? onDelete,
    VoidCallback? onForward,
    VoidCallback? onCopy,
  }) {
    Haptics.selection();

    PremiumBottomSheet.show(
      context: context,
      title: 'الخيارات',
      child: MessageActionMenu(
        message: InboxMessage(
          id: -1,
          channel: '',
          body: '',
          status: '',
          createdAt: '',
        ),
        isSelectionMode: true,
        selectedCount: selectedCount,
        onDelete: onDelete,
        onForward: onForward,
        onCopy: onCopy,
      ),
    );
  }

  static void hide(BuildContext context) {
    Navigator.pop(context);
  }
}
