import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:share_plus/share_plus.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';
import 'package:almudeer_mobile_app/presentation/widgets/animated_toast.dart';
import 'package:almudeer_mobile_app/core/services/browser_download_manager.dart';
import 'package:almudeer_mobile_app/core/services/ad_blocker_service.dart';
import 'package:almudeer_mobile_app/presentation/screens/library/tools/downloads_screen.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:almudeer_mobile_app/core/models/browser_tab_persistence.dart';
import 'package:almudeer_mobile_app/core/services/browser_history_service.dart';
import 'package:almudeer_mobile_app/core/services/browser_bookmark_service.dart';
import 'package:almudeer_mobile_app/presentation/screens/library/tools/browser_history_screen.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

class BrowserTab {
  final String id;
  late final WebViewController controller;
  String title;
  String url;
  double progress = 0;
  bool isLoading = true;
  bool isInitialized = false;
  Uint8List? snapshot;
  bool isDesktopMode = false;
  bool canShowReaderMode = false;
  bool jsInjected = false;

  BrowserTab({
    required this.id,
    required this.url,
    this.title = 'المتصفح',
    this.isDesktopMode = false,
  });
}

class BrowserScreen extends StatefulWidget {
  final String? initialUrl;
  const BrowserScreen({super.key, this.initialUrl});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final List<BrowserTab> _tabs = [];
  int _activeTabIndex = 0;
  final TextEditingController _urlController = TextEditingController();
  final BrowserDownloadManager _downloadManager = BrowserDownloadManager();
  final AdBlockerService _adBlocker = AdBlockerService();
  final BrowserHistoryService _historyService = BrowserHistoryService();
  final BrowserBookmarkService _bookmarkService = BrowserBookmarkService();
  bool _isRestoring = true;
  bool _isReaderMode = false;
  String? _readerTitle;
  late final WebViewController _readerController;
  final GlobalKey _repaintKey = GlobalKey();
  bool _showSearch = false;
  final TextEditingController _searchTextController = TextEditingController();
  final Set<String> _recentHistoryUrls = {};
  DateTime? _lastHistoryAdd;

  @override
  void initState() {
    super.initState();
    _adBlocker.init();
    _historyService.init();
    _bookmarkService.init();
    _initReaderController();
    _restoreSession();
  }

  void _initReaderController() {
    _readerController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _searchTextController.dispose();
    super.dispose();
  }

  Future<void> _restoreSession() async {
    if (widget.initialUrl != null && widget.initialUrl!.isNotEmpty) {
      _addNewTab(url: widget.initialUrl!);
      setState(() {
        _activeTabIndex = 0;
        _urlController.text = _tabs[0].url;
        _isRestoring = false;
      });
      return;
    }

    final box = await Hive.openBox<BrowserTabPersistence>('browser_session');
    if (box.isNotEmpty) {
      for (var savedTab in box.values) {
        _addNewTab(
          url: savedTab.url,
          title: savedTab.title,
          id: savedTab.id,
          isDesktopMode: savedTab.isDesktopMode,
        );
      }
      setState(() {
        _activeTabIndex = 0;
        if (_tabs.isNotEmpty) {
          _urlController.text = _tabs[0].url;
        }
        _isRestoring = false;
      });
    } else {
      _addNewTab(url: 'https://google.com');
      setState(() => _isRestoring = false);
    }
  }

  Future<void> _saveSession() async {
    final box = await Hive.openBox<BrowserTabPersistence>('browser_session');
    await box.clear();
    for (var tab in _tabs) {
      await box.add(
        BrowserTabPersistence(
          id: tab.id,
          url: tab.url,
          title: tab.title,
          isDesktopMode: tab.isDesktopMode,
        ),
      );
    }
  }

