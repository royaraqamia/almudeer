import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:quran/quran.dart' as quran;
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
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

class _SurahDetailScreenState extends State<SurahDetailScreen> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  bool _isAutoScrolling = false;

  int _currentReciter = 0;
  bool _isLoadingAudio = false;

  // Track which verses have been requested for remote tafsir to prevent duplicate requests
  final Set<String> _requestedTafsirVerses = {};

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
    });

    if (widget.initialVerse != null) {
      _isAutoScrolling = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToVerse(widget.initialVerse!);
      });
    }
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

      await audioProvider.playQuranRecitation(url, surahName);

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
    setState(() => _currentReciter = index);
    final audioProvider = context.read<AudioPlayerProvider>();
    audioProvider.stopQuranRecitation();
    _loadAndPlaySurah();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verseCount = quran.getVerseCount(widget.surahNumber);
    final quranProvider = context.watch<QuranProvider>();

    return Consumer<AudioPlayerProvider>(
      builder: (context, audioProvider, _) {
        final isPlaying = audioProvider.isPlaying;
        final isCurrentSurah =
            audioProvider.currentAudioTitle ==
            quran.getSurahNameArabic(widget.surahNumber);

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
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
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
                      // Check if this is the current surah (regardless of playing state)
                      final isActuallyCurrentSurah =
                          audioProvider.currentAudioTitle ==
                          quran.getSurahNameArabic(widget.surahNumber);

                      if (isActuallyCurrentSurah && isPlaying) {
                        // Pause current surah
                        audioProvider.handler?.pause();
                      } else if (isActuallyCurrentSurah && !isPlaying) {
                        // Resume paused surah
                        audioProvider.handler?.play();
                      } else {
                        // Load new surah
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
              PopupMenuButton<int>(
                icon: const Icon(SolarLinearIcons.musicNote2),
                tooltip: 'اختيار القارئ',
                onSelected: (index) => _changeReciter(index),
                itemBuilder: (context) =>
                    _reciters.asMap().entries.map((entry) {
                      return PopupMenuItem<int>(
                        value: entry.key,
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
                    }).toList(),
              ),
              IconButton(
                icon: const Icon(SolarLinearIcons.map),
                onPressed: _showJumpToVerseDialog,
                tooltip: 'الانتقال إلى آية',
              ),
              IconButton(
                icon: Icon(
                  quranProvider.showTafsir
                      ? SolarBoldIcons.notes
                      : SolarLinearIcons.notes,
                  color: quranProvider.showTafsir ? AppColors.primary : null,
                ),
                onPressed: () => quranProvider.toggleTafsir(),
                tooltip: 'تبديل التفسير',
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
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

                      // Fetch remote tafsir lazily (outside build phase) - only once per verse
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

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Verse number separator
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8.0,
                              ),
                              child: Center(
                                child: VerseSeparator(
                                  verseNumber: verseNumber,
                                  size: 50,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              quran.getVerse(
                                widget.surahNumber,
                                verseNumber,
                                verseEndSymbol: false,
                              ),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontFamily: 'Amiri Quran',
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
                            const SizedBox(height: 12),
                            // Share button with loading indicator
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        SolarLinearIcons.share,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        final text =
                                            '${quran.getVerse(widget.surahNumber, verseNumber, verseEndSymbol: true)}\n\n'
                                            '[سورة ${quran.getSurahNameArabic(widget.surahNumber)}: $verseNumber]';
                                        Clipboard.setData(
                                          ClipboardData(text: text),
                                        );
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('تم نسخ الآية'),
                                          ),
                                        );
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
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            AppColors.primary,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            if (quranProvider.showTafsir &&
                                tafsirText.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: theme
                                      .colorScheme
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      quranProvider.selectedTafsir == 'local'
                                          ? 'تفسير ابن كثير (الكامل)'
                                          : 'tafsir',
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
                                        fontSize: quranProvider.fontSize - 6,
                                        height: 1.8,
                                        color:
                                            theme.textTheme.bodyMedium?.color,
                                      ),
                                    ),
                                  ],
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
                                    color: Colors.orange.withValues(alpha: 0.5),
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
                                          color: theme.textTheme.bodyMedium?.color,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Divider(
                              color: theme.dividerColor.withValues(alpha: 0.5),
                            ),
                          ],
                        ),
                      );
                    },
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
