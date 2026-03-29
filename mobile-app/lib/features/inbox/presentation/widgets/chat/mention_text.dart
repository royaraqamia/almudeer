import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:linkify/linkify.dart';

import 'package:almudeer_mobile_app/core/constants/colors.dart';

/// A text widget that renders both URLs and @username mentions as clickable spans
class MentionText extends StatelessWidget {
  final String text;
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
    // First, process mentions manually
    final mentionPattern = RegExp(r'@([a-zA-Z0-9_\u0600-\u06FF\u0750-\u077F-]{2,32})');
    final mentions = mentionPattern.allMatches(text);

    // Decode HTML entities first
    final decodedText = _decodeHtmlEntities(text);
    
    // If no mentions, use simple URL detection
    if (mentions.isEmpty) {
      return _buildSimpleTextWithUrls(context, decodedText);
    }

    // Has mentions - use custom rich text
    return _buildRichTextWithMentions(context, mentionPattern, decodedText);
  }

  /// Simple text with URL detection for text without mentions
  Widget _buildSimpleTextWithUrls(BuildContext context, String textToParse) {
    // URL pattern - matches http, https, and domain-only URLs
    final urlPattern = RegExp(
      r'(https?://)?([a-zA-Z0-9][-a-zA-Z0-9]*\.)+[a-zA-Z]{2,}(/[^\s]*)?',
      caseSensitive: false,
    );

    final matches = urlPattern.allMatches(textToParse);

    if (matches.isEmpty) {
      // No URLs, just return regular text
      return Text(
        textToParse,
        style: style,
        textAlign: textAlign,
        textDirection: textDirection ?? TextDirection.ltr,
      );
    }

    // Build a list of widgets (Text and GestureDetector for URLs)
    final List<InlineSpan> spans = [];
    int lastEnd = 0;

    for (var match in matches) {
      // Add text before the URL
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: textToParse.substring(lastEnd, match.start),
          style: style,
        ));
      }

      // Add the URL as a clickable span
      final String url = match.group(0)!;
      String displayUrl = url;
      
      // Remove protocol for display
      if (displayUrl.startsWith('http://')) {
        displayUrl = displayUrl.substring(7);
      } else if (displayUrl.startsWith('https://')) {
        displayUrl = displayUrl.substring(8);
      }

      // Ensure URL has protocol for navigation
      String navigableUrl = url;
      if (!navigableUrl.startsWith('http://') && !navigableUrl.startsWith('https://')) {
        navigableUrl = 'https://$navigableUrl';
      }

      // Create URL style - same color as regular text but with underline
      final urlStyle = TextStyle(
        color: style?.color, // Use same color as parent text
        decoration: TextDecoration.underline,
        fontSize: style?.fontSize ?? 15,
        fontWeight: style?.fontWeight ?? FontWeight.normal,
        fontFamily: style?.fontFamily ?? 'IBM Plex Sans Arabic',
        height: style?.height ?? 1.5,
        letterSpacing: style?.letterSpacing,
      );

      spans.add(TextSpan(
        text: displayUrl,
        style: urlStyle,
        recognizer: TapGestureRecognizer()
          ..onTap = () {
            if (onUrlTap != null) {
              onUrlTap!(navigableUrl);
            }
          },
      ));

      lastEnd = match.end;
    }

    // Add remaining text after the last URL
    if (lastEnd < textToParse.length) {
      spans.add(TextSpan(
        text: textToParse.substring(lastEnd),
        style: style,
      ));
    }

    // Use RichText with explicit text style
    return RichText(
      text: TextSpan(
        style: TextStyle(
          color: style?.color ?? Colors.black, // Ensure base color is set
          fontSize: style?.fontSize ?? 15,
          fontFamily: style?.fontFamily ?? 'IBM Plex Sans Arabic',
          height: style?.height ?? 1.5,
        ),
        children: spans,
      ),
      textAlign: textAlign ?? TextAlign.left,
      textDirection: textDirection ?? TextDirection.ltr,
      textWidthBasis: TextWidthBasis.parent,
    );
  }

  /// Custom rich text builder for text with mentions
  Widget _buildRichTextWithMentions(BuildContext context, RegExp mentionPattern, String decodedText) {
    // Parse the decoded text into linkify elements
    final elements = linkify(
      decodedText,
      options: const LinkifyOptions(
        humanize: false,
        looseUrl: true,
      ),
    );

    final spans = <TextSpan>[];

    // Process each linkify element
    for (var element in elements) {
      if (element is TextElement) {
        // This is plain text - check for mentions within it
        _addTextWithMentions(
          spans,
          element.text,
          mentionPattern,
        );
      } else if (element is UrlElement) {
        // This is a URL - make it clickable
        final url = element.url;

        // Remove protocol prefix for cleaner display
        String displayText = url;
        if (displayText.startsWith('http://')) {
          displayText = displayText.substring(7);
        } else if (displayText.startsWith('https://')) {
          displayText = displayText.substring(8);
        }

        spans.add(TextSpan(
          text: displayText,
          style: linkStyle ??
              TextStyle(
                color: style?.color, // Use same color as parent text
                decoration: TextDecoration.underline,
                fontSize: style?.fontSize,
                fontWeight: style?.fontWeight,
                fontFamily: style?.fontFamily,
                height: style?.height,
              ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              if (onUrlTap != null) {
                onUrlTap!(url);
              }
            },
        ));
      }
    }

    return RichText(
      text: TextSpan(
        style: style,
        children: spans,
      ),
      textAlign: textAlign ?? TextAlign.left,
      textDirection: textDirection ?? TextDirection.ltr,
      textWidthBasis: TextWidthBasis.parent,
    );
  }

  /// Decode HTML entities in URLs (e.g., &amp; -> &, &lt; -> <, etc.)
  String _decodeHtmlEntities(String url) {
    return url
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
  }

  void _addTextWithMentions(
    List<TextSpan> spans,
    String text,
    RegExp mentionPattern,
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
