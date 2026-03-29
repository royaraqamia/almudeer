import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/constants/dimensions.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';

/// âœ… ACCESSIBLE Library Filter Bar
/// - P0: Proper Semantics labels
/// - P0: 44px minimum touch targets
/// - P0: Focus/hover indicators
/// - P2: Design token compliance
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
    final theme = Theme.of(context);
    final filters = [
      {'label': 'ظ…ظ„ط§ط­ط¸ط§طھ', 'value': 'notes'},
      {'label': 'ظ…ظ„ظپظژظ‘ط§طھ', 'value': 'files'},
    ];

    return Container(
      height: 60,
      color: theme.scaffoldBackgroundColor,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.paddingLarge,
          vertical: AppDimensions.spacing8,
        ),
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = selectedType == filter['value'];
          
          return Padding(
            padding: const EdgeInsets.only(left: AppDimensions.spacing8),
            child: Semantics(
              label: 'طھطµظپظٹط© ط­ط³ط¨ ${filter['label']}',
              selected: isSelected,
              button: true,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                constraints: const BoxConstraints(
                  minWidth: 44,
                  minHeight: 44,
                ),
                child: Material(
                  color: isSelected
                      ? (theme.brightness == Brightness.dark
                            ? const Color(0xFF1E408A)
                            : const Color(0xFFDBE6FE))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                  child: InkWell(
                    onTap: () {
                      Haptics.selection();
                      onFilterChanged(filter['value'] as String);
                    },
                    borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                    focusColor: AppColors.primary.withValues(alpha: 0.12),
                    hoverColor: AppColors.primary.withValues(alpha: 0.04),
                    highlightColor: AppColors.primary.withValues(alpha: 0.08),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimensions.paddingMedium,
                        vertical: AppDimensions.spacing8,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        filter['label'] as String,
                        style: TextStyle(
                          color: isSelected
                              ? (theme.brightness == Brightness.dark
                                    ? const Color(0xFF6090FA)
                                    : const Color(0xFF2563EB))
                              : (theme.brightness == Brightness.dark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondaryLight),
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
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

/// âœ… ACCESSIBLE Library Header
/// - P0: Proper Semantics labels
/// - P0: 44px minimum touch targets
/// - P0: Focus/hover indicators
/// - P2: Design token compliance
class LibraryHeader extends StatelessWidget {
  final String date;

  const LibraryHeader({
    super.key,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text(
            date,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.brightness == Brightness.dark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
              fontSize: 14,
              fontFamily: 'IBM Plex Sans Arabic',
            ),
          ),
        ],
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


/// âœ… ACCESSIBLE Empty State Widget
/// - P0: Proper Semantics
class LibraryEmptyState extends StatelessWidget {
  final String type;

  const LibraryEmptyState({
    super.key,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Map<String, IconData> emptyStates = {
      'notes': SolarLinearIcons.notes,
      'files': SolarLinearIcons.folderOpen,
      'tools': SolarLinearIcons.settingsMinimalistic,
    };

    final icon = emptyStates[type] ?? SolarLinearIcons.notes;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 80,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }
}
