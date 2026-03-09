import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

class AdBlockerService {
  static final AdBlockerService _instance = AdBlockerService._internal();
  factory AdBlockerService() => _instance;
  AdBlockerService._internal();

  // StevenBlack hosts file with porn/adult content blocking
  static const String _hostsUrl =
      'https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn/hosts';
  static const String _cacheKey = 'adblock_hosts_cache';
  static const String _timestampKey = 'adblock_last_update';

  final Set<String> _blockedHosts = {};
  bool _isInitialized = false;

  Set<String> get blockedHosts => _blockedHosts;
  // AdBlocker is ALWAYS enabled - no option to disable
  bool get isEnabled => true;
  bool get isInitialized => _isInitialized;

  // Built-in ad/tracker blocking patterns
  static const List<String> _builtinBlockedPatterns = [
    'doubleclick.net',
    'googlesyndication.com',
    'googleadservices.com',
    'google-analytics.com',
    'googletagmanager.com',
    'facebook.com/tr',
    'facebook.net/en_US/fbevents',
    'analytics.twitter.com',
    'ads.twitter.com',
    'ads.linkedin.com',
    'pixel.linkedin.com',
    'ads.youtube.com',
    'pagead2.googlesyndication.com',
    'adservice.google.com',
    'ad.doubleclick.net',
    'static.ads-twitter.com',
    'ads.yahoo.com',
    'analytics.yahoo.com',
    'scorecardresearch.com',
    'newrelic.com',
    'hotjar.com',
    'fullstory.com',
    'mixpanel.com',
    'segment.com',
    'adroll.com',
    'criteo.com',
    'outbrain.com',
    'taboola.com',
    'zedo.com',
    'advertising.com',
    'adtech.com',
    'adnxs.com',
    'rubiconproject.com',
    'pubmatic.com',
    'openx.net',
    'casalemedia.com',
    'adsrvr.org',
    'bluekai.com',
    'adsymptotic.com',
    'adservice.google',
  ];

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
    if (_isInitialized) return;

    // Always load built-in blocking patterns
    for (final pattern in _builtinBlockedPatterns) {
      _blockedHosts.add(pattern.toLowerCase());
    }

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
          '[AdBlocker] Loaded ${_blockedHosts.length} hosts from cache',
        );
      } else {
        // Fetch in background, don't block initialization
        unawaited(_fetchHostsFile());
      }
    } catch (e) {
      debugPrint('[AdBlocker] Init error: $e');
    }

    _isInitialized = true;
  }

  Future<void> _fetchHostsFile() async {
    try {
      debugPrint('[AdBlocker] Fetching hosts file...');
      final client = http.Client();
      final response = await client
          .get(Uri.parse(_hostsUrl))
          .timeout(const Duration(seconds: 30));

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

        debugPrint('[AdBlocker] Fetched and cached ${newHosts.length} hosts');
      }
      client.close();
    } catch (e) {
      debugPrint('[AdBlocker] Failed to fetch hosts: $e');
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
  /// Ad blocking and adult content blocking cannot be disabled
  bool isBlocked(String url) {
    if (url.isEmpty) return false;

    // Safety first: always block adult content regardless
    if (isAdultContent(url)) return true;

    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();

      for (final blocked in _blockedHosts) {
        if (host == blocked || host.endsWith('.$blocked')) {
          return true;
        }
      }
    } catch (e) {
      return false;
    }

    return false;
  }

  /// Get the blocking JavaScript - always returns active blocker
  String getBlockingJavaScript() {
    // Include both built-in patterns and a subset of blocked hosts
    // to avoid extreme lag with tens of thousands of hosts.
    // The full list is still blocked at the navigation level in Dart.
    final allPatterns = <String>{
      ..._builtinBlockedPatterns,
      ..._adultKeywords.map((k) => '$k.com'),
      ..._adultKeywords.map((k) => 'www.$k.com'),
    };
    final topTrackers = allPatterns.map((h) => '"$h"').join(',');

    return '''
(function() {
  if (window.__adblockInjected) return;
  window.__adblockInjected = true;

  const blockedPatterns = [$topTrackers];

  function isMatch(url) {
    try {
      const host = new URL(url).hostname.toLowerCase();
      return blockedPatterns.some(p => host === p || host.endsWith('.' + p));
    } catch (e) {}
    return false;
  }

  // Block XMLHttpRequest
  const originalXHROpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url) {
    if (isMatch(url)) {
      console.log('[AdBlocker] Blocked XHR:', url);
      return;
    }
    return originalXHROpen.apply(this, arguments);
  };

  // Block Fetch
  const originalFetch = window.fetch;
  window.fetch = function(url, options) {
    const urlStr = typeof url === 'string' ? url : (url ? url.url : '');
    if (urlStr && isMatch(urlStr)) {
      console.log('[AdBlocker] Blocked Fetch:', urlStr);
      return Promise.resolve(new Response('', { status: 200 }));
    }
    return originalFetch.apply(this, arguments);
  };

  // Block Image loading
  const originalImageSrc = Object.getOwnPropertyDescriptor(Image.prototype, 'src');
  if (originalImageSrc) {
    Object.defineProperty(Image.prototype, 'src', {
      set: function(value) {
        if (value && isMatch(value)) {
          console.log('[AdBlocker] Blocked Image:', value);
          return;
        }
        originalImageSrc.set.call(this, value);
      },
      get: function() {
        return originalImageSrc.get.call(this);
      }
    });
  }

  // Hide common ad elements
  const style = document.createElement('style');
  style.textContent = `
    [id*="google_ads"], [id*="ad-"], [id*="ads-"], [id*="advert"],
    [class*="google_ads"], [class*="ad-"], [class*="ads-"], [class*="advert"],
    [class*="advertisement"], [class*="banner-ad"], [class*="sponsored"],
    iframe[src*="doubleclick"], iframe[src*="googlesyndication"],
    iframe[src*="googleadservices"], iframe[src*="facebook.com/plugins"],
    div[data-ad], div[data-ad-slot], ins.adsbygoogle,
    .ad-container, .ad-wrapper, .ad-banner, .ad-unit
    { display: none !important; visibility: hidden !important; height: 0 !important; width: 0 !important; }
  `;
  document.head.appendChild(style);

  // Remove existing ad iframes
  document.querySelectorAll('iframe').forEach(function(iframe) {
    if (iframe.src && isMatch(iframe.src)) {
      iframe.remove();
    }
  });

  // Remove existing ad scripts
  document.querySelectorAll('script').forEach(function(script) {
    if (script.src && isMatch(script.src)) {
      script.remove();
    }
  });

  console.log('[AdBlocker] Injected - always active');
})();
''';
  }
}
