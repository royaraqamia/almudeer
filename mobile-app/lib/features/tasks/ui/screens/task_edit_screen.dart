import 'dart:async';
import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:uuid/uuid.dart';

import '../../models/task_model.dart';
import '../../providers/task_provider.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/dimensions.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../core/extensions/string_extension.dart';
import '../../../../core/utils/permission_helper.dart';
import '../widgets/hijri_date_picker_dialog.dart';
import '../widgets/priority_picker.dart';
import '../../../../presentation/widgets/premium_bottom_sheet.dart';
import '../../../../presentation/widgets/animated_toast.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../presentation/widgets/library/share_item_dialog.dart';

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
  bool _pendingSave = false;  // FIX MOBILE-003: Track pending save requests

  // Permission state
  late String _permissionLevel;
  late bool _canEdit;
  late bool _canShare;

  @override
  void initState() {
    super.initState();
    _isNewTask = widget.task == null;

    // Initialize permission state
    if (!_isNewTask && widget.task != null) {
      // FIX: Check if current user is the owner by comparing createdBy with currentUserId
      // Legacy tasks (createdBy == null) are treated as owned by the current user
      final currentUserId = context.read<TaskProvider>().currentUserId;
      final isOwner = widget.task!.createdBy == null || widget.task!.createdBy == currentUserId;
      _permissionLevel = getEffectivePermission(widget.task!.sharePermission, isOwner);
      _canEdit = canEdit(_permissionLevel);
      _canShare = canShare(_permissionLevel);
    } else {
      // New task - user is owner
      _permissionLevel = PermissionLevel.owner;
      _canEdit = true;
      _canShare = true;
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
        ).toFormat("dd MMMM").toEnglishNumbers;
      }
    } else {
      _taskId = const Uuid().v4();
    }

    _titleController.addListener(_onChanged);
    _descriptionController.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _titleController.dispose();
    _descriptionController.dispose();
    _dateController.dispose();
    _titleFocusNode.dispose();
    _descriptionFocusNode.dispose();

    super.dispose();
  }

  void _onChanged() {
    // FIX MOBILE-003: Use single debounce timer for all fields to prevent race conditions
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    // Use consistent debounce time for all fields to ensure ordered saves
    _debounce = Timer(const Duration(milliseconds: 1000), _saveTask);
  }

  Future<void> _saveTask() async {
    // FIX MOBILE-003: Prevent concurrent saves with generation counter
    if (_isSaving) {
      _pendingSave = true;
      return;
    }

    _isSaving = true;
    _pendingSave = false;

    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _isSaving = false);
      return;
    }

    DateTime? alarmDateTime;
    final selectedDate = _selectedDate;
    final alarmTime = _alarmTime;
    if (_alarmEnabled && alarmTime != null && selectedDate != null) {
      alarmDateTime = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        alarmTime.hour,
        alarmTime.minute,
      );
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

        if (provider.tasks.isNotEmpty) {
          _taskId = provider.tasks.first.id;
          _isNewTask = false;
        }
      } else {
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
                createdBy: context.read<TaskProvider>().currentUserId,
              ),
        );
      }
      debugPrint('[TaskEditScreen] Task saved successfully');
    } catch (e) {
      debugPrint('Auto-save error: $e');
      if (mounted) {
        AnimatedToast.error(context, 'حدث خطأ أثناء الحفظ');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
        // FIX MOBILE-003: Process pending save if one was requested during save
        if (_pendingSave) {
          _pendingSave = false;
          _saveTask();  // Trigger another save
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
        _dateController.text = pickedDate.toFormat("dd MMMM").toEnglishNumbers;
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
              onSurface: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
              surface: isDark ? AppColors.surfaceCardDark : AppColors.surfaceCardLight,
            ),
          ),
          child: child!,
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

  void _pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null) {
      setState(() {
        for (var file in result.files) {
          if (file.path != null) {
            final fileName = file.name;
            final extension = p.extension(file.path!).toLowerCase();
            final type =
                (extension == '.jpg' ||
                    extension == '.jpeg' ||
                    extension == '.png' ||
                    extension == '.gif')
                ? 'image'
                : 'file';

            _attachments.add({
              'path': file.path,
              'file_name': fileName,
              'type': type,
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
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
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
              icon: const Icon(SolarLinearIcons.arrowRight, size: 24),
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
            // PERMISSION: Only show share button for users with edit/admin/owner permission
            if (!_isNewTask && widget.task != null && _canShare)
              Semantics(
                label: 'مشاركة',
                button: true,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      Haptics.lightTap();
                      ShareItemDialog.show(
                        context,
                        itemId: 0,
                        itemTitle: widget.task!.title,
                        taskIds: widget.task!.id,
                      );
                    },
                    borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                    focusColor: AppColors.primary.withValues(alpha: 0.12),
                    hoverColor: AppColors.primary.withValues(alpha: 0.04),
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
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
        body: SafeArea(
          child: _buildDetailsTab(),
        ),
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
            prefixIcon: const Icon(SolarLinearIcons.pen, size: 20),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            readOnly: !_canEdit,
            enabled: _canEdit,
          ),
          const SizedBox(height: 16),
          // PERMISSION: Description field - read-only for users without edit permission
          AppTextField(
            controller: _descriptionController,
            hintText: 'التَّفاصيل (اختياري)',
            prefixIcon: const Icon(SolarLinearIcons.documentText, size: 20),
            maxLines: null,
            minLines: 3,
            borderRadius: AppDimensions.radiusLarge,
            readOnly: !_canEdit,
            enabled: _canEdit,
          ),
          const SizedBox(height: 16),
          // PERMISSION: Date field - read-only for all (always was), but disable picker for read-only users
          AppTextField(
            controller: _dateController,
            hintText: 'التَّاريخ (اختياري)',
            readOnly: true,
            onTap: _canEdit ? () {
              Haptics.lightTap();
              _presentDatePicker();
            } : null,
            prefixIcon: Icon(
              SolarLinearIcons.calendar,
              size: 20,
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
              fontSize: 14,
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
                fontSize: 14,
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
                onDeleted: _canEdit ? () {
                  setState(() => _attachments.removeAt(index));
                  _onChanged();
                } : null,
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
            fontSize: 14,
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
                onChanged: _canEdit ? (val) {
                  setState(() {
                    _alarmEnabled = val;
                    if (val && _alarmTime == null) {
                      _alarmTime = TimeOfDay.now();
                    }
                  });
                  _onChanged();
                } : null,
                title: Text(
                  'تفعيل التَّنبيه',
                  style: TextStyle(
                    fontSize: 14,
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
                  size: 20,
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
                    borderRadius: BorderRadius.circular(8),
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
                        borderRadius: BorderRadius.circular(8),
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
                if (_selectedDate == null)
                  const SizedBox(height: 24),
                if (_selectedDate == null)
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
                                  fontSize: 12,
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
            ],
          ),
        ),
      ],
    );
  }

}
