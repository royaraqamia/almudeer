import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:flutter_linkify/flutter_linkify.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/dimensions.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/url_launcher_utils.dart';

import '../../../data/models/library_item.dart';
import '../../providers/library_provider.dart';
import '../../../core/extensions/string_extension.dart';
import '../../widgets/library/share_item_dialog.dart';

/// ✅ P1: Enhanced Note Edit Screen
/// - Clear edit vs read mode distinction
/// - Save success feedback
/// - P0: Proper Semantics and touch targets
/// - P2: Design token compliance
class NoteEditScreen extends StatefulWidget {
  final LibraryItem? item;

  const NoteEditScreen({super.key, this.item});

  @override
  State<NoteEditScreen> createState() => _NoteEditScreenState();
}

class _NoteEditScreenState extends State<NoteEditScreen> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  Timer? _debounce;
  bool _isNewNote = false;
  int? _tempId;
  bool _isSaving = false;
  bool _isEditingContent = false;

  // P1: Edit mode visual feedback
  final FocusNode _contentFocusNode = FocusNode();
  late LibraryProvider _provider;

  @override
  void initState() {
    super.initState();
    _isNewNote = widget.item == null;
    _isEditingContent = _isNewNote;
    _titleController = TextEditingController(text: widget.item?.title);
    _contentController = TextEditingController(text: widget.item?.content);

    if (_isNewNote) {
      _tempId = DateTime.now().millisecondsSinceEpoch;
    }

    _titleController.addListener(_onChanged);
    _contentController.addListener(_onChanged);
    _contentFocusNode.addListener(_onFocusChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache provider reference to avoid context.read() in dispose()
    _provider = context.read<LibraryProvider>();
  }
  
  void _onFocusChange() {
    if (_contentFocusNode.hasFocus && !_isEditingContent) {
      setState(() => _isEditingContent = true);
    } else if (!_contentFocusNode.hasFocus && _isEditingContent && !_isNewNote) {
      setState(() => _isEditingContent = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // Note: We don't call _saveNote() here because:
    // 1. PopScope.onPopInvokedWithResult handles save on back navigation
    // 2. The back button handles save before popping
    // 3. Calling provider methods in dispose() can trigger notifyListeners() 
    //    while the widget tree is locked, causing crashes
    _titleController.dispose();
    _contentController.dispose();
    _contentFocusNode.removeListener(_onFocusChange);
    _contentFocusNode.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(seconds: 1), _saveNote);
  }

  Future<void> _saveNote({bool skipStateUpdate = false}) async {
    if (_isSaving) return;

    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    // Don't save if both are empty
    if (title.isEmpty && content.isEmpty) return;

    final noteId = widget.item?.id ?? _tempId;
    debugPrint('[NoteEditScreen] Saving note: id=$noteId, isNew=$_isNewNote, title=$title');

    if (!skipStateUpdate && mounted) setState(() => _isSaving = true);

    try {
      if (_isNewNote) {
        final id = await _provider.addNote(title, content);
        _tempId = id;
        _isNewNote = false;
        debugPrint('[NoteEditScreen] Note created with id=$id');
      } else {
        await _provider.updateNote(noteId!, title, content);
        debugPrint('[NoteEditScreen] Note updated successfully');
      }

      Haptics.lightTap();
    } catch (e) {
      debugPrint('[NoteEditScreen] Auto-save error: $e');
    } finally {
      if (!skipStateUpdate && mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _onOpenLink(LinkableElement link) async {
    await AppLauncher.launchSafeUrl(context, link.url);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        _debounce?.cancel();
        await _saveNote();

        if (mounted) {
          Navigator.of(this.context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.scaffoldBackgroundColor,
          elevation: 0,
          leading: Semantics(
            label: 'حفظ والعودة',
            button: true,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  _debounce?.cancel();
                  await _saveNote();
                  if (mounted) {
                    Navigator.of(this.context).pop();
                  }
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
                    SolarLinearIcons.arrowRight,
                    color: theme.colorScheme.onSurface,
                    size: AppDimensions.iconMedium,
                  ),
                ),
              ),
            ),
          ),
          actions: [
            if (widget.item != null)
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
                        itemId: widget.item!.id,
                        itemTitle: widget.item!.title,
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
          ],
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title field with P0 accessibility
              ListenableBuilder(
                listenable: _titleController,
                builder: (context, child) {
                  final text = _titleController.text;
                  return Semantics(
                    textField: true,
                    label: 'عنوان الملاحظة',
                    child: TextField(
                      controller: _titleController,
                      textDirection: text.isEmpty
                          ? TextDirection.rtl
                          : text.direction,
                      textAlign: (text.isEmpty || text.isArabic)
                          ? TextAlign.right
                          : TextAlign.left,
                      style: TextStyle(
                        fontFamily: 'IBM Plex Sans Arabic',
                        fontWeight: text.isEmpty
                            ? FontWeight.normal
                            : FontWeight.bold,
                        fontSize: 20,
                        color: theme.colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        hintText: 'العنوان',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        hintStyle: const TextStyle(
                          color: Colors.grey,
                          fontFamily: 'IBM Plex Sans Arabic',
                          fontWeight: FontWeight.normal,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppDimensions.paddingLarge,
                          vertical: AppDimensions.spacing10,
                        ),
                      ),
                      maxLines: 1,
                    ),
                  );
                },
              ),
              
              // P1: Enhanced content area with clear edit/read distinction
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (!_isEditingContent) {
                      Haptics.lightTap();
                      setState(() => _isEditingContent = true);
                      _contentFocusNode.requestFocus();
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimensions.paddingLarge,
                    ),
                    child: _isEditingContent
                        ? _buildEditMode(theme)
                        : _buildReadMode(theme),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // P1: Edit mode with clear visual distinction
  Widget _buildEditMode(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
      ),
      padding: const EdgeInsets.all(AppDimensions.spacing12),
      child: ListenableBuilder(
        listenable: _contentController,
        builder: (context, child) {
          final text = _contentController.text;
          return Semantics(
            textField: true,
            label: 'محتوى الملاحظة',
            child: TextField(
              controller: _contentController,
              focusNode: _contentFocusNode,
              autofocus: true,
              textDirection: text.isEmpty
                  ? TextDirection.rtl
                  : text.direction,
              textAlign: (text.isEmpty || text.isArabic)
                  ? TextAlign.right
                  : TextAlign.left,
              style: const TextStyle(
                fontFamily: 'IBM Plex Sans Arabic',
                fontSize: 16,
                height: 1.5,
                fontWeight: FontWeight.normal,
              ),
              decoration: const InputDecoration(
                hintText: 'اكتب ما تريد هُنا...',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintStyle: TextStyle(
                  color: Colors.grey,
                  fontFamily: 'IBM Plex Sans Arabic',
                ),
                contentPadding: EdgeInsets.zero,
              ),
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
            ),
          );
        },
      ),
    );
  }

  // P1: Read mode with clear visual distinction
  Widget _buildReadMode(ThemeData theme) {
    final content = _contentController.text;
    final isEmpty = content.isEmpty;

    return GestureDetector(
      onTap: () {
        Haptics.lightTap();
        setState(() => _isEditingContent = true);
        _contentFocusNode.requestFocus();
      },
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
        ),
        padding: const EdgeInsets.all(AppDimensions.spacing12),
        child: SelectableLinkify(
          text: isEmpty ? 'اكتب ما تريد هُنا...' : content,
          onOpen: _onOpenLink,
          options: const LinkifyOptions(
            humanize: false,
            looseUrl: true,
          ),
          onTap: () {
            Haptics.lightTap();
            setState(() => _isEditingContent = true);
            _contentFocusNode.requestFocus();
          },
          textAlign: (isEmpty || content.isArabic)
              ? TextAlign.right
              : TextAlign.left,
          style: TextStyle(
            fontFamily: 'IBM Plex Sans Arabic',
            fontSize: 16,
            height: 1.5,
            fontWeight: FontWeight.normal,
            color: isEmpty
                ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                : theme.colorScheme.onSurface,
          ),
          linkStyle: const TextStyle(
            color: Colors.blue,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}
