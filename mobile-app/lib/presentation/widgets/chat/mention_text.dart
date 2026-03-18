import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:linkify/linkify.dart';

import '../../../core/constants/colors.dart';

/// A text widget that renders both URLs and @username mentions as clickable spans
class MentionText extends StatelessWidget {
  final String text;
  final List<Map<String, dynamic>>? mentions;
  final TextStyle? style;
  final TextStyle? mentionStyle;
  final TextStyle? linkStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Function(String username)? onMentionTap;
  final Function(String url)? onUrlTap;

  const MentionText({
    super.key,
    required this.text,
    this.mentions,
    this.style,
    this.mentionStyle,
    this.linkStyle,
    this.textAlign,
    this.textDirection,
    this.onMentionTap,
    this.onUrlTap,
  });

  @override
  Widget build(BuildContext context) {
    // Parse the text into linkify elements (URLs, emails, etc.)
    final elements = linkify(
      text,
      options: const LinkifyOptions(
        humanize: false,
        looseUrl: true,
      ),
    );

    // If no mentions, use regular Linkify for URLs only
    if (mentions == null || mentions!.isEmpty) {
      return Linkify(
        text: text,
        onOpen: (link) {
          if (onUrlTap != null) {
            onUrlTap!(link.url);
          }
        },
        options: const LinkifyOptions(
          humanize: false,
          looseUrl: true,
        ),
        textDirection: textDirection,
        textAlign: textAlign ?? TextAlign.left,
        style: style,
        linkStyle: linkStyle ??
            const TextStyle(
              color: AppColors.primary,
              decoration: TextDecoration.underline,
            ),
      );
    }

    // Build rich text with both URLs and mentions
    return _buildRichTextWithLinks(context, elements);
  }

  Widget _buildRichTextWithLinks(BuildContext context, List<LinkifyElement> elements) {
    final spans = <TextSpan>[];
    final mentionMap = <String, Map<String, dynamic>>{};

    // Create a map of username to mention data for quick lookup
    for (var mention in mentions!) {
      final username = mention['username'] as String;
      mentionMap[username] = mention;
    }

    // Pattern to match @mentions - same as task_edit_screen.dart and note_edit_screen.dart
    // Supports both Latin and Arabic characters, 2-32 chars long
    final mentionPattern = RegExp(r'@([a-zA-Z0-9_\u0600-\u06FF\u0750-\u077F-]{2,32})');

    // Process each linkify element
    for (var element in elements) {
      if (element is TextElement) {
        // This is plain text - check for mentions within it
        _addTextWithMentions(
          spans,
          element.text,
          mentionPattern,
          mentionMap,
        );
      } else if (element is UrlElement) {
        // This is a URL - make it clickable
        spans.add(TextSpan(
          text: element.url,
          style: linkStyle ??
              const TextStyle(
                color: AppColors.primary,
                decoration: TextDecoration.underline,
              ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              if (onUrlTap != null) {
                onUrlTap!(element.url);
              }
            },
        ));
      }
    }

    return RichText(
      text: TextSpan(
        style: style?.copyWith(color: style?.color ?? Colors.black),
        children: spans,
      ),
      textAlign: textAlign ?? TextAlign.left,
      textDirection: textDirection,
    );
  }

  void _addTextWithMentions(
    List<TextSpan> spans,
    String text,
    RegExp mentionPattern,
    Map<String, Map<String, dynamic>> mentionMap,
  ) {
    final matches = mentionPattern.allMatches(text);
    int lastEnd = 0;

    for (var match in matches) {
      // Add text before the mention
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }

      // Add the mention as a clickable span
      final username = match.group(1)!;
      spans.add(TextSpan(
        text: '@$username',
        style: mentionStyle ??
            const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.primary,
            ),
        recognizer: TapGestureRecognizer()
          ..onTap = () {
            if (onMentionTap != null) {
              onMentionTap!(username);
            }
          },
      ));

      lastEnd = match.end;
    }

    // Add remaining text after the last mention
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
  }
}
