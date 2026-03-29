import 'package:flutter/material.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';

class LibraryFilterBar extends StatelessWidget {
  final String selectedType;
  final Function(String) onFilterChanged;

  const LibraryFilterBar({
    super.key,
    required this.selectedType,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final filters = [
      {'label': 'ظ…ظ„ط§ط­ط¸ط§طھ', 'value': 'notes'},
      {'label': 'ظ…ظ„ظپظژظ‘ط§طھ', 'value': 'files'},
    ];

    return Container(
      height: 60,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = selectedType == filter['value'];
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Semantics(
              label: 'طھطµظپظٹط© ط­ط³ط¨ ${filter['label']}',
              selected: isSelected,
              button: true,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 32,
                child: Material(
                  color: isSelected
                      ? (Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF1E408A)
                            : const Color(0xFFDBE6FE))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    onTap: () {
                      Haptics.selection();
                      onFilterChanged(filter['value'] as String);
                    },
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      child: Text(
                        filter['label'] as String,
                        style: TextStyle(
                          color: isSelected
                              ? (Theme.of(context).brightness == Brightness.dark
                                    ? const Color(0xFF6090FA)
                                    : const Color(0xFF2563EB))
                              : (Theme.of(context).brightness == Brightness.dark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondaryLight),
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          fontFamily: 'IBM Plex Sans Arabic',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class LibraryHeader extends StatelessWidget {
  final String date;

  const LibraryHeader({
    super.key,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Text(
        date,
        style: theme.textTheme.bodySmall?.copyWith(
          color: isDark
              ? AppColors.textSecondaryDark
              : AppColors.textSecondaryLight,
          fontSize: 14,
          fontFamily: 'IBM Plex Sans Arabic',
        ),
      ),
    );
  }
}

class FilterHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  FilterHeaderDelegate({required this.child});

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  double get maxExtent => 60;

  @override
  double get minExtent => 60;

  @override
  bool shouldRebuild(covariant FilterHeaderDelegate oldDelegate) {
    return true;
  }
}