  void _addNewTab({
    String url = 'https://google.com',
    String? title,
    String? id,
    bool isDesktopMode = false,
  }) {
    final tabId = id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final tab = BrowserTab(
      id: tabId,
      url: url,
      title: title ?? 'المتصفح',
      isDesktopMode: isDesktopMode,
    );

    tab.controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        tab.isDesktopMode
            ? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
            : null,
      )
      ..addJavaScriptChannel(
        'ImageLongPressChannel',
        onMessageReceived: (JavaScriptMessage message) {
          _showImageContextMenu(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            setState(() {
              tab.progress = progress / 100;
            });
          },
          onPageStarted: (String url) {
            setState(() {
              tab.isLoading = true;
              tab.url = url;
              if (_tabs.indexOf(tab) == _activeTabIndex) {
                _urlController.text = url;
              }
            });
            // Inject ad blocker on page start - always enabled
            if (!tab.jsInjected) {
              tab.controller.runJavaScript(_adBlocker.getBlockingJavaScript());
            }
          },
          onPageFinished: (String url) async {
            final pageTitle = await tab.controller.getTitle();
            setState(() {
              tab.isLoading = false;
              if (pageTitle != null && pageTitle.isNotEmpty) {
                tab.title = pageTitle;
              }
            });
            // Always save to history and session (no incognito mode)
            _saveSession();
            if (pageTitle != null && pageTitle.isNotEmpty) {
              // Debounce: only add to history if 2+ seconds since last add
              // or if URL is different from recently added
              final now = DateTime.now();
              final isDuplicate = _recentHistoryUrls.contains(url);
              final timeSinceLastAdd = _lastHistoryAdd != null
                  ? now.difference(_lastHistoryAdd!).inMilliseconds
                  : 2000;

              if (!isDuplicate || timeSinceLastAdd > 2000) {
                _historyService.addEntry(url, pageTitle);
                _recentHistoryUrls.add(url);
                _lastHistoryAdd = now;

                // Clean up old entries from recent set after 10 seconds
                Future.delayed(const Duration(seconds: 10), () {
                  _recentHistoryUrls.remove(url);
                });
              }
            }
            _checkReaderModeAvailability(tab.controller);
            // Inject long press detector only once
            if (!tab.jsInjected) {
              _injectLongPressDetector(tab.controller);
              // Inject CSS to allow websites to use their native color scheme
              _injectNativeColorScheme(tab.controller);
              // Ad blocker is always enabled - inject again to ensure it's active
              tab.controller.runJavaScript(
                _adBlocker.getBlockingJavaScript(),
              );
              tab.jsInjected = true;
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            final navUrl = request.url.toLowerCase();

            if (_adBlocker.isAdultContent(request.url)) {
              AnimatedToast.error(
                context,
                'تم حظر هذا الموقع بموجب سياسة المحتوى الآمن',
              );
              return NavigationDecision.prevent;
            }

            if (_adBlocker.isBlocked(request.url)) {
              debugPrint('[Browser] Blocked ad/tracker: ${request.url}');
              return NavigationDecision.prevent;
            }

            final downloadExtensions = [
              '.apk',
              '.zip',
              '.pdf',
              '.jpg',
              '.jpeg',
              '.png',
              '.gif',
              '.mp4',
              '.mov',
              '.avi',
              '.mp3',
              '.wav',
              '.rar',
              '.7z',
            ];

            if (downloadExtensions.any((ext) => navUrl.endsWith(ext))) {
              _downloadManager.startDownload(request.url);
              AnimatedToast.success(context, 'بدأ تحميل الملف');
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..setBackgroundColor(const Color(0x00000000))
      ..loadRequest(Uri.parse(url));

    setState(() {
      _tabs.add(tab);
      if (!_isRestoring) {
        _activeTabIndex = _tabs.length - 1;
        _urlController.text = url;
      }
    });
  }

  void _injectLongPressDetector(WebViewController controller) {
    const script = """
      if (!window.hasLongPressListener) {
        window.hasLongPressListener = true;
        document.addEventListener('contextmenu', function(event) {
          var target = event.target;
          while (target && target.tagName !== 'IMG' && target.tagName !== 'A') {
            target = target.parentElement;
          }
          if (target) {
            event.preventDefault();
            if (target.tagName === 'IMG') {
              ImageLongPressChannel.postMessage(target.src);
            } else if (target.tagName === 'A' && target.href) {
               // Optional: handle link long press
            }
          }
        }, true);
      }
    """;
    controller.runJavaScript(script);
  }

  void _injectNativeColorScheme(WebViewController controller) {
    // Inject CSS to allow websites to render with their native color scheme
    // This prevents Android WebView from forcing dark mode on light-themed websites
    const script = """
      (function() {
        if (window.__nativeColorSchemeInjected) return;
        window.__nativeColorSchemeInjected = true;

        try {
          // Set color-scheme to both light and dark to allow websites to choose
          const metaColorScheme = document.createElement('meta');
          metaColorScheme.name = 'color-scheme';
          metaColorScheme.content = 'light dark';
          if (document.head) {
            document.head.appendChild(metaColorScheme);
          }

          // Override any CSS color-scheme that might force dark mode
          const style = document.createElement('style');
          style.textContent = ':root { color-scheme: light dark !important; } html { color-scheme: light dark !important; } body { color-scheme: light dark !important; }';
          if (document.head) {
            document.head.appendChild(style);
          }

          console.log('[NativeColorScheme] Injected - websites use native theme');
        } catch (e) {
          // Silently fail on pages with strict CSP
          console.log('[NativeColorScheme] Skipped due to CSP or other restrictions');
        }
      })();
    """;
    controller.runJavaScript(script);
  }

  Future<void> _captureSnapshot() async {
    try {
      final boundary =
          _repaintKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 0.5);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          setState(() {
            _tabs[_activeTabIndex].snapshot = byteData.buffer.asUint8List();
          });
        }
      }
    } catch (e) {
      debugPrint('Error capturing snapshot: $e');
    }
  }

  void _toggleDesktopMode() {
    Haptics.mediumTap();
    setState(() {
      final tab = _tabs[_activeTabIndex];
      tab.isDesktopMode = !tab.isDesktopMode;
      const desktopUA =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
      tab.controller.setUserAgent(tab.isDesktopMode ? desktopUA : null);
      tab.controller.reload();
    });
  }

  void _executeSearch(String query) {
    if (query.isEmpty) return;
    // Properly escape for JavaScript - escape both single and double quotes, backslashes
    final escapedQuery = query
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r');
    _tabs[_activeTabIndex].controller.runJavaScript("""
      (function() {
        var searchTerm = "$escapedQuery";
        if (window.find) {
          window.find(searchTerm, false, false, true, false, false, true);
        } else {
          var selection = window.getSelection();
          selection.removeAllRanges();
          var range = document.createRange();
          var textNodes = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null, false);
          var node;
          var lowerSearch = searchTerm.toLowerCase();
          while (node = textNodes.nextNode()) {
            var index = node.textContent.toLowerCase().indexOf(lowerSearch);
            if (index !== -1) {
              range.setStart(node, index);
              range.setEnd(node, index + searchTerm.length);
              selection.addRange(range);
              node.parentElement.scrollIntoView({behavior: 'smooth', block: 'center'});
              break;
            }
          }
        }
      })();
    """);
  }

  void _showImageContextMenu(String imageUrl) {
    Haptics.mediumTap();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imageUrl,
                  height: 150,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Icon(SolarLinearIcons.gallery, size: 50),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(SolarLinearIcons.download),
              title: const Text('حفظ الصورة'),
              onTap: () {
                Navigator.pop(context);
                _downloadManager.startDownload(imageUrl);
                AnimatedToast.success(context, 'بدأ تحميل الصورة');
              },
            ),
            ListTile(
              leading: const Icon(SolarLinearIcons.shareCircle),
              title: const Text('مشاركة رابط الصورة'),
              onTap: () {
                Navigator.pop(context);
                SharePlus.instance.share(ShareParams(text: imageUrl));
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _checkReaderModeAvailability(
    WebViewController controller,
  ) async {
    const script = """
      (function() {
        const article = document.querySelector('article') || document.querySelector('main') || document.querySelector('.content') || document.querySelector('#content');
        if (article) {
          const text = article.innerText;
          return text.length > 500;
        }
        return document.body.innerText.length > 2000;
      })();
    """;
    try {
      final result = await controller.runJavaScriptReturningResult(script);
      if (mounted) {
        setState(() {
          _tabs[_activeTabIndex].canShowReaderMode = result == true;
        });
      }
    } catch (e) {
      debugPrint("Error checking reader mode: $e");
    }
  }

  Future<void> _toggleReaderMode() async {
    if (_isReaderMode) {
      setState(() => _isReaderMode = false);
      return;
    }

    final controller = _tabs[_activeTabIndex].controller;
    const script = """
      (function() {
        const title = document.title;
        const article = document.querySelector('article') || document.querySelector('main') || document.querySelector('.content') || document.querySelector('#content') || document.body;
        
        // Basic cleanup
        const clone = article.cloneNode(true);
        const tagsToRemove = ['script', 'style', 'nav', 'header', 'footer', 'aside', 'iframe', 'ads'];
        tagsToRemove.forEach(tag => {
          const elements = clone.querySelectorAll(tag);
          elements.forEach(el => el.remove());
        });

        return JSON.stringify({
          title: title,
          content: clone.innerHTML
        });
      })();
    """;

    try {
      final jsonStr = await controller.runJavaScriptReturningResult(script);

      String jsonString = jsonStr.toString();
      if (jsonString.startsWith('"') && jsonString.endsWith('"')) {
        jsonString = jsonString
            .substring(1, jsonString.length - 1)
            .replaceAll('\\"', '"')
            .replaceAll('\\\\', '\\');
      }

      final Map<String, dynamic> data = jsonDecode(jsonString);
      final html = _generateReaderHtml(
        data['title']?.toString() ?? 'Untitled',
        data['content']?.toString() ?? '',
      );

      await _readerController.loadHtmlString(html);

      setState(() {
        _isReaderMode = true;
        _readerTitle = data['title']?.toString();
      });
    } catch (e) {
      debugPrint("Error entering reader mode: $e");
      if (mounted) {
        AnimatedToast.error(context, 'فشل في تفعيل وضع القراءة');
      }
    }
  }

  String _generateReaderHtml(String title, String content) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? '#0F2E42' : '#FFFFFF';
    final textColor = isDark ? '#E8EEFF' : '#333333';

    return """
      <!DOCTYPE html>
      <html dir="rtl">
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
          body { 
            font-family: 'IBM Plex Sans Arabic', sans-serif; 
            padding: 20px; 
            line-height: 1.8; 
            background-color: $bgColor; 
            color: $textColor;
          }
          h1 { font-size: 24px; margin-bottom: 20px; }
          img { max-width: 100%; height: auto; border-radius: 8px; }
          p { margin-bottom: 16px; }
        </style>
      </head>
      <body>
        <h1>$title</h1>
        $content
      </body>
      </html>
    """;
  }

  Widget _buildReaderModeOverlay() {
    if (!_isReaderMode) return const SizedBox.shrink();

    return Positioned.fill(
      child: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Column(
          children: [
            AppBar(
              elevation: 0,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              leading: IconButton(
                icon: const Icon(SolarLinearIcons.closeCircle),
                onPressed: () => setState(() => _isReaderMode = false),
              ),
              title: Text(
                _readerTitle ?? _tabs[_activeTabIndex].title,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_readerTitle != null)
                      Text(
                        _readerTitle!,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontFamily: 'IBM Plex Sans Arabic',
                            ),
                      ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.7,
                      child: WebViewWidget(controller: _readerController),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _loadUrl() {
    String url = _urlController.text.trim();
    if (url.isEmpty) return;

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    if (_adBlocker.isAdultContent(url)) {
      AnimatedToast.error(
        context,
        'تم حظر هذا الموقع بموجب سياسة المحتوى الآمن',
      );
      return;
    }

    try {
      _tabs[_activeTabIndex].controller.loadRequest(Uri.parse(url));
      FocusScope.of(context).unfocus();
    } catch (e) {
      AnimatedToast.error(context, 'رابط غير صالح');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_tabs.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final activeTab = _tabs[_activeTabIndex];

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        ),
        title: GestureDetector(
          onTap: () => _showTabsSwitcher(),
          child: Column(
            children: [
              Text(
                activeTab.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  fontFamily: 'IBM Plex Sans Arabic',
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (!activeTab.isLoading && activeTab.url.isNotEmpty)
                Text(
                  _getHostFromUrl(activeTab.url),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: Colors.grey,
                  ),
                ),
            ],
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(SolarLinearIcons.arrowRight, size: 24),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(SolarLinearIcons.download, size: 22),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DownloadsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(SolarLinearIcons.refresh, size: 22),
            onPressed: () {
              Haptics.lightTap();
              activeTab.controller.reload();
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(SolarLinearIcons.menuDots, size: 22),
            onSelected: (value) {
              Haptics.lightTap();
              if (value == 'desktop') {
                _toggleDesktopMode();
              } else if (value == 'search') {
                setState(() => _showSearch = true);
              } else if (value == 'history') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const BrowserHistoryScreen(),
                  ),
                ).then((_) => setState(() {}));
              } else if (value == 'bookmark') {
                final tab = _tabs[_activeTabIndex];
                _bookmarkService.toggleBookmark(tab.url, tab.title);
                setState(() {});
                AnimatedToast.success(
                  context,
                  _bookmarkService.isBookmarked(tab.url)
                      ? 'تمت إضافة الإشارة المرجعية'
                      : 'تمت إزالة الإشارة المرجعية',
                );
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'desktop',
                child: Row(
                  children: [
                    Icon(
                      _tabs[_activeTabIndex].isDesktopMode
                          ? SolarBoldIcons.monitor
                          : SolarLinearIcons.monitor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text('عرض سطح المكتب'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'search',
                child: Row(
                  children: [
                    Icon(SolarLinearIcons.magnifer, size: 20),
                    SizedBox(width: 8),
                    Text('بحث في الصفحة'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'history',
                child: Row(
                  children: [
                    Icon(SolarLinearIcons.history, size: 20),
                    SizedBox(width: 8),
                    Text('السجل والإشارات'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'bookmark',
                child: Row(
                  children: [
                    Icon(
                      _bookmarkService.isBookmarked(activeTab.url)
                          ? SolarBoldIcons.bookmark
                          : SolarLinearIcons.bookmark,
                      size: 20,
                      color: _bookmarkService.isBookmarked(activeTab.url)
                          ? Colors.amber
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _bookmarkService.isBookmarked(activeTab.url)
                          ? 'إزالة الإشارة المرجعية'
                          : 'إضافة إشارة مرجعية',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[900] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                    ),
                  ),
                  child: TextField(
                    controller: _urlController,
                    onSubmitted: (_) => _loadUrl(),
                    style: const TextStyle(fontSize: 14, height: 1.0),
                    decoration: InputDecoration(
                      hintText: 'أدخل الرابط هنا...',
                      hintStyle: const TextStyle(fontSize: 14),
                      prefixIcon: const Icon(
                        SolarLinearIcons.global,
                        size: 18,
                      ),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (activeTab.canShowReaderMode)
                            IconButton(
                              icon: Icon(
                                _isReaderMode
                                    ? SolarBoldIcons.billList
                                    : SolarLinearIcons.billList,
                                size: 18,
                              ),
                              onPressed: _toggleReaderMode,
                              tooltip: 'وضع القراءة',
                            ),
                          IconButton(
                            icon: const Icon(
                              SolarLinearIcons.arrowLeft,
                              size: 18,
                            ),
                            onPressed: _loadUrl,
                          ),
                        ],
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
              ),
              if (activeTab.isLoading)
                LinearProgressIndicator(
                  value: activeTab.progress,
                  backgroundColor: Colors.transparent,
                  color: AppColors.primary,
                  minHeight: 2,
                ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (_showSearch)
            Container(
              padding: const EdgeInsets.all(8.0),
              color: isDark ? Colors.grey[900] : Colors.grey[200],
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchTextController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'البحث في الصفحة...',
                        border: InputBorder.none,
                      ),
                      onSubmitted: _executeSearch,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(SolarLinearIcons.closeCircle),
                    onPressed: () {
                      setState(() {
                        _showSearch = false;
                        _searchTextController.clear();
                      });
                    },
                  ),
                ],
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                ..._tabs.asMap().entries.map((entry) {
                  final isSelected = _activeTabIndex == entry.key;
                  return Offstage(
                    offstage: !isSelected,
                    child: RepaintBoundary(
                      key: entry.value.id == activeTab.id ? _repaintKey : null,
                      child: _WebViewWithErrorHandling(
                        controller: entry.value.controller,
                      ),
                    ),
                  );
                }),
                _buildReaderModeOverlay(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(SolarLinearIcons.altArrowRight, size: 24),
                onPressed: () async {
                  Haptics.lightTap();
                  if (await activeTab.controller.canGoBack()) {
                    activeTab.controller.goBack();
                  }
                },
              ),
              IconButton(
                icon: const Icon(SolarLinearIcons.altArrowLeft, size: 24),
                onPressed: () async {
                  Haptics.lightTap();
                  if (await activeTab.controller.canGoForward()) {
                    activeTab.controller.goForward();
                  }
                },
              ),
              GestureDetector(
                onTap: () {
                  Haptics.lightTap();
                  _showTabsSwitcher();
                },
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: theme.iconTheme.color ?? Colors.grey,
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _tabs.length.toString(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: theme.iconTheme.color ?? Colors.grey,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(SolarLinearIcons.shareCircle, size: 24),
                onPressed: () {
                  Haptics.lightTap();
                  if (activeTab.url.isNotEmpty) {
                    SharePlus.instance.share(ShareParams(text: activeTab.url));
                  }
                },
              ),
              IconButton(
                icon: const Icon(SolarLinearIcons.copy, size: 24),
                onPressed: () {
                  Haptics.lightTap();
                  Clipboard.setData(ClipboardData(text: activeTab.url));
                  AnimatedToast.success(context, 'تم نسخ الرابط');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getHostFromUrl(String url) {
    try {
      return Uri.parse(url).host;
    } catch (e) {
      return url;
    }
  }

  void _showTabsSwitcher() async {
    if (!mounted) return;

    // Capture the current tab's snapshot before showing the switcher
    // to ensure the thumbnail is up to date.
    await _captureSnapshot();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _TabsSwitcher(
        tabs: _tabs,
        currentIndex: _activeTabIndex,
        onTabSelected: (index) async {
          setState(() {
            _activeTabIndex = index;
            _urlController.text = _tabs[index].url;
          });
          if (context.mounted) Navigator.pop(context);
        },
        onTabClosed: (index) {
          if (_tabs.length > 1) {
            setState(() {
              _tabs.removeAt(index);
              if (_activeTabIndex >= _tabs.length) {
                _activeTabIndex = _tabs.length - 1;
              }
              _urlController.text = _tabs[_activeTabIndex].url;
            });
            _saveSession();
          }
        },
        onNewTab: () {
          _addNewTab();
          Navigator.pop(context);
        },
      ),
    );
  }
}

class _TabsSwitcher extends StatelessWidget {
  final List<BrowserTab> tabs;
  final int currentIndex;
  final Function(int) onTabSelected;
  final Function(int) onTabClosed;
  final VoidCallback onNewTab;

  const _TabsSwitcher({
    required this.tabs,
    required this.currentIndex,
    required this.onTabSelected,
    required this.onTabClosed,
    required this.onNewTab,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'علامات التبويب',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(SolarLinearIcons.addCircle),
                  onPressed: onNewTab,
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.8,
              ),
              itemCount: tabs.length,
              itemBuilder: (context, index) {
                final tab = tabs[index];
                final isSelected = index == currentIndex;
                return GestureDetector(
                  onTap: () => onTabSelected(index),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[900] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : (isDark
                                  ? Colors.grey[800]!
                                  : Colors.grey[300]!),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Stack(
                      children: [
                        if (tab.snapshot != null)
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Opacity(
                                opacity: 0.6,
                                child: Image.memory(
                                  tab.snapshot!,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  tab.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                tab.url,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 4,
                          left: 4,
                          child: IconButton(
                            icon: const Icon(
                              SolarLinearIcons.closeCircle,
                              size: 20,
                              color: Colors.red,
                            ),
                            onPressed: () => onTabClosed(index),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WebViewWithErrorHandling extends StatelessWidget {
  final WebViewController controller;

  const _WebViewWithErrorHandling({required this.controller});

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: controller);
  }
}
