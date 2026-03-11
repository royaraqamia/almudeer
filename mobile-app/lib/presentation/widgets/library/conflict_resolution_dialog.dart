/// P1-7: Conflict Resolution Dialog
/// Shows when server version is newer than local version
/// User can choose: Keep Local, Use Server, or Merge

library;

import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/dimensions.dart';
import '../../../core/localization/library_localizations.dart';
import '../../../data/models/library_item.dart';

class ConflictResolutionDialog extends StatelessWidget {
  final LibraryItem localItem;
  final LibraryItem serverItem;
  final VoidCallback onKeepLocal;
  final VoidCallback onUseServer;
  final VoidCallback onMerge;

  const ConflictResolutionDialog({
    super.key,
    required this.localItem,
    required this.serverItem,
    required this.onKeepLocal,
    required this.onUseServer,
    required this.onMerge,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = LibraryLocalizations.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusXXLarge),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.paddingLarge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppDimensions.spacing10),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(
                      AppDimensions.radiusMedium,
                    ),
                  ),
                  child: const Icon(
                    SolarLinearIcons.danger,
                    color: AppColors.warning,
                    size: AppDimensions.iconLarge,
                  ),
                ),
                const SizedBox(width: AppDimensions.spacing12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.conflictDetected,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontFamily: 'IBM Plex Sans Arabic',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        l10n.conflictDescription,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppDimensions.spacing24),

            // Version comparison
            _buildVersionComparison(context, theme, l10n),

            const SizedBox(height: AppDimensions.spacing24),

            // Action buttons
            _buildActionButtons(context, l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildVersionComparison(
    BuildContext context,
    ThemeData theme,
    LibraryLocalizations l10n,
  ) {
    return Container(
      padding: const EdgeInsets.all(AppDimensions.paddingMedium),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
      ),
      child: Column(
        children: [
          // Local version
          _buildVersionRow(
            context,
            label: l10n.localVersion,
            version: localItem.version?.toString() ?? '1',
            updatedAt: localItem.updatedAt,
            isLocal: true,
            l10n: l10n,
          ),

          const SizedBox(height: AppDimensions.spacing12),

          // Server version
          _buildVersionRow(
            context,
            label: l10n.serverVersion,
            version: serverItem.version?.toString() ?? '1',
            updatedAt: serverItem.updatedAt,
            isLocal: false,
            l10n: l10n,
          ),
        ],
      ),
    );
  }

  Widget _buildVersionRow(
    BuildContext context, {
    required String label,
    required String version,
    required DateTime? updatedAt,
    required bool isLocal,
    required LibraryLocalizations l10n,
  }) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          isLocal ? SolarLinearIcons.smartphone : SolarLinearIcons.cloud,
          size: AppDimensions.iconMedium,
          color: isLocal ? AppColors.primary : theme.colorScheme.secondary,
        ),
        const SizedBox(width: AppDimensions.spacing12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'v$version • ${_formatDate(updatedAt)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (isLocal)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.spacing8,
              vertical: AppDimensions.spacing4,
            ),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppDimensions.radiusSmall),
            ),
            child: Text(
              l10n.current,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, LibraryLocalizations l10n) {
    return Column(
      children: [
        // Keep Local (Primary action)
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              onKeepLocal();
            },
            icon: const Icon(SolarLinearIcons.smartphone),
            label: Text(l10n.keepLocalVersion),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                vertical: AppDimensions.paddingMedium,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
              ),
            ),
          ),
        ),

        const SizedBox(height: AppDimensions.spacing12),

        // Use Server
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              onUseServer();
            },
            icon: const Icon(SolarLinearIcons.cloud),
            label: Text(l10n.useServerVersion),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(
                vertical: AppDimensions.paddingMedium,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
              ),
            ),
          ),
        ),

        const SizedBox(height: AppDimensions.spacing12),

        // Merge (Secondary action)
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              onMerge();
            },
            icon: const Icon(SolarLinearIcons.linkRound),
            label: Text(l10n.mergeVersions),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.info,
              padding: const EdgeInsets.symmetric(
                vertical: AppDimensions.paddingMedium,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
