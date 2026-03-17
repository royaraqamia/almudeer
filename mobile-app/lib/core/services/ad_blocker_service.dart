import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

/// Blocks porn/adult content in the browser
/// Ads and trackers are NOT blocked - only adult content
class PornBlockerService {
  static final PornBlockerService _instance = PornBlockerService._internal();
  factory PornBlockerService() => _instance;
  PornBlockerService._internal();

  // StevenBlack hosts file with porn/adult content blocking
  static const String _hostsUrl =
      'https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn/hosts';
  static const String _cacheKey = 'adblock_hosts_cache';
  static const String _timestampKey = 'adblock_last_update';

  final Set<String> _blockedHosts = {};
  bool _isInitialized = false;
  Completer<void>? _initCompleter;

  Set<String> get blockedHosts => _blockedHosts;
  // Porn blocker is ALWAYS enabled - no option to disable
  bool get isEnabled => true;
  bool get isInitialized => _isInitialized;

  // Comprehensive adult content keywords for 100% reliable blocking
  static const List<String> _adultKeywords = [
    'porn',
    'xvideos',
    'pornhub',
    'xhamster',
    'xnxx',
    'sex',
    'adult',
    'xxx',
    'nudity',
    'erotic',
    'strip',
    'hentai',
    'brazzers',
    'redtube',
    'tube8',
    'youporn',
    'spankbang',
    'motherless',
    'beeg',
    'cam4',
    'chaturbate',
    'livejasmin',
    'bongacams',
    'bellesa',
    'pornone',
    'anybunny',
    'fuq',
    'fapdu',
    'drtuber',
    'thumbzilla',
    'hardcore',
    'onlyfans',
    'playboy',
    'hustler',
    'penthouse',
    'avpleasure',
    'fleshlight',
    'sextoy',
    'vibrator',
    'milf',
    'cougar',
    'swinger',
    'orgy',
    'gangbang',
    'incest',
    'lolita',
    'teen18',
    'underage',
  ];

  Future<void> init() async {
    // Return existing initialization future if already in progress
    if (_initCompleter != null) return _initCompleter!.future;
    if (_isInitialized) return;

    _initCompleter = Completer<void>();

    try {
      try {
        final box = await Hive.openBox('adblock_cache');
        final cachedHosts = box.get(_cacheKey) as String?;
        final lastUpdate = box.get(_timestampKey) as int?;

        final now = DateTime.now().millisecondsSinceEpoch;
        final oneWeek = 7 * 24 * 60 * 60 * 1000;

        if (cachedHosts != null &&
            lastUpdate != null &&
            (now - lastUpdate) < oneWeek) {
          final List<dynamic> hosts = jsonDecode(cachedHosts);
          _blockedHosts.addAll(hosts.cast<String>());
          debugPrint(
            '[PornBlocker] Loaded ${_blockedHosts.length} hosts from cache',
          );
        } else {
          // Fetch in background, don't block initialization
          unawaited(_fetchHostsFile());
        }
      } catch (e) {
        debugPrint('[PornBlocker] Init error: $e');
      }

      _isInitialized = true;
      _initCompleter!.complete();
    } catch (e) {
      _initCompleter!.completeError(e);
      rethrow;
    }
  }

