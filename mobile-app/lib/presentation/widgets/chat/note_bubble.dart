import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:figma_squircle/figma_squircle.dart';
import '../../../core/extensions/string_extension.dart';
import '../../../core/constants/colors.dart';
import '../../providers/library_provider.dart';
import '../../widgets/animated_toast.dart';

class NoteBubble extends StatelessWidget {
  final Map<String, dynamic> noteData;
  final bool isOutgoing;
  final Color color;

  const NoteBubble({
    super.key,
    required this.noteData,
    required this.isOutgoing,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Robust key mapping for both local optimistic data and server response
    final title =
        noteData['title']?.toString() ??
        noteData['name']?.toString() ??
        noteData['NoteTitle']?.toString() ??
        noteData['note_title']?.toString() ??
        'ملاحظة';
    final content =
        noteData['content']?.toString() ??
        noteData['body']?.toString() ??
        noteData['NoteContent']?.toString() ??
        noteData['note_content']?.toString() ??
        '';

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),  // Reduced from 7 for better text readability
        child: Container(
          width: 280,
          margin: const EdgeInsets.only(bottom: 4),
          decoration: ShapeDecoration(
            color: isOutgoing
                ? color.withValues(alpha: 0.15)
                : (isDark
                      ? AppColors.hoverDark
                      : AppColors.hoverLight),
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(
                cornerRadius: 16,
                cornerSmoothing: 1,
              ),
              side: BorderSide(
                color: isOutgoing
                    ? Colors.white.withValues(alpha: 0.1)
                    : (isDark
                          ? Colors.white.withValues(alpha: 0.08)  // Increased from 0.05 for better definition
                          : Colors.black.withValues(alpha: 0.08)),
                width: 0.5,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with Gradient
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      isOutgoing
                          ? Colors.white.withValues(alpha: 0.1)
                          : color.withValues(alpha: 0.1),
                      Colors.transparent,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: isOutgoing
                          ? Colors.white.withValues(alpha: 0.1)
                          : (isDark
                                ? Colors.white.withValues(alpha: 0.08)  // Increased from 0.05
                                : Colors.black.withValues(alpha: 0.08)),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: (isOutgoing ? Colors.white : color).withValues(
                          alpha: 0.2,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        SolarBoldIcons.notes,
                        size: 14,
                        color: isOutgoing ? Colors.white : color,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title.isNotEmpty ? title : 'ملاحظة',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: isOutgoing
                              ? Colors.white
                              : theme.colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!isOutgoing)
                      _SaveToLibraryButton(title: title, content: content),
                  ],
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  content.safeUtf16,
                  textDirection: content.direction,
                  textAlign: content.isArabic
                      ? TextAlign.right
                      : TextAlign.left,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isOutgoing
                        ? Colors.white.withValues(alpha: 0.9)
                        : theme.textTheme.bodySmall?.color,
                    height: 1.4,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaveToLibraryButton extends StatefulWidget {
  final String title;
  final String content;

  const _SaveToLibraryButton({required this.title, required this.content});

  @override
  State<_SaveToLibraryButton> createState() => _SaveToLibraryButtonState();
}

class _SaveToLibraryButtonState extends State<_SaveToLibraryButton> {
  bool _isSaved = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _isSaved
          ? null
          : () async {
              try {
                await context.read<LibraryProvider>().addNote(
                  widget.title,
                  widget.content,
                );
                if (mounted) {
                  setState(() {
                    _isSaved = true;
                  });
                  if (context.mounted) {
                    AnimatedToast.success(context, 'تم الحفظ في المكتبة');
                  }
                }
              } catch (e) {
                if (mounted && context.mounted) {
                  AnimatedToast.error(context, 'فشل الحفظ: $e');
                }
              }
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _isSaved
              ? AppColors.success.withValues(alpha: 0.2)
              : AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isSaved ? SolarBoldIcons.checkCircle : SolarBoldIcons.import,
              size: 12,
              color: _isSaved ? AppColors.success : AppColors.primary,
            ),
            const SizedBox(width: 4),
            Text(
              _isSaved ? 'تم' : 'حفظ',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: _isSaved ? AppColors.success : AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
