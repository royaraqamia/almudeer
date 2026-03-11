/// P3-13: Version History Screen
/// Shows version history for a library item
/// Allows viewing and restoring previous versions

library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/dimensions.dart';
import '../../../data/models/library_item.dart';
import '../../providers/library_provider.dart';
import '../../widgets/common_widgets.dart';

class VersionHistoryScreen extends StatefulWidget {
  final LibraryItem item;

  const VersionHistoryScreen({super.key, required this.item});

  @override
  State<VersionHistoryScreen> createState() => _VersionHistoryScreenState();
}

class _VersionHistoryScreenState extends State<VersionHistoryScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _versions = [];
  int? _restoringVersionId;

  @override
  void initState() {
    super.initState();
    _loadVersions();
  }

  Future<void> _loadVersions() async {
    setState(() => _isLoading = true);
    
    try {
      final provider = context.read<LibraryProvider>();
      final versions = await provider.getItemVersions(widget.item.id);
      
      setState(() {
        _versions = versions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل جلب سجل الإصدارات: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _restoreVersion(int versionId, int versionNumber) async {
    if (!mounted) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('استعادة الإصدار'),
        content: Text('هل أنت متأكد من استعادة الإصدار #$versionNumber؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('استعادة'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _restoringVersionId = versionId);

    try {
      if (!mounted) return;
      final provider = context.read<LibraryProvider>();
      await provider.restoreVersion(widget.item.id, versionId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(SolarBoldIcons.checkCircle, color: Colors.white),
                const SizedBox(width: 8),
                Text('تم استعادة الإصدار #$versionNumber بنجاح'),
              ],
            ),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true); // Return to previous screen
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل استعادة الإصدار: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() => _restoringVersionId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'سجل الإصدارات',
          style: TextStyle(
            fontFamily: 'IBM Plex Sans Arabic',
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            SolarLinearIcons.arrowRight,
            color: theme.colorScheme.onSurface,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _versions.isEmpty
              ? _buildEmptyState(theme)
              : _buildVersionsList(theme),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return EmptyStateWidget(
      icon: SolarLinearIcons.history,
      iconColor: theme.colorScheme.primary,
    );
  }

  Widget _buildVersionsList(ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppDimensions.paddingMedium),
      itemCount: _versions.length,
      itemBuilder: (context, index) {
        final version = _versions[index];
        final isCurrentVersion = index == 0;
        final isRestoring = _restoringVersionId == version['id'];

        return Card(
          margin: const EdgeInsets.only(bottom: AppDimensions.spacing12),
          elevation: isCurrentVersion ? 2 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
            side: isCurrentVersion
                ? BorderSide(color: AppColors.primary, width: 2)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: isRestoring || isCurrentVersion
                ? null
                : () => _restoreVersion(version['id'], version['version']),
            borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
            child: Padding(
              padding: const EdgeInsets.all(AppDimensions.paddingMedium),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Version badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimensions.spacing8,
                          vertical: AppDimensions.spacing4,
                        ),
                        decoration: BoxDecoration(
                          color: isCurrentVersion
                              ? AppColors.primary
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(AppDimensions.radiusSmall),
                        ),
                        child: Text(
                          'v${version['version']}',
                          style: TextStyle(
                            color: isCurrentVersion
                                ? Colors.white
                                : theme.colorScheme.onSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: AppDimensions.spacing12),
                      
                      // Timestamp
                      Expanded(
                        child: Text(
                          _formatDate(version['created_at']),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      
                      // Restore button
                      if (!isCurrentVersion && !isRestoring)
                        IconButton(
                          icon: const Icon(SolarLinearIcons.refresh),
                          color: AppColors.primary,
                          onPressed: () => _restoreVersion(
                            version['id'],
                            version['version'],
                          ),
                        ),
                      
                      if (isRestoring)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      
                      if (isCurrentVersion)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppDimensions.spacing8,
                            vertical: AppDimensions.spacing4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(AppDimensions.radiusSmall),
                          ),
                          child: const Text(
                            'حالي',
                            style: TextStyle(
                              color: AppColors.success,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  
                  if (version['change_summary'] != null) ...[
                    const SizedBox(height: AppDimensions.spacing8),
                    Text(
                      version['change_summary'],
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  
                  if (version['created_by'] != null) ...[
                    const SizedBox(height: AppDimensions.spacing4),
                    Row(
                      children: [
                        Icon(
                          SolarLinearIcons.user,
                          size: AppDimensions.iconSmall,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppDimensions.spacing4),
                        Text(
                          version['created_by'],
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return '';
    final dateTime = date is DateTime ? date : DateTime.parse(date.toString());
    return DateFormat('yyyy/MM/dd HH:mm').format(dateTime);
  }
}
