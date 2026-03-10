import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/dimensions.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/share_error_codes.dart';
import '../../../core/widgets/app_gradient_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../providers/library_provider.dart';
import '../../../features/tasks/providers/task_provider.dart';
import '../premium_bottom_sheet.dart';
import '../../widgets/animated_toast.dart';

/// P3-14: Share item dialog for sharing library items with other users
class ShareItemDialog extends StatelessWidget {
  final int itemId;
  final String itemTitle;
  final String? taskIds; // Comma-separated task IDs for task assignment
  final String? libraryItemIds; // Comma-separated library item IDs for bulk sharing

  const ShareItemDialog({
    super.key,
    required this.itemId,
    required this.itemTitle,
    this.taskIds,
    this.libraryItemIds,
  });

  /// Show the share bottom sheet
  static void show(BuildContext context, {required int itemId, required String itemTitle, String? taskIds, String? libraryItemIds}) {
    final provider = context.read<LibraryProvider>();
    provider.clearUsernameLookup();

    PremiumBottomSheet.show(
      context: context,
      title: 'مشاركة مباشرة مع...',
      onDismiss: () => provider.clearUsernameLookup(),
      child: _ShareForm(itemId: itemId, itemTitle: itemTitle, taskIds: taskIds, libraryItemIds: libraryItemIds),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _ShareForm extends StatefulWidget {
  final int itemId;
  final String itemTitle;
  final String? taskIds;
  final String? libraryItemIds;

  const _ShareForm({
    required this.itemId,
    required this.itemTitle,
    this.taskIds,
    this.libraryItemIds,
  });

  @override
  State<_ShareForm> createState() => _ShareFormState();
}

class _ShareFormState extends State<_ShareForm> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  String _selectedPermission = 'read';
  bool _isLoading = false;
  bool _isLoadingShares = false;
  final List<Map<String, dynamic>> _selectedUsernames = [];
  List<Map<String, dynamic>> _existingShares = [];  // FIX: Track existing shares

  final List<Map<String, dynamic>> _permissionOptions = [
    {'value': 'read', 'label': 'قراءة فقط', 'icon': SolarLinearIcons.eye},
    {'value': 'edit', 'label': 'تعديل', 'icon': SolarLinearIcons.pen},
    {'value': 'admin', 'label': 'مدير', 'icon': SolarLinearIcons.userHeart},
  ];

  @override
  void initState() {
    super.initState();
    _usernameController.addListener(() {
      context.read<LibraryProvider>().lookupUsername(_usernameController.text);
    });
    // FIX: Load existing shares when dialog opens
    _loadExistingShares();
  }

  Future<void> _loadExistingShares() async {
    if (widget.taskIds != null) {
      // For tasks - task sharing is not yet implemented
      debugPrint('Task sharing is not yet implemented');
    } else if (widget.libraryItemIds == null) {
      // For single library item
      setState(() => _isLoadingShares = true);
      try {
        final libraryProvider = context.read<LibraryProvider>();
        await libraryProvider.loadItemShares(widget.itemId);
        final shares = libraryProvider.itemShares[widget.itemId] ?? [];
        setState(() {
          _existingShares = shares.map((share) => {
            'username': share['shared_with_email'] ?? share['shared_with_user_id'] ?? '',
            'displayName': share['shared_with_name'] ?? 'Unknown',
            'permission': share['permission'] ?? 'read',
            'isExisting': true,
          }).toList();
        });
      } catch (e) {
        debugPrint('Failed to load existing library shares: $e');
      } finally {
        if (mounted) setState(() => _isLoadingShares = false);
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  void _addUsername() {
    final provider = context.read<LibraryProvider>();
    final username = _usernameController.text.trim().replaceAll('@', '');
    
    if (provider.foundUsernameDetails != null && username.isNotEmpty) {
      // FIX BUG #9: Check for duplicate username before adding
      final isDuplicate = _selectedUsernames.any(
        (user) => user['username'] == username
      );
      
      if (isDuplicate) {
        AnimatedToast.warning(
          context,
          'هذا المستخدم مُضاف بالفعل',
        );
        _usernameController.clear();
        provider.clearUsernameLookup();
        return;
      }
      
      setState(() {
        _selectedUsernames.add({
          'username': username,
          'displayName': provider.foundUsernameDetails!.toString(),
        });
      });
      _usernameController.clear();
      provider.clearUsernameLookup();
      Haptics.lightTap();
    }
  }

  void _removeUsername(int index) {
    setState(() {
      _selectedUsernames.removeAt(index);
    });
    Haptics.lightTap();
  }

  Future<void> _handleShare() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedUsernames.isEmpty) {
      AnimatedToast.error(context, 'يرجى إضافة معرِّف مستخدم واحد على الأقل');
      return;
    }

    Haptics.mediumTap();
    setState(() => _isLoading = true);

    try {
      final libraryProvider = context.read<LibraryProvider>();
      int successCount = 0;
      int failCount = 0;

      if (widget.taskIds != null) {
        // Handle task sharing
        final taskProvider = context.read<TaskProvider>();
        final taskIdList = widget.taskIds!.split(',');

        // UI-001 FIX: Track unique tasks and users separately for accurate messaging
        final Set<String> successfulTaskIds = {};
        final Set<String> failedTaskIds = {};
        int successfulUserCount = 0;
        int failedUserCount = 0;

        for (final user in _selectedUsernames) {
          bool userHadSuccess = false;
          bool userHadFailure = false;

          for (final taskId in taskIdList) {
            try {
              await taskProvider.shareTask(
                taskId: taskId,
                sharedWithUserId: user['username'].toString(),
                permission: _selectedPermission,
              );
              successfulTaskIds.add(taskId);
              userHadSuccess = true;
            } catch (e) {
              // FIX: Use error codes instead of string matching
              final errorCode = ShareErrorHelper.extractErrorCode(e);
              
              // Handle "already shared" gracefully - treat as success
              if (ShareErrorHelper.isSoftError(errorCode)) {
                // Share already exists - backend updated it successfully
                successfulTaskIds.add(taskId);
                userHadSuccess = true;
                debugPrint('[ShareItemDialog] Share already exists for task $taskId with ${user['username']}, updated successfully');
              } else {
                failedTaskIds.add(taskId);
                userHadFailure = true;
                debugPrint('[ShareItemDialog] Failed to share task $taskId with ${user['username']}: $e');
              }
            }
          }

          if (userHadSuccess) successfulUserCount++;
          if (userHadFailure) failedUserCount++;
        }

        successCount = successfulTaskIds.length;
        failCount = failedTaskIds.length;

        // UI-001 FIX: Show accurate message with task and user counts
        if (mounted) {
          Navigator.pop(context);
          if (failCount > 0) {
            AnimatedToast.warning(
              context,
              'تمت مشاركة $successCount مهام مع $successfulUserCount مستخدمين، فشل $failCount مهام مع $failedUserCount مستخدمين',
            );
          } else {
            AnimatedToast.success(
              context,
              'تمت مشاركة $successCount مهام مع ${_selectedUsernames.length} مستخدمين',
            );
          }
        }
        
        // FIX BUG #11: Refresh tasks list to show updated shared state
        await taskProvider.loadTasks();
      } else if (widget.libraryItemIds != null) {
        // Handle bulk library item sharing
        final itemIdList = widget.libraryItemIds!.split(',').map((id) => int.parse(id)).toList();

        // Track unique items and users separately for accurate messaging
        final Set<int> successfulItemIds = {};
        final Set<int> failedItemIds = {};
        int successfulUserCount = 0;
        int failedUserCount = 0;

        for (final user in _selectedUsernames) {
          bool userHadSuccess = false;
          bool userHadFailure = false;

          for (final itemId in itemIdList) {
            try {
              await libraryProvider.shareItem(
                itemId: itemId,
                sharedWithUserId: user['username'].toString(),
                permission: _selectedPermission,
              );
              successfulItemIds.add(itemId);
              userHadSuccess = true;
            } catch (e) {
              // FIX: Use error codes instead of string matching
              final errorCode = ShareErrorHelper.extractErrorCode(e);
              
              // Handle "already shared" gracefully - treat as success
              if (ShareErrorHelper.isSoftError(errorCode)) {
                // Share already exists - backend updated it successfully
                successfulItemIds.add(itemId);
                userHadSuccess = true;
                debugPrint('[ShareItemDialog] Share already exists for item $itemId with ${user['username']}, updated successfully');
              } else {
                failedItemIds.add(itemId);
                userHadFailure = true;
                debugPrint('[ShareItemDialog] Failed to share library item $itemId with ${user['username']}: $e');
              }
            }
          }

          if (userHadSuccess) successfulUserCount++;
          if (userHadFailure) failedUserCount++;
        }

        successCount = successfulItemIds.length;
        failCount = failedItemIds.length;

        // Clear selection after sharing
        libraryProvider.clearSelection();

        // FIX BUG #11: Refresh the shares list for this item
        await libraryProvider.loadItemShares(widget.itemId);

        // Show accurate message with item and user counts
        if (mounted) {
          Navigator.pop(context);
          if (failCount > 0) {
            AnimatedToast.warning(
              context,
              'تمت مشاركة $successCount عناصر مع $successfulUserCount مستخدمين، فشل $failCount عناصر مع $failedUserCount مستخدمين',
            );
          } else {
            AnimatedToast.success(
              context,
              'تمت مشاركة $successCount عناصر مع ${_selectedUsernames.length} مستخدمين',
            );
          }
        }
      } else {
        // Handle single library item sharing
        for (final user in _selectedUsernames) {
          try {
            await libraryProvider.shareItem(
              itemId: widget.itemId,
              sharedWithUserId: user['username'].toString(),
              permission: _selectedPermission,
            );
            successCount++;
          } catch (e) {
            failCount++;
            debugPrint('[ShareItemDialog] Failed to share with ${user['username']}: $e');
          }
        }

        if (mounted) {
          Navigator.pop(context);
          if (failCount > 0) {
            AnimatedToast.warning(
              context,
              'تمت المشاركة مع $successCount مستخدمين، فشل $failCount',
            );
          } else {
            AnimatedToast.success(
              context,
              'تمت المشاركة مع $successCount مستخدمين',
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        AnimatedToast.error(context, e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Username input with lookup
            Consumer<LibraryProvider>(
              builder: (context, provider, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Username input field
                    AppTextField(
                      controller: _usernameController,
                      hintText: 'معرِّف الشَّخص على التَّطبيق',
                      prefixIcon: provider.isCheckingUsername
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary,
                                ),
                              ),
                            )
                          : provider.foundUsernameDetails != null
                              ? GestureDetector(
                                  onTap: _addUsername,
                                  child: ShaderMask(
                                    shaderCallback: (bounds) => const LinearGradient(
                                      colors: [Color(0xFF2563EB), Color(0xFF0891B2)],
                                    ).createShader(bounds),
                                    child: const Icon(
                                      SolarBoldIcons.add,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                )
                              : provider.usernameNotFound
                                  ? const Icon(
                                      SolarBoldIcons.closeCircle,
                                      color: AppColors.error,
                                      size: 20,
                                    )
                                  : const Icon(SolarLinearIcons.userCircle),
                      onChanged: (_) => setState(() {}),
                    ),
                    // Success message
                    if (provider.foundUsernameDetails != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Icon(
                              SolarLinearIcons.infoCircle,
                              size: 14,
                              color: AppColors.success.withValues(alpha: 0.8),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'تمَّ العثور على: ${provider.foundUsernameDetails}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.success.withValues(alpha: 0.8),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Error message
                    if (provider.usernameNotFound &&
                        _usernameController.text.length >= 3)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Icon(
                              SolarLinearIcons.infoCircle,
                              size: 14,
                              color: AppColors.error.withValues(alpha: 0.8),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'لم يتم العثور على شخص بهذا المعرِّف',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.error.withValues(alpha: 0.8),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Selected usernames chips
                    if (_selectedUsernames.isNotEmpty) ...[
                      const SizedBox(height: AppDimensions.spacing12),
                      Wrap(
                        spacing: AppDimensions.spacing8,
                        runSpacing: AppDimensions.spacing8,
                        children: List.generate(_selectedUsernames.length, (index) {
                          final user = _selectedUsernames[index];
                          return Chip(
                            label: Text(
                              user['username'].toString(),
                              style: const TextStyle(fontSize: 13),
                            ),
                            deleteIcon: const Icon(SolarLinearIcons.closeCircle, size: 18),
                            onDeleted: () => _removeUsername(index),
                            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                            labelStyle: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        }),
                      ),
                    ],
                    // FIX: Display existing shares
                    if (_existingShares.isNotEmpty) ...[
                      const SizedBox(height: AppDimensions.spacing16),
                      Row(
                        children: [
                          Icon(
                            SolarLinearIcons.userHeart,
                            size: 16,
                            color: AppColors.success,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'يشارك معك حالياً',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppDimensions.spacing8),
                      Wrap(
                        spacing: AppDimensions.spacing8,
                        runSpacing: AppDimensions.spacing8,
                        children: List.generate(_existingShares.length, (index) {
                          final share = _existingShares[index];
                          final permissionColor = share['permission'] == 'admin'
                              ? AppColors.warning
                              : share['permission'] == 'edit'
                                  ? AppColors.primary
                                  : AppColors.success;
                          return Chip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  share['username'].toString(),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: permissionColor.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    share['permission'].toString(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: permissionColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            backgroundColor: AppColors.success.withValues(alpha: 0.1),
                            labelStyle: TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.w500,
                            ),
                          );
                        }),
                      ),
                    ],
                    // Loading indicator for existing shares
                    if (_isLoadingShares) ...[
                      const SizedBox(height: AppDimensions.spacing12),
                      const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),

            const SizedBox(height: AppDimensions.spacing20),

            // Permission selector
            Text(
              'صلاحية الوصول',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppDimensions.spacing12),
            Wrap(
              spacing: AppDimensions.spacing12,
              runSpacing: AppDimensions.spacing12,
              children: _permissionOptions.map((option) {
                final isSelected = _selectedPermission == option['value'];
                return ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        option['icon'] as IconData,
                        size: 18,
                        color: isSelected
                            ? AppColors.primary
                            : theme.hintColor,
                      ),
                      const SizedBox(width: 8),
                      Text(option['label'] as String),
                    ],
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    Haptics.lightTap();
                    setState(() => _selectedPermission = option['value']);
                  },
                  selectedColor: AppColors.primary.withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    color: isSelected
                        ? AppColors.primary
                        : theme.textTheme.bodyMedium?.color,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: AppDimensions.spacing20),

            // Share button
            SizedBox(
              width: double.infinity,
              child: AppGradientButton(
                onPressed: _isLoading ? null : _handleShare,
                text: _isLoading ? 'جاري المشاركة...' : 'مشاركة',
                icon: _isLoading ? SolarLinearIcons.refresh : null,
                isLoading: _isLoading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
