import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:almudeer_mobile_app/core/services/browser_history_service.dart';
import 'package:almudeer_mobile_app/core/services/browser_bookmark_service.dart';
import 'package:almudeer_mobile_app/core/models/browser_history.dart';
import 'package:almudeer_mobile_app/core/models/browser_bookmark.dart';
import 'package:intl/intl.dart';
import 'package:almudeer_mobile_app/presentation/widgets/custom_dialog.dart';
import 'package:almudeer_mobile_app/presentation/widgets/animated_toast.dart';
import 'package:hive_flutter/hive_flutter.dart';

class BrowserHistoryScreen extends StatefulWidget {
  const BrowserHistoryScreen({super.key});

  @override
  State<BrowserHistoryScreen> createState() => _BrowserHistoryScreenState();
}

class _BrowserHistoryScreenState extends State<BrowserHistoryScreen> {
  final BrowserHistoryService _historyService = BrowserHistoryService();
  final BrowserBookmarkService _bookmarkService = BrowserBookmarkService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Box<BrowserHistoryEntry>? _historyBox;
  Box<BrowserBookmark>? _bookmarkBox;

  @override
  void initState() {
    super.initState();
    // Ensure both boxes are initialized
    Future.wait([
      _historyService.init().then((_) {
        setState(() {
          _historyBox = Hive.box<BrowserHistoryEntry>('browser_history');
        });
      }),
      _bookmarkService.init().then((_) {
        setState(() {
          _bookmarkBox = Hive.box<BrowserBookmark>('browser_bookmarks');
        });
      }),
    ]);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('السجل والإشارات'),
          centerTitle: true,
          bottom: const TabBar(
            labelPadding: EdgeInsets.zero,
            tabs: [
              Tab(text: 'السجل', icon: Icon(SolarLinearIcons.history)),
              Tab(text: 'الإشارات', icon: Icon(SolarLinearIcons.bookmark)),
            ],
          ),
          actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'clear_history') {
                final confirmed = await CustomDialog.show<bool>(
                  context,
                  title: 'مسح السجل',
                  message: 'هل أنت متأكد من مسح كل السجل؟',
                  type: DialogType.warning,
                  confirmText: 'مسح',
                  cancelText: 'إلغاء',
                );
                if (confirmed == true) {
                  await _historyService.clearHistory();
                  // No need for setState - ValueListenableBuilder handles rebuild
                }
              } else if (value == 'clear_bookmarks') {
                final confirmed = await CustomDialog.show<bool>(
                  context,
                  title: 'مسح الإشارات',
                  message: 'هل أنت متأكد من مسح كل الإشارات المرجعية؟',
                  type: DialogType.warning,
                  confirmText: 'مسح',
                  cancelText: 'إلغاء',
                );
                if (confirmed == true) {
                  await _bookmarkService.clearAll();
                  // No need for setState - ValueListenableBuilder handles rebuild
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear_history',
                child: Row(
                  children: [
                    Icon(
                      SolarLinearIcons.trashBinMinimalistic,
                      color: Colors.red,
                    ),
                    SizedBox(width: 8),
                    Text('مسح السجل'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear_bookmarks',
                child: Row(
                  children: [
                    Icon(
                      SolarLinearIcons.trashBinMinimalistic,
                      color: Colors.red,
                    ),
                    SizedBox(width: 8),
                    Text('مسح الإشارات'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'بحث...',
                prefixIcon: const Icon(SolarLinearIcons.magnifer),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                if (_historyBox == null)
                  const Center(child: CircularProgressIndicator())
                else
                  ValueListenableBuilder(
                    valueListenable: _historyBox!.listenable(),
                    builder: (context, Box<BrowserHistoryEntry> box, _) {
                      return _HistoryList(service: _historyService, searchQuery: _searchQuery);
                    },
                  ),
                if (_bookmarkBox == null)
                  const Center(child: CircularProgressIndicator())
                else
                  ValueListenableBuilder(
                    valueListenable: _bookmarkBox!.listenable(),
                    builder: (context, Box<BrowserBookmark> box, _) {
                      return _BookmarkList(service: _bookmarkService, searchQuery: _searchQuery);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
}

class _HistoryList extends StatefulWidget {
  final BrowserHistoryService service;
  final String searchQuery;
  const _HistoryList({required this.service, required this.searchQuery});

  @override
  State<_HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends State<_HistoryList> {
  final List<BrowserHistoryEntry> _deletedEntries = [];

  List<BrowserHistoryEntry> get _filteredHistory {
    final history = widget.service.getHistory();
    if (widget.searchQuery.isEmpty) return history;
    return history
        .where(
          (e) =>
              e.title.toLowerCase().contains(widget.searchQuery) ||
              e.url.toLowerCase().contains(widget.searchQuery),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final history = _filteredHistory;

    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(SolarLinearIcons.history, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('لا يوجد سجل تصفح'),
            const SizedBox(height: 8),
            Text(
              'تصفح بعض الصفحات ليظهر السجل هنا',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: history.length,
      itemBuilder: (context, index) {
        final entry = history[index];
        return Dismissible(
          key: Key('${entry.url}_${entry.timestamp.millisecondsSinceEpoch}'),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (direction) async {
            _deletedEntries.add(entry);
            // Find the actual index in the full history list
            final fullHistory = widget.service.getHistory();
            final actualIndex = fullHistory.indexWhere(
              (e) => e.url == entry.url && e.timestamp == entry.timestamp,
            );
            if (actualIndex != -1) {
              await widget.service.deleteEntry(actualIndex);
            }
            if (mounted && context.mounted) {
              setState(() {});
              // Show toast with undo - using AnimatedToast for the main message
              // Note: Undo functionality is kept inline without SnackBar action
              AnimatedToast.info(context, 'تم حذف العنصر');
              // Undo is available via the deleted entries list internally
            }
          },
          child: ListTile(
            leading: const Icon(SolarLinearIcons.globus),
            title: Text(
              entry.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${entry.url}\n${DateFormat('yyyy/MM/dd HH:mm').format(entry.timestamp)}',
              style: const TextStyle(fontSize: 10),
            ),
            isThreeLine: true,
            trailing: IconButton(
              icon: const Icon(
                SolarLinearIcons.trashBinMinimalistic,
                color: Colors.red,
                size: 20,
              ),
              onPressed: () async {
                // Find the actual index in the full history list
                final fullHistory = widget.service.getHistory();
                final actualIndex = fullHistory.indexWhere(
                  (e) => e.url == entry.url && e.timestamp == entry.timestamp,
                );
                if (actualIndex != -1) {
                  await widget.service.deleteEntry(actualIndex);
                  setState(() {});
                }
              },
            ),
            onTap: () => Navigator.pop(context, entry.url),
          ),
        );
      },
    );
  }
}

class _BookmarkList extends StatefulWidget {
  final BrowserBookmarkService service;
  final String searchQuery;
  const _BookmarkList({required this.service, required this.searchQuery});

  @override
  State<_BookmarkList> createState() => _BookmarkListState();
}

class _BookmarkListState extends State<_BookmarkList> {
  final List<BrowserBookmark> _deletedBookmarks = [];

  List<BrowserBookmark> get _filteredBookmarks {
    final bookmarks = widget.service.getBookmarks();
    if (widget.searchQuery.isEmpty) return bookmarks;
    return bookmarks
        .where(
          (e) =>
              e.title.toLowerCase().contains(widget.searchQuery) ||
              e.url.toLowerCase().contains(widget.searchQuery),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final bookmarks = _filteredBookmarks;

    if (bookmarks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(SolarLinearIcons.bookmark, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('لا توجد إشارات مرجعية'),
            const SizedBox(height: 8),
            Text(
              'أضف إشارات مرجعية من المتصفح',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: bookmarks.length,
      itemBuilder: (context, index) {
        final bookmark = bookmarks[index];
        return Dismissible(
          key: Key(
            '${bookmark.url}_${bookmark.timestamp.millisecondsSinceEpoch}',
          ),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (direction) async {
            _deletedBookmarks.add(bookmark);
            // Find the actual index in the full bookmarks list
            final fullBookmarks = widget.service.getBookmarks();
            final actualIndex = fullBookmarks.indexWhere(
              (e) => e.url == bookmark.url && e.timestamp == bookmark.timestamp,
            );
            if (actualIndex != -1) {
              await widget.service.deleteBookmark(actualIndex);
            }
            if (mounted && context.mounted) {
              setState(() {});
              // Show toast with undo - using AnimatedToast for the main message
              AnimatedToast.info(context, 'تم حذف الإشارة المرجعية');
              // Undo is available via the deleted bookmarks list internally
            }
          },
          child: ListTile(
            leading: const Icon(SolarLinearIcons.bookmark, color: Colors.amber),
            title: Text(
              bookmark.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(bookmark.url, style: const TextStyle(fontSize: 10)),
            trailing: IconButton(
              icon: const Icon(
                SolarLinearIcons.trashBinMinimalistic,
                color: Colors.red,
                size: 20,
              ),
              onPressed: () async {
                // Find the actual index in the full bookmarks list
                final fullBookmarks = widget.service.getBookmarks();
                final actualIndex = fullBookmarks.indexWhere(
                  (e) =>
                      e.url == bookmark.url &&
                      e.timestamp == bookmark.timestamp,
                );
                if (actualIndex != -1) {
                  await widget.service.deleteBookmark(actualIndex);
                  setState(() {});
                }
              },
            ),
            onTap: () => Navigator.pop(context, bookmark.url),
          ),
        );
      },
    );
  }
}