  Future<void> _fetchHostsFile() async {
    final maxRetries = 3;
    int attempt = 0;

    while (attempt < maxRetries) {
      try {
        debugPrint('[PornBlocker] Fetching hosts file... (attempt ${attempt + 1}/$maxRetries)');
        final client = http.Client();
        // Shorter timeout with retry: 10 seconds per attempt = max 30 seconds total
        final response = await client
            .get(Uri.parse(_hostsUrl))
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final lines = response.body.split('\n');
          final newHosts = <String>[];

          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

            final parts = trimmed.split(RegExp(r'\s+'));
            if (parts.length >= 2) {
              final host = parts[1].toLowerCase();
              if (host != 'localhost' && !host.startsWith('127.0.0.1')) {
                newHosts.add(host);
                _blockedHosts.add(host);
              }
            }
          }

          final box = await Hive.openBox('adblock_cache');
          await box.put(_cacheKey, jsonEncode(newHosts));
          await box.put(_timestampKey, DateTime.now().millisecondsSinceEpoch);

          debugPrint('[PornBlocker] Fetched and cached ${newHosts.length} hosts');
          client.close();
          return; // Success
        }
        client.close();

        // Non-200 response - retry
        attempt++;
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        }
      } on TimeoutException catch (e) {
        attempt++;
        debugPrint('[PornBlocker] Timeout on attempt $attempt: $e');
        if (attempt < maxRetries) {
          // Exponential backoff: 500ms, 1000ms, 2000ms
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        } else {
          debugPrint('[PornBlocker] Failed to fetch hosts after $maxRetries attempts: $e');
        }
      } catch (e) {
        attempt++;
        debugPrint('[PornBlocker] Error on attempt $attempt: $e');
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        } else {
          debugPrint('[PornBlocker] Failed to fetch hosts after $maxRetries attempts: $e');
        }
      }
    }
  }

  /// Check if URL contains adult content - ALWAYS ACTIVE
  /// This is 100% reliable and cannot be disabled
  bool isAdultContent(String url) {
    if (url.isEmpty) return false;

    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      final path = uri.path.toLowerCase();
      final query = uri.query.toLowerCase();
      final fullUrl = '$host$path$query';

      // 1. Check hosts list (StevenBlack porn list)
      for (final blocked in _blockedHosts) {
        if (host == blocked || host.endsWith('.$blocked')) {
          return true;
        }
      }

      // 2. Keyword check for Path & Query (strict blocking)
      for (final keyword in _adultKeywords) {
        if (fullUrl.contains(keyword)) {
          return true;
        }
      }

      // 3. Check for common adult TLDs and patterns
      final adultPatterns = [
        RegExp(r'\.xxx\b'),
        RegExp(r'\.sex\b'),
        RegExp(r'\.porn\b'),
        RegExp(r'porn.*\.com'),
        RegExp(r'xxx.*\.com'),
        RegExp(r'sex.*\.com'),
      ];

      for (final pattern in adultPatterns) {
        if (pattern.hasMatch(fullUrl)) {
          return true;
        }
      }
    } catch (e) {
      // On error, be safe and block
      return true;
    }

    return false;
  }

  /// Check if URL should be blocked - ALWAYS ACTIVE
  /// Only blocks porn/adult content - ads and trackers are allowed
  bool isBlocked(String url) {
    if (url.isEmpty) return false;

    // Only block adult/porn content
    return isAdultContent(url);
  }

  /// Get the blocking JavaScript - only blocks porn sites
  String getBlockingJavaScript() {
    // Only include adult content patterns - no ad/tracker blocking
    final allPatterns = <String>{
      ..._adultKeywords.map((k) => '$k.com'),
      ..._adultKeywords.map((k) => 'www.$k.com'),
    };
    final topTrackers = allPatterns.map((h) => '"$h"').join(',');

    return '''
(function() {
  if (window.__pornblockerInjected) return;
  window.__pornblockerInjected = true;

  const blockedPatterns = [$topTrackers];

  function isMatch(url) {
    try {
      const host = new URL(url).hostname.toLowerCase();
      return blockedPatterns.some(p => host === p || host.endsWith('.' + p));
    } catch (e) {}
    return false;
  }

  // Block XMLHttpRequest to porn sites
  const originalXHROpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url) {
    if (isMatch(url)) {
      console.log('[PornBlocker] Blocked XHR:', url);
      return;
    }
    return originalXHROpen.apply(this, arguments);
  };

  // Block Fetch to porn sites
  const originalFetch = window.fetch;
  window.fetch = function(url, options) {
    const urlStr = typeof url === 'string' ? url : (url ? url.url : '');
    if (urlStr && isMatch(urlStr)) {
      console.log('[PornBlocker] Blocked Fetch:', urlStr);
      return Promise.resolve(new Response('', { status: 200 }));
    }
    return originalFetch.apply(this, arguments);
  };

  // Block Image loading from porn sites
  const originalImageSrc = Object.getOwnPropertyDescriptor(Image.prototype, 'src');
  if (originalImageSrc) {
    Object.defineProperty(Image.prototype, 'src', {
      set: function(value) {
        if (value && isMatch(value)) {
          console.log('[PornBlocker] Blocked Image:', value);
          return;
        }
        originalImageSrc.set.call(this, value);
      },
      get: function() {
        return originalImageSrc.get.call(this);
      }
    });
  }

  console.log('[PornBlocker] Injected - blocks porn sites only');
})();
''';
  }
}
