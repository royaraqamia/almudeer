import 'package:flutter/widgets.dart' show TextDirection;
import 'package:intl/intl.dart' show Bidi;
import '../api/endpoints.dart';

extension StringExtension on String {
  /// Fixes malformed UTF-16 strings (e.g. unpaired surrogates) that cause
  /// "Invalid argument(s): string is not well-formed UTF-16" crashes in Flutter's Text widget.
  String get safeUtf16 {
    bool hasIssue = false;
    final units = codeUnits;
    for (int i = 0; i < units.length; i++) {
      final u = units[i];
      if (u >= 0xD800 && u <= 0xDBFF) {
        // High surrogate
        if (i + 1 < units.length) {
          final next = units[i + 1];
          if (next >= 0xDC00 && next <= 0xDFFF) {
            // Valid pair, skip next
            i++;
            continue;
          }
        }
        hasIssue = true;
        break;
      } else if (u >= 0xDC00 && u <= 0xDFFF) {
        // Low surrogate without preceding high
        hasIssue = true;
        break;
      }
    }

    if (!hasIssue) return this;

    final buffer = StringBuffer();
    for (int i = 0; i < units.length; i++) {
      final u = units[i];
      if (u >= 0xD800 && u <= 0xDBFF) {
        // High surrogate
        if (i + 1 < units.length) {
          final next = units[i + 1];
          if (next >= 0xDC00 && next <= 0xDFFF) {
            // Valid pair
            buffer.writeCharCode(u);
            buffer.writeCharCode(next);
            i++;
            continue;
          }
        }
        // Invalid high surrogate
        buffer.write('\uFFFD');
      } else if (u >= 0xDC00 && u <= 0xDFFF) {
        // Low surrogate (unpaired because paired ones are skipped above)
        buffer.write('\uFFFD');
      } else {
        buffer.writeCharCode(u);
      }
    }
    return buffer.toString();
  }

  /// Converts Eastern Arabic numerals (٠-٩) to Western numerals (0-9)
  String get toEnglishNumbers {
    const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

    String result = this;
    for (int i = 0; i < arabic.length; i++) {
      result = result.replaceAll(arabic[i], english[i]);
    }
    return result;
  }

  /// Converts relative server paths (e.g. /static/uploads/...) to full URLs
  String get toFullUrl {
    if (isEmpty) return this;
    if (startsWith('http://') ||
        startsWith('https://') ||
        startsWith('data:')) {
      return this;
    }

    // Normalize baseUrl and path to avoid double slashes
    final baseUrl = Endpoints.baseUrl.endsWith('/')
        ? Endpoints.baseUrl.substring(0, Endpoints.baseUrl.length - 1)
        : Endpoints.baseUrl;
    final path = startsWith('/') ? substring(1) : this;

    return '$baseUrl/$path';
  }

  /// Returns true if the string has any RTL characters
  bool get isArabic {
    if (isEmpty) return false;
    return Bidi.hasAnyRtl(this);
  }

  /// Returns TextDirection.rtl if the string is Arabic, otherwise TextDirection.ltr
  TextDirection get direction =>
      isArabic ? TextDirection.rtl : TextDirection.ltr;
}
