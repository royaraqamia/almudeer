import 'dart:async';
import 'dart:io';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:path/path.dart' as p;

import 'package:provider/provider.dart';
import '../../providers/conversation_detail_provider.dart';
import '../../providers/inbox_provider.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/extensions/string_extension.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/animated_toast.dart';
import 'reply_preview.dart';
import 'media_preview_dialog.dart';
import 'mention_autocomplete.dart';

/// Message input section with emoji and send functionality
class MessageInputSection extends StatefulWidget {
  final Future<void> Function(
    String text, {
    List<File>? mediaFiles,
    Map<String, dynamic>? metadata,
    String? replyToPlatformId,
    String? replyToBodyPreview,
    List<Map<String, dynamic>>? customAttachments,
  })
  onSend;
  final String? replyToSender;
  final String? replyToBody;
  final String? replyToPlatformId;
  final String? replyToBodyPreview;
  final List<Map<String, dynamic>>? replyToAttachments;
  final VoidCallback? onCancelReply;
  final Function(bool isTyping)? onTypingChanged;
  final bool isBottomCompact;
  final bool isReplyToOutgoing;

  const MessageInputSection({
    super.key,
    required this.onSend,
    this.replyToSender,
    this.replyToBody,
    this.replyToPlatformId,
    this.replyToBodyPreview,
    this.replyToAttachments,
    this.onCancelReply,
    this.onTypingChanged,
    this.isBottomCompact = false,
    this.isReplyToOutgoing = false,
  });

  @override
  State<MessageInputSection> createState() => _MessageInputSectionState();
}

