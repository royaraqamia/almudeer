import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:quran/quran.dart' as quran;
import 'package:almudeer_mobile_app/core/services/offline_sync_service.dart';

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
        final serverSurah = progress['last_surah'] as int?;
        final serverVerse = progress['last_verse'] as int?;

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

  Future<void> loadTafsir() async {
    if (_tafsirLoaded) return;
    _isLoadingTafsir = true;
    notifyListeners();

    try {
      // Try loading full Ibn Kathir tafsir first (comprehensive version)
      // Note: This is a large file (~14MB) - may take time on low-end devices
      debugPrint('Loading full Ibn Kathir tafsir...');
      final stopwatch = Stopwatch()..start();
      final String response = await rootBundle.loadString(
        'assets/json/tafsir_ibn_kathir_full.json',
      );
      _tafsirData = json.decode(response);
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

  Future<void> _fetchRemoteTafsir(int surah, int verse) async {
    final cacheKey = '$surah:$verse';
    if (_remoteTafsirCache.containsKey(cacheKey)) return;

    try {
      final url = '$_quranApiBaseUrl/quran/tafsirs/$_defaultTafsirId?verse_key=$surah:$verse';
      final response = await http.get(Uri.parse(url)).timeout(_httpTimeout);

      // Handle different HTTP status codes
      if (response.statusCode == 429) {
        // Rate limited - don't retry immediately
        debugPrint('Tafsir API rate limited (429) for $surah:$verse');
        return;
      } else if (response.statusCode >= 500) {
        // Server error - log but don't crash
        debugPrint('Tafsir API server error (${response.statusCode}) for $surah:$verse');
        return;
      } else if (response.statusCode >= 400) {
        // Client error (4xx) - likely invalid request
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
    } catch (e) {
      debugPrint('Error fetching remote tafsir ($surah:$verse): $e');
    }
  }

  Future<void> saveLastRead(int surah, int verse) async {
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
      await _syncService.queueQuranProgress(surah, verse);
    }
  }

  /// Save immediately without debouncing (called when app is closing)
  Future<void> saveLastReadImmediate() async {
    if (_lastSurah == null || _lastVerse == null) return;
    await _saveToPrefs(_lastSurah!, _lastVerse!);
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
    if (_lastSurah == null) return 'لم يتم القراءة بعد';
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
