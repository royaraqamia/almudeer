import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/dimensions.dart';
import '../../providers/library_provider.dart';
import '../../widgets/common_widgets.dart';
import 'widgets/library_item_card.dart';

/// P3-14: Screen showing items shared with the current user
class SharedWithMeScreen extends StatefulWidget {
  const SharedWithMeScreen({super.key});

  @override
  State<SharedWithMeScreen> createState() => _SharedWithMeScreenState();
}

class _SharedWithMeScreenState extends State<SharedWithMeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedPermission;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSharedItems();
  }

  Future<void> _loadSharedItems() async {
    final provider = context.read<LibraryProvider>();
    await provider.fetchSharedWithMe(permission: _selectedPermission);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<LibraryProvider>();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'شارك معي',
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
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
          indicatorColor: AppColors.primary,
          dividerColor: Colors.transparent,
          labelStyle: const TextStyle(
            fontFamily: 'IBM Plex Sans Arabic',
            fontWeight: FontWeight.bold,
          ),
          unselectedLabelStyle: const TextStyle(
            fontFamily: 'IBM Plex Sans Arabic',
          ),
          tabs: const [
            Tab(text: 'الكل'),
            Tab(text: 'قراءة فقط'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              SolarLinearIcons.refresh,
              color: theme.colorScheme.onSurface,
            ),
            onPressed: _loadSharedItems,
          ),
        ],
      ),
      body: Column(
        children: [
          // Permission filter chips
          Container(
            padding: const EdgeInsets.all(AppDimensions.paddingMedium),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip(
                    context,
                    label: 'الكل',
                    isSelected: _selectedPermission == null,
                    onSelected: () {
                      setState(() => _selectedPermission = null);
                      _loadSharedItems();
                    },
                  ),
                  const SizedBox(width: AppDimensions.spacing8),
                  _buildFilterChip(
                    context,
                    label: 'قراءة فقط',
                    isSelected: _selectedPermission == 'read',
                    onSelected: () {
                      setState(() => _selectedPermission = 'read');
                      _loadSharedItems();
                    },
                  ),
                  const SizedBox(width: AppDimensions.spacing8),
                  _buildFilterChip(
                    context,
                    label: 'تعديل',
                    isSelected: _selectedPermission == 'edit',
                    onSelected: () {
                      setState(() => _selectedPermission = 'edit');
                      _loadSharedItems();
                    },
                  ),
                  const SizedBox(width: AppDimensions.spacing8),
                  _buildFilterChip(
                    context,
                    label: 'مدير',
                    isSelected: _selectedPermission == 'admin',
                    onSelected: () {
                      setState(() => _selectedPermission = 'admin');
                      _loadSharedItems();
                    },
                  ),
                ],
              ),
            ),
          ),

          // Content
          Expanded(
            child: provider.isLoadingShared
                ? const Center(child: CircularProgressIndicator())
                : provider.sharedItems.isEmpty
                    ? _buildEmptyState(theme)
                    : _buildItemsGrid(provider, theme),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    BuildContext context, {
    required String label,
    required bool isSelected,
    required VoidCallback onSelected,
  }) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: Semantics(
        label: 'تصفية حسب $label',
        selected: isSelected,
        button: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onSelected,
            borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
            focusColor: AppColors.primary.withValues(alpha: 0.12),
            hoverColor: AppColors.primary.withValues(alpha: 0.04),
            highlightColor: AppColors.primary.withValues(alpha: 0.08),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              constraints: const BoxConstraints(
                minWidth: 44,
                minHeight: 44,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.paddingMedium,
                vertical: AppDimensions.spacing8,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : theme.dividerColor.withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : theme.colorScheme.onSurface,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontFamily: 'IBM Plex Sans Arabic',
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return EmptyStateWidget(
      icon: SolarLinearIcons.folderOpen,
      iconColor: theme.colorScheme.primary,
    );
  }

  Widget _buildItemsGrid(
    LibraryProvider provider,
    ThemeData theme,
  ) {
    final items = provider.sharedItems;

    return GridView.builder(
      padding: const EdgeInsets.all(AppDimensions.paddingMedium),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: AppDimensions.spacing12,
        mainAxisSpacing: AppDimensions.spacing12,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Stack(
          children: [
            LibraryItemCard(
              item: item,
              provider: provider,
              onView: () {
                // Handle view action
              },
            ),
            // Permission badge
            Positioned(
              top: AppDimensions.spacing8,
              right: AppDimensions.spacing8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.spacing8,
                  vertical: AppDimensions.spacing4,
                ),
                decoration: BoxDecoration(
                  color: _getPermissionColor(item.sharePermission ?? 'read').withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusSmall),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getPermissionIcon(item.sharePermission ?? 'read'),
                      size: AppDimensions.iconSmall,
                      color: Colors.white,
                    ),
                    const SizedBox(width: AppDimensions.spacing4),
                    Text(
                      _getPermissionLabel(item.sharePermission ?? 'read'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  IconData _getPermissionIcon(String permission) {
    switch (permission) {
      case 'edit':
        return SolarLinearIcons.pen;
      case 'admin':
        return SolarLinearIcons.userHeart;
      default:
        return SolarLinearIcons.eye;
    }
  }

  String _getPermissionLabel(String permission) {
    switch (permission) {
      case 'edit':
        return 'تعديل';
      case 'admin':
        return 'مدير';
      default:
        return 'قراءة';
    }
  }

  Color _getPermissionColor(String permission) {
    switch (permission) {
      case 'edit':
        return Colors.blue;
      case 'admin':
        return Colors.purple;
      default:
        return AppColors.primary;
    }
  }
}
