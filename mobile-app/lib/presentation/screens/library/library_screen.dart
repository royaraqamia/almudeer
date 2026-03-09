import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

import '../../../core/utils/haptics.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/dimensions.dart';
import '../../../core/extensions/string_extension.dart';
import '../../../core/localization/library_localizations.dart';
import '../../../data/models/library_item.dart';
import '../../providers/library_provider.dart';
import '../../widgets/premium_fab.dart';
import '../../widgets/common_widgets.dart';
import 'package:hijri/hijri_calendar.dart';
import '../viewers/universal_viewer_screen.dart';
import 'note_edit_screen.dart';
import 'widgets/accessible_library_widgets.dart';
import 'widgets/library_item_card.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  String _selectedType = 'notes';
  final ScrollController _scrollController = ScrollController();
  // Track which categories have been loaded (for animation control)
  final Set<String> _loadedCategories = {};
  // Track which categories have already been animated
  final Set<String> _animatedCategories = {};
  late String _hijriDate;

  @override
  void initState() {
    super.initState();
    HijriCalendar.setLocal('ar');
    _hijriDate = HijriCalendar.now().toFormat('DD, dd MMMM yyyy').toEnglishNumbers;
    _loadedCategories.add(_selectedType);
    _scrollController.addListener(_onScroll);
    // Defer fetch until after build to avoid setState() during build
    // Use Future.microtask to ensure it runs after the current frame completes
    Future.microtask(() {
      if (mounted) {
        // Don't await - let it run asynchronously to prevent build-phase issues
        context.read<LibraryProvider>().fetchItems(category: _selectedType);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final provider = context.read<LibraryProvider>();
      if (provider.hasMore && !provider.isFetchingMore && !provider.isLoading) {
        // Fire-and-forget with error handling to prevent uncaught exceptions
        // Wrap in try-catch to handle any synchronous exceptions before future is returned
        try {
          provider.fetchItems(loadMore: true, category: _selectedType).catchError((error) {
            debugPrint('[LibraryScreen] Scroll-triggered fetch failed: $error');
            // Don't show snackbar for scroll loads - too intrusive
            // The provider will retry on next scroll event
          });
        } catch (e) {
          // Handle any synchronous exceptions
          debugPrint('[LibraryScreen] Scroll-triggered fetch threw synchronously: $e');
        }
      }
    }
  }

  Future<void> _onFilterChanged(String type) async {
    if (_selectedType == type) return;
    setState(() {
      _selectedType = type;
      _loadedCategories.add(type);
    });

    // Provider automatically detects category change and forces refresh
    await context.read<LibraryProvider>().fetchItems(category: type);

    // Reset scroll position to avoid jarring scroll jumps
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  Widget _buildLibraryList(List<LibraryItem> items, LibraryProvider provider, String type) {
    // Animate only the first time a category is loaded
    final shouldAnimate = !_animatedCategories.contains(type);
    if (shouldAnimate) {
      _animatedCategories.add(type);
    }

    // Use Key to force widget recreation and proper disposal of old content
    // RepaintBoundary prevents visual artifacts during tab switching
    return RepaintBoundary(
      child: Padding(
        key: ValueKey('library-list-$type'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spacing12,
          vertical: AppDimensions.spacing8,
        ),
        child: type == 'files'
            ? ListView.builder(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Padding(
                    key: ValueKey('file-item-${item.id}'),
                    padding: const EdgeInsets.only(
                      bottom: AppDimensions.spacing10,
                    ),
                    child: StaggeredAnimatedItem(
                      index: index,
                      animate: shouldAnimate,
                      child: LibraryItemListCard(
                        key: ValueKey('file-card-${item.id}'),
                        item: item,
                        provider: provider,
                        onView: () => _viewItem(item),
                      ),
                    ),
                  );
                },
              )
            : GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: AppDimensions.spacing10,
                  mainAxisSpacing: AppDimensions.spacing10,
                  childAspectRatio: 0.85,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return StaggeredAnimatedItem(
                    index: index,
                    animate: shouldAnimate,
                    child: LibraryItemCard(
                      key: ValueKey('note-card-${item.id}'),
                      item: item,
                      provider: provider,
                      onView: () => _viewItem(item),
                    ),
                  );
                },
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LibraryProvider>();
    final items = context.select((LibraryProvider p) => p.items);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  Haptics.mediumTap();
                  await context.read<LibraryProvider>().fetchItems(
                    category: _selectedType,
                    refresh: true,
                  );
                },
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  controller: _scrollController,
                  slivers: [
                    // P0: Accessible header with proper Semantics
                    SliverToBoxAdapter(
                      child: LibraryHeader(
                        date: _hijriDate,
                      ),
                    ),
                    
                    // P0: Accessible filter bar with 44px touch targets
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: FilterHeaderDelegate(
                        child: LibraryFilterBar(
                          selectedType: _selectedType,
                          onFilterChanged: _onFilterChanged,
                        ),
                      ),
                    ),

                    // Show cached data immediately - no skeleton loader
                    if (items.isEmpty)
                      // P2: Empty state
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: LibraryEmptyState(
                          type: _selectedType,
                        ),
                      )
                    else
                      // P2: Design token compliance for spacing
                      // Direct switching with unique key to ensure proper widget disposal
                      SliverToBoxAdapter(
                        child: _buildLibraryList(items, provider, _selectedType),
                      ),
                    
                    // P2: Design token compliance for bottom padding
                    const SliverPadding(
                      padding: EdgeInsets.only(
                        bottom: AppDimensions.spacing100,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _selectedType == 'tools'
          ? null
          : Padding(
              padding: const EdgeInsets.only(
                bottom: AppDimensions.spacing24,
              ),
              child: PremiumFAB(
                heroTag: 'library_fab',
                standalone: false,
                onPressed: () {
                  Haptics.mediumTap();
                  if (_selectedType == 'notes') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const NoteEditScreen(),
                      ),
                    );
                  } else if (_selectedType == 'files') {
                    _pickFile(fromBottomSheet: false);
                  } else {
                    _showAddOptions();
                  }
                },
                gradientColors: [
                  AppColors.primary,
                  AppColors.accent,
                ],
                icon: Icon(
                  _selectedType == 'notes'
                      ? SolarBoldIcons.documentAdd
                      : _selectedType == 'files'
                      ? SolarBoldIcons.folderAdd
                      : SolarBoldIcons.addCircle,
                  color: Colors.white,
                  size: AppDimensions.iconXLarge,
                ),
              ),
            ),
    );
  }

  Future<void> _viewItem(LibraryItem item) async {
    Haptics.lightTap();

    try {
      if (item.type == 'note') {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NoteEditScreen(item: item),
          ),
        );
        if (!mounted) return;
        // Note: No need to manually refresh - the provider's WebSocket stream
        // handles sync automatically. Optimistic updates ensure UI stays current.
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UniversalViewerScreen(
            url: item.filePath,
            fileName: item.title,
            fileType: item.type,
          ),
        ),
      );
      if (!mounted) return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${LibraryLocalizations.of(context).errorOpeningItem}: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // P1: Enhanced file upload with progress tracking
  Future<void> _pickFile({bool fromBottomSheet = true}) async {
    final provider = context.read<LibraryProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.first;

      // P0: Immediate null check for file path (required on some platforms)
      final filePath = file.path;
      if (filePath == null || filePath.isEmpty) {
        // On some platforms (especially iOS), files may be selected but not directly accessible
        // In this case, we need to use the bytes instead of the path
        if (file.bytes != null && file.bytes!.isNotEmpty) {
          if (!mounted) return;
          messenger.showSnackBar(
            SnackBar(
              content: Text(LibraryLocalizations.of(context).fileAccessError),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          if (!mounted) return;
          messenger.showSnackBar(
            SnackBar(
              content: Text(LibraryLocalizations.of(context).fileSelectedError),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      if (!mounted) return;

      final fileName = file.name;

      // Additional validation: check if file exists (for platforms that support it)
      try {
        final fileExists = await File(filePath).exists();
        if (!fileExists) {
          if (!mounted) return;
          messenger.showSnackBar(
            SnackBar(
              content: Text(LibraryLocalizations.of(context).fileNotFound),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(LibraryLocalizations.of(context).fileAccessError),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      // Provider handles upload with progress on the item card
      provider.uploadFile(filePath).then((_) {
        if (!mounted) return;

        // P3: Success celebration with haptic
        Haptics.mediumTap();

        // Show success toast
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(SolarBoldIcons.checkCircle, color: Colors.white),
                const SizedBox(width: AppDimensions.spacing8),
                Text(LibraryLocalizations.of(context).uploadSuccess(fileName)),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }).catchError((error) {
        if (!mounted) return;

        // P1: Error with retry option
        messenger.showSnackBar(
          SnackBar(
            content: Text(LibraryLocalizations.of(context).uploadFailedWithName(fileName, error.toString())),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: LibraryLocalizations.of(context).retry,
              textColor: Colors.white,
              onPressed: () => _pickFile(fromBottomSheet: fromBottomSheet),
            ),
          ),
        );
      });

      if (fromBottomSheet && mounted) {
        navigator.pop();
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('${LibraryLocalizations.of(context).uploadFailed}: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(AppDimensions.paddingLarge),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(AppDimensions.radiusXXLarge),
            topRight: Radius.circular(AppDimensions.radiusXXLarge),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppDimensions.spacing16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.only(bottom: AppDimensions.spacing16),
              child: Text(
                LibraryLocalizations.of(context).addNewContent,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontFamily: 'IBM Plex Sans Arabic',
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            // Note option
            Semantics(
              button: true,
              label: LibraryLocalizations.of(context).noteOption,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Haptics.lightTap();
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const NoteEditScreen(),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
                  focusColor: AppColors.primary.withValues(alpha: 0.12),
                  hoverColor: AppColors.primary.withValues(alpha: 0.04),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppDimensions.spacing12,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(AppDimensions.spacing10),
                          decoration: BoxDecoration(
                            color: AppColors.info.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
                          ),
                          child: const Icon(
                            SolarLinearIcons.documentText,
                            color: AppColors.info,
                            size: AppDimensions.iconMedium,
                          ),
                        ),
                        const SizedBox(width: AppDimensions.spacing12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                LibraryLocalizations.of(context).noteOption,
                                style: TextStyle(
                                  fontFamily: 'IBM Plex Sans Arabic',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                LibraryLocalizations.of(context).writeNewNote,
                                style: TextStyle(
                                  fontFamily: 'IBM Plex Sans Arabic',
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          SolarLinearIcons.altArrowLeft,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 24),
            // File option
            Semantics(
              button: true,
              label: LibraryLocalizations.of(context).uploadFile,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Haptics.lightTap();
                    Navigator.pop(context);
                    _pickFile(fromBottomSheet: false);
                  },
                  borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
                  focusColor: AppColors.primary.withValues(alpha: 0.12),
                  hoverColor: AppColors.primary.withValues(alpha: 0.04),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppDimensions.spacing12,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(AppDimensions.spacing10),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
                          ),
                          child: const Icon(
                            SolarLinearIcons.upload,
                            color: AppColors.primary,
                            size: AppDimensions.iconMedium,
                          ),
                        ),
                        const SizedBox(width: AppDimensions.spacing12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                LibraryLocalizations.of(context).uploadFile,
                                style: TextStyle(
                                  fontFamily: 'IBM Plex Sans Arabic',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                LibraryLocalizations.of(context).selectFromFile,
                                style: TextStyle(
                                  fontFamily: 'IBM Plex Sans Arabic',
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          SolarLinearIcons.altArrowLeft,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.spacing8),
          ],
        ),
      ),
    );
  }
}
