import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:quran/quran.dart' as quran;
import 'package:almudeer_mobile_app/core/services/offline_sync_service.dart';

/// Top-level function for compute isolate (JSON parsing)
/// Must be top-level to be sent to isolate
Map<String, dynamic> _parseTafsirJson(String jsonString) {
  return json.decode(jsonString) as Map<String, dynamic>;
}

class QuranProvider extends ChangeNotifier {
  static const String _lastSurahKey = 'quran_last_surah';
  static const String _lastVerseKey = 'quran_last_verse';
  static const String _fontSizeKey = 'quran_font_size';
  static const String _showTafsirKey = 'quran_show_tafsir';
  static const String _selectedTafsirKey = 'quran_selected_tafsir';

  final OfflineSyncService? _syncService;
  int? _lastSurah;
  int? _lastVerse;
  double _fontSize = 22.0;
  bool _showTafsir = true;
  String _selectedTafsir = 'local';
  bool _isInitialized = false;
  bool _isLoadingTafsir = false;
  Timer? _debounceTimer;
  Map<String, dynamic> _tafsirData = {};
  Map<String, String> _remoteTafsirCache = {};
  final Set<String> _pendingTafsirRequests = {}; // Track verses being fetched
  bool _tafsirLoaded = false;

  static const String _remoteTafsirKey = 'quran_remote_tafsir_cache';
  static const int _maxRemoteTafsirCacheSize = 200; // LRU cache limit to prevent storage bloat

  QuranProvider({OfflineSyncService? syncService}) : _syncService = syncService;

  int? get lastSurah => _lastSurah;
  int? get lastVerse => _lastVerse;
  double get fontSize => _fontSize;
  bool get showTafsir => _showTafsir;
  String get selectedTafsir => _selectedTafsir;
  bool get isInitialized => _isInitialized;
  bool get isLoadingTafsir => _isLoadingTafsir;

  /// Check if a specific verse's tafsir is being fetched
  bool isTafsirPending(int surah, int verse) {
    final cacheKey = '$surah:$verse';
    return _pendingTafsirRequests.contains(cacheKey);
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _lastSurah = prefs.getInt(_lastSurahKey);
    _lastVerse = prefs.getInt(_lastVerseKey);
    _fontSize = prefs.getDouble(_fontSizeKey) ?? 22.0;
    _showTafsir = prefs.getBool(_showTafsirKey) ?? true;
    _selectedTafsir = prefs.getString(_selectedTafsirKey) ?? 'local';

    final remoteCacheStr = prefs.getString(_remoteTafsirKey);
    if (remoteCacheStr != null) {
      try {
        _remoteTafsirCache = Map<String, String>.from(
          json.decode(remoteCacheStr),
        );
      } catch (e) {
        debugPrint('Error decoding remote tafsir cache: $e');
      }
    }

    await _fetchServerProgress();

    _isInitialized = true;
    notifyListeners();
  }

