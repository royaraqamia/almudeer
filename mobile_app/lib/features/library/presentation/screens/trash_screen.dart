/// Issue #26: Trash Screen
/// Shows soft-deleted items that can be restored or permanently deleted

library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:intl/intl.dart';

import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/constants/dimensions.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';
import 'package:almudeer_mobile_app/features/library/data/models/library_item.dart';
import 'package:almudeer_mobile_app/features/library/presentation/providers/library_provider.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/common_widgets.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  bool _isLoading = true;
  List<LibraryItem> _trashItems = [];
  final Set<int> _selectedItems = {};
  bool _isSelecting = false;

  @override
  void initState() {
    super.initState();
    _loadTrash();
  }

  Future<void> _loadTrash() async {
    setState(() => _isLoading = true);

    try {
      final provider = context.read<LibraryProvider>();
      final items = await provider.getTrashItems();

      setState(() {
        _trashItems = items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ظپط´ظ„ ط¬ظ„ط¨ ط³ظ„ط© ط§ظ„ظ…ظ‡ظ…ظ„ط§طھ: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _restoreItem(LibraryItem item) async {
    Haptics.lightTap();

    try {
      final provider = context.read<LibraryProvider>();
      await provider.restoreFromTrash(item.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(SolarBoldIcons.checkCircle, color: Colors.white),
                const SizedBox(width: 8),
                Text('طھظ… ط§ط³طھط¹ط§ط¯ط© "${item.title}"'),
              ],
            ),
            backgroundColor: AppColors.success,
          ),
        );
        _loadTrash();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ظپط´ظ„ ط§ظ„ط§ط³طھط¹ط§ط¯ط©: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _deletePermanently(LibraryItem item) async {
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ط­ط°ظپ ظ†ظ‡ط§ط¦ظٹ'),
        content: Text(
          'ظ‡ظ„ ط£ظ†طھ ظ…طھط£ظƒط¯ ظ…ظ† ط­ط°ظپ "${item.title}" ظ†ظ‡ط§ط¦ظٹط§ظ‹طں ظ„ط§ ظٹظ…ظƒظ† ط§ظ„طھط±ط§ط¬ط¹ ط¹ظ† ظ‡ط°ط§ ط§ظ„ط¥ط¬ط±ط§ط،.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ط¥ظ„ط؛ط§ط،'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('ط­ط°ظپ'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    Haptics.mediumTap();

    try {
      if (!mounted) return;
      final provider = context.read<LibraryProvider>();
      await provider.deletePermanently(item.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('طھظ… ط­ط°ظپ "${item.title}" ظ†ظ‡ط§ط¦ظٹط§ظ‹'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadTrash();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ظپط´ظ„ ط§ظ„ط­ط°ظپ: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _emptyTrash() async {
    if (_trashItems.isEmpty) return;

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ط¥ظپط±ط§ط؛ ط³ظ„ط© ط§ظ„ظ…ظ‡ظ…ظ„ط§طھ'),
        content: Text(
          'ظ‡ظ„ ط£ظ†طھ ظ…طھط£ظƒط¯ ظ…ظ† ط­ط°ظپ ط¬ظ…ظٹط¹ ط§ظ„ط¹ظ†ط§طµط± (${_trashItems.length}) ظ†ظ‡ط§ط¦ظٹط§ظ‹طں',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ط¥ظ„ط؛ط§ط،'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('ط­ط°ظپ ط§ظ„ظƒظ„'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    Haptics.heavyTap();

    try {
      if (!mounted) return;
      final provider = context.read<LibraryProvider>();
      await provider.emptyTrash();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('طھظ… ط¥ظپط±ط§ط؛ ط³ظ„ط© ط§ظ„ظ…ظ‡ظ…ظ„ط§طھ'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadTrash();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ظپط´ظ„ ط¥ظپط±ط§ط؛ ط§ظ„ط³ظ„ط©: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemCount = _selectedItems.isEmpty
        ? _trashItems.length
        : _selectedItems.length;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          _isSelecting ? '$itemCount' : 'ط³ظ„ط© ط§ظ„ظ…ظ‡ظ…ظ„ط§طھ',
          style: const TextStyle(
            fontFamily: 'IBM Plex Sans Arabic',
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            _isSelecting ? SolarLinearIcons.close : SolarLinearIcons.arrowRight,
            color: theme.colorScheme.onSurface,
          ),
          onPressed: () {
            if (_isSelecting) {
              setState(() {
                _isSelecting = false;
                _selectedItems.clear();
              });
            } else {
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          if (!_isSelecting) ...[
            // Select button
            if (_trashItems.isNotEmpty)
              IconButton(
                icon: const Icon(SolarLinearIcons.checkRead),
                onPressed: () {
                  Haptics.lightTap();
                  setState(() => _isSelecting = true);
                },
              ),
            // Empty trash button
            IconButton(
              icon: const Icon(SolarLinearIcons.trashBinMinimalistic),
              color: AppColors.error,
              onPressed: _trashItems.isNotEmpty ? _emptyTrash : null,
            ),
            // Refresh button
            IconButton(
              icon: const Icon(SolarLinearIcons.refresh),
              onPressed: _loadTrash,
            ),
          ] else ...[
            // Bulk restore
            if (_selectedItems.isNotEmpty)
              IconButton(
                icon: const Icon(SolarLinearIcons.refresh),
                color: AppColors.success,
                onPressed: () async {
                  final provider = context.read<LibraryProvider>();
                  for (final id in _selectedItems) {
                    try {
                      await provider.restoreFromTrash(id);
                    } catch (e) {
                      // Continue with other items
                    }
                  }
                  if (mounted) {
                    setState(() {
                      _isSelecting = false;
                      _selectedItems.clear();
                    });
                    _loadTrash();
                  }
                },
              ),
            // Bulk delete
            if (_selectedItems.isNotEmpty)
              IconButton(
                icon: const Icon(SolarLinearIcons.trashBinMinimalistic),
                color: AppColors.error,
                onPressed: () async {
                  final provider = context.read<LibraryProvider>();
                  for (final id in _selectedItems) {
                    try {
                      await provider.deletePermanently(id);
                    } catch (e) {
                      // Continue with other items
                    }
                  }
                  if (mounted) {
                    setState(() {
                      _isSelecting = false;
                      _selectedItems.clear();
                    });
                    _loadTrash();
                  }
                },
              ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _trashItems.isEmpty
          ? _buildEmptyState(theme)
          : _buildTrashList(theme),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.paddingLarge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            EmptyStateWidget(
              icon: SolarLinearIcons.trashBinMinimalistic,
              iconColor: theme.colorScheme.primary,
            ),
            const SizedBox(height: AppDimensions.spacing24),
            Text(
              'ط³ظ„ط© ط§ظ„ظ…ظ‡ظ…ظ„ط§طھ ظپط§ط±ط؛ط©',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDimensions.spacing8),
            Text(
              'ط§ظ„ط¹ظ†ط§طµط± ط§ظ„ظ…ط­ط°ظˆظپط© ط³طھط¸ظ‡ط± ظ‡ظ†ط§ ظ„ظ…ط¯ط© 30 ظٹظˆظ…ط§ظ‹',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrashList(ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppDimensions.paddingMedium),
      itemCount: _trashItems.length,
      itemBuilder: (context, index) {
        final item = _trashItems[index];
        final isSelected = _selectedItems.contains(item.id);
        final deletedAt = item.deletedAt;

        return Dismissible(
          key: Key('trash-item-${item.id}'),
          direction: DismissDirection.horizontal,
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: AppDimensions.paddingMedium),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
            ),
            child: const Icon(SolarLinearIcons.refresh, color: Colors.white),
          ),
          secondaryBackground: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: AppDimensions.paddingMedium),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
            ),
            child: const Icon(
              SolarLinearIcons.trashBinMinimalistic,
              color: Colors.white,
            ),
          ),
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.startToEnd) {
              await _restoreItem(item);
              return false;
            } else {
              return await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('ط­ط°ظپ ظ†ظ‡ط§ط¦ظٹ'),
                      content: const Text('ظ‡ظ„ ط£ظ†طھ ظ…طھط£ظƒط¯ ظ…ظ† ط§ظ„ط­ط°ظپ ظ†ظ‡ط§ط¦ظٹط§ظ‹طں'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('ط¥ظ„ط؛ط§ط،'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.error,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('ط­ط°ظپ'),
                        ),
                      ],
                    ),
                  ) ??
                  false;
            }
          },
          onDismissed: (direction) {
            if (direction == DismissDirection.endToStart) {
              _deletePermanently(item);
            }
          },
          child: Card(
            margin: const EdgeInsets.only(bottom: AppDimensions.spacing12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
              side: isSelected
                  ? const BorderSide(color: AppColors.primary, width: 2)
                  : BorderSide.none,
            ),
            child: InkWell(
              onTap: _isSelecting
                  ? () {
                      Haptics.lightTap();
                      setState(() {
                        if (_selectedItems.contains(item.id)) {
                          _selectedItems.remove(item.id);
                        } else {
                          _selectedItems.add(item.id);
                        }
                      });
                    }
                  : null,
              borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
              child: Padding(
                padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                child: Row(
                  children: [
                    // Checkbox for selection mode
                    if (_isSelecting) ...[
                      Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary
                              : Colors.transparent,
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : theme.colorScheme.outline,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        width: 24,
                        height: 24,
                        child: isSelected
                            ? const Icon(
                                SolarBoldIcons.check,
                                size: 16,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      const SizedBox(width: AppDimensions.spacing12),
                    ],

                    // Icon based on type
                    Container(
                      padding: const EdgeInsets.all(AppDimensions.spacing10),
                      decoration: BoxDecoration(
                        color: _getItemTypeColor(
                          item.type,
                        ).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(
                          AppDimensions.radiusMedium,
                        ),
                      ),
                      child: Icon(
                        _getItemTypeIcon(item.type),
                        color: _getItemTypeColor(item.type),
                        size: AppDimensions.iconMedium,
                      ),
                    ),

                    const SizedBox(width: AppDimensions.spacing12),

                    // Item info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'ط­ظڈط°ظپ ${_formatDeletedDate(deletedAt)}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Actions
                    if (!_isSelecting) ...[
                      IconButton(
                        icon: const Icon(SolarLinearIcons.refresh),
                        color: AppColors.success,
                        onPressed: () => _restoreItem(item),
                      ),
                      IconButton(
                        icon: const Icon(SolarLinearIcons.trashBinMinimalistic),
                        color: AppColors.error,
                        onPressed: () => _deletePermanently(item),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  IconData _getItemTypeIcon(String? type) {
    switch (type) {
      case 'note':
        return SolarLinearIcons.documentText;
      case 'image':
        return SolarLinearIcons.gallery;
      case 'audio':
        return SolarLinearIcons.musicNote;
      case 'video':
        return SolarLinearIcons.videocamera;
      default:
        return SolarLinearIcons.document;
    }
  }

  Color _getItemTypeColor(String? type) {
    switch (type) {
      case 'note':
        return AppColors.info;
      case 'image':
        return AppColors.primary;
      case 'audio':
        return AppColors.accent;
      case 'video':
        return AppColors.warning;
      default:
        return AppColors.textSecondaryLight;
    }
  }

  String _formatDeletedDate(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'ط§ظ„ظٹظˆظ…';
    } else if (diff.inDays == 1) {
      return 'ط£ظ…ط³';
    } else if (diff.inDays < 7) {
      return 'ظ…ظ†ط° ${diff.inDays} ط£ظٹط§ظ…';
    } else {
      return DateFormat('yyyy/MM/dd').format(date);
    }
  }
}
