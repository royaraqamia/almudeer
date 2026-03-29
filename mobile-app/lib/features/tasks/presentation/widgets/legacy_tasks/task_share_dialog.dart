import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/constants/dimensions.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';
import 'package:almudeer_mobile_app/core/utils/share_error_codes.dart';
import 'package:almudeer_mobile_app/core/widgets/app_gradient_button.dart';
import 'package:almudeer_mobile_app/core/widgets/app_text_field.dart';
import 'package:almudeer_mobile_app/features/library/presentation/providers/library_provider.dart';
import 'package:almudeer_mobile_app/features/tasks/presentation/providers/task_provider.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/premium_bottom_sheet.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/animated_toast.dart';

/// P4-2: Task-specific share dialog for sharing tasks with other users
/// Supports single and multiple task sharing with permission levels (read/edit/admin)
class TaskShareDialog extends StatelessWidget {
  final String taskId;
  final String taskTitle;
  final List<String>? additionalTaskIds; // For bulk sharing

  const TaskShareDialog({
    super.key,
    required this.taskId,
    required this.taskTitle,
    this.additionalTaskIds,
  });

  /// Show the task share bottom sheet
  static void show(
    BuildContext context, {
    required String taskId,
    required String taskTitle,
    List<String>? additionalTaskIds,
  }) {
    final taskProvider = context.read<TaskProvider>();
    taskProvider.clearTypingIndicator(taskId); // Clean up typing state

    PremiumBottomSheet.show(
      context: context,
      title: 'ظ…ط´ط§ط±ظƒط© ط§ظ„ظ…ظ‡ظ…ظژظ‘ط© ظ…ط¹...',
      onDismiss: () => taskProvider.clearTypingIndicator(taskId),
      child: _TaskShareForm(
        taskId: taskId,
        taskTitle: taskTitle,
        additionalTaskIds: additionalTaskIds,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _TaskShareForm extends StatefulWidget {
  final String taskId;
  final String taskTitle;
  final List<String>? additionalTaskIds;

  const _TaskShareForm({
    required this.taskId,
    required this.taskTitle,
    this.additionalTaskIds,
  });

  @override
  State<_TaskShareForm> createState() => _TaskShareFormState();
}

class _TaskShareFormState extends State<_TaskShareForm> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  String _selectedPermission = 'read';
  bool _isLoading = false;
  bool _isLoadingShares = false;
  final List<Map<String, dynamic>> _selectedUsernames = [];
  List<Map<String, dynamic>> _existingShares = [];

  final List<Map<String, dynamic>> _permissionOptions = [
    {'value': 'read', 'label': 'ظ‚ط±ط§ط،ط© ظپظ‚ط·', 'icon': SolarLinearIcons.eye},
    {'value': 'edit', 'label': 'طھط¹ط¯ظٹظ„', 'icon': SolarLinearIcons.pen},
    {'value': 'admin', 'label': 'ظ…ط¯ظٹط±', 'icon': SolarLinearIcons.userHeart},
  ];

  @override
  void initState() {
    super.initState();
    _usernameController.addListener(() {
      context.read<LibraryProvider>().lookupUsername(_usernameController.text);
    });
    _loadExistingShares();
  }

  Future<void> _loadExistingShares() async {
    setState(() => _isLoadingShares = true);
    try {
      final taskProvider = context.read<TaskProvider>();
      // Note: For now, we show existing shares from the first task only
      // The backend handles all tasks atomically during sharing
      final shares = await taskProvider.repository.syncService.fetchTaskShares(
        widget.taskId,
      );

      setState(() {
        _existingShares = shares
            .map(
              (share) => {
                'username':
                    share['shared_with_user_id'] ??
                    '',
                'displayName': share['shared_with_name'] ?? 'Unknown',
                'permission': share['permission'] ?? 'read',
                'isExisting': true,
              },
            )
            .toList();
      });
    } catch (e) {
      debugPrint('Failed to load existing task shares: $e');
    } finally {
      if (mounted) setState(() => _isLoadingShares = false);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  void _addUsername() {
    final libraryProvider = context.read<LibraryProvider>();
    final username = _usernameController.text.trim().replaceAll('@', '');

    if (libraryProvider.foundUsernameDetails != null && username.isNotEmpty) {
      // Check for duplicate username before adding
      final isDuplicate = _selectedUsernames.any(
        (user) => user['username'] == username,
      );

      if (isDuplicate) {
        AnimatedToast.warning(context, 'ظ‡ط°ط§ ط§ظ„ظ…ط³طھط®ط¯ظ… ظ…ظڈط¶ط§ظپ ط¨ط§ظ„ظپط¹ظ„');
        _usernameController.clear();
        libraryProvider.clearUsernameLookup();
        return;
      }

      setState(() {
        _selectedUsernames.add({
          'username': username,
          'displayName': libraryProvider.foundUsernameDetails.toString(),
        });
      });
      _usernameController.clear();
      libraryProvider.clearUsernameLookup();
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
      AnimatedToast.error(context, 'ظٹط±ط¬ظ‰ ط¥ط¶ط§ظپط© ظ…ط¹ط±ظگظ‘ظپ ظ…ط³طھط®ط¯ظ… ظˆط§ط­ط¯ ط¹ظ„ظ‰ ط§ظ„ط£ظ‚ظ„');
      return;
    }

    Haptics.mediumTap();
    setState(() => _isLoading = true);

    try {
      final taskProvider = context.read<TaskProvider>();
      final allTaskIds = [
        widget.taskId,
        if (widget.additionalTaskIds != null) ...widget.additionalTaskIds!,
      ];

      int successCount = 0;
      int failCount = 0;
      final Set<String> successfulTaskIds = {};
      final Set<String> failedTaskIds = {};
      int successfulUserCount = 0;
      int failedUserCount = 0;

      for (final user in _selectedUsernames) {
        bool userHadSuccess = false;
        bool userHadFailure = false;

        for (final taskId in allTaskIds) {
          try {
            await taskProvider.shareTask(
              taskId: taskId,
              sharedWithUserId: user['username'].toString(),
              permission: _selectedPermission,
            );
            successfulTaskIds.add(taskId);
            userHadSuccess = true;
          } catch (e) {
            // Use error codes instead of string matching
            final errorCode = ShareErrorHelper.extractErrorCode(e);

            // Handle "already shared" gracefully - treat as success
            if (ShareErrorHelper.isSoftError(errorCode)) {
              // Share already exists - backend updated it successfully
              successfulTaskIds.add(taskId);
              userHadSuccess = true;
              debugPrint(
                '[TaskShareDialog] Share already exists for task $taskId with ${user['username']}, updated successfully',
              );
            } else {
              failedTaskIds.add(taskId);
              userHadFailure = true;
              debugPrint(
                '[TaskShareDialog] Failed to share task $taskId with ${user['username']}: $e',
              );
            }
          }
        }

        if (userHadSuccess) successfulUserCount++;
        if (userHadFailure) failedUserCount++;
      }

      successCount = successfulTaskIds.length;
      failCount = failedTaskIds.length;

      // Show accurate message with task and user counts
      if (mounted) {
        Navigator.pop(context);
        if (failCount > 0) {
          AnimatedToast.warning(
            context,
            'طھظ…طھ ظ…ط´ط§ط±ظƒط© $successCount ظ…ظ‡ط§ظ… ظ…ط¹ $successfulUserCount ظ…ط³طھط®ط¯ظ…ظٹظ†طŒ ظپط´ظ„ $failCount ظ…ظ‡ط§ظ… ظ…ط¹ $failedUserCount ظ…ط³طھط®ط¯ظ…ظٹظ†',
          );
        } else {
          AnimatedToast.success(
            context,
            'طھظ…طھ ظ…ط´ط§ط±ظƒط© $successCount ظ…ظ‡ط§ظ… ظ…ط¹ ${_selectedUsernames.length} ظ…ط³طھط®ط¯ظ…ظٹظ†',
          );
        }
      }

      // Refresh tasks list to show updated shared state
      await taskProvider.loadTasks();
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
            // Task info
            Container(
              padding: const EdgeInsets.all(AppDimensions.spacing12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius:
                    BorderRadius.circular(AppDimensions.radiusMedium),
              ),
              child: Row(
                children: [
                  const Icon(
                    SolarLinearIcons.checkSquare,
                    color: AppColors.primary,
                    size: AppDimensions.iconMedium,
                  ),
                  const SizedBox(width: AppDimensions.spacing8),
                  Expanded(
                    child: Text(
                      widget.taskTitle,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppDimensions.spacing20),

            // Username input with lookup
            Consumer<LibraryProvider>(
              builder: (context, provider, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Username input field
                    AppTextField(
                      controller: _usernameController,
                      hintText: 'ظ…ط¹ط±ظگظ‘ظپ ط§ظ„ط´ظژظ‘ط®طµ ط¹ظ„ظ‰ ط§ظ„طھظژظ‘ط·ط¨ظٹظ‚',
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
                                shaderCallback: (bounds) =>
                                    const LinearGradient(
                                      colors: [
                                        Color(0xFF2563EB),
                                        Color(0xFF0891B2),
                                      ],
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
                              color:
                                  AppColors.success.withValues(alpha: 0.8),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'طھظ…ظژظ‘ ط§ظ„ط¹ط«ظˆط± ط¹ظ„ظ‰: ${provider.foundUsernameDetails}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.success.withValues(
                                  alpha: 0.8,
                                ),
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
                              'ظ„ظ… ظٹطھظ… ط§ظ„ط¹ط«ظˆط± ط¹ظ„ظ‰ ط´ط®طµ ط¨ظ‡ط°ط§ ط§ظ„ظ…ط¹ط±ظگظ‘ظپ',
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
                        children: List.generate(
                          _selectedUsernames.length,
                          (index) {
                            final user = _selectedUsernames[index];
                            return Chip(
                              label: Text(
                                user['username'].toString(),
                                style: const TextStyle(fontSize: 13),
                              ),
                              deleteIcon: const Icon(
                                SolarLinearIcons.closeCircle,
                                size: 18,
                              ),
                              onDeleted: () => _removeUsername(index),
                              backgroundColor: AppColors.primary.withValues(
                                alpha: 0.1,
                              ),
                              labelStyle: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    // Display existing shares
                    if (_existingShares.isNotEmpty) ...[
                      const SizedBox(height: AppDimensions.spacing16),
                      const Row(
                        children: [
                          Icon(
                            SolarLinearIcons.userHeart,
                            size: 16,
                            color: AppColors.success,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'ظٹط´ط§ط±ظƒ ظ…ط¹ظƒ ط­ط§ظ„ظٹط§ظ‹',
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
                        children: List.generate(
                          _existingShares.length,
                          (index) {
                            final share = _existingShares[index];
                            final permissionColor =
                                share['permission'] == 'admin'
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
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: permissionColor.withValues(
                                        alpha: 0.2,
                                      ),
                                      borderRadius:
                                          BorderRadius.circular(10),
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
                              backgroundColor:
                                  AppColors.success.withValues(alpha: 0.1),
                              labelStyle: const TextStyle(
                                color: AppColors.success,
                                fontWeight: FontWeight.w500,
                              ),
                            );
                          },
                        ),
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
              'طµظ„ط§ط­ظٹط© ط§ظ„ظˆطµظˆظ„',
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
                        color: isSelected ? AppColors.primary : theme.hintColor,
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
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: AppDimensions.spacing20),

            // Share button
            SizedBox(
              width: double.infinity,
              child: AppGradientButton(
                text: _isLoading ? 'ط¬ط§ط±ظٹ ط§ظ„ظ…ط´ط§ط±ظƒط©...' : 'ظ…ط´ط§ط±ظƒط©',
                isLoading: _isLoading,
                onPressed: _handleShare,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