  Future<void> _fetchServerProgress() async {
    if (_syncService == null) return;

    try {
      final response = await _syncService.getQuranProgress();
      if (response != null && response['progress'] != null) {
        final progress = response['progress'];
        
        // CRITICAL: Safe type coercion - handle both int and String values
        final serverSurah = _safeParseInt(progress['last_surah']);
        final serverVerse = _safeParseInt(progress['last_verse']);

        // CRITICAL: Ensure both values are non-null before comparison
        if (serverSurah != null && serverVerse != null) {
          // Validate surah range (1-114) and verse range (positive)
          if (serverSurah < 1 || serverSurah > 114 || serverVerse < 1) {
            debugPrint('Invalid server progress: surah=$serverSurah, verse=$serverVerse');
            return;
          }

          final localSurah = _lastSurah ?? 0;
          final localVerse = _lastVerse ?? 0;

          if (serverSurah > localSurah ||
              (serverSurah == localSurah && serverVerse > localVerse)) {
            _lastSurah = serverSurah;
            _lastVerse = serverVerse;

            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt(_lastSurahKey, serverSurah);
            await prefs.setInt(_lastVerseKey, serverVerse);
            debugPrint('Updated progress from server: Surah $serverSurah, Verse $serverVerse');
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching server quran progress: $e');
    }
  }

  /// Safely parse int from various types (int, String, double)
  /// Returns null if parsing fails or value is invalid
  int? _safeParseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    if (value is double) {
      // Reject non-integer doubles (e.g., 1.9) but accept integer doubles (e.g., 1.0)
      if (value == value.toInt()) {
        return value.toInt();
      }
      return null;
    }
    return null;
  }

  Future<void> loadTafsir() async {
    if (_tafsirLoaded) return;
    _isLoadingTafsir = true;
    notifyListeners();

    try {
      // Try loading full Ibn Kathir tafsir first (comprehensive version)
      // Note: This is a large file (~14MB) - may take time on low-end devices
      debugPrint('Loading full Ibn Kathir tafsir...');
      final stopwatch = Stopwatch()..start();
      
      // Load string from assets
      final String jsonString = await rootBundle.loadString(
        'assets/json/tafsir_ibn_kathir_full.json',
      );
      
      // Parse JSON in a separate isolate to prevent UI jank
      _tafsirData = await compute(_parseTafsirJson, jsonString);
      
      _tafsirLoaded = true;
      stopwatch.stop();
      debugPrint('Full Ibn Kathir tafsir loaded successfully in ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      debugPrint('Error loading full Ibn Kathir tafsir: $e');
      // No fallback - the full version is the only supported format now
      _tafsirLoaded = true; // Mark as loaded to prevent retry loops
      _tafsirData = {}; // Empty data means tafsir unavailable
    } finally {
      _isLoadingTafsir = false;
      notifyListeners();
    }
  }

  String getTafsir(int surah, int verse) {
    if (!_tafsirLoaded) {
      return '';
    }

    if (_selectedTafsir == 'local') {
      // Try new comprehensive format first (metadata.tafsir[].ayahs[])
      if (_tafsirData.containsKey('tafsir') && _tafsirData['tafsir'] is List) {
        final tafsirList = _tafsirData['tafsir'] as List;
        if (surah >= 1 && surah <= tafsirList.length) {
          final surahData = tafsirList[surah - 1];
          if (surahData.containsKey('ayahs') && surahData['ayahs'] is List) {
            final ayahs = surahData['ayahs'] as List;
            for (final ayah in ayahs) {
              if (ayah['ayah'] == verse) {
                return ayah['text'] ?? '';
              }
            }
          }
        }
      }
      
      // Fallback to old format: { "1": { "1": "text", ... }, "2": { ... } }
      final local = _tafsirData[surah.toString()]?[verse.toString()];
      if (local != null && local.toString().isNotEmpty) {
        return local.toString();
      }
    }

    final cacheKey = '$surah:$verse';
    if (_remoteTafsirCache.containsKey(cacheKey)) {
      return _remoteTafsirCache[cacheKey]!;
    }

    return '';
  }

  /// Call this method outside of build phase to load tafsir data
  Future<void> ensureTafsirLoaded() async {
    if (!_tafsirLoaded && !_isLoadingTafsir) {
      await loadTafsir();
    }
  }

  /// Call this method outside of build phase to fetch remote tafsir
  void fetchRemoteTafsirIfNeeded(int surah, int verse) {
    if (_tafsirLoaded && _selectedTafsir != 'local') {
      final cacheKey = '$surah:$verse';
      if (!_remoteTafsirCache.containsKey(cacheKey)) {
        _fetchRemoteTafsir(surah, verse);
      }
    }
  }

  /// Quran.com API base URL - configurable for environment switching
  static const String _quranApiBaseUrl = 'https://api.quran.com/api/v4';
  
  /// Ibn Kathir (Abridged) - Arabic/English - most authentic and widely respected tafsir
  static const String _defaultTafsirId = '169';
  
  /// HTTP request timeout duration
  static const Duration _httpTimeout = Duration(seconds: 10);

  /// Maximum retry attempts for failed tafsir requests
  static const int _maxTafsirRetries = 2;

  /// Base delay for exponential backoff (milliseconds)
  static const int _tafsirRetryBaseDelayMs = 500;

  Future<void> _fetchRemoteTafsir(int surah, int verse, {int retryCount = 0}) async {
    final cacheKey = '$surah:$verse';
    if (_remoteTafsirCache.containsKey(cacheKey)) return;
    if (_pendingTafsirRequests.contains(cacheKey)) return; // Already fetching

    // Mark as pending
    _pendingTafsirRequests.add(cacheKey);
    notifyListeners();

    try {
      final url = '$_quranApiBaseUrl/quran/tafsirs/$_defaultTafsirId?verse_key=$surah:$verse';
      final response = await http.get(Uri.parse(url)).timeout(_httpTimeout);

      // Handle different HTTP status codes
      if (response.statusCode == 429) {
        // Rate limited - don't retry immediately
        debugPrint('Tafsir API rate limited (429) for $surah:$verse');
        return;
      } else if (response.statusCode >= 500) {
        // Server error - retry with exponential backoff
        debugPrint('Tafsir API server error (${response.statusCode}) for $surah:$verse');
        
        if (retryCount < _maxTafsirRetries) {
          final delayMs = _tafsirRetryBaseDelayMs * (1 << retryCount); // Exponential backoff
          final jitter = DateTime.now().millisecondsSinceEpoch % 200;
          debugPrint('Retrying tafsir fetch in ${delayMs + jitter}ms (attempt ${retryCount + 1}/$_maxTafsirRetries)');
          await Future.delayed(Duration(milliseconds: delayMs + jitter));
          await _fetchRemoteTafsir(surah, verse, retryCount: retryCount + 1);
        }
        return;
      } else if (response.statusCode >= 400) {
        // Client error (4xx) - likely invalid request, don't retry
        debugPrint('Tafsir API client error (${response.statusCode}) for $surah:$verse: ${response.body}');
        return;
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final tafsirs = data['tafsirs'] as List?;
        if (tafsirs != null && tafsirs.isNotEmpty) {
          final textObj = tafsirs[0]['text'];
          if (textObj != null) {
            final text = textObj.toString();
            final cleanText = text.replaceAll(RegExp(r'<[^>]*>'), '');

            // LRU Cache: Remove oldest entry if cache is full
            if (_remoteTafsirCache.length >= _maxRemoteTafsirCacheSize) {
              // Remove the first (oldest) entry
              final oldestKey = _remoteTafsirCache.keys.first;
              _remoteTafsirCache.remove(oldestKey);
              debugPrint('LRU cache full: evicted oldest entry ($oldestKey)');
            }

            _remoteTafsirCache[cacheKey] = cleanText;
            notifyListeners();

            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(
              _remoteTafsirKey,
              json.encode(_remoteTafsirCache),
            );
          }
        }
      }
    } on TimeoutException {
      debugPrint('Timeout fetching remote tafsir ($surah:$verse)');
      
      // Retry on timeout with exponential backoff
      if (retryCount < _maxTafsirRetries) {
        final delayMs = _tafsirRetryBaseDelayMs * (1 << retryCount);
        final jitter = DateTime.now().millisecondsSinceEpoch % 200;
        debugPrint('Retrying tafsir fetch after timeout in ${delayMs + jitter}ms (attempt ${retryCount + 1}/$_maxTafsirRetries)');
        await Future.delayed(Duration(milliseconds: delayMs + jitter));
        await _fetchRemoteTafsir(surah, verse, retryCount: retryCount + 1);
      }
    } catch (e) {
      debugPrint('Error fetching remote tafsir ($surah:$verse): $e');
    } finally {
      // Always remove from pending
      _pendingTafsirRequests.remove(cacheKey);
      notifyListeners();
    }
  }

  /// Maximum number of verses in any surah (Al-Baqarah)
  static const int _maxVersesInSurah = 286;

  /// Validate surah and verse numbers
  bool _isValidProgress(int surah, int verse) {
    return surah >= 1 && surah <= 114 && verse >= 1 && verse <= _maxVersesInSurah;
  }

  Future<void> saveLastRead(int surah, int verse) async {
    // Validate input before saving
    if (!_isValidProgress(surah, verse)) {
      debugPrint('Invalid Quran progress: surah=$surah, verse=$verse');
      return;
    }

    if (_lastSurah == surah && _lastVerse == verse) return;

    _lastSurah = surah;
    _lastVerse = verse;
    notifyListeners();

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () async {
      await _saveToPrefs(surah, verse);
    });
  }

  /// Save immediately to SharedPreferences (used on dispose to prevent data loss)
  Future<void> _saveToPrefs(int surah, int verse) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastSurahKey, surah);
    await prefs.setInt(_lastVerseKey, verse);

    if (_syncService != null) {
      try {
        await _syncService.queueQuranProgress(surah, verse);
      } catch (e) {
        // Log but don't fail - sync will retry later
        debugPrint('Failed to queue Quran progress for sync: $e');
      }
    }
  }

