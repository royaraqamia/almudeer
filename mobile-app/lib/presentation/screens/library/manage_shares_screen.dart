import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:figma_squircle/figma_squircle.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/dimensions.dart';
import '../../../core/utils/haptics.dart';
import '../../providers/library_provider.dart';
import '../../widgets/custom_dialog.dart';
import '../../widgets/animated_toast.dart';

/// P3-14: Manage shares screen for viewing and managing item shares
class ManageSharesScreen extends StatefulWidget {
  final int itemId;
  final String itemTitle;

  const ManageSharesScreen({
    super.key,
    required this.itemId,
    required this.itemTitle,
  });

  @override
  State<ManageSharesScreen> createState() => _ManageSharesScreenState();
}

class _ManageSharesScreenState extends State<ManageSharesScreen> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadShares();
  }

  Future<void> _loadShares() async {
    setState(() => _isLoading = true);
    final provider = context.read<LibraryProvider>();
    await provider.loadItemShares(widget.itemId);
    setState(() => _isLoading = false);
  }

  Future<void> _handleRemoveShare(int shareId) async {
    Haptics.mediumTap();

    final confirmed = await CustomDialog.show<bool>(
      context,
      title: 'إزالة المشاركة',
      message: 'هل أنت متأكد من إزالة صلاحية الوصول لهذا المستخدم؟',
      type: DialogType.warning,
      confirmText: 'إزالة',
      cancelText: 'إلغاء',
    );

    if (confirmed == true && mounted) {
      try {
        final provider = context.read<LibraryProvider>();
        await provider.removeShare(shareId: shareId, itemId: widget.itemId);

        if (!mounted) return;
        AnimatedToast.success(context, 'تم إزالة المشاركة بنجاح');
        await _loadShares();
      } catch (e) {
        if (!mounted) return;
        AnimatedToast.error(context, e.toString());
      }
    }
  }

  Future<void> _handleUpdatePermission(int shareId, String currentPermission) async {
    Haptics.lightTap();
    
    final newPermission = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'تحديث الصلاحية',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(SolarLinearIcons.eye, color: AppColors.primary),
              title: const Text('قراءة فقط'),
              subtitle: const Text('يمكنه فقط عرض العنصر'),
              selected: currentPermission == 'read',
              onTap: () => Navigator.pop(context, 'read'),
            ),
            ListTile(
              leading: const Icon(SolarLinearIcons.pen, color: AppColors.primary),
              title: const Text('تعديل'),
              subtitle: const Text('يمكنه تعديل العنصر'),
              selected: currentPermission == 'edit',
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(SolarLinearIcons.userHeart, color: AppColors.primary),
              title: const Text('مدير'),
              subtitle: const Text('صلاحيات كاملة بما في ذلك الحذف'),
              selected: currentPermission == 'admin',
              onTap: () => Navigator.pop(context, 'admin'),
            ),
          ],
        ),
      ),
    );

    if (newPermission != null && newPermission != currentPermission && mounted) {
      try {
        final provider = context.read<LibraryProvider>();
        await provider.updateSharePermission(
          shareId: shareId,
          permission: newPermission,
          itemId: widget.itemId,
        );

        if (!mounted) return;
        AnimatedToast.success(context, 'تم تحديث الصلاحية بنجاح');
        await _loadShares();
      } catch (e) {
        if (!mounted) return;
        AnimatedToast.error(context, e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<LibraryProvider>();
    final shares = provider.itemShares[widget.itemId] ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة المشاركات'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(SolarLinearIcons.refresh),
            onPressed: _loadShares,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : shares.isEmpty
              ? _buildEmptyState(theme)
              : _buildSharesList(theme, shares),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            SolarLinearIcons.share,
            size: 80,
            color: theme.hintColor,
          ),
        ],
      ),
    );
  }

  Widget _buildSharesList(ThemeData theme, List<Map<String, dynamic>> shares) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppDimensions.paddingMedium),
      itemCount: shares.length,
      itemBuilder: (context, index) {
        final share = shares[index];
        final permission = share['permission'] as String;
        final sharedWith = share['shared_with_user_id'] as String;
        final expiresAt = share['expires_at'] as DateTime?;
        final createdAt = share['created_at'] as DateTime?;

        return Container(
          margin: const EdgeInsets.only(bottom: AppDimensions.spacing12),
          padding: const EdgeInsets.all(AppDimensions.paddingMedium),
          decoration: ShapeDecoration(
            color: theme.cardColor,
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(
                cornerRadius: AppDimensions.radiusCard,
                cornerSmoothing: 1.0,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppDimensions.spacing10),
                    decoration: BoxDecoration(
                      color: _getPermissionColor(permission).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
                    ),
                    child: Icon(
                      _getPermissionIcon(permission),
                      color: _getPermissionColor(permission),
                      size: AppDimensions.iconMedium,
                    ),
                  ),
                  const SizedBox(width: AppDimensions.spacing12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sharedWith,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _getPermissionLabel(permission),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _getPermissionColor(permission),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Semantics(
                    label: 'خيارات المشاركة',
                    button: true,
                    child: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') {
                          _handleUpdatePermission(share['id'], permission);
                        } else if (value == 'remove') {
                          _handleRemoveShare(share['id']);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(SolarLinearIcons.pen, size: 20),
                              SizedBox(width: 8),
                              Text('تعديل الصلاحية'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'remove',
                          child: Row(
                            children: [
                              Icon(SolarLinearIcons.trashBinMinimalistic, size: 20, color: AppColors.error),
                              SizedBox(width: 8),
                              Text('إزالة', style: TextStyle(color: AppColors.error)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              if (expiresAt != null) ...[
                const SizedBox(height: AppDimensions.spacing12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.spacing12,
                    vertical: AppDimensions.spacing6,
                  ),
                  decoration: BoxDecoration(
                    color: expiresAt.isBefore(DateTime.now())
                        ? AppColors.error.withValues(alpha: 0.1)
                        : Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppDimensions.radiusSmall),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        SolarLinearIcons.clockCircle,
                        size: AppDimensions.iconSmall,
                        color: expiresAt.isBefore(DateTime.now())
                            ? AppColors.error
                            : Colors.orange,
                      ),
                      const SizedBox(width: AppDimensions.spacing4),
                      Text(
                        expiresAt.isBefore(DateTime.now())
                            ? 'منتهية الصلاحية'
                            : 'تنتهي في ${expiresAt.day}/${expiresAt.month}/${expiresAt.year}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: expiresAt.isBefore(DateTime.now())
                              ? AppColors.error
                              : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (createdAt != null) ...[
                const SizedBox(height: AppDimensions.spacing8),
                Text(
                  'تمت المشاركة في ${createdAt.day}/${createdAt.month}/${createdAt.year}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  IconData _getPermissionIcon(String permission) {
    switch (permission) {
      case 'edit':
        return SolarLinearIcons.pen;
      case 'admin':
        return SolarLinearIcons.userHeart;
      default:
        return SolarLinearIcons.eye;
    }
  }

  String _getPermissionLabel(String permission) {
    switch (permission) {
      case 'edit':
        return 'تعديل';
      case 'admin':
        return 'مدير';
      default:
        return 'قراءة فقط';
    }
  }

  Color _getPermissionColor(String permission) {
    switch (permission) {
      case 'edit':
        return Colors.blue;
      case 'admin':
        return Colors.purple;
      default:
        return AppColors.primary;
    }
  }
}
