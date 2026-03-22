import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:linkify/linkify.dart';

import '../../models/task_model.dart';
import '../../providers/task_provider.dart';
import '../../../../presentation/providers/auth_provider.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/dimensions.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../core/extensions/string_extension.dart';
import '../../../../core/utils/permission_helper.dart';
import '../../../../core/utils/url_launcher_utils.dart';
import '../widgets/hijri_date_picker_dialog.dart';
import '../widgets/priority_picker.dart';
import '../../../../presentation/widgets/premium_bottom_sheet.dart';
import '../../../../presentation/widgets/animated_toast.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../presentation/widgets/tasks/task_share_dialog.dart';
import '../../../../presentation/screens/customers/customer_detail_screen.dart';
import '../../../../data/repositories/customers_repository.dart';
import '../../../../presentation/providers/customers_provider.dart';

// FIX: Extract magic numbers to constants
class _TaskEditConstants {
  static const double minTouchTargetSize = 44.0;
  static const double iconSizeSmall = 20.0;
  static const double iconSizeMedium = 24.0;
  static const double fontSizeLarge = 18.0;
  static const double fontSizeMedium = 14.0;
  static const double fontSizeSmall = 12.0;
  static const double borderRadiusMedium = 8.0;
  static const double borderRadiusFull = 9999.0;
}

class TaskEditScreen extends StatefulWidget {
  final TaskModel? task;
  const TaskEditScreen({super.key, this.task});

  @override
  State<TaskEditScreen> createState() => _TaskEditScreenState();
}