  /// Save immediately without debouncing (called when app is closing)
  Future<void> saveLastReadImmediate() async {
    if (_lastSurah == null || _lastVerse == null) return;

    final surah = _lastSurah!;
    final verse = _lastVerse!;

    // Validate before saving with detailed logging for debugging
    if (!_isValidProgress(surah, verse)) {
      debugPrint('⚠️ Invalid Quran progress on dispose - possible data corruption:');
      debugPrint('   Surah: $surah (expected: 1-114)');
      debugPrint('   Verse: $verse (expected: 1-$_maxVersesInSurah)');
      debugPrint('   Action: Skipping save to prevent corruption');
      return;
    }

    try {
      await _saveToPrefs(surah, verse);
      debugPrint('✓ Saved Quran progress: Surah $surah, Verse $verse');
    } catch (e) {
      debugPrint('❌ Error saving Quran progress on dispose: $e');
    }
  }

  Future<void> setFontSize(double size) async {
    _fontSize = size;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, size);
  }

  Future<void> toggleTafsir() async {
    _showTafsir = !_showTafsir;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showTafsirKey, _showTafsir);
  }

  Future<void> setSelectedTafsir(String tafsir) async {
    _selectedTafsir = tafsir;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedTafsirKey, tafsir);
  }

  String get lastReadLabel {
    if (_lastSurah == null || _lastVerse == null) return 'لم يتم القراءة بعد';
    final surahName = quran.getSurahNameArabic(_lastSurah!);
    return 'سورة $surahName، الآية $_lastVerse';
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    // Save immediately to prevent data loss when provider is disposed
    // This handles the race condition where user navigates away before debounce fires
    saveLastReadImmediate();
    super.dispose();
  }
}
