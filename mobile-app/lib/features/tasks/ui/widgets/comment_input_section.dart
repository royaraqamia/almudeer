import 'dart:io';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

import '../../../../core/utils/haptics.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/extensions/string_extension.dart';

/// Comment input section with emoji and attachment support
class CommentInputSection extends StatefulWidget {
  final Future<void> Function(
    String text, {
    List<File>? mediaFiles,
  })
  onSend;

  const CommentInputSection({
    super.key,
    required this.onSend,
  });

  @override
  State<CommentInputSection> createState() => _CommentInputSectionState();
}

class _CommentInputSectionState extends State<CommentInputSection> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  // Sending State
  bool _isSending = false;

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
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSendText() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    // FIX: Prevent double-send and show loading state
    if (_isSending) return;

    Haptics.lightTap();
    _controller.clear();

    try {
      setState(() {
        _isSending = true;
      });

      await widget.onSend(text);
    } catch (_) {
      // Re-enable send on error
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
      rethrow;
    } finally {
      // Always reset sending state
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  void _onTextChanged(String text) {
    setState(() {});
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
    List<File> selectedFiles = [];
    try {
      if (type == 'camera') {
        final XFile? image = await ImagePicker().pickImage(
          source: ImageSource.camera,
          imageQuality: 70,
        );
        if (image != null) selectedFiles.add(File(image.path));
      } else if (type == 'gallery') {
        final List<XFile> images = await ImagePicker().pickMultiImage(
          imageQuality: 70,
        );
        if (images.isNotEmpty) {
          selectedFiles.addAll(images.map((x) => File(x.path)));
        }
      } else if (type == 'file') {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
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
        widget.onSend('', mediaFiles: selectedFiles);
        setState(() {
          _showAttachments = false;
        });
      }
    } catch (e) {
      debugPrint('Attachment error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isRtl = Directionality.of(context);

    // Detect if keyboard is visible to hide custom panels (fail-safe)
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    final effectiveShowEmoji = _showEmoji && !isKeyboardVisible;
    final effectiveShowAttachments = _showAttachments && !isKeyboardVisible;

    return Container(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main Input Area
          Container(
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              top: 8,
              bottom: isKeyboardVisible
                  ? 8.0
                  : MediaQuery.of(context).padding.bottom + 12.0,
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
                          return TextField(
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
                              constraints: const BoxConstraints(
                                minHeight: 48,
                              ),
                              filled: false,
                              hintText: 'أضف تعليقاً...',
                              hintStyle: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.normal,
                                height: 1.5,
                                color: isDark
                                    ? AppColors.textTertiaryDark
                                    : AppColors.textTertiaryLight,
                              ),
                              prefixIcon: Semantics(
                                label: 'إظهار الرموز',
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
                                    tooltip: _showEmoji ? 'إخفاء الرموز' : 'الرموز',
                                  ),
                                ),
                              ),
                              suffixIcon: Semantics(
                                label: 'إضافة مرفق',
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
                                    tooltip: 'مرفقات',
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
                          );
                        },
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Send Button
                _buildSendButton(theme, isDark, isRtl),
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
                    label: 'كاميرا',
                    onTap: () {
                      Haptics.lightTap();
                      _handleAttachmentSelection('camera');
                    },
                  ),
                  _buildAttachmentOption(
                    icon: SolarLinearIcons.gallery,
                    color: Colors.purple,
                    label: 'صور',
                    onTap: () {
                      Haptics.lightTap();
                      _handleAttachmentSelection('gallery');
                    },
                  ),
                  _buildAttachmentOption(
                    icon: SolarLinearIcons.file,
                    color: Colors.blue,
                    label: 'ملف',
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
    TextDirection isRtl,
  ) {
    return Semantics(
      label: 'إرسال التَّعليق',
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
              child: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : isRtl == TextDirection.rtl
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
