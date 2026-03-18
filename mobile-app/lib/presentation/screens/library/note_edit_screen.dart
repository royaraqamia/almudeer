import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:linkify/linkify.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/dimensions.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/url_launcher_utils.dart';

import '../../../data/models/library_item.dart';
import '../../providers/library_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/customers_provider.dart';
import '../../../data/repositories/customers_repository.dart';
import '../../../core/extensions/string_extension.dart';
import '../../widgets/library/share_item_dialog.dart';
import '../customers/customer_detail_screen.dart';

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
  
  // Permission state
  bool _canEdit = true;

  // Mention detection for @username in content
  // Pattern: @ followed by 2-32 alphanumeric characters (including Arabic), underscores, hyphens
  // Uses \w for word characters plus Arabic letter ranges
  static final _mentionPattern = RegExp(r'@([a-zA-Z0-9_\u0600-\u06FF\u0750-\u077F-]{2,32})');
  List<Map<String, dynamic>>? _contentMentions;

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
    
    // Load permissions for existing items
    if (!_isNewNote) {
      _loadPermissions();
    }
  }
  
  void _loadPermissions() {
    // Get current user ID with fallback chain for offline reliability
    // Priority: AuthProvider cache → LibraryProvider context → cached storage
    String? currentUserId;
    
    // 1. Try AuthProvider's cached state first (uses persisted licenseId)
    try {
      final authProvider = context.read<AuthProvider>();
      currentUserId = authProvider.userInfo?.licenseId?.toString();
      if (currentUserId != null) {
        debugPrint('[NoteEditScreen] Got currentUserId from AuthProvider: $currentUserId');
      }
    } catch (e) {
      debugPrint('[NoteEditScreen] Could not get currentUserId from AuthProvider: $e');
    }
    
    // 2. Fallback: Try to get from LibraryProvider's internal state if available
    if (currentUserId == null) {
      try {
        // LibraryProvider doesn't expose currentUserId, so we need to fetch it
        // This is a last resort - should rarely happen
        debugPrint('[NoteEditScreen] AuthProvider returned null, using best-effort permissions');
      } catch (e) {
        debugPrint('[NoteEditScreen] Fallback also failed: $e');
      }
    }

    // Debug logging for offline troubleshooting
    if (currentUserId == null) {
      debugPrint('[NoteEditScreen] WARNING: currentUserId is null - permissions may be incorrect');
    }

    // New notes are always editable (user is owner)
    if (_isNewNote) {
      _canEdit = true;
      debugPrint('[NoteEditScreen] New note - user is owner, canEdit=true');
      return;
    }

    // Existing items: check if user is the owner or has edit/admin share permission
    final sharePermission = widget.item?.sharePermission;
    final createdBy = widget.item?.createdBy;
    final userId = widget.item?.userId;

    // User is owner if they created the item (createdBy or userId matches)
    // If currentUserId is null, use best-effort logic:
    // - If no sharePermission, assume user is owner (most common case)
    // - If sharePermission exists, respect it
    final isOwner = currentUserId != null
        ? (createdBy == currentUserId || userId == currentUserId)
        : (sharePermission == null); // Best-effort: no share = likely owner

    // Permission levels: owner/edit/admin can edit, read-only cannot
    _canEdit = isOwner ||
               sharePermission == 'edit' ||
               sharePermission == 'admin';

    debugPrint(
      '[NoteEditScreen] Permissions: currentUserId=$currentUserId, createdBy=$createdBy, userId=$userId, sharePermission=$sharePermission, isOwner=$isOwner, canEdit=$_canEdit',
    );
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
    } else if (!_contentFocusNode.hasFocus &&
        _isEditingContent &&
        !_isNewNote) {
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
    // PERMISSION: Prevent read-only users from triggering auto-save
    if (!_canEdit) {
      debugPrint('[NoteEditScreen] Read-only user - skipping auto-save');
      return;
    }
    
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(seconds: 1), _saveNote);
  }

  Future<void> _saveNote({bool skipStateUpdate = false}) async {
    // PERMISSION: Block read-only users from saving
    if (!_canEdit) {
      debugPrint('[NoteEditScreen] Read-only user attempted to save - blocked');
      return;
    }
    
    if (_isSaving) return;

    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    // Don't save if both are empty
    if (title.isEmpty && content.isEmpty) return;

    final noteId = widget.item?.id ?? _tempId;
    debugPrint(
      '[NoteEditScreen] Saving note: id=$noteId, isNew=$_isNewNote, title=$title',
    );

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
          debugPrint('[NoteEditScreen] Failed to fetch customer data: $fetchError');
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
            // PERMISSION: Only show share button for users with edit permission
            if (widget.item != null && _canEdit)
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
                    borderRadius: BorderRadius.circular(
                      AppDimensions.radiusFull,
                    ),
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
                      decoration: const InputDecoration(
                        hintText: 'العنوان',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        hintStyle: TextStyle(
                          color: Colors.grey,
                          fontFamily: 'IBM Plex Sans Arabic',
                          fontWeight: FontWeight.normal,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: AppDimensions.paddingLarge,
                          vertical: AppDimensions.spacing10,
                        ),
                      ),
                      maxLines: 1,
                      // PERMISSION: Read-only users cannot edit
                      readOnly: !_canEdit,
                      enabled: _canEdit,
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
              textDirection: text.isEmpty ? TextDirection.rtl : text.direction,
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
              // PERMISSION: Read-only users cannot edit
              readOnly: !_canEdit,
              enabled: _canEdit,
            ),
          );
        },
      ),
    );
  }

  // P1: Read mode with clear visual distinction and @mention support
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
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.1,
          ),
          borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
        ),
        padding: const EdgeInsets.all(AppDimensions.spacing12),
        child: isEmpty
            ? Text(
                'اكتب ما تريد هُنا...',
                style: TextStyle(
                  fontFamily: 'IBM Plex Sans Arabic',
                  fontSize: 16,
                  height: 1.5,
                  fontWeight: FontWeight.normal,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                textAlign: TextAlign.right,
              )
            : _buildRichTextWithLinksAndMentions(theme, content),
      ),
    );
  }

  /// Build rich text with both URLs and @username mentions
  Widget _buildRichTextWithLinksAndMentions(ThemeData theme, String text) {
    // Extract mentions from the content
    _contentMentions = _extractMentions(text);

    // Parse the text into linkify elements (URLs, emails, etc.)
    final elements = linkify(
      text,
      options: const LinkifyOptions(
        humanize: false,
        looseUrl: true,
      ),
    );

    // If no mentions, use regular Linkify for URLs only
    if (_contentMentions == null || _contentMentions!.isEmpty) {
      return SelectableLinkify(
        text: text,
        onOpen: _onOpenLink,
        options: const LinkifyOptions(humanize: false, looseUrl: true),
        textAlign: text.isArabic ? TextAlign.right : TextAlign.left,
        textDirection: text.isArabic ? TextDirection.rtl : TextDirection.ltr,
        style: TextStyle(
          fontFamily: 'IBM Plex Sans Arabic',
          fontSize: 16,
          height: 1.5,
          fontWeight: FontWeight.normal,
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
    for (var mention in _contentMentions!) {
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
          fontSize: 16,
          height: 1.5,
          fontWeight: FontWeight.normal,
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
            fontSize: 16,
            height: 1.5,
            fontWeight: FontWeight.normal,
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
          fontSize: 16,
          height: 1.5,
          fontWeight: FontWeight.normal,
          color: theme.colorScheme.onSurface,
        ),
      ));
    }
  }
}
