import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:quran/quran.dart' as quran;
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';
import 'package:almudeer_mobile_app/presentation/providers/quran_provider.dart';
import 'package:almudeer_mobile_app/presentation/providers/audio_player_provider.dart';
import 'package:almudeer_mobile_app/presentation/widgets/quran/verse_separator.dart';
import 'package:almudeer_mobile_app/presentation/widgets/custom_dialog.dart';
import 'package:almudeer_mobile_app/presentation/widgets/animated_toast.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class SurahDetailScreen extends StatefulWidget {
  final int surahNumber;
  final int? initialVerse;

  const SurahDetailScreen({
    super.key,
    required this.surahNumber,
    this.initialVerse,
  });

  @override
  State<SurahDetailScreen> createState() => _SurahDetailScreenState();
}

class _SurahDetailScreenState extends State<SurahDetailScreen>
    with TickerProviderStateMixin {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  bool _isAutoScrolling = false;

  int _currentReciter = 0;
  bool _isLoadingAudio = false;
  bool _isLoadingTimings = false;

  // Track which verses have been requested for remote tafsir to prevent duplicate requests
  final Set<String> _requestedTafsirVerses = {};

  // Track highlighted (playing) verse
  int? _highlightedVerse;

  // For tafsir fade-in animation
  final Map<int, AnimationController> _tafsirAnimationControllers = {};
  final Map<int, Animation<double>> _tafsirFadeAnimations = {};

  // Bookmarked verses
  final Set<int> _bookmarkedVerses = {};

  // Translation cache for visible verses
  final Map<int, String> _translationCache = {};

  // Repeat mode UI
  bool _isSettingRepeatStart = false;
  bool _isSettingRepeatEnd = false;

  static const List<Map<String, String>> _reciters = [
    {'name': 'عبدالرحمن السديس', 'server': 'https://server8.mp3quran.net/sds/'},
    {'name': 'مشاري العفاسي', 'server': 'https://server8.mp3quran.net/afs/'},
    {'name': 'سعد الغامدي', 'server': 'https://server6.mp3quran.net/ghamdi/'},
    {'name': 'ماهر المعيقلي', 'server': 'https://server12.mp3quran.net/maher/'},
    {
      'name': 'محمود خليل الحصري',
      'server': 'https://server13.mp3quran.net/husr/',
    },
    {
      'name': 'محمد صديق المنشاوي',
      'server': 'https://server10.mp3quran.net/minsh/',
    },
    {'name': 'محمد أيوب', 'server': 'https://server8.mp3quran.net/ayyub/'},
  ];

  @override
  void initState() {
    super.initState();
    _itemPositionsListener.itemPositions.addListener(_onScroll);

    // Load tafsir data outside of build phase
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<QuranProvider>().ensureTafsirLoaded();
      _loadVerseTimings();
    });

    if (widget.initialVerse != null) {
      _isAutoScrolling = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToVerse(widget.initialVerse!);
      });
    }
  }

  /// Load verse timings for audio sync
  Future<void> _loadVerseTimings() async {
    if (_isLoadingTimings) return;
    setState(() => _isLoadingTimings = true);

    final quranProvider = context.read<QuranProvider>();
    await quranProvider.getVerseTimings(widget.surahNumber);

    setState(() => _isLoadingTimings = false);
  }

  void _scrollToVerse(int verseNumber) {
    if (_itemScrollController.isAttached) {
      _itemScrollController.jumpTo(index: verseNumber - 1);
      _isAutoScrolling = false;
    }
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(_onScroll);
    // Dispose all animation controllers
    for (final controller in _tafsirAnimationControllers.values) {
      controller.dispose();
    }
    // Don't stop audio - let it continue playing in background
    super.dispose();
  }

  void _onScroll() {
    if (_isAutoScrolling) return;

    final positions = _itemPositionsListener.itemPositions.value;
    final visiblePositions = positions
        .where((position) => position.itemLeadingEdge >= 0)
        .toList();

    if (visiblePositions.isNotEmpty) {
      final min = visiblePositions.reduce(
        (min, position) =>
            position.itemLeadingEdge < min.itemLeadingEdge ? position : min,
      );

      // Update last read verse (index + 1)
      final verseNumber = min.index + 1;
      context.read<QuranProvider>().saveLastRead(
        widget.surahNumber,
        verseNumber,
      );
    }
  }

  /// Fallback servers for each reciter - used when primary server fails
  static const List<List<String>> _reciterFallbackServers = [
    // Corresponds to _reciters order - backup mp3quran.net mirrors
    ['https://server7.mp3quran.net/sds/'], // السديس
    ['https://server11.mp3quran.net/afs/'], // العفاسي
    ['https://server8.mp3quran.net/ghamdi/'], // الغامدي
    ['https://server7.mp3quran.net/maher/'], // المعيقلي
    ['https://server11.mp3quran.net/husr/'], // الحصري
    ['https://server7.mp3quran.net/minsh/'], // المنشاوي
    ['https://server11.mp3quran.net/ayyub/'], // أيوب
  ];

  /// Track failed servers to avoid retrying them
  final Set<String> _failedServers = {};

  Future<void> _loadAndPlaySurah({int retryCount = 0}) async {
    // Get audio provider safely
    final audioProvider = context.read<AudioPlayerProvider>();

    // Don't show loading if already playing this surah
    final isCurrentSurah =
        audioProvider.currentAudioTitle ==
        quran.getSurahNameArabic(widget.surahNumber);
    if (!isCurrentSurah || !audioProvider.isPlaying) {
      setState(() => _isLoadingAudio = true);
    }

    try {
      // Try primary server first
      String serverUrl = _reciters[_currentReciter]['server']!;

      // If primary failed before, try fallback
      final primaryServerKey = '${_currentReciter}_primary';
      if (_failedServers.contains(primaryServerKey) && retryCount == 0) {
        final fallbackServers = _reciterFallbackServers[_currentReciter];
        if (fallbackServers.isNotEmpty) {
          serverUrl = fallbackServers[0];
          debugPrint(
            'Using fallback server for reciter ${_reciters[_currentReciter]['name']}',
          );
        }
      }

      final paddedSurah = widget.surahNumber.toString().padLeft(3, '0');
      final url = '$serverUrl$paddedSurah.mp3';
      final surahName = quran.getSurahNameArabic(widget.surahNumber);

      // Pass surah number for verse timing sync
      await audioProvider.playQuranRecitation(
        url,
        surahName,
        surahNumber: widget.surahNumber,
      );

      // Highlight first verse when starting playback
      setState(() => _highlightedVerse = 1);

      // Success - clear failed server mark
      _failedServers.remove(primaryServerKey);
    } catch (e) {
      debugPrint('Error loading audio (attempt ${retryCount + 1}): $e');

      // Mark primary server as failed
      final primaryServerKey = '${_currentReciter}_primary';
      _failedServers.add(primaryServerKey);

      // Retry once with fallback server
      if (retryCount < 1 &&
          _reciterFallbackServers[_currentReciter].isNotEmpty) {
        debugPrint('Retrying with fallback server...');
        await Future.delayed(const Duration(milliseconds: 500));
        await _loadAndPlaySurah(retryCount: retryCount + 1);
        return;
      }

      if (mounted) {
        AnimatedToast.error(
          context,
          'خطأ في تحميل الصوت - تأكد من اتصال الإنترنت',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingAudio = false);
      }
    }
  }

  void _changeReciter(int index) {
    Haptics.selection();
    setState(() => _currentReciter = index);
    final audioProvider = context.read<AudioPlayerProvider>();
    audioProvider.stopQuranRecitation();
    _loadAndPlaySurah();
  }

  /// Get tafsir source name for display
  String _getTafsirSourceName(String selectedTafsir) {
    if (selectedTafsir == 'local') {
      return 'تفسير ابن كثير (الكامل)';
    }
    // For remote tafsir, show the actual source name
    return 'تفسير ابن كثير (المختصر)';
  }

  /// Create or get fade-in animation controller for a verse's tafsir
  Animation<double> _getTafsirFadeAnimation(int verseNumber) {
    if (!_tafsirFadeAnimations.containsKey(verseNumber)) {
      final controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300),
      );
      _tafsirAnimationControllers[verseNumber] = controller;
      _tafsirFadeAnimations[verseNumber] = CurvedAnimation(
        parent: controller,
        curve: Curves.easeInOut,
      );
      controller.forward();
    }
    return _tafsirFadeAnimations[verseNumber]!;
  }

  /// Toggle bookmark for a verse
  void _toggleBookmark(int verseNumber) {
    Haptics.lightTap();
    setState(() {
      if (_bookmarkedVerses.contains(verseNumber)) {
        _bookmarkedVerses.remove(verseNumber);
        AnimatedToast.info(context, 'تمت إزالة العلامة');
      } else {
        _bookmarkedVerses.add(verseNumber);
        AnimatedToast.success(context, 'تمت إضافة العلامة');
      }
    });
  }

  /// Show verse action menu on long press
  void _showVerseActionMenu(int verseNumber, String verseText) {
    Haptics.mediumTap();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(SolarLinearIcons.share),
              title: const Text('مشاركة الآية'),
              onTap: () {
                Navigator.pop(context);
                _shareVerse(verseNumber, verseText);
              },
            ),
            ListTile(
              leading: Icon(
                _bookmarkedVerses.contains(verseNumber)
                    ? SolarBoldIcons.bookmark
                    : SolarLinearIcons.bookmark,
                color: _bookmarkedVerses.contains(verseNumber)
                    ? AppColors.primary
                    : null,
              ),
              title: Text(
                _bookmarkedVerses.contains(verseNumber)
                    ? 'إزالة العلامة'
                    : 'إضافة علامة',
              ),
              onTap: () {
                Navigator.pop(context);
                _toggleBookmark(verseNumber);
              },
            ),
            ListTile(
              leading: const Icon(SolarLinearIcons.copy),
              title: const Text('نص الآية'),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: verseText));
                AnimatedToast.success(context, 'تم نسخ النص');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Share verse text
  void _shareVerse(int verseNumber, String verseText) {
    Haptics.lightTap();
    final text =
        '$verseText\n\n[سورة ${quran.getSurahNameArabic(widget.surahNumber)}: $verseNumber]';
    Clipboard.setData(ClipboardData(text: text));
    AnimatedToast.success(context, 'تم نسخ الآية للمشاركة');
  }

  /// Show mushaf type selector
  void _showMushafTypeSelector() {
    Haptics.selection();
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            const Text(
              'نوع المصحف',
              style: TextStyle(
                fontFamily: 'IBM Plex Sans Arabic',
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Consumer<QuranProvider>(
              builder: (context, provider, _) {
                return Column(
                  children: [
                    _buildMushafOption(
                      MushafType.uthmani,
                      'الرسم العثماني',
                      SolarLinearIcons.book2,
                      provider.mushafType == MushafType.uthmani,
                    ),
                    _buildMushafOption(
                      MushafType.indopak,
                      'الرسم الهندي',
                      SolarLinearIcons.book2,
                      provider.mushafType == MushafType.indopak,
                    ),
                    _buildMushafOption(
                      MushafType.tajweed,
                      'مصحف التجويد',
                      SolarLinearIcons.palette,
                      provider.mushafType == MushafType.tajweed,
                    ),
                    _buildMushafOption(
                      MushafType.simple,
                      'بدون تشكيل',
                      SolarLinearIcons.text,
                      provider.mushafType == MushafType.simple,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildMushafOption(
    MushafType type,
    String label,
    IconData icon,
    bool isSelected,
  ) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: isSelected
          ? const Icon(Icons.check, color: AppColors.primary)
          : null,
      onTap: () {
        Haptics.lightTap();
        context.read<QuranProvider>().setMushafType(type);
        Navigator.pop(context);
      },
    );
  }

  /// Show translation selector
  void _showTranslationSelector() {
    Haptics.selection();
    showModalBottomSheet(
      context: context,
      builder: (context) => Consumer<QuranProvider>(
        builder: (context, provider, _) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 16),
                const Text(
                  'الترجمة',
                  style: TextStyle(
                    fontFamily: 'IBM Plex Sans Arabic',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildTranslationOption(
                  TranslationLanguage.none,
                  'بدون ترجمة',
                  provider.translation == TranslationLanguage.none,
                ),
                _buildTranslationOption(
                  TranslationLanguage.english,
                  'English (Sahih International)',
                  provider.translation == TranslationLanguage.english,
                ),
                _buildTranslationOption(
                  TranslationLanguage.urdu,
                  'اردو (محمد جالندھری)',
                  provider.translation == TranslationLanguage.urdu,
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTranslationOption(
    TranslationLanguage language,
    String label,
    bool isSelected,
  ) {
    return ListTile(
      leading: Icon(
        isSelected ? SolarBoldIcons.earth : SolarLinearIcons.earth,
        color: isSelected ? AppColors.primary : null,
      ),
      title: Text(label),
      trailing: isSelected
          ? const Icon(Icons.check, color: AppColors.primary)
          : null,
      onTap: () {
        Haptics.lightTap();
        context.read<QuranProvider>().setTranslation(language);
        Navigator.pop(context);
        _translationCache.clear(); // Clear cache when changing language
      },
    );
  }

  /// Show playback settings (speed, repeat, auto-scroll)
  void _showPlaybackSettings() {
    Haptics.selection();
    showModalBottomSheet(
      context: context,
      builder: (context) => Consumer<QuranProvider>(
        builder: (context, provider, _) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 16),
                const Text(
                  'إعدادات التشغيل',
                  style: TextStyle(
                    fontFamily: 'IBM Plex Sans Arabic',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                // Playback speed
                ListTile(
                  leading: const Icon(Icons.speed),
                  title: const Text('سرعة التشغيل'),
                  subtitle: Text('${provider.playbackSpeed}x'),
                  trailing: SizedBox(
                    width: 100,
                    child: Slider(
                      value: provider.playbackSpeed,
                      min: 0.5,
                      max: 2.0,
                      divisions: 6,
                      label: '${provider.playbackSpeed}x',
                      onChanged: (value) {
                        provider.setPlaybackSpeed(value);
                      },
                    ),
                  ),
                ),
                // Auto-scroll toggle
                SwitchListTile(
                  secondary: const Icon(SolarLinearIcons.arrowDown),
                  title: const Text('التمرير التلقائي'),
                  subtitle: const Text('تتبع الآية المقروءة'),
                  value: provider.autoScroll,
                  onChanged: (value) {
                    Haptics.selection();
                    provider.toggleAutoScroll();
                  },
                ),
                // Repeat mode toggle
                SwitchListTile(
                  secondary: Icon(
                    provider.repeatMode
                        ? SolarBoldIcons.repeat
                        : SolarLinearIcons.repeat,
                  ),
                  title: const Text('وضع التكرار'),
                  subtitle: const Text('تكرار الآيات للحفظ'),
                  value: provider.repeatMode,
                  onChanged: (value) {
                    Haptics.selection();
                    provider.toggleRepeatMode();
                    if (!value) {
                      provider.clearRepeatRange();
                    }
                  },
                ),
                if (provider.repeatMode) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Haptics.lightTap();
                              setState(() {
                                _isSettingRepeatStart = true;
                                _isSettingRepeatEnd = false;
                              });
                              AnimatedToast.info(
                                context,
                                'اختر الآية بداية للتكرار',
                              );
                            },
                            icon: const Icon(SolarLinearIcons.bookmark),
                            label: Text(
                              _isSettingRepeatStart
                                  ? 'جاري التحديد...'
                                  : provider.repeatStartVerse != null
                                      ? 'البداية: ${provider.repeatStartVerse}'
                                      : 'تحديد البداية',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Haptics.lightTap();
                              setState(() {
                                _isSettingRepeatEnd = true;
                                _isSettingRepeatStart = false;
                              });
                              AnimatedToast.info(
                                context,
                                'اختر الآية نهاية للتكرار',
                              );
                            },
                            icon: const Icon(SolarLinearIcons.bookmark),
                            label: Text(
                              _isSettingRepeatEnd
                                  ? 'جاري التحديد...'
                                  : provider.repeatEndVerse != null
                                      ? 'النهاية: ${provider.repeatEndVerse}'
                                      : 'تحديد النهاية',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // Sleep timer
                const Divider(),
                Consumer<AudioPlayerProvider>(
                  builder: (context, audioProvider, _) {
                    return Column(
                      children: [
                        SwitchListTile(
                          secondary: const Icon(Icons.timer),
                          title: const Text('مؤقت النوم'),
                          subtitle: Text(
                            audioProvider.isSleepTimerActive
                                ? 'متبقي: ${audioProvider.sleepTimerLabel}'
                                : 'إيقاف التشغيل بعد وقت محدد',
                          ),
                          value: audioProvider.isSleepTimerActive,
                          onChanged: (value) {
                            if (value) {
                              _showSleepTimerDurationSelector();
                            } else {
                              Haptics.selection();
                              audioProvider.cancelSleepTimer();
                            }
                          },
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Set repeat point (called when user selects a verse)
  void _setRepeatPoint(int verseNumber) {
    final quranProvider = context.read<QuranProvider>();

    if (_isSettingRepeatStart) {
      quranProvider.setRepeatRange(
        verseNumber,
        quranProvider.repeatEndVerse ?? verseNumber,
      );
      setState(() => _isSettingRepeatStart = false);
      AnimatedToast.success(context, 'تم تحديد بداية التكرار');
    } else if (_isSettingRepeatEnd) {
      quranProvider.setRepeatRange(
        quranProvider.repeatStartVerse ?? verseNumber,
        verseNumber,
      );
      setState(() => _isSettingRepeatEnd = false);
      AnimatedToast.success(context, 'تم تحديد نهاية التكرار');
    }
  }

  /// Show sleep timer duration selector
  void _showSleepTimerDurationSelector() {
    Haptics.selection();
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            const Text(
              'مدة مؤقت النوم',
              style: TextStyle(
                fontFamily: 'IBM Plex Sans Arabic',
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildSleepTimerOption(
              '15 دقيقة',
              const Duration(minutes: 15),
            ),
            _buildSleepTimerOption(
              '30 دقيقة',
              const Duration(minutes: 30),
            ),
            _buildSleepTimerOption(
              '45 دقيقة',
              const Duration(minutes: 45),
            ),
            _buildSleepTimerOption(
              'ساعة',
              const Duration(minutes: 60),
            ),
            _buildSleepTimerOption(
              'ساعتين',
              const Duration(minutes: 120),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(
                SolarLinearIcons.closeCircle,
                color: Colors.red,
              ),
              title: const Text(
                'إلغاء المؤقت',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                context.read<AudioPlayerProvider>().cancelSleepTimer();
                AnimatedToast.info(context, 'تم إلغاء مؤقت النوم');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildSleepTimerOption(String label, Duration duration) {
    return ListTile(
      leading: const Icon(Icons.timer),
      title: Text(label),
      onTap: () {
        Haptics.lightTap();
        Navigator.pop(context);
        context.read<AudioPlayerProvider>().setSleepTimer(duration);
        AnimatedToast.success(context, 'تم ضبط مؤقت النوم: $label');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verseCount = quran.getVerseCount(widget.surahNumber);
    final quranProvider = context.watch<QuranProvider>();
    final fontFamily = quranProvider.getFontFamily();

    return Consumer<AudioPlayerProvider>(
      builder: (context, audioProvider, _) {
        final isPlaying = audioProvider.isPlaying;
        final isCurrentSurah =
            audioProvider.currentAudioTitle ==
            quran.getSurahNameArabic(widget.surahNumber);

        // Update highlighted verse based on audio position
        if (isPlaying && isCurrentSurah && quranProvider.autoScroll) {
          final currentVerse = audioProvider.currentVerse;
          if (currentVerse != _highlightedVerse) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() => _highlightedVerse = currentVerse);
                _itemScrollController.scrollTo(
                  index: currentVerse - 1,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                );

                // Handle repeat mode
                if (quranProvider.repeatMode &&
                    quranProvider.repeatEndVerse != null &&
                    currentVerse >= quranProvider.repeatEndVerse!) {
                  audioProvider.handleRepeatSeek(quranProvider.repeatStartVerse);
                }
              }
            });
          }
        }

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            title: Text(
              quran.getSurahNameArabic(widget.surahNumber),
              style: const TextStyle(
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
              onPressed: () {
                Haptics.lightTap();
                Navigator.pop(context);
              },
            ),
            actions: [
              // Play/Pause button
              Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: Icon(
                      isPlaying && isCurrentSurah
                          ? SolarBoldIcons.pause
                          : SolarLinearIcons.play,
                      color: (isPlaying && isCurrentSurah)
                          ? AppColors.primary
                          : null,
                    ),
                    onPressed: () {
                      final isActuallyCurrentSurah =
                          audioProvider.currentAudioTitle ==
                          quran.getSurahNameArabic(widget.surahNumber);

                      if (isActuallyCurrentSurah && isPlaying) {
                        audioProvider.handler?.pause();
                        Haptics.lightTap();
                      } else if (isActuallyCurrentSurah && !isPlaying) {
                        audioProvider.handler?.play();
                        Haptics.lightTap();
                      } else {
                        Haptics.lightTap();
                        _loadAndPlaySurah();
                      }
                    },
                    tooltip: (isPlaying && isCurrentSurah) ? 'إيقاف' : 'تشغيل',
                  ),
                  if (_isLoadingAudio)
                    const Positioned(
                      right: 4,
                      top: 4,
                      child: SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
              // More options menu
              PopupMenuButton<String>(
                icon: const Icon(SolarLinearIcons.menuDotsCircle),
                tooltip: 'المزيد',
                onSelected: (value) {
                  switch (value) {
                    case 'mushaf':
                      _showMushafTypeSelector();
                      break;
                    case 'translation':
                      _showTranslationSelector();
                      break;
                    case 'playback':
                      _showPlaybackSettings();
                      break;
                    case 'jump':
                      Haptics.selection();
                      _showJumpToVerseDialog();
                      break;
                    default:
                      // Handle reciter selection (reciter_0, reciter_1, etc.)
                      if (value.startsWith('reciter_')) {
                        final index = int.parse(value.substring(8));
                        _changeReciter(index);
                      }
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'mushaf',
                    child: Row(
                      children: [
                        Icon(SolarLinearIcons.book2),
                        SizedBox(width: 12),
                        Text('نوع المصحف'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'translation',
                    child: Row(
                      children: [
                        Icon(SolarLinearIcons.earth),
                        SizedBox(width: 12),
                        Text('الترجمة'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'playback',
                    child: Row(
                      children: [
                        Icon(SolarLinearIcons.settings),
                        SizedBox(width: 12),
                        Text('إعدادات التشغيل'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'jump',
                    child: Row(
                      children: [
                        Icon(SolarLinearIcons.arrowUp),
                        SizedBox(width: 12),
                        Text('الانتقال إلى آية'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  // Reciter header
                  const PopupMenuItem<String>(
                    enabled: false,
                    child: Row(
                      children: [
                        Icon(SolarLinearIcons.musicNote2),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'القارئ',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Current reciter indicator
                  PopupMenuItem<String>(
                    enabled: false,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: AppColors.primary,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _reciters[_currentReciter]['name']!,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Reciter selection options
                  ..._reciters.asMap().entries.map((entry) {
                    return PopupMenuItem<String>(
                      value: 'reciter_${entry.key}',
                      child: Row(
                        children: [
                          if (entry.key == _currentReciter)
                            const Icon(
                              Icons.check,
                              color: AppColors.primary,
                              size: 18,
                            )
                          else
                            const SizedBox(width: 18),
                          const SizedBox(width: 8),
                          Text(entry.value['name']!),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                // Reading progress indicator
                Consumer<QuranProvider>(
                  builder: (context, provider, _) {
                    final lastReadVerse = provider.lastVerse;
                    final isCurrentSurah =
                        provider.lastSurah == widget.surahNumber;
                    final progressPercent =
                        (lastReadVerse! / verseCount * 100).clamp(0, 100);

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            SolarLinearIcons.bookmark,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isCurrentSurah
                                  ? 'آخر قراءة: الآية $lastReadVerse من $verseCount'
                                  : 'آخر قراءة: سورة ${quran.getSurahNameArabic(provider.lastSurah!)}',
                              style: const TextStyle(
                                fontFamily: 'IBM Plex Sans Arabic',
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${progressPercent.toStringAsFixed(0)}%',
                            style: const TextStyle(
                              fontFamily: 'IBM Plex Sans Arabic',
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                // Progress bar
                Consumer<QuranProvider>(
                  builder: (context, provider, _) {
                    final lastReadVerse = provider.lastVerse;
                    final isCurrentSurah =
                        provider.lastSurah == widget.surahNumber;
                    final progress = isCurrentSurah
                        ? (lastReadVerse! / verseCount).clamp(0.0, 1.0)
                        : 0.0;

                    return LinearProgressIndicator(
                      value: progress,
                      backgroundColor: theme.dividerColor,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
                      minHeight: 3,
                    );
                  },
                ),
                // Basmalah (except for Surah At-Tawbah #9)
                if (widget.surahNumber != 9)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
                    child: Text(
                      quran.basmala,
                      style: TextStyle(
                        fontFamily: 'Amiri Quran',
                        fontSize: 28,
                        fontWeight: FontWeight.w400,
                        height: 1.8,
                        inherit: false,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      Haptics.selection();
                      // Refresh tafsir
                      context.read<QuranProvider>().retryLoadTafsir();
                      // Reload audio
                      if (audioProvider.isPlaying && isCurrentSurah) {
                        audioProvider.stopQuranRecitation();
                        await Future.delayed(
                          const Duration(milliseconds: 200),
                        );
                        await _loadAndPlaySurah();
                      }
                      // Reload timings
                      await _loadVerseTimings();
                      if (!context.mounted) return;
                      AnimatedToast.success(context, 'تم التحديث');
                    },
                    child: ScrollablePositionedList.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      itemCount: verseCount,
                      itemScrollController: _itemScrollController,
                      itemPositionsListener: _itemPositionsListener,
                      initialScrollIndex: widget.initialVerse != null
                          ? widget.initialVerse! - 1
                          : 0,
                      itemBuilder: (context, index) {
                        final verseNumber = index + 1;
                        final tafsirText = quranProvider.getTafsir(
                          widget.surahNumber,
                          verseNumber,
                        );

                        // Fetch remote tafsir lazily
                        final verseKey = '${widget.surahNumber}:$verseNumber';
                        final isTafsirPending = quranProvider.isTafsirPending(
                          widget.surahNumber,
                          verseNumber,
                        );
                        if (tafsirText.isEmpty &&
                            quranProvider.selectedTafsir != 'local' &&
                            !_requestedTafsirVerses.contains(verseKey)) {
                          _requestedTafsirVerses.add(verseKey);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            context
                                .read<QuranProvider>()
                                .fetchRemoteTafsirIfNeeded(
                                  widget.surahNumber,
                                  verseNumber,
                                );
                          });
                        }

                        // Get verse text
                        final verseText = quran.getVerse(
                          widget.surahNumber,
                          verseNumber,
                          verseEndSymbol: true,
                        );

                        // Calculate separator size based on font size
                        final separatorSize = (quranProvider.fontSize / 22.0 * 50)
                            .clamp(40.0, 70.0);

                        // Check if this verse is highlighted (playing)
                        final isHighlighted = _highlightedVerse == verseNumber &&
                            isPlaying &&
                            isCurrentSurah;

                        // Check if setting repeat point
                        final isSettingRepeat =
                            (_isSettingRepeatStart || _isSettingRepeatEnd);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 24.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Verse number separator
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8.0),
                                child: Center(
                                  child: VerseSeparator(
                                    verseNumber: verseNumber,
                                    size: separatorSize,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Verse text container with highlight support
                              GestureDetector(
                                onLongPress: () =>
                                    _showVerseActionMenu(verseNumber, verseText),
                                onTap: () {
                                  if (isSettingRepeat) {
                                    _setRepeatPoint(verseNumber);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isHighlighted
                                        ? AppColors.primary.withValues(
                                            alpha: 0.08,
                                          )
                                        : isSettingRepeat
                                            ? AppColors.primary.withValues(
                                                alpha: 0.04,
                                              )
                                            : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isHighlighted
                                          ? AppColors.primary.withValues(
                                              alpha: 0.3,
                                            )
                                          : isSettingRepeat
                                              ? AppColors.primary.withValues(
                                                  alpha: 0.2,
                                                )
                                              : Colors.transparent,
                                      width: isHighlighted ? 2 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      // Arabic text
                                      Text(
                                        quran.getVerse(
                                          widget.surahNumber,
                                          verseNumber,
                                          verseEndSymbol: false,
                                        ),
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontFamily: fontFamily,
                                          fontSize: quranProvider.fontSize,
                                          height: 2.0,
                                          fontWeight: FontWeight.w400,
                                          inherit: false,
                                          fontFeatures: const [
                                            FontFeature.enable('liga'),
                                            FontFeature.enable('calt'),
                                          ],
                                        ),
                                      ),
                                      // Translation (if enabled)
                                      if (quranProvider.translation !=
                                          TranslationLanguage.none) ...[
                                        const SizedBox(height: 12),
                                        FutureBuilder<String>(
                                          future: quranProvider.getTranslation(
                                            widget.surahNumber,
                                            verseNumber,
                                          ),
                                          builder: (context, snapshot) {
                                            if (snapshot.connectionState ==
                                                ConnectionState.waiting) {
                                              return const SizedBox(
                                                height: 20,
                                                width: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              );
                                            }
                                            if (snapshot.hasData &&
                                                snapshot.data!.isNotEmpty) {
                                              return Text(
                                                snapshot.data!,
                                                textAlign: TextAlign.right,
                                                style: TextStyle(
                                                  fontFamily:
                                                      'IBM Plex Sans Arabic',
                                                  fontSize:
                                                      quranProvider.fontSize -
                                                          4,
                                                  height: 1.6,
                                                  color: theme.textTheme
                                                      .bodyMedium?.color,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              );
                                            }
                                            return const SizedBox.shrink();
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Action buttons row
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Share button
                                  Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          SolarLinearIcons.share,
                                          size: 20,
                                        ),
                                        onPressed: () {
                                          _shareVerse(verseNumber, verseText);
                                        },
                                        constraints: const BoxConstraints(),
                                        padding: const EdgeInsets.all(8),
                                        tooltip: 'مشاركة الآية',
                                      ),
                                      if (isTafsirPending)
                                        const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                              AppColors.primary,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  // Bookmark button
                                  IconButton(
                                    icon: Icon(
                                      _bookmarkedVerses.contains(verseNumber)
                                          ? SolarBoldIcons.bookmark
                                          : SolarLinearIcons.bookmark,
                                      size: 20,
                                      color: _bookmarkedVerses
                                              .contains(verseNumber)
                                          ? AppColors.primary
                                          : null,
                                    ),
                                    onPressed: () =>
                                        _toggleBookmark(verseNumber),
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(8),
                                    tooltip: _bookmarkedVerses
                                            .contains(verseNumber)
                                        ? 'إزالة العلامة'
                                        : 'إضافة علامة',
                                  ),
                                ],
                              ),
                              // Tafsir section with fade-in animation
                              if (quranProvider.showTafsir &&
                                  tafsirText.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                FadeTransition(
                                  opacity:
                                      _getTafsirFadeAnimation(verseNumber),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border(
                                        right: BorderSide(
                                          color: AppColors.primary.withValues(
                                            alpha: 0.5,
                                          ),
                                          width: 4,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _getTafsirSourceName(
                                            quranProvider.selectedTafsir,
                                          ),
                                          style: const TextStyle(
                                            fontFamily: 'IBM Plex Sans Arabic',
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          tafsirText,
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            fontFamily: 'IBM Plex Sans Arabic',
                                            fontSize:
                                                quranProvider.fontSize - 6,
                                            height: 1.8,
                                            color: theme.textTheme.bodyMedium
                                                ?.color,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ] else if (quranProvider.showTafsir &&
                                  quranProvider.selectedTafsir == 'local' &&
                                  quranProvider.isTafsirLoadFailed) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color:
                                          Colors.orange.withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.warning_amber_rounded,
                                        color: Colors.orange,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'تعذر تحميل التفسير - تحقق من اتصال الإنترنت',
                                          style: TextStyle(
                                            fontFamily: 'IBM Plex Sans Arabic',
                                            fontSize: 12,
                                            color: theme.textTheme.bodyMedium
                                                ?.color,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Haptics.lightTap();
                                          context
                                              .read<QuranProvider>()
                                              .retryLoadTafsir();
                                        },
                                        child: const Text('إعادة المحاولة'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Divider(
                                color:
                                    theme.dividerColor.withValues(alpha: 0.5),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showJumpToVerseDialog() {
    final verseCount = quran.getVerseCount(widget.surahNumber);

    CustomDialog.show(
      context,
      title: 'الانتقال إلى آية',
      message: 'أدخل رقم الآية (1 - $verseCount)',
      type: DialogType.input,
      confirmText: 'انتقال',
      cancelText: 'إلغاء',
      onConfirmInput: (value) {
        final verse = int.tryParse(value);
        if (verse != null && verse >= 1 && verse <= verseCount) {
          Haptics.selection();
          _itemScrollController.scrollTo(
            index: verse - 1,
            duration: const Duration(seconds: 1),
            curve: Curves.easeInOutCubic,
          );
        }
      },
    );
  }
}
