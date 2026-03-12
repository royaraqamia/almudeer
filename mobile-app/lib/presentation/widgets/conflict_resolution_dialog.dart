import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/dimensions.dart';
import '../../../core/localization/library_localizations.dart';
import '../../../data/models/library_item.dart';

/// P1-5: Conflict resolution dialog for version conflicts
///
/// Shown when local changes conflict with server version.
/// Gives user three options:
/// 1. Keep Local - Preserve local changes, discard server version
/// 2. Use Server - Accept server version, discard local changes
/// 3. Merge - Combine both versions (for text content)
class ConflictResolutionDialog extends StatelessWidget {
  final LibraryItem localItem;
  final LibraryItem serverItem;
  final String? conflictReason;

  const ConflictResolutionDialog({
    super.key,
    required this.localItem,
    required this.serverItem,
    this.conflictReason,
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
            // Header with icon
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppDimensions.spacing10),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
                  ),
                  child: const Icon(
                    SolarLinearIcons.infoCircle,
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
                        l10n.conflictTitle,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontFamily: 'IBM Plex Sans Arabic',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (conflictReason != null) ...[
                        const SizedBox(height: AppDimensions.spacing4),
                        Text(
                          conflictReason!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppDimensions.spacing24),

            // Conflict description
            Text(
              l10n.conflictDescription,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: AppDimensions.spacing24),

            // Version comparison
            _buildVersionComparison(context),

            const SizedBox(height: AppDimensions.spacing24),

            // Action buttons
            _buildActionButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildVersionComparison(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = LibraryLocalizations.of(context);

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
            timestamp: localItem.updatedAt,
            content: localItem.content ?? localItem.title,
            isLocal: true,
          ),

          const SizedBox(height: AppDimensions.spacing16),

          // VS divider
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacing12),
                child: Text(
                  'VS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),

          const SizedBox(height: AppDimensions.spacing16),

          // Server version
          _buildVersionRow(
            context,
            label: l10n.serverVersion,
            timestamp: serverItem.updatedAt,
            content: serverItem.content ?? serverItem.title,
            isLocal: false,
          ),
        ],
      ),
    );
  }

  Widget _buildVersionRow(
    BuildContext context, {
    required String label,
    required DateTime timestamp,
    required String content,
    required bool isLocal,
  }) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isLocal ? SolarBoldIcons.documentText : SolarBoldIcons.cloud,
          size: AppDimensions.iconMedium,
          color: isLocal ? AppColors.primary : AppColors.info,
        ),
        const SizedBox(width: AppDimensions.spacing10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppDimensions.spacing4),
              Text(
                _formatTimestamp(timestamp),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppDimensions.spacing8),
              Container(
                padding: const EdgeInsets.all(AppDimensions.spacing8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
                ),
                child: Text(
                  _truncateContent(content),
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = LibraryLocalizations.of(context);

    return Column(
      children: [
        // Keep Local button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop('keep_local'),
            icon: const Icon(SolarLinearIcons.documentText),
            label: Text(l10n.keepLocal),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                vertical: AppDimensions.spacing12,
              ),
            ),
          ),
        ),

        const SizedBox(height: AppDimensions.spacing10),

        // Use Server button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop('use_server'),
            icon: const Icon(SolarLinearIcons.cloud),
            label: Text(l10n.useServer),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.info,
              padding: const EdgeInsets.symmetric(
                vertical: AppDimensions.spacing12,
              ),
            ),
          ),
        ),

        const SizedBox(height: AppDimensions.spacing10),

        // Merge button (only for notes)
        if (localItem.type == 'note')
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).pop('merge'),
              icon: const Icon(SolarBoldIcons.documentText),
              label: Text(l10n.mergeVersions),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(
                  vertical: AppDimensions.spacing12,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'الآن';
    } else if (difference.inHours < 1) {
      return 'منذ ${difference.inMinutes} دقيقة';
    } else if (difference.inDays < 1) {
      return 'منذ ${difference.inHours} ساعة';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }

  String _truncateContent(String content) {
    if (content.length > 100) {
      return '${content.substring(0, 100)}...';
    }
    return content;
  }
}