class _MessageInputSectionState extends State<MessageInputSection> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  // Editing State
  int? _lastEditingId;

  // Mention Autocomplete State
  String? _mentionQuery;
  final double _mentionOffsetX = 0;
  final double _mentionOffsetY = 0;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _mentionOverlayEntry;

  // UI State
  bool _showEmoji = false;
  bool _showAttachments = false;

  @override
  void initState() {
    super.initState();

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        setState(() {
          _showEmoji = false;
          _showAttachments = false;
        });
      }
    });

    // Draft Loading
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final provider = context.read<ConversationDetailProvider>();
        final contact = provider.senderContact;
        if (contact != null) {
          final draft = provider.getDraft(contact);
          if (draft.isNotEmpty) {
            _controller.text = draft;
            _onTextChanged(draft); // Update UI state
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _hideMentionAutocomplete();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSendText() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    Haptics.lightTap();
    _controller.clear();

    // Clear draft and reply immediately for better UX
    if (mounted) {
      final provider = context.read<ConversationDetailProvider>();
      final contact = provider.senderContact;
      if (contact != null) {
        provider.clearDraft(contact);
      }
    }
    if (widget.onCancelReply != null) widget.onCancelReply!();

    await widget.onSend(
      text,
      replyToPlatformId: widget.replyToPlatformId,
      replyToBodyPreview: widget.replyToBodyPreview,
    );
  }

  Timer? _typingTimer;
  bool _isTyping = false;

  void _onTextChanged(String text) {
    setState(() {});

    final provider = context.read<ConversationDetailProvider>();

    // FIX: Don't save draft when editing an existing message
    // Editing is modifying a sent message, not creating a new draft
    if (!provider.isEditing) {
      provider.saveDraft(text);
    }

    // Check for @mention pattern
    _checkForMention(text);

    if (widget.onTypingChanged == null) return;

    if (!_isTyping && text.isNotEmpty) {
      _isTyping = true;
      widget.onTypingChanged?.call(true);
      context.read<ConversationDetailProvider>().setTypingStatus(true);
    } else if (_isTyping && text.isEmpty) {
      _isTyping = false;
      widget.onTypingChanged?.call(false);
      context.read<ConversationDetailProvider>().setTypingStatus(false);
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (_isTyping) {
        _isTyping = false;
        widget.onTypingChanged?.call(false);
        context.read<ConversationDetailProvider>().setTypingStatus(false);
      }
    });
  }

  /// Check for @mention pattern and show/hide autocomplete
  void _checkForMention(String text) {
    final cursorPosition = _controller.selection.baseOffset;
    if (cursorPosition < 0 || cursorPosition > text.length) return;

    // Find the word before cursor
    final textBeforeCursor = text.substring(0, cursorPosition);
    final words = textBeforeCursor.split(RegExp(r'\s+'));
    final lastWord = words.last;

    // Check if last word starts with @
    if (lastWord.startsWith('@')) {
      final query = lastWord.substring(1); // Remove @
      
      // Validate username: same pattern as task_edit_screen.dart and note_edit_screen.dart
      // Supports both Latin and Arabic characters, 2-32 chars long
      final validUsernamePattern = RegExp(r'^[a-zA-Z0-9_\u0600-\u06FF\u0750-\u077F-]{2,32}$');
      
      if (query.isNotEmpty && 
          query.length <= 32 && 
          validUsernamePattern.hasMatch(query)) {
        // Valid username length and format
        setState(() {
          _mentionQuery = query;
        });
        _showMentionAutocomplete();
        return;
      }
    }

    // Hide autocomplete if no valid mention
    _hideMentionAutocomplete();
  }

  /// Show mention autocomplete overlay
  void _showMentionAutocomplete() {
    _hideMentionAutocomplete(); // Hide any existing overlay first

    _mentionOverlayEntry = OverlayEntry(
      builder: (context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _hideMentionAutocomplete, // Dismiss on tap outside
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                color: Colors.transparent,
              ),
            ),
            // Use CompositedTransformFollower to follow the text field
            CompositedTransformFollower(
              link: _layerLink,
              offset: Offset(
                Directionality.of(context) == TextDirection.rtl ? 0 : 0,
                -50.0, // Position above the text field
              ),
              child: MentionAutocomplete(
                query: _mentionQuery ?? '',
                offsetX: _mentionOffsetX,
                offsetY: _mentionOffsetY,
                onMentionSelected: _handleMentionSelection,
                onDismiss: _hideMentionAutocomplete,
              ),
            ),
          ],
        ),
      ),
    );

    Overlay.of(context).insert(_mentionOverlayEntry!);
  }

  /// Hide mention autocomplete overlay
  void _hideMentionAutocomplete() {
    _mentionOverlayEntry?.remove();
    _mentionOverlayEntry = null;
    _mentionQuery = null;
  }

  /// Handle mention selection from autocomplete
  void _handleMentionSelection(String username) {
    final text = _controller.text;
    final cursorPosition = _controller.selection.baseOffset;

    // Find the start of the @mention
    final textBeforeCursor = text.substring(0, cursorPosition);
    final atIndex = textBeforeCursor.lastIndexOf('@');

    if (atIndex != -1) {
      // Replace @query with @username
      final newText = text.replaceRange(atIndex, cursorPosition, '@$username ');
      _controller.text = newText;
      _controller.selection = TextSelection.collapsed(offset: atIndex + username.length + 2);

      _hideMentionAutocomplete();
      Haptics.lightTap();
    }
  }

  void _toggleEmoji() {
    Haptics.selection();
    setState(() {
      _showEmoji = !_showEmoji;
      _showAttachments = false;
    });
    if (_showEmoji) {
      _focusNode.unfocus();
    } else {
      _focusNode.requestFocus();
    }
  }

  void _toggleAttachments() {
    Haptics.selection();
    setState(() {
      _showAttachments = !_showAttachments;
      _showEmoji = false;
    });
    if (_showAttachments) {
      _focusNode.unfocus();
    } else {
      _focusNode.requestFocus();
    }
  }

  Future<void> _handleAttachmentSelection(String type) async {
    final List<File> selectedFiles = [];
    try {
      if (type == 'camera') {
        final XFile? image = await ImagePicker().pickImage(
          source: ImageSource.camera,
          imageQuality: 70,
        );
        if (image != null) {
          // Show preview with caption for camera photos
          if (!mounted) return;
          final result = await showDialog<Map<String, dynamic>>(
            context: context,
            barrierDismissible: false,
            builder: (context) => MediaPreviewDialog(
              file: File(image.path),
              mediaType: 'image',
              onConfirm: (file, caption) => Navigator.pop(context, {
                'file': file,
                'caption': caption,
              }),
              onCancel: () => Navigator.pop(context, null),
            ),
          );

          if (result != null && result['file'] != null && mounted) {
            final file = result['file'] as File;
            final caption = result['caption'] as String?;
            
            final attachments = <Map<String, dynamic>>[{
              'path': file.path,
              'type': 'image',
              if (caption != null && caption.isNotEmpty) 'caption': caption,
            }];
            
            widget.onSend('', customAttachments: attachments);
          }
          setState(() {
            _showAttachments = false;
          });
          return;
        }
      } else if (type == 'gallery') {
        final List<XFile> images = await ImagePicker().pickMultiImage(
          imageQuality: 70,
        );
        if (images.isNotEmpty) {
          selectedFiles.addAll(images.map((x) => File(x.path)));
        }
      } else if (type == 'file') {
        final FilePickerResult? result = await FilePicker.platform.pickFiles(
          allowMultiple: true,
          type: FileType.any,
        );
        if (result != null) {
          selectedFiles.addAll(
            result.paths.where((p) => p != null).map((p) => File(p!)),
          );
        }
      }

      if (selectedFiles.isNotEmpty) {
        // Process each file with preview dialog
        final List<Map<String, dynamic>> attachments = [];
        
        for (final file in selectedFiles) {
          if (!mounted) break;
          
          final ext = p.extension(file.path).toLowerCase();
          final isImage = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.heif'].contains(ext);
          final isVideo = ['.mp4', '.mov', '.avi', '.mkv', '.webm'].contains(ext);
          
          String mediaType;
          if (isImage) {
            mediaType = 'image';
          } else if (isVideo) {
            mediaType = 'video';
          } else {
            mediaType = 'file';
          }
          
          // Show preview dialog for each file
          final result = await showDialog<Map<String, dynamic>>(
            context: context,
            barrierDismissible: false,
            builder: (context) => MediaPreviewDialog(
              file: file,
              mediaType: mediaType,
              fileName: p.basename(file.path),
              onConfirm: (f, caption) => Navigator.pop(context, {
                'file': f,
                'caption': caption,
              }),
              onCancel: () => Navigator.pop(context, null),
            ),
          );

          if (result != null && result['file'] != null) {
            final f = result['file'] as File;
            final caption = result['caption'] as String?;
            
            attachments.add({
              'path': f.path,
              'type': mediaType,
              'filename': p.basename(f.path),
              if (caption != null && caption.isNotEmpty) 'caption': caption,
            });
          }
        }

        if (attachments.isNotEmpty && mounted) {
          widget.onSend('', customAttachments: attachments);
        }
        setState(() {
          _showAttachments = false;
        });
      }
    } catch (e) {
      debugPrint('Attachment error: $e');
      if (mounted) {
        AnimatedToast.error(context, 'ط­ط¯ط« ط®ط·ط£ ظپظٹ ط¥ط±ظپط§ظ‚ ط§ظ„ظ…ظ„ظپ: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch editing state
    final provider = context.watch<ConversationDetailProvider>();
    if (provider.isEditing && provider.editingMessageId != _lastEditingId) {
      _lastEditingId = provider.editingMessageId;
      _controller.text = provider.editingMessageBody ?? '';
      // Request focus
      Future.microtask(() => _focusNode.requestFocus());
    } else if (!provider.isEditing && _lastEditingId != null) {
      _lastEditingId = null;
      _controller.clear();
      _focusNode.unfocus();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isRtl = Directionality.of(context);
    final isEditing = provider.isEditing;

    // Detect if keyboard is visible to hide custom panels (fail-safe)
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    final effectiveShowEmoji = _showEmoji && !isKeyboardVisible;
    final effectiveShowAttachments = _showAttachments && !isKeyboardVisible;

    return Container(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Reply preview OR Edit Preview (Header)
          if (isEditing)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.scaffoldBackgroundColor,
              child: Row(
                children: [
                  const Icon(
                    SolarLinearIcons.pen,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'طھط¹ط¯ظٹظ„ ط§ظ„ط±ظگظ‘ط³ط§ظ„ط©',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Semantics(
                    label: 'ط¥ظ„ط؛ط§ط، ط§ظ„طھظژظ‘ط¹ط¯ظٹظ„',
                    button: true,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: InkWell(
                        onTap: () {
                          Haptics.lightTap();
                          provider.cancelEditing();
                          _controller.clear();
                        },
                        focusColor: AppColors.primary.withValues(alpha: 0.12),
                        hoverColor: AppColors.primary.withValues(alpha: 0.04),
                        highlightColor: AppColors.primary.withValues(
                          alpha: 0.08,
                        ),
                        borderRadius: BorderRadius.circular(22),
                        child: const Center(
                          child: Icon(
                            SolarLinearIcons.closeCircle,
                            size: 20,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (widget.replyToSender != null && widget.replyToBody != null)
            ReplyPreview(
              senderName: widget.replyToSender!,
              messageBody: widget.replyToBody!,
              isOutgoing: widget.isReplyToOutgoing,
              attachments: widget.replyToAttachments,
              onCancel: () {
                Haptics.lightTap();
                if (widget.onCancelReply != null) widget.onCancelReply!();
              },
            ),

          // Main Input Area
          Container(
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              top: widget.isBottomCompact ? 0 : 8,
              bottom: (widget.isBottomCompact && !isKeyboardVisible)
                  ? 24.0
                  : (isKeyboardVisible
                        ? 8.0
                        : MediaQuery.of(context).padding.bottom + 12.0),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: Container(
                      key: const ValueKey('input'),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.surfaceDark
                            : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: isDark
                              ? Colors.white10
                              : AppColors.borderLight,
                        ),
                      ),
                      child: ListenableBuilder(
                        listenable: _controller,
                        builder: (context, child) {
                          final text = _controller.text;
                          return CompositedTransformTarget(
                            link: _layerLink,
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              minLines: 1,
                              maxLines: 5,
                              textDirection: text.isEmpty
                                  ? TextDirection.rtl
                                  : text.direction,
                              textAlign: (text.isEmpty || text.isArabic)
                                  ? TextAlign.right
                                  : TextAlign.left,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              onChanged: _onTextChanged,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                height: 1.5,
                                color: isDark
                                    ? AppColors.textPrimaryDark
                                    : AppColors.textPrimaryLight,
                              ),
                              decoration: InputDecoration(
                                // Override global theme's fixed 48px height constraint
                                constraints: const BoxConstraints(minHeight: 48),
                                filled: false,
                                hintText: isEditing
                                    ? 'طھط¹ط¯ظٹظ„ ط§ظ„ط±ظگظ‘ط³ط§ظ„ط©...'
                                    : 'ط§ظƒطھط¨ ط±ط³ط§ظ„طھظƒ...',
                                hintStyle: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.normal,
                                  height: 1.5,
                                  color: isDark
                                      ? AppColors.textTertiaryDark
                                      : AppColors.textTertiaryLight,
                                ),
                                prefixIcon: Semantics(
                                  label: _showEmoji
                                      ? 'ط¥ط¸ظ‡ط§ط± ط§ظ„ط±ظ…ظˆط²'
                                      : 'ط¥ط¸ظ‡ط§ط± ط§ظ„ط±ظ…ظˆط²',
                                  button: true,
                                  child: SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: IconButton(
                                      onPressed: _toggleEmoji,
                                      icon: Icon(
                                        _showEmoji
                                            ? SolarLinearIcons.keyboard
                                            : SolarLinearIcons.stickerCircle,
                                        color: _showEmoji
                                            ? AppColors.primary
                                            : theme.hintColor.withValues(
                                                alpha: 0.7,
                                              ),
                                        size: 24,
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      tooltip: _showEmoji
                                          ? 'ط¥ط®ظپط§ط، ط§ظ„ط±ظ…ظˆط²'
                                          : 'ط§ظ„ط±ظ…ظˆط²',
                                    ),
                                  ),
                                ),
                                suffixIcon: Semantics(
                                  label: _showAttachments
                                      ? 'ط¥ط®ظپط§ط، ط§ظ„ظ…ط±ظپظ‚ط§طھ'
                                      : 'ط¥ط¶ط§ظپط© ظ…ط±ظپظ‚',
                                  button: true,
                                  child: SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: IconButton(
                                      onPressed: _toggleAttachments,
                                      icon: Icon(
                                        SolarLinearIcons.paperclip,
                                        color: _showAttachments
                                            ? AppColors.primary
                                            : theme.hintColor.withValues(
                                                alpha: 0.7,
                                              ),
                                        size: 24,
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      tooltip: 'ظ…ط±ظپظ‚ط§طھ',
                                    ),
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Send Button / Edit Save Button
                _buildSendButton(theme, isDark, isRtl, isEditing),
              ],
            ),
          ),

          // Emoji Picker
          if (effectiveShowEmoji)
            SizedBox(
              height: 250,
              child: EmojiPicker(
                textEditingController: _controller,
                config: Config(
                  checkPlatformCompatibility: true,
                  emojiViewConfig: EmojiViewConfig(
                    columns: 7,
                    emojiSizeMax: 28 * (Platform.isIOS ? 1.20 : 1.0),
                    backgroundColor: isDark ? Colors.grey[900]! : Colors.white,
                  ),
                ),
              ),
            ),

          // Attachment Options
          if (effectiveShowAttachments)
            Container(
              height: 250,
              color: isDark ? Colors.grey[900] : Colors.white,
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAttachmentOption(
                    icon: SolarLinearIcons.camera,
                    color: Colors.pink,
                    label: 'ظƒط§ظ…ظٹط±ط§',
                    onTap: () {
                      Haptics.lightTap();
                      _handleAttachmentSelection('camera');
                    },
                  ),
                  _buildAttachmentOption(
                    icon: SolarLinearIcons.gallery,
                    color: Colors.purple,
                    label: 'طµظˆط±',
                    onTap: () {
                      Haptics.lightTap();
                      _handleAttachmentSelection('gallery');
                    },
                  ),
                  _buildAttachmentOption(
                    icon: SolarLinearIcons.file,
                    color: Colors.blue,
                    label: 'ظ…ظ„ظپ',
                    onTap: () {
                      Haptics.lightTap();
                      _handleAttachmentSelection('file');
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSendButton(
    ThemeData theme,
    bool isDark,
    TextDirection isRtl, [
    bool isEditing = false,
  ]) {
    // If Editing, show Save checkmark
    if (isEditing) {
      return Semantics(
        label: 'ط­ظپط¸ ط§ظ„طھظژظ‘ط¹ط¯ظٹظ„',
        button: true,
        child: Container(
          height: 52,
          width: 52,
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                Haptics.lightTap();
                final provider = context.read<ConversationDetailProvider>();
                final inboxProvider = context.read<InboxProvider>();
                final body = _controller.text.trim();

                // Validate before attempting save
                if (body.isEmpty) {
                  AnimatedToast.info(context, 'ظ„ط§ ظٹظ…ظƒظ† ط­ظپط¸ ط±ط³ط§ظ„ط© ظپط§ط±ط؛ط©');
                  provider.cancelEditing();
                  return;
                }

                await provider.saveEditedMessage(body, inboxProvider);
              },
              focusColor: AppColors.primary.withValues(alpha: 0.2),
              hoverColor: AppColors.primary.withValues(alpha: 0.1),
              highlightColor: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(26),
              child: const Center(
                child: Icon(
                  SolarBoldIcons.checkCircle,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Send Button
    return Semantics(
      label: 'ط¥ط±ط³ط§ظ„ ط§ظ„ط±ظگظ‘ط³ط§ظ„ط©',
      button: true,
      child: Container(
        height: 52,
        width: 52,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _handleSendText,
            focusColor: AppColors.primary.withValues(alpha: 0.2),
            hoverColor: AppColors.primary.withValues(alpha: 0.1),
            highlightColor: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(26),
            child: Center(
              child: isRtl == TextDirection.rtl
                  ? const Icon(
                      SolarBoldIcons.plain2,
                      color: Colors.white,
                      size: 24,
                    )
                  : Transform.rotate(
                      angle: 3.14,
                      child: const Icon(
                        SolarBoldIcons.plain2,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: label,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
