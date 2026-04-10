import 'package:flutter/material.dart';
import 'package:hijri/hijri_calendar.dart';

import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/widgets/app_gradient_button.dart';

class HijriDatePickerDialog extends StatefulWidget {
  final HijriCalendar? initialDate;
  final HijriCalendar? firstDate;
  final HijriCalendar? lastDate;
  final ValueChanged<HijriCalendar>? onDateSelected;

  const HijriDatePickerDialog({
    super.key,
    this.initialDate,
    this.firstDate,
    this.lastDate,
    this.onDateSelected,
  });

  @override
  State<HijriDatePickerDialog> createState() => _HijriDatePickerDialogState();
}

class _HijriDatePickerDialogState extends State<HijriDatePickerDialog> {
  late HijriCalendar _selectedDate;
  late int _selectedDay;
  late int _selectedMonth;
  late int _selectedYear;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? HijriCalendar.now();
    _selectedDay = _selectedDate.hDay;
    _selectedMonth = _selectedDate.hMonth;
    _selectedYear = _selectedDate.hYear;
    HijriCalendar.setLocal('ar');
  }

  void _updateDate() {
    // FIX: Create new HijriCalendar object instead of modifying now()
    // Using HijriCalendar.now() and then modifying properties can cause
    // incorrect date calculations because the internal state is based on
    // the current date
    final newDate = HijriCalendar()
      ..hYear = _selectedYear
      ..hMonth = _selectedMonth
      ..hDay = _selectedDay;

    // Validate day count for month
    if (newDate.isValid()) {
      setState(() {
        _selectedDate = newDate;
      });
    } else {
      // Adjust day if invalid (e.g. 30th in a 29-day month)
      setState(() {
        _selectedDay = newDate.lengthOfMonth;
        _selectedDate = HijriCalendar()
          ..hYear = _selectedYear
          ..hMonth = _selectedMonth
          ..hDay = _selectedDay;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Generate years list
    final currentYear = HijriCalendar.now().hYear;
    final startYear = widget.firstDate?.hYear ?? currentYear - 5;
    final endYear = widget.lastDate?.hYear ?? currentYear + 5;
    final years = List.generate(
      endYear - startYear + 1,
      (index) => startYear + index,
    );

    // Generate days
    final daysInMonth = _selectedDate.lengthOfMonth;
    final days = List.generate(daysInMonth, (index) => index + 1);

    // Months names
    final months = List.generate(12, (index) {
      final temp = HijriCalendar.now()..hMonth = index + 1;
      return {'index': index + 1, 'name': temp.toFormat('MMMM')};
    });

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        const Text(
          'ط§ط®طھط± ط§ظ„طھظ‘ظژط§ط±ظٹط® ط§ظ„ظ‡ط¬ط±ظٹ',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            _selectedDate.toFormat('DD, dd MMMM yyyy'),
            style: const TextStyle(
              fontSize: 18,
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            // Day
            Expanded(
              flex: 2,
              child: _buildDropdown<int>(
                value: _selectedDay,
                items: days,
                label: (day) => day.toString(),
                onChanged: (val) {
                  if (val != null) {
                    _selectedDay = val;
                    _updateDate();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            // Month
            Expanded(
              flex: 3,
              child: _buildDropdown<int>(
                value: _selectedMonth,
                items: months.map((m) => m['index'] as int).toList(),
                label: (mIndex) =>
                    months.firstWhere((m) => m['index'] == mIndex)['name']
                        as String,
                onChanged: (val) {
                  if (val != null) {
                    _selectedMonth = val;
                    _updateDate();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            // Year
            Expanded(
              flex: 2,
              child: _buildDropdown<int>(
                value: _selectedYear,
                items: years,
                label: (year) => year.toString(),
                onChanged: (val) {
                  if (val != null) {
                    _selectedYear = val;
                    _updateDate();
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('ط¥ظ„ط؛ط§ط،', style: TextStyle()),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: AppGradientButton(
                text: 'طھط£ظƒظٹط¯',
                onPressed: () {
                  if (widget.onDateSelected != null) {
                    widget.onDateSelected!(_selectedDate);
                  }
                  Navigator.of(context).pop(_selectedDate);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required List<T> items,
    required String Function(T) label,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          items: items
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(
                    label(item),
                    style: const TextStyle(fontSize: 14),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