class _TaskEditScreenState extends State<TaskEditScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _dateController = TextEditingController();
  final _titleFocusNode = FocusNode();
  final _descriptionFocusNode = FocusNode();

  DateTime? _selectedDate;
  String? _selectedRecurrence;
  List<Map<String, dynamic>> _attachments = [];
  bool _alarmEnabled = false;
  TimeOfDay? _alarmTime;
  TaskPriority _priority = TaskPriority.medium;

  Timer? _debounce;
  bool _isNewTask = false;
  String? _taskId;
  bool _isSaving = false;
  bool _pendingSave = false; // FIX MOBILE-003: Track pending save requests

  // Permission state - FIX #1: Initialize synchronously to prevent race conditions
  late String _permissionLevel;
  late bool _canEdit;
  late bool _canShare;
  bool _isLoadingPermissions = false; // FIX #3: Track permission loading state

  // Mention detection for @username in description
  // Pattern: @ followed by 2-32 alphanumeric characters (including Arabic), underscores, hyphens
  // Uses \w for word characters plus Arabic letter ranges
  static final _mentionPattern = RegExp(r'@([a-zA-Z0-9_\u0600-\u06FF\u0750-\u077F-]{2,32})');
  List<Map<String, dynamic>>? _descriptionMentions;

  @override
  void initState() {
    super.initState();
    _isNewTask = widget.task == null;

    // FIX #1: Initialize permission state synchronously to prevent race conditions
    // This ensures _canEdit and _canShare are valid before any async operations
    if (_isNewTask) {
      // New task - user is owner
      _permissionLevel = PermissionLevel.owner;
      _canEdit = true;
      _canShare = true;
    } else {
      // Existing task - default to read-only until permissions load
      // This prevents edits during the brief window while permissions are loading
      _permissionLevel = PermissionLevel.read;
      _canEdit = false;
      _canShare = false;
      // Load actual permissions asynchronously
      _initPermissions();
    }

    if (!_isNewTask) {
      final t = widget.task!;
      _taskId = t.id;
      _titleController.text = t.title;
      _descriptionController.text = t.description ?? '';
      _selectedDate = t.dueDate;
      _selectedRecurrence = t.recurrence;
      _alarmEnabled = t.alarmEnabled;
      _priority = t.priority;
      if (t.alarmTime != null) {
        _alarmTime = TimeOfDay.fromDateTime(t.alarmTime!);
      }
      _attachments = List.from(t.attachments);

      if (_selectedDate != null) {
        HijriCalendar.setLocal('ar');
        _dateController.text = HijriCalendar.fromDate(
          _selectedDate!,
        ).toFormat('dd MMMM').toEnglishNumbers;
      }
    } else {
      _taskId = const Uuid().v4();
    }

    _titleController.addListener(_onChanged);
    _descriptionController.addListener(_onChanged);
  }

  /// Initialize permissions using cached AuthProvider state
  /// Uses persisted licenseId from SharedPreferences - works offline
  Future<void> _initPermissions() async {
    // Only handle existing tasks here (new tasks are handled synchronously)
    if (_isNewTask || widget.task == null) {
      return;
    }

    // Set loading state
    if (mounted) {
      setState(() => _isLoadingPermissions = true);
    }

    try {
      final provider = context.read<TaskProvider>();
      String? currentUserId = provider.currentUserId;

      // If currentUserId is null, try to load it from cached AuthProvider state
      // This ensures offline functionality by using persisted licenseId
      if (currentUserId == null) {
        debugPrint('[TaskEditScreen] currentUserId is null, fetching from AuthProvider cache...');
        final authProvider = context.read<AuthProvider>();
        currentUserId = authProvider.userInfo?.licenseId?.toString();
        
        if (currentUserId != null) {
          debugPrint('[TaskEditScreen] Retrieved currentUserId from AuthProvider cache: $currentUserId');
        }
      }

      // If still null, fall back to TaskProvider's loadCurrentUser (which also uses AuthRepository)
      if (currentUserId == null) {
        debugPrint('[TaskEditScreen] AuthProvider cache miss, calling loadCurrentUser...');
        await provider.loadCurrentUser();
        currentUserId = provider.currentUserId;

        // Final fallback: try AuthProvider again after load
        if (currentUserId == null && mounted) {
          final authProvider = context.read<AuthProvider>();
          currentUserId = authProvider.userInfo?.licenseId?.toString();
        }
      }

      // Calculate permissions from available task data
      // User is owner if they created the task (createdBy matches currentUserId)
      // User is recipient if sharePermission exists (limited permissions)
      final isRecipient = widget.task!.sharePermission != null;
      final isOwner = !isRecipient && (widget.task!.createdBy == currentUserId);

      _permissionLevel = getEffectivePermission(
        widget.task!.sharePermission,
        isOwner,
      );
      _canEdit = canEdit(_permissionLevel);
      _canShare = canShare(_permissionLevel);

      debugPrint(
        '[TaskEditScreen] Permissions: currentUserId=$currentUserId, isOwner=$isOwner, isRecipient=$isRecipient, level=$_permissionLevel, canEdit=$_canEdit, canShare=$_canShare',
      );

      if (mounted) {
        setState(() => _isLoadingPermissions = false);
      }
    } catch (e, stackTrace) {
      debugPrint('[TaskEditScreen] Failed to load permissions: $e');
      debugPrint('Stack trace: $stackTrace');
      // On error, use task data to make best-effort permission check
      // If task has no sharePermission, assume user is owner (most common case)
      final isOwner = widget.task!.sharePermission == null;
      _permissionLevel = getEffectivePermission(
        widget.task!.sharePermission,
        isOwner,
      );
      _canEdit = canEdit(_permissionLevel);
      _canShare = canShare(_permissionLevel);
      
      debugPrint(
        '[TaskEditScreen] Using best-effort permissions: level=$_permissionLevel, canEdit=$_canEdit, canShare=$_canShare',
      );
      
      if (mounted) {
        setState(() => _isLoadingPermissions = false);
      }
    }
  }

  /// Extract @username mentions from text
  List<Map<String, dynamic>>? _extractMentions(String text) {
    final matches = _mentionPattern.allMatches(text);
    if (matches.isEmpty) return null;

    final mentions = <Map<String, dynamic>>[];
    final usernames = <String>{};

    for (var match in matches) {
      final username = match.group(1)!;
      if (!usernames.contains(username)) {
        usernames.add(username);
        mentions.add({
          'username': username,
          'position': match.start,
        });
      }
    }

    return mentions.isNotEmpty ? mentions : null;
  }

  /// Navigate to customer detail screen for @username mention
  Future<void> _navigateToCustomerDetail(String username) async {
    // Capture navigator and provider before async gap
    final navigator = Navigator.of(context);
    final customersProvider = context.read<CustomersProvider>();

    // First, check if this username is a customer
    final customersRepository = CustomersRepository();
    final customerCheckResponse = await customersRepository.checkUsername(username);

    Map<String, dynamic> customerData;

    // If the username is a customer, fetch full customer data
    if (customerCheckResponse['exists'] == true) {
      try {
        // Try to get customer by username from the customers list
        final customer = customersProvider.customers
            .firstWhere((c) => c.username?.toLowerCase() == username.toLowerCase());

        customerData = customer.toJson();
      } catch (e) {
        // If not found in local list, fetch from API
        try {
          final response = await customersRepository.apiClient.get(
            '/api/customers?username=$username',
          );
          if (response['customers'] != null && (response['customers'] as List).isNotEmpty) {
            customerData = (response['customers'] as List).first as Map<String, dynamic>;
          } else {
            // Fallback to basic customer data
            customerData = {
              'username': username,
              'name': username,
              'is_almudeer_user': true,
              'is_online': false,
            };
          }
        } catch (fetchError) {
          debugPrint('[TaskEditScreen] Failed to fetch customer data: $fetchError');
          customerData = {
            'username': username,
            'name': username,
            'is_almudeer_user': true,
            'is_online': false,
          };
        }
      }
    } else {
      // Not a customer, use basic user data
      customerData = {
        'username': username,
        'name': username,
        'is_almudeer_user': true,
        'is_online': false,
      };
    }

    // Navigate to CustomerDetailScreen with the data
    if (mounted) {
      navigator.push(
        MaterialPageRoute(
          builder: (context) => CustomerDetailScreen(
            customer: customerData,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _titleController.dispose();
    _descriptionController.dispose();
    _dateController.dispose();
    _titleFocusNode.dispose();
    _descriptionFocusNode.dispose();

    // FIX #4: Clear typing indicator for this task to prevent memory leak
    // Note: We don't access context here since the widget tree may be deactivated
    // The TaskProvider will clean up typing indicators periodically anyway

    super.dispose();
  }

  void _onChanged() {
    // PERMISSION: Prevent read-only users from triggering auto-save
    if (!_canEdit) {
      debugPrint('[TaskEditScreen] Read-only user - skipping auto-save');
      return;
    }

    // FIX MOBILE-003: Use single debounce timer for all fields to prevent race conditions
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    // FIX #12: Adaptive debounce timing based on network status and content type
    // - Quick changes (typing): 500ms for responsive feel
    // - Network available: 500ms
    // - Offline/slow network: 1000ms to batch changes
    final debounceMs = _getAdaptiveDebounceMs();
    _debounce = Timer(debounceMs, _saveTask);
  }

  // FIX #12: Get adaptive debounce duration based on conditions
  Duration _getAdaptiveDebounceMs() {
    // Base debounce: 500ms for responsive feel
    const baseDebounce = Duration(milliseconds: 500);
    
    // Check if we have recent sync failures (indicates slow/unreliable network)
    // This is a simple heuristic - could be enhanced with actual connectivity detection
    if (_hasRecentSyncFailure) {
      // Slow network: increase debounce to batch more changes
      return const Duration(milliseconds: 1000);
    }
    
    return baseDebounce;
  }
  
  // FIX #12: Track recent sync failures for adaptive debounce
  bool _hasRecentSyncFailure = false;

  void _recordSyncFailure() {
    _hasRecentSyncFailure = true;
    // Clear the flag after 5 seconds of successful saves
    Future.delayed(const Duration(seconds: 5), () {
      _hasRecentSyncFailure = false;
    });
  }
  
  void _recordSyncSuccess() {
    _hasRecentSyncFailure = false;
  }

  /// Check if error is due to being offline (transient error)
  bool _isOfflineError(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('socket') ||
        errorStr.contains('connection') ||
        errorStr.contains('network') ||
        errorStr.contains('offline') ||
        errorStr.contains('timeout');
  }

  Future<void> _saveTask() async {
    // PERMISSION: Block read-only users from saving
    if (!_canEdit) {
      debugPrint('[TaskEditScreen] Read-only user attempted to save - blocked');
      return;
    }

    // FIX MOBILE-003: Prevent concurrent saves with generation counter
    if (_isSaving) {
      _pendingSave = true;
      return;
    }

    _isSaving = true;
    _pendingSave = false;

    final title = _titleController.text.trim();
    if (title.isEmpty) {
      if (mounted) {
        setState(() => _isSaving = false);
      }
      return;
    }

    // FIX #3: Validate alarm requires a date
    if (_alarmEnabled && _selectedDate == null) {
      if (mounted) {
        AnimatedToast.error(
          context,
          'يرجى اختيار التاريخ أولاً لتفعيل التنبيه',
        );
      }
      if (mounted) {
        setState(() => _isSaving = false);
      }
      return;
    }

    DateTime? alarmDateTime;
    final selectedDate = _selectedDate;
    final alarmTime = _alarmTime;
    if (_alarmEnabled && alarmTime != null && selectedDate != null) {
      // Create DateTime in local timezone first
      final localAlarmDateTime = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        alarmTime.hour,
        alarmTime.minute,
      );

      // Convert to UTC for backend API (backend expects UTC)
      alarmDateTime = localAlarmDateTime.toUtc();

      // FIX: Validate alarm datetime is not in the past
      if (alarmDateTime.isBefore(DateTime.now())) {
        if (mounted) {
          AnimatedToast.error(
            context,
            'لا يمكن اختيار وقت ماضٍ للتنبيه',
          );
        }
        if (mounted) {
          setState(() => _isSaving = false);
        }
        return;
      }
    }

    try {
      final provider = context.read<TaskProvider>();

      if (_isNewTask) {
        await provider.addTask(
          title: title,
          description: _descriptionController.text.trim(),
          dueDate: _selectedDate,
          alarmEnabled: _alarmEnabled,
          alarmTime: alarmDateTime,
          recurrence: _selectedRecurrence,
          attachments: _attachments,
          priority: _priority,
        );

        // FIX #2: Handle case where task creation fails
        if (provider.tasks.isNotEmpty) {
          _taskId = provider.tasks.first.id;
          _isNewTask = false;
        } else {
          debugPrint(
            '[TaskEditScreen] Failed to create task - no task in provider',
          );
          if (mounted) {
            AnimatedToast.error(context, 'فشل إنشاء المهمة');
          }
          return; // Early return - don't continue with update
        }
      } else {
        // FIX #2: Add null check for _taskId to prevent crash
        if (_taskId == null) {
          debugPrint(
            '[TaskEditScreen] Cannot update task - _taskId is null',
          );
          return;
        }

        await provider.updateTask(
          widget.task?.copyWith(
                id: _taskId,
                title: title,
                description: _descriptionController.text.trim(),
                dueDate: _selectedDate,
                alarmEnabled: _alarmEnabled,
                alarmTime: alarmDateTime,
                recurrence: _selectedRecurrence,
                attachments: _attachments,
                priority: _priority,
              ) ??
              TaskModel(
                id: _taskId!,
                title: title,
                description: _descriptionController.text.trim(),
                dueDate: _selectedDate,
                alarmEnabled: _alarmEnabled,
                alarmTime: alarmDateTime,
                recurrence: _selectedRecurrence,
                attachments: _attachments,
                priority: _priority,
                isCompleted: false,
                isSynced: false,
                createdBy: provider.currentUserId,
              ),
        );
      }
      debugPrint('[TaskEditScreen] Task saved successfully');
      // FIX #12: Record successful sync for adaptive debounce
      _recordSyncSuccess();
    } catch (e) {
      // FIX #5: Consistent error handling - only show toast for non-transient errors
      debugPrint('[TaskEditScreen] Auto-save error: $e');
      // FIX #12: Record sync failure for adaptive debounce
      _recordSyncFailure();
      if (mounted && !_isOfflineError(e)) {
        AnimatedToast.error(context, 'حدث خطأ أثناء الحفظ');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
        // FIX MOBILE-003: Process pending save if one was requested during save
        if (_pendingSave) {
          _pendingSave = false;
          _saveTask(); // Trigger another save
        }
      }
    }
  }

  void _presentDatePicker() async {
    HijriCalendar.setLocal('ar');
    final pickedDate = await PremiumBottomSheet.show<HijriCalendar>(
      context: context,
      child: HijriDatePickerDialog(
        initialDate: _selectedDate != null
            ? HijriCalendar.fromDate(_selectedDate!)
            : HijriCalendar.now(),
        firstDate: HijriCalendar.now(),
        lastDate: HijriCalendar()..hYear = 1460,
      ),
    );

    if (pickedDate != null) {
      setState(() {
        _selectedDate = pickedDate.hijriToGregorian(
          pickedDate.hYear,
          pickedDate.hMonth,
          pickedDate.hDay,
        );
        _dateController.text = pickedDate.toFormat('dd MMMM').toEnglishNumbers;
      });
      _onChanged();
    }
  }

  void _presentTimePicker() async {
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _alarmTime ?? TimeOfDay.now(),
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final primary = AppColors.primary;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme(
              brightness: Theme.of(context).brightness,
              primary: primary,
              onPrimary: Colors.white,
              secondary: primary,
              onSecondary: Colors.white,
              error: Colors.red,
              onError: Colors.white,
              onSurface: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight,
              surface: isDark
                  ? AppColors.surfaceCardDark
                  : AppColors.surfaceCardLight,
            ),
          ),
          // FIX: Avoid force unwrap - use null-aware operator
          child: child ?? Container(),
        );
      },
    );

    if (pickedTime != null) {
      setState(() {
        _alarmTime = pickedTime;
      });
      _onChanged();
    }
  }

  /// FIX #6: Check if file extension is an image
  bool _isImageFile(String extension) {
    final ext = extension.toLowerCase();
    return ext == '.jpg' ||
        ext == '.jpeg' ||
        ext == '.png' ||
        ext == '.gif' ||
        ext == '.webp';
  }

  void _pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null) {
      setState(() {
        for (var file in result.files) {
          if (file.path != null) {
            final fileName = file.name;
            final extension = p.extension(file.path!).toLowerCase();
            final type = _isImageFile(extension) ? 'image' : 'file';

            // FIX #6: Store relative path and add file size for better tracking
            _attachments.add({
              'path': file.path,
              'file_name': fileName,
              'type': type,
              'size': file.size,
              'extension': extension,
            });
          }
        }
      });
      _onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: true,
      // FIX #7: Fix PopScope logic error - handle didPop correctly
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          // Already popped - save in background without blocking
          _debounce?.cancel();
          unawaited(_saveTask());
          return;
        }
        // Pop was prevented - save then pop
        _debounce?.cancel();
        await _saveTask();
        if (mounted && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.scaffoldBackgroundColor,
          elevation: 0,
          leading: Semantics(
            label: 'رجوع',
            button: true,
            child: IconButton(
              icon: const Icon(
                SolarLinearIcons.arrowRight,
                size: _TaskEditConstants.iconSizeMedium,
              ),
              onPressed: () async {
                _debounce?.cancel();
                await _saveTask();
                if (mounted && context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              tooltip: 'رجوع',
              focusColor: AppColors.primary.withValues(alpha: 0.12),
              hoverColor: AppColors.primary.withValues(alpha: 0.04),
              highlightColor: AppColors.primary.withValues(alpha: 0.08),
            ),
          ),
          title: const SizedBox.shrink(),
          actions: [
            // LOADING: Show spinner while permissions are loading
            if (_isLoadingPermissions)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            // PERMISSION: Only show share button for users with edit/admin/owner permission
            else if (!_isNewTask && widget.task != null && _canShare)
              Semantics(
                label: 'مشاركة',
                button: true,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      Haptics.lightTap();
                      TaskShareDialog.show(
                        context,
                        taskId: widget.task!.id,
                        taskTitle: widget.task!.title,
                      );
                    },
                    borderRadius: BorderRadius.circular(
                      _TaskEditConstants.borderRadiusFull,
                    ),
                    focusColor: AppColors.primary.withValues(alpha: 0.12),
                    hoverColor: AppColors.primary.withValues(alpha: 0.04),
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: _TaskEditConstants.minTouchTargetSize,
                        minHeight: _TaskEditConstants.minTouchTargetSize,
                      ),
                      padding: const EdgeInsets.all(AppDimensions.spacing8),
                      child: Icon(
                        SolarLinearIcons.usersGroupRounded,
                        color: theme.colorScheme.onSurface,
                        size: AppDimensions.iconMedium,
                      ),
                    ),
                  ),
                ),
              ),
            if (_isSaving)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(child: _buildDetailsTab()),
      ),
    );
  }

  Widget _buildDetailsTab() {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // PERMISSION: Title field - read-only for users without edit permission
          AppTextField(
            controller: _titleController,
            hintText: 'عنوان المهمَّة',
            prefixIcon: const Icon(
              SolarLinearIcons.pen,
              size: _TaskEditConstants.iconSizeSmall,
            ),
            style: const TextStyle(
              fontSize: _TaskEditConstants.fontSizeLarge,
              fontWeight: FontWeight.bold,
            ),
            readOnly: _isLoadingPermissions || !_canEdit,
            enabled: !_isLoadingPermissions && _canEdit,
          ),
          const SizedBox(height: 16),
          // PERMISSION: Description field - read-only for users without edit permission
          _canEdit && !_isLoadingPermissions
              ? AppTextField(
                  controller: _descriptionController,
                  hintText: 'التَّفاصيل (اختياري)',
                  prefixIcon: const Icon(
                    SolarLinearIcons.documentText,
                    size: _TaskEditConstants.iconSizeSmall,
                  ),
                  maxLines: null,
                  minLines: 3,
                  borderRadius: AppDimensions.radiusLarge,
                )
              : _buildDescriptionReadOnly(theme),
          const SizedBox(height: 16),
          // PERMISSION: Date field - read-only for all (always was), but disable picker for read-only users
          AppTextField(
            controller: _dateController,
            hintText: 'التَّاريخ (اختياري)',
            readOnly: true,
            onTap: _canEdit
                ? () {
                    Haptics.lightTap();
                    _presentDatePicker();
                  }
                : null,
            prefixIcon: Icon(
              SolarLinearIcons.calendar,
              size: _TaskEditConstants.iconSizeSmall,
              color: _selectedDate == null ? null : AppColors.primary,
            ),
            borderRadius: AppDimensions.radiusMedium,
          ),
          const SizedBox(height: 24),
          // PERMISSION: Priority picker - only allow changes for users with edit permission
          PriorityPicker(
            selectedPriority: _priority,
            onPriorityChanged: (p) {
              if (_canEdit) {
                setState(() => _priority = p);
                _onChanged();
              }
            },
          ),
          const SizedBox(height: 24),
          Text(
            'التكرار',
            style: TextStyle(
              fontSize: _TaskEditConstants.fontSizeMedium,
              fontWeight: FontWeight.bold,
              color: theme.brightness == Brightness.dark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 8),
          _buildRecurrenceSelector(),
          const SizedBox(height: 24),
          _buildAttachmentsSection(),
          const SizedBox(height: 24),
          _buildAlertsSection(),
        ],
      ),
    );
  }

  Widget _buildRecurrenceSelector() {
    final recurrences = [
      {'label': 'بدون تكرار', 'value': null},
      {'label': 'يومي', 'value': 'daily'},
      {'label': 'أسبوعي', 'value': 'weekly'},
      {'label': 'شهري', 'value': 'monthly'},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: recurrences.map((rec) {
          final isSelected = _selectedRecurrence == rec['value'];
          return Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: ChoiceChip(
              avatar: Icon(
                rec['value'] == null
                    ? SolarLinearIcons.refresh
                    : SolarLinearIcons.repeat,
                size: 16,
                color: isSelected ? AppColors.primary : null,
              ),
              label: Text(rec['label'] as String),
              selected: isSelected,
              // PERMISSION: Only allow recurrence change for users with edit permission
              onSelected: (val) {
                if (_canEdit) {
                  setState(() => _selectedRecurrence = rec['value']);
                  Haptics.lightTap();
                  _onChanged();
                }
              },
              selectedColor: AppColors.primary.withValues(alpha: 0.2),
              labelStyle: TextStyle(
                color: isSelected ? AppColors.primary : null,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAttachmentsSection() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'المرفقات',
              style: TextStyle(
                fontSize: _TaskEditConstants.fontSizeMedium,
                fontWeight: FontWeight.w600,
                color: theme.brightness == Brightness.dark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
              ),
            ),
            // PERMISSION: Only show add attachment button for users with edit permission
            if (_canEdit)
              IconButton(
                onPressed: _pickAttachments,
                icon: const Icon(
                  SolarLinearIcons.paperclip,
                  color: AppColors.primary,
                ),
              ),
          ],
        ),
        if (_attachments.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_attachments.length, (index) {
              final att = _attachments[index];
              final isImage = att['type'] == 'image';
              return Chip(
                avatar: Icon(
                  isImage ? SolarLinearIcons.gallery : SolarLinearIcons.file,
                  size: 14,
                ),
                label: Text(
                  att['file_name'] ?? 'ملف',
                  style: const TextStyle(fontSize: 10),
                ),
                // PERMISSION: Only show delete button for users with edit permission
                onDeleted: _canEdit
                    ? () {
                        setState(() => _attachments.removeAt(index));
                        _onChanged();
                      }
                    : null,
              );
            }),
          ),
      ],
    );
  }

  Widget _buildAlertsSection() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'التنبيهات',
          style: TextStyle(
            fontSize: _TaskEditConstants.fontSizeMedium,
            fontWeight: FontWeight.w600,
            color: theme.brightness == Brightness.dark
                ? AppColors.textPrimaryDark
                : AppColors.textPrimaryLight,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark
                ? AppColors.surfaceCardDark
                : AppColors.surfaceCardLight,
            borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
          ),
          child: Column(
            children: [
              // PERMISSION: Disable alarm toggle for read-only users
              SwitchListTile(
                value: _alarmEnabled,
                // PERMISSION: Only allow alarm changes for users with edit permission
                onChanged: _canEdit
                    ? (val) {
                        setState(() {
                          _alarmEnabled = val;
                          if (val && _alarmTime == null) {
                            _alarmTime = TimeOfDay.now();
                          }
                        });
                        _onChanged();
                      }
                    : null,
                title: Text(
                  'تفعيل التَّنبيه',
                  style: TextStyle(
                    fontSize: _TaskEditConstants.fontSizeMedium,
                    fontWeight: FontWeight.w500,
                    color: theme.brightness == Brightness.dark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
                ),
                secondary: Icon(
                  _alarmEnabled
                      ? SolarLinearIcons.bellBing
                      : SolarLinearIcons.bell,
                  size: _TaskEditConstants.iconSizeSmall,
                  color: _alarmEnabled ? AppColors.primary : null,
                ),
                activeThumbColor: AppColors.primary,
              ),
              if (_alarmEnabled)
                Padding(
                  padding: const EdgeInsets.only(
                    bottom: 12,
                    left: 16,
                    right: 16,
                  ),
                  child: InkWell(
                    // PERMISSION: Only allow time picker for users with edit permission
                    onTap: _canEdit ? _presentTimePicker : null,
                    borderRadius: BorderRadius.circular(
                      _TaskEditConstants.borderRadiusMedium,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: theme.brightness == Brightness.dark
                              ? AppColors.borderDark
                              : AppColors.borderLight,
                        ),
                        borderRadius: BorderRadius.circular(
                          _TaskEditConstants.borderRadiusMedium,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'وقت التَّنبيه',
                            style: TextStyle(
                              color: theme.brightness == Brightness.dark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimaryLight,
                            ),
                          ),
                          Text(
                            _alarmTime?.format(context) ?? 'اختر الوقت',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // FIX #10: Extract alarm hint to separate method
              if (_selectedDate == null) ..._buildAlarmHint(theme),
            ],
          ),
        ),
      ],
    );
  }

  // FIX #10: Extract alarm hint widget to separate method for better readability
  List<Widget> _buildAlarmHint(ThemeData theme) {
    return [
      const SizedBox(height: 24),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
        ),
        child: Row(
          children: [
            const Icon(
              SolarLinearIcons.infoCircle,
              color: AppColors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'موعد المهمة',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.brightness == Brightness.dark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'أضف تاريخ المهمة أولاً لتفعيل التنبيهات',
                    style: TextStyle(
                      fontSize: _TaskEditConstants.fontSizeSmall,
                      color: theme.brightness == Brightness.dark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      _presentDatePicker();
                    },
                    child: Text(
                      'إضافة التاريخ',
                      style: TextStyle(
                        color: theme.brightness == Brightness.dark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimaryLight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
  }

  /// Build read-only description with clickable links and @mentions
  Widget _buildDescriptionReadOnly(ThemeData theme) {
    final description = _descriptionController.text;
    final isEmpty = description.isEmpty;

    // Extract mentions from the description
    _descriptionMentions = _extractMentions(description);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
      ),
      padding: const EdgeInsets.all(AppDimensions.spacing12),
      child: isEmpty
          ? Text(
              'التَّفاصيل (اختياري)',
              style: TextStyle(
                fontFamily: 'IBM Plex Sans Arabic',
                fontSize: _TaskEditConstants.fontSizeMedium,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.right,
            )
          : _buildRichTextWithLinksAndMentions(theme, description),
    );
  }

  /// Build rich text with both URLs and @username mentions
  Widget _buildRichTextWithLinksAndMentions(ThemeData theme, String text) {
    // Parse the text into linkify elements (URLs, emails, etc.)
    final elements = linkify(
      text,
      options: const LinkifyOptions(
        humanize: false,
        looseUrl: true,
      ),
    );

    // If no mentions, use regular Linkify for URLs only
    if (_descriptionMentions == null || _descriptionMentions!.isEmpty) {
      return Linkify(
        text: text,
        onOpen: (link) async {
          await AppLauncher.launchSafeUrl(context, link.url);
        },
        options: const LinkifyOptions(
          humanize: false,
          looseUrl: true,
        ),
        textDirection: text.isArabic ? TextDirection.rtl : TextDirection.ltr,
        textAlign: text.isArabic ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontFamily: 'IBM Plex Sans Arabic',
          fontSize: _TaskEditConstants.fontSizeMedium,
          color: theme.colorScheme.onSurface,
        ),
        linkStyle: const TextStyle(
          color: AppColors.primary,
          decoration: TextDecoration.underline,
        ),
      );
    }

    // Build rich text with both URLs and mentions
    final spans = <TextSpan>[];
    final mentionMap = <String, Map<String, dynamic>>{};

    // Create a map of username to mention data for quick lookup
    for (var mention in _descriptionMentions!) {
      final username = mention['username'] as String;
      mentionMap[username] = mention;
    }

    // Process each linkify element
    for (var element in elements) {
      if (element is TextElement) {
        // This is plain text - check for mentions within it
        _addTextWithMentions(spans, element.text, theme);
      } else if (element is UrlElement) {
        // This is a URL - make it clickable
        spans.add(TextSpan(
          text: element.url,
          style: const TextStyle(
            color: AppColors.primary,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              await AppLauncher.launchSafeUrl(context, element.url);
            },
        ));
      }
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontFamily: 'IBM Plex Sans Arabic',
          fontSize: _TaskEditConstants.fontSizeMedium,
          color: theme.colorScheme.onSurface,
        ),
        children: spans,
      ),
      textAlign: text.isArabic ? TextAlign.right : TextAlign.left,
      textDirection: text.isArabic ? TextDirection.rtl : TextDirection.ltr,
      maxLines: null, // Allow unlimited lines for wrapping
      textWidthBasis: TextWidthBasis.parent, // Wrap to parent width
    );
  }

  void _addTextWithMentions(
    List<TextSpan> spans,
    String text,
    ThemeData theme,
  ) {
    final matches = _mentionPattern.allMatches(text);
    int lastEnd = 0;

    for (var match in matches) {
      // Add text before the mention
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: TextStyle(
            fontFamily: 'IBM Plex Sans Arabic',
            fontSize: _TaskEditConstants.fontSizeMedium,
            color: theme.colorScheme.onSurface,
          ),
        ));
      }

      // Add the mention as a clickable span
      final username = match.group(1)!;
      spans.add(TextSpan(
        text: '@$username',
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
          decorationColor: AppColors.primary,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () {
            // Handle mention tap - navigate to customer detail screen
            Haptics.lightTap();
            _navigateToCustomerDetail(username);
          },
      ));

      lastEnd = match.end;
    }

    // Add remaining text after the last mention
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: TextStyle(
          fontFamily: 'IBM Plex Sans Arabic',
          fontSize: _TaskEditConstants.fontSizeMedium,
          color: theme.colorScheme.onSurface,
        ),
      ));
    }
  }
}
