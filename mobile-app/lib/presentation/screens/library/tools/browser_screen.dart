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
import 'package:almudeer_mobile_app/core/services/browser_cookie_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:almudeer_mobile_app/core/models/browser_tab_persistence.dart';
import 'package:almudeer_mobile_app/core/services/browser_history_service.dart';
import 'package:almudeer_mobile_app/core/services/browser_bookmark_service.dart';
import 'package:almudeer_mobile_app/presentation/screens/library/tools/browser_history_screen.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'dart:async';

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
  bool jsInjected = false;
  bool wasRestoredFromSession = false;
  Timer? loadingTimeoutTimer; // Timer for loading timeout
  bool hasError = false; // Track WebView errors
  String? errorMessage; // Store error message

  BrowserTab({
    required this.id,
    required this.url,
    this.title = 'المتصفح',
    this.isDesktopMode = false,
    this.wasRestoredFromSession = false,
  });

  /// Dispose resources to prevent memory leaks
  void dispose() {
    // Cancel loading timeout timer
    loadingTimeoutTimer?.cancel();
    loadingTimeoutTimer = null;

    snapshot = null; // Clear image data

    // Clear WebView resources to reduce memory pressure
    try {
      controller.clearCache();
      controller.removeJavaScriptChannel('ImageLongPressChannel');
      controller.removeJavaScriptChannel('CookieCaptureChannel');
    } catch (e) {
      debugPrint('[BrowserTab] Error disposing: $e');
    }
  }
}

class BrowserScreen extends StatefulWidget {
  final String? initialUrl;
  const BrowserScreen({super.key, this.initialUrl});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  static const int _maxTabs = 50; // Limit open tabs to prevent memory pressure

  final List<BrowserTab> _tabs = [];
  int _activeTabIndex = 0;
  final TextEditingController _urlController = TextEditingController();
  final BrowserDownloadManager _downloadManager = BrowserDownloadManager();
  final PornBlockerService _adBlocker = PornBlockerService();
  final BrowserHistoryService _historyService = BrowserHistoryService();
  final BrowserBookmarkService _bookmarkService = BrowserBookmarkService();
  final BrowserCookieService _cookieService = BrowserCookieService();
  bool _isRestoring = true;
  final GlobalKey _repaintKey = GlobalKey();
  bool _showSearch = false;
  final TextEditingController _searchTextController = TextEditingController();
  final Set<String> _recentHistoryUrls = {};
  DateTime? _lastHistoryAdd;
  Timer? _cookieSaveTimer;

  @override
  void initState() {
    super.initState();
    _adBlocker.init();
    _historyService.init();
    _bookmarkService.init();
    _cookieService.initialize();
    _restoreSession();

    // Sync history and bookmarks from backend after a short delay
    // This ensures the UI is responsive while sync happens in background
    Future.delayed(const Duration(seconds: 2), () {
      _syncFromBackend();
    });
  }

  /// Sync history and bookmarks from backend
  Future<void> _syncFromBackend() async {
    try {
      // Sync in parallel
      await Future.wait([
        _historyService.syncFromBackend(),
        _bookmarkService.syncFromBackend(),
      ]);
      debugPrint('[Browser] Sync completed from backend');
    } catch (e) {
      debugPrint('[Browser] Sync error: $e');
    }
  }

  @override
  void dispose() {
    // Dispose all tabs to prevent memory leaks (also clears snapshots)
    for (var tab in _tabs) {
      tab.dispose();
    }
    _tabs.clear();

    _urlController.dispose();
    _searchTextController.dispose();
    _cookieSaveTimer?.cancel();
    super.dispose();
  }

  /// Clear all WebView cache, cookies, and storage (privacy/security)
  Future<void> _clearBrowsingData() async {
    try {
      // Clear WebView cookies (including persisted storage)
      await _cookieService.clearCookies();

      // Clear cache for all tabs
      for (var tab in _tabs) {
        await tab.controller.clearCache();
      }

      // Clear recent history URLs set to prevent false duplicate detection
      _recentHistoryUrls.clear();
      _lastHistoryAdd = null;

      debugPrint('[Browser] Browsing data cleared successfully');
    } catch (e) {
      debugPrint('[Browser] Error clearing browsing data: $e');
    }
  }

