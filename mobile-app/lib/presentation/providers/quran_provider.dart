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
  static const String _showTranslationKey = 'quran_show_translation';
  static const String _selectedTafsirKey = 'quran_selected_tafsir';

  final OfflineSyncService? _syncService;
  int? _lastSurah;
  int? _lastVerse;
  double _fontSize = 22.0;
  bool _showTafsir = true;
  bool _showTranslation = false;
  String _selectedTafsir = 'local';
  bool _isInitialized = false;
  bool _isLoadingTafsir = false;
  Timer? _debounceTimer;
  Map<String, dynamic> _tafsirData = {};
  Map<String, dynamic> _translationData = {};
  Map<String, String> _remoteTafsirCache = {};
  bool _tafsirLoaded = false;
  bool _translationLoaded = false;
  
  static const String _remoteTafsirKey = 'quran_remote_tafsir_cache';

  QuranProvider({OfflineSyncService? syncService}) : _syncService = syncService;

  int? get lastSurah => _lastSurah;
  int? get lastVerse => _lastVerse;
  double get fontSize => _fontSize;
  bool get showTafsir => _showTafsir;
  bool get showTranslation => _showTranslation;
  String get selectedTafsir => _selectedTafsir;
  bool get isInitialized => _isInitialized;
  bool get isLoadingTafsir => _isLoadingTafsir;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _lastSurah = prefs.getInt(_lastSurahKey);
    _lastVerse = prefs.getInt(_lastVerseKey);
    _fontSize = prefs.getDouble(_fontSizeKey) ?? 22.0;
    _showTafsir = prefs.getBool(_showTafsirKey) ?? true;
    _showTranslation = prefs.getBool(_showTranslationKey) ?? false;
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
        final serverSurah = progress['last_surah'];
        final serverVerse = progress['last_verse'];
        
        if (serverSurah != null && serverVerse != null) {
          final localSurah = _lastSurah ?? 0;
          final localVerse = _lastVerse ?? 0;
          
          if (serverSurah > localSurah || 
              (serverSurah == localSurah && serverVerse > localVerse)) {
            _lastSurah = serverSurah;
            _lastVerse = serverVerse;
            
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt(_lastSurahKey, serverSurah);
            await prefs.setInt(_lastVerseKey, serverVerse);
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
      final String response = await rootBundle.loadString(
        'assets/json/tafsir_ibn_kathir_full.json',
      );
      _tafsirData = json.decode(response);
      _tafsirLoaded = true;
      debugPrint('Full Ibn Kathir tafsir loaded successfully');
    } catch (e) {
      debugPrint('Error loading full Ibn Kathir tafsir: $e');
      
      // Fallback to standard Ibn Kathir (if exists)
      try {
        final String response = await rootBundle.loadString(
          'assets/json/tafsir_ibn_kathir.json',
        );
        _tafsirData = json.decode(response);
        _tafsirLoaded = true;
        debugPrint('Standard Ibn Kathir tafsir loaded as fallback');
      } catch (e2) {
        debugPrint('Error loading standard Ibn Kathir tafsir: $e2');
        // No more fallbacks - tafsir data not available
      }
    } finally {
      _isLoadingTafsir = false;
      notifyListeners();
    }
  }

  Future<void> loadTranslation() async {
    if (_translationLoaded) return;
    
    try {
      final String response = await rootBundle.loadString(
        'assets/json/translation_en.json',
      );
      _translationData = json.decode(response);
      _translationLoaded = true;
    } catch (e) {
      debugPrint('Error loading translation: $e');
      try {
        final String response = await rootBundle.loadString(
          'assets/json/translation_english.json',
        );
        _translationData = json.decode(response);
        _translationLoaded = true;
      } catch (e2) {
        debugPrint('Error loading fallback translation: $e2');
      }
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

  String getTranslation(int surah, int verse) {
    if (!_translationLoaded) {
      return '';
    }

    final translation = _translationData[surah.toString()]?[verse.toString()];
    if (translation != null && translation.toString().isNotEmpty) {
      return translation.toString();
    }
    return '';
  }

  /// Call this method outside of build phase to load translation data
  Future<void> ensureTranslationLoaded() async {
    if (!_translationLoaded) {
      await loadTranslation();
    }
  }

  Future<void> _fetchRemoteTafsir(int surah, int verse) async {
    final cacheKey = '$surah:$verse';
    if (_remoteTafsirCache.containsKey(cacheKey)) return;

    try {
      // Use Ibn Kathir (Arabic) - ID 169 from Quran.com API
      // This is the most authentic and widely respected tafsir
      final tafsirId = '169'; // Ibn Kathir (Abridged) - Arabic/English
      final url =
          'https://api.quran.com/api/v4/quran/tafsirs/$tafsirId?verse_key=$surah:$verse';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final tafsirs = data['tafsirs'] as List;
        if (tafsirs.isNotEmpty) {
          final text = tafsirs[0]['text'] as String;
          final cleanText = text.replaceAll(RegExp(r'<[^>]*>'), '');

          _remoteTafsirCache[cacheKey] = cleanText;
          notifyListeners();

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            _remoteTafsirKey,
            json.encode(_remoteTafsirCache),
          );
        }
      }
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastSurahKey, surah);
      await prefs.setInt(_lastVerseKey, verse);

      if (_syncService != null) {
        await _syncService.queueQuranProgress(surah, verse);
      }
    });
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

  Future<void> toggleTranslation() async {
    _showTranslation = !_showTranslation;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showTranslationKey, _showTranslation);

    if (_showTranslation) {
      await ensureTranslationLoaded();
    }
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
    super.dispose();
  }
}
