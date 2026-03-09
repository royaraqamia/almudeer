import 'package:hijri/hijri_calendar.dart';
import 'package:intl/intl.dart';
import 'string_extension.dart';

extension DateTimeExtension on DateTime {
  /// Formats the date for conversation headers (e.g., "Today", "Yesterday", or Hijri date)
  String toConversationHeaderString() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final checkDate = DateTime(year, month, day);

    if (checkDate == today) {
      return 'اليوم';
    } else if (checkDate == yesterday) {
      return 'أمس';
    } else {
      HijriCalendar.setLocal('en');
      final hijriDate = HijriCalendar.fromDate(this);
      return hijriDate.toFormat("dd/mm/yyyy").toEnglishNumbers;
    }
  }

  /// Formats time only (e.g., "٢:٣٠ م") — used in message bubbles
  String toTimeString() {
    return DateFormat.jm('ar_AE').format(toLocal()).toEnglishNumbers;
  }

  /// Formats for inbox tile: today → time, yesterday → "أمس", else → Hijri date
  String toInboxTimeString() {
    final localDate = toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(localDate.year, localDate.month, localDate.day);

    if (msgDate == today) {
      return DateFormat.jm('ar_AE').format(localDate).toEnglishNumbers;
    } else if (msgDate == today.subtract(const Duration(days: 1))) {
      return 'أمس';
    } else {
      HijriCalendar.setLocal('en');
      final hijri = HijriCalendar.fromDate(localDate);
      return hijri.toFormat("dd/mm/yyyy").toEnglishNumbers;
    }
  }
}

extension ServerDateParsing on String {
  /// Parses a server date string, treating timezone-unaware strings as UTC
  DateTime parseServerDate() {
    var date = DateTime.parse(this);
    if (!endsWith('Z') && !contains('+')) {
      date = DateTime.utc(
        date.year,
        date.month,
        date.day,
        date.hour,
        date.minute,
        date.second,
      );
    }
    return date;
  }
}