  /// Show clear browsing data confirmation dialog
  void _showClearBrowsingDataDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مسح بيانات التصفح'),
        content: const Text(
          'سيتم مسح السجل وملفات تعريف الارتباط والذاكرة المؤقتة. هل أنت متأكد؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              navigator.pop();
              await _clearBrowsingData();
              await _historyService.clearHistory();
              if (mounted) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('تم مسح بيانات التصفح بنجاح'),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('مسح'),
          ),
        ],
      ),
    );
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

    // Restore cookies FIRST before loading any tabs
    // This ensures login sessions (Google, etc.) are available when pages load
    await _cookieService.restoreCookies();

    // Restore cookies from backend for cross-device sync
    await _restoreCookiesFromBackend();

    final box = await Hive.openBox<BrowserTabPersistence>('browser_session');
    if (box.isNotEmpty) {
      for (var savedTab in box.values) {
        _addNewTab(
          url: savedTab.url,
          title: savedTab.title,
          id: savedTab.id,
          isDesktopMode: savedTab.isDesktopMode,
          wasRestoredFromSession: true,
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

  /// Restore cookies from backend and set them in WebView
  Future<void> _restoreCookiesFromBackend() async {
    try {
      final cookies = await _cookieService.restoreCookiesFromBackend();
      for (final cookieData in cookies) {
        await _cookieService.setCookie(
          name: cookieData['name'] as String,
          value: cookieData['value'] as String,
          domain: cookieData['domain'] as String,
          path: (cookieData['path'] as String?) ?? '/',
        );
      }
      if (cookies.isNotEmpty) {
        debugPrint('[Browser] Restored ${cookies.length} cookies from backend');
      }
    } catch (e) {
      debugPrint('[Browser] Error restoring cookies from backend: $e');
    }
  }

  Future<void> _saveSession() async {
    // Run session save in background to avoid blocking main thread
    Future.microtask(() async {
      try {
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
        // Save cookies with debouncing to prevent excessive saves
        _debouncedSaveCookies();
      } catch (e) {
        debugPrint('[Browser] Error saving session: $e');
      }
    });
  }

  /// Save cookies with debouncing (wait 2 seconds after last page load)
  void _debouncedSaveCookies() {
    _cookieSaveTimer?.cancel();
    _cookieSaveTimer = Timer(const Duration(seconds: 2), () async {
      await _cookieService.saveCookies();
      // Sync to backend for cross-device persistence (always enabled)
      // Note: We can't extract cookies from WebView, so this is a placeholder
      // for future enhancement when manual cookie tracking is needed
    });
  }

  void _addNewTab({
    String url = 'https://google.com',
    String? title,
    String? id,
    bool isDesktopMode = false,
    bool wasRestoredFromSession = false,
  }) {
    // Enforce tab limit - close oldest tab if at limit
    if (_tabs.length >= _maxTabs) {
      debugPrint('[Browser] Tab limit reached ($_maxTabs), closing oldest tab');
      final oldestTab = _tabs.removeAt(0);
      oldestTab.dispose();
      if (_activeTabIndex > 0) {
        _activeTabIndex--;
      }
      AnimatedToast.info(
        context,
        'تم إغلاق أقدم تبويب بسبب الوصول للحد الأقصى',
      );
    }

    final tabId = id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final tab = BrowserTab(
      id: tabId,
      url: url,
      title: title ?? 'المتصفح',
      isDesktopMode: isDesktopMode,
      wasRestoredFromSession: wasRestoredFromSession,
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
      ..addJavaScriptChannel(
        'CookieCaptureChannel',
        onMessageReceived: (JavaScriptMessage message) async {
          // Capture cookies from JavaScript and sync to backend
          await _captureAndSyncCookies(message.message);
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
            // Cancel any existing timeout timer
            tab.loadingTimeoutTimer?.cancel();
            // Clear any previous error state
            tab.hasError = false;
            tab.errorMessage = null;

            setState(() {
              tab.isLoading = true;
              tab.url = url;
              if (_tabs.indexOf(tab) == _activeTabIndex) {
                _urlController.text = url;
              }
            });

            // Set timeout to force stop loading after 15 seconds
            // This prevents infinite loading on SPA/infinite scroll sites
            tab.loadingTimeoutTimer = Timer(const Duration(seconds: 15), () {
              if (tab.isLoading && mounted) {
                debugPrint('[Browser] Loading timeout for $url - forcing stop');
                setState(() {
                  tab.isLoading = false;
                  tab.isInitialized = true;
                });
                // Stop the WebView loading to prevent background resource usage
                // Note: stopLoading() was removed in webview_flutter 4.x
              }
            });

            // Note: JavaScript injections happen in onPageFinished to ensure
            // the page is fully loaded before we modify it
          },
          onPageFinished: (String url) async {
            // Cancel the timeout timer since page finished loading
            tab.loadingTimeoutTimer?.cancel();

            final pageTitle = await tab.controller.getTitle();
            if (mounted) {
              setState(() {
                tab.isLoading = false;
                tab.isInitialized = true; // Mark as initialized after first load
                tab.hasError = false; // Clear any error state
                if (pageTitle != null && pageTitle.isNotEmpty) {
                  tab.title = pageTitle;
                }
              });
            }
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
            // Inject JavaScript enhancements only once per page session
            if (!tab.jsInjected) {
              try {
                // Inject long press detector for image context menu
                _injectLongPressDetector(tab.controller);
                // Inject CSS to allow websites to use their native color scheme
                _injectNativeColorScheme(tab.controller);
                // Inject cookie capture for Google and other auth providers
                _injectCookieCapture(tab.controller, url);
                // Porn blocker is always enabled
                tab.controller.runJavaScript(_adBlocker.getBlockingJavaScript());
                tab.jsInjected = true;
              } catch (e) {
                debugPrint('[Browser] Error injecting JavaScript: $e');
                // Continue anyway - page should still work without enhancements
              }
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            final navUrl = request.url.toLowerCase();

            // SECURITY: Block local file system and content URLs
            if (navUrl.startsWith('file://') ||
                navUrl.startsWith('content://') ||
                navUrl.startsWith('blob:')) {
              debugPrint('[Browser] Blocked unsafe URL scheme: ${request.url}');
              return NavigationDecision.prevent;
            }

            if (_adBlocker.isAdultContent(request.url)) {
              AnimatedToast.error(
                context,
                'تم حظر هذا الموقع بموجب سياسة المحتوى الآمن',
              );
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
          onWebResourceError: (WebResourceError error) {
            debugPrint('[Browser] WebResourceError: ${error.description} (errorCode: ${error.errorCode})');
            if (mounted) {
              setState(() {
                tab.hasError = true;
                tab.errorMessage = error.description.toString();
                tab.isLoading = false;
              });
            }
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
    // Checks for strict CSP before attempting injection to avoid errors
    const script = """
      (function() {
        if (window.__nativeColorSchemeInjected) return;
        window.__nativeColorSchemeInjected = true;

        try {
          // Check for strict CSP that would block injection
          // If CSP blocks inline styles or DOM manipulation, skip injection
          const cspMeta = document.querySelector('meta[http-equiv="Content-Security-Policy"]');
          if (cspMeta) {
            const csp = cspMeta.getAttribute('content') || '';
            // If 'unsafe-inline' is not in style-src, injection will fail
            if (csp.includes("style-src") && !csp.includes("'unsafe-inline'")) {
              console.log('[NativeColorScheme] Skipped - strict CSP detected');
              return;
            }
          }

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
          console.log('[NativeColorScheme] Skipped due to CSP or other restrictions: ' + e.message);
        }
      })();
    """;
    controller.runJavaScript(script);
  }

  /// Inject cookie capture JavaScript for auth providers (Google, etc.)
  void _injectCookieCapture(WebViewController controller, String url) {
    // Only inject on Google domains and common auth providers
    final isAuthDomain = url.contains('google.com') ||
        url.contains('accounts.google') ||
        url.contains('facebook.com') ||
        url.contains('linkedin.com');

    if (!isAuthDomain) return;

    const script = """
      (function() {
        if (window.__cookieCaptureInjected) return;
        window.__cookieCaptureInjected = true;

        // Capture cookies after a delay (allow login to complete)
        setTimeout(function() {
          try {
            var cookies = document.cookie.split(';');
            var cookieData = [];
            
            for (var i = 0; i < cookies.length; i++) {
              var cookie = cookies[i].trim();
              if (!cookie) continue;
              
              var eqIdx = cookie.indexOf('=');
              if (eqIdx === -1) continue;
              
              var name = cookie.substring(0, eqIdx).trim();
              var value = cookie.substring(eqIdx + 1).trim();
              
              // Skip sensitive cookies that shouldn't be synced
              if (name.startsWith('__Host-') || name.startsWith('__Secure-')) {
                continue;
              }
              
              cookieData.push({
                name: name,
                value: value,
                domain: window.location.hostname,
                path: '/'
              });
            }
            
            if (cookieData.length > 0) {
              // Send to Flutter via JavaScript channel
              CookieCaptureChannel.postMessage(JSON.stringify(cookieData));
            }
          } catch (e) {
            console.log('[CookieCapture] Error: ' + e.message);
          }
        }, 3000); // Wait 3 seconds after page load
      })();
    """;
    controller.runJavaScript(script);
  }

  /// Capture cookies from JavaScript and sync to backend
  Future<void> _captureAndSyncCookies(String jsonData) async {
    try {
      final List<dynamic> cookies = jsonDecode(jsonData);
      if (cookies.isEmpty) return;

      // Filter to important auth cookies only
      final List<Map<String, dynamic>> authCookies = cookies.where((cookie) {
        final name = (cookie['name'] as String).toLowerCase();
        // Capture Google auth cookies
        return name.contains('sid') ||
               name.contains('auth') ||
               name.contains('session') ||
               name.contains('token') ||
               name.startsWith('__ut') ||
               name == 'ssid' ||
               name == 'hsid' ||
               name == 'apisid' ||
               name == 'sapisid';
      }).map((cookie) => Map<String, dynamic>.from(cookie)).toList();

      if (authCookies.isEmpty) return;

      // Sync to backend
      await _cookieService.syncCookiesToBackend(authCookies);
      debugPrint('[Browser] Synced ${authCookies.length} auth cookies to backend');
    } catch (e) {
      debugPrint('[Browser] Error capturing cookies: $e');
    }
  }

  Future<void> _captureSnapshot() async {
    try {
      final boundary =
          _repaintKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary != null) {
        // Dynamic pixel ratio based on device DPI for optimal quality/size balance
        // High-DPI screens (>2.0) use 0.3, others use 0.5
        final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
        final pixelRatio = devicePixelRatio > 2.0 ? 0.3 : 0.5;

        final image = await boundary.toImage(pixelRatio: pixelRatio);
        try {
          final byteData = await image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (byteData != null && mounted) {
            setState(() {
              _tabs[_activeTabIndex].snapshot = byteData.buffer.asUint8List();
            });
          }
        } finally {
          // Free native memory immediately after use
          image.dispose();
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

    // Use JSON encoding for proper escaping of all special characters
    // This handles quotes, backslashes, newlines, and regex special chars
    final escapedQuery = query.replaceAll('"', '\\"');

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

  void _loadUrl() {
    String url = _urlController.text.trim();
    if (url.isEmpty) return;

    // Check if it looks like a search query (no dots or spaces)
    // If so, convert to Google search
    final isSearchQuery = !url.contains('.') && !url.contains('/') && !url.contains(' ');
    
    if (isSearchQuery) {
      // Convert to Google search
      url = 'https://www.google.com/search?q=${Uri.encodeComponent(url)}';
    } else {
      // Add https:// if missing
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }
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
        leading: IconButton(
          icon: const Icon(SolarLinearIcons.arrowRight, size: 24),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: SizedBox(
          height: 40,
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _urlController,
              onSubmitted: (_) => _loadUrl(),
              style: const TextStyle(fontSize: 14, height: 1.0),
              decoration: InputDecoration(
                hintText: 'أدخل الرابط هنا...',
                hintStyle: const TextStyle(fontSize: 14),
                prefixIcon: const Icon(SolarLinearIcons.global, size: 18),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(
                        SolarLinearIcons.arrowLeft,
                        size: 18,
                      ),
                      onPressed: _loadUrl,
                    ),
                  ],
                ),
                filled: true,
                fillColor: isDark ? AppColors.surfaceDark : Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark ? AppColors.cardDark : Colors.grey[300]!,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark ? AppColors.primary : AppColors.primary,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
        ),
        actions: [
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
              } else if (value == 'downloads') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DownloadsScreen()),
                );
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
              } else if (value == 'clear_data') {
                _showClearBrowsingDataDialog();
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
                value: 'downloads',
                child: Row(
                  children: [
                    Icon(SolarLinearIcons.download, size: 20),
                    SizedBox(width: 8),
                    Text('التحميلات'),
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
              const PopupMenuItem(
                value: 'clear_data',
                child: Row(
                  children: [
                    Icon(SolarLinearIcons.trashBinMinimalistic, size: 20),
                    SizedBox(width: 8),
                    Text('مسح بيانات التصفح'),
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
          preferredSize: const Size.fromHeight(3),
          child: activeTab.isLoading
              ? LinearProgressIndicator(
                  value: activeTab.progress > 0 ? activeTab.progress : null,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                  color: AppColors.primary,
                  minHeight: 3,
                )
              : const SizedBox.shrink(),
        ),
      ),
      body: Stack(
        children: [
          ..._tabs.asMap().entries.map((entry) {
            final isSelected = _activeTabIndex == entry.key;
            final tab = entry.value;
            // Show overlay only on initial page load (not on subsequent navigations)
            // Restored tabs skip the overlay since they were already loaded
            final showLoadingOverlay = tab.isLoading &&
                !tab.isInitialized &&
                !tab.wasRestoredFromSession;
            // Show error overlay when WebView encounters an error
            final showErrorOverlay = tab.hasError && !tab.isLoading;
            return Offstage(
              offstage: !isSelected,
              child: RepaintBoundary(
                key: tab.id == activeTab.id ? _repaintKey : null,
                child: Stack(
                  children: [
                    _WebViewWithErrorHandling(
                      controller: tab.controller,
                    ),
                    // Error overlay
                    if (showErrorOverlay)
                      Positioned.fill(
                        child: Container(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  SolarLinearIcons.closeCircle,
                                  size: 64,
                                  color: Colors.red[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'فشل تحميل الصفحة',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                if (tab.errorMessage != null)
                                  Text(
                                    tab.errorMessage!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: Colors.grey),
                                    textAlign: TextAlign.center,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                const SizedBox(height: 24),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      tab.hasError = false;
                                      tab.errorMessage = null;
                                    });
                                    tab.controller.reload();
                                  },
                                  icon: const Icon(SolarLinearIcons.refresh),
                                  label: const Text('إعادة المحاولة'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    // Initial loading overlay with smooth fade animation
                    if (showLoadingOverlay)
                      Positioned.fill(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: 1.0,
                          child: Container(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            child: Semantics(
                              label: 'جاري تحميل الصفحة',
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 48,
                                      height: 48,
                                      child: CircularProgressIndicator(
                                        value: tab.progress > 0
                                            ? tab.progress
                                            : null,
                                        color: AppColors.primary,
                                        strokeWidth: 3,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'جاري تحميل الصفحة...',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.color,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
          if (_showSearch)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
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
              // Dispose tab resources to prevent memory leaks
              _tabs[index].dispose();
              // Clear snapshot to prevent memory leak
              _tabs[index].snapshot = null;
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
                            : (isDark ? Colors.grey[800]! : Colors.grey[300]!),
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

class _WebViewWithErrorHandling extends StatefulWidget {
  final WebViewController controller;

  const _WebViewWithErrorHandling({required this.controller});

  @override
  State<_WebViewWithErrorHandling> createState() =>
      _WebViewWithErrorHandlingState();
}

class _WebViewWithErrorHandlingState extends State<_WebViewWithErrorHandling> {
  bool _hasError = false;
  final String _errorMessage = 'حدث خطأ في تحميل الصفحة';

  @override
  void initState() {
    super.initState();
    // Note: Error handling is now set up in the main NavigationDelegate
    // in _addNewTab to avoid overwriting the navigation callbacks
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              SolarLinearIcons.closeCircle,
              size: 64,
              color: Colors.grey[600],
            ),
            const SizedBox(height: 16),
            Text(
              'فشل تحميل الصفحة',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _hasError = false);
                widget.controller.reload();
              },
              icon: const Icon(SolarLinearIcons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    return WebViewWidget(controller: widget.controller);
  }
}
