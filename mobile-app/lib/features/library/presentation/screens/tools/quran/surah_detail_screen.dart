import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:quran/quran.dart' as quran;
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';
import 'package:almudeer_mobile_app/features/quran/presentation/providers/quran_provider.dart';
import 'package:almudeer_mobile_app/features/viewer/presentation/providers/audio_player_provider.dart';
import 'package:almudeer_mobile_app/features/quran/presentation/widgets/quran/verse_separator.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/custom_dialog.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/animated_toast.dart';
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

  // Repeat mode UI
  bool _isSettingRepeatStart = false;
  bool _isSettingRepeatEnd = false;

  static const List<Map<String, String>> _reciters = [
    {'name': 'ط¹ط¨ط¯ط§ظ„ط±ط­ظ…ظ† ط§ظ„ط³ط¯ظٹط³', 'server': 'https://server8.mp3quran.net/sds/'},
    {'name': 'ظ…ط´ط§ط±ظٹ ط§ظ„ط¹ظپط§ط³ظٹ', 'server': 'https://server8.mp3quran.net/afs/'},
    {'name': 'ط³ط¹ط¯ ط§ظ„ط؛ط§ظ…ط¯ظٹ', 'server': 'https://server6.mp3quran.net/ghamdi/'},
    {'name': 'ظ…ط§ظ‡ط± ط§ظ„ظ…ط¹ظٹظ‚ظ„ظٹ', 'server': 'https://server12.mp3quran.net/maher/'},
    {
      'name': 'ظ…ط­ظ…ظˆط¯ ط®ظ„ظٹظ„ ط§ظ„ط­طµط±ظٹ',
      'server': 'https://server13.mp3quran.net/husr/',
    },
    {
      'name': 'ظ…ط­ظ…ط¯ طµط¯ظٹظ‚ ط§ظ„ظ…ظ†ط´ط§ظˆظٹ',
      'server': 'https://server10.mp3quran.net/minsh/',
    },
    {'name': 'ظ…ط­ظ…ط¯ ط£ظٹظˆط¨', 'server': 'https://server8.mp3quran.net/ayyub/'},
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
      // Account for basmala at index 0 (except for Surah 9)
      final index = widget.surahNumber == 9 ? verseNumber - 1 : verseNumber;
      _itemScrollController.jumpTo(index: index);
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

      // Update last read verse (account for basmala at index 0, except Surah 9)
      final verseNumber = widget.surahNumber == 9 ? min.index + 1 : min.index;
      if (verseNumber > 0) {
        context.read<QuranProvider>().saveLastRead(
          widget.surahNumber,
          verseNumber,
        );
      }
    }
  }

  /// Fallback servers for each reciter - used when primary server fails
  static const List<List<String>> _reciterFallbackServers = [
    // Corresponds to _reciters order - backup mp3quran.net mirrors
    ['https://server7.mp3quran.net/sds/'], // ط§ظ„ط³ط¯ظٹط³
    ['https://server11.mp3quran.net/afs/'], // ط§ظ„ط¹ظپط§ط³ظٹ
    ['https://server8.mp3quran.net/ghamdi/'], // ط§ظ„ط؛ط§ظ…ط¯ظٹ
    ['https://server7.mp3quran.net/maher/'], // ط§ظ„ظ…ط¹ظٹظ‚ظ„ظٹ
    ['https://server11.mp3quran.net/husr/'], // ط§ظ„ط­طµط±ظٹ
    ['https://server7.mp3quran.net/minsh/'], // ط§ظ„ظ…ظ†ط´ط§ظˆظٹ
    ['https://server11.mp3quran.net/ayyub/'], // ط£ظٹظˆط¨
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
          'ط®ط·ط£ ظپظٹ طھط­ظ…ظٹظ„ ط§ظ„طµظˆطھ - طھط£ظƒط¯ ظ…ظ† ط§طھطµط§ظ„ ط§ظ„ط¥ظ†طھط±ظ†طھ',
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
      return 'طھظپط³ظٹط± ط§ط¨ظ† ظƒط«ظٹط± (ط§ظ„ظƒط§ظ…ظ„)';
    }
    // For remote tafsir, show the actual source name
    return 'طھظپط³ظٹط± ط§ط¨ظ† ظƒط«ظٹط± (ط§ظ„ظ…ط®طھطµط±)';
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
        AnimatedToast.info(context, 'طھظ…طھ ط¥ط²ط§ظ„ط© ط§ظ„ط¹ظ„ط§ظ…ط©');
      } else {
        _bookmarkedVerses.add(verseNumber);
        AnimatedToast.success(context, 'طھظ…طھ ط¥ط¶ط§ظپط© ط§ظ„ط¹ظ„ط§ظ…ط©');
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
              title: const Text('ظ…ط´ط§ط±ظƒط© ط§ظ„ط¢ظٹط©'),
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
                    ? 'ط¥ط²ط§ظ„ط© ط§ظ„ط¹ظ„ط§ظ…ط©'
                    : 'ط¥ط¶ط§ظپط© ط¹ظ„ط§ظ…ط©',
              ),
              onTap: () {
                Navigator.pop(context);
                _toggleBookmark(verseNumber);
              },
            ),
            ListTile(
              leading: const Icon(SolarLinearIcons.copy),
              title: const Text('ظ†طµ ط§ظ„ط¢ظٹط©'),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: verseText));
                AnimatedToast.success(context, 'طھظ… ظ†ط³ط® ط§ظ„ظ†طµ');
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
        '$verseText\n\n[ط³ظˆط±ط© ${quran.getSurahNameArabic(widget.surahNumber)}: $verseNumber]';
    Clipboard.setData(ClipboardData(text: text));
    AnimatedToast.success(context, 'طھظ… ظ†ط³ط® ط§ظ„ط¢ظٹط© ظ„ظ„ظ…ط´ط§ط±ظƒط©');
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
                  'ط¥ط¹ط¯ط§ط¯ط§طھ ط§ظ„طھط´ط؛ظٹظ„',
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
                  title: const Text('ط³ط±ط¹ط© ط§ظ„طھط´ط؛ظٹظ„'),
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
                  title: const Text('ط§ظ„طھظ…ط±ظٹط± ط§ظ„طھظ„ظ‚ط§ط¦ظٹ'),
                  subtitle: const Text('طھطھط¨ط¹ ط§ظ„ط¢ظٹط© ط§ظ„ظ…ظ‚ط±ظˆط،ط©'),
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
                  title: const Text('ظˆط¶ط¹ ط§ظ„طھظƒط±ط§ط±'),
                  subtitle: const Text('طھظƒط±ط§ط± ط§ظ„ط¢ظٹط§طھ ظ„ظ„ط­ظپط¸'),
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
                                'ط§ط®طھط± ط§ظ„ط¢ظٹط© ط¨ط¯ط§ظٹط© ظ„ظ„طھظƒط±ط§ط±',
                              );
                            },
                            icon: const Icon(SolarLinearIcons.bookmark),
                            label: Text(
                              _isSettingRepeatStart
                                  ? 'ط¬ط§ط±ظٹ ط§ظ„طھط­ط¯ظٹط¯...'
                                  : provider.repeatStartVerse != null
                                      ? 'ط§ظ„ط¨ط¯ط§ظٹط©: ${provider.repeatStartVerse}'
                                      : 'طھط­ط¯ظٹط¯ ط§ظ„ط¨ط¯ط§ظٹط©',
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
                                'ط§ط®طھط± ط§ظ„ط¢ظٹط© ظ†ظ‡ط§ظٹط© ظ„ظ„طھظƒط±ط§ط±',
                              );
                            },
                            icon: const Icon(SolarLinearIcons.bookmark),
                            label: Text(
                              _isSettingRepeatEnd
                                  ? 'ط¬ط§ط±ظٹ ط§ظ„طھط­ط¯ظٹط¯...'
                                  : provider.repeatEndVerse != null
                                      ? 'ط§ظ„ظ†ظ‡ط§ظٹط©: ${provider.repeatEndVerse}'
                                      : 'طھط­ط¯ظٹط¯ ط§ظ„ظ†ظ‡ط§ظٹط©',
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
                          title: const Text('ظ…ط¤ظ‚طھ ط§ظ„ظ†ظˆظ…'),
                          subtitle: Text(
                            audioProvider.isSleepTimerActive
                                ? 'ظ…طھط¨ظ‚ظٹ: ${audioProvider.sleepTimerLabel}'
                                : 'ط¥ظٹظ‚ط§ظپ ط§ظ„طھط´ط؛ظٹظ„ ط¨ط¹ط¯ ظˆظ‚طھ ظ…ط­ط¯ط¯',
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
      AnimatedToast.success(context, 'طھظ… طھط­ط¯ظٹط¯ ط¨ط¯ط§ظٹط© ط§ظ„طھظƒط±ط§ط±');
    } else if (_isSettingRepeatEnd) {
      quranProvider.setRepeatRange(
        quranProvider.repeatStartVerse ?? verseNumber,
        verseNumber,
      );
      setState(() => _isSettingRepeatEnd = false);
      AnimatedToast.success(context, 'طھظ… طھط­ط¯ظٹط¯ ظ†ظ‡ط§ظٹط© ط§ظ„طھظƒط±ط§ط±');
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
              'ظ…ط¯ط© ظ…ط¤ظ‚طھ ط§ظ„ظ†ظˆظ…',
              style: TextStyle(
                fontFamily: 'IBM Plex Sans Arabic',
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildSleepTimerOption(
              '15 ط¯ظ‚ظٹظ‚ط©',
              const Duration(minutes: 15),
            ),
            _buildSleepTimerOption(
              '30 ط¯ظ‚ظٹظ‚ط©',
              const Duration(minutes: 30),
            ),
            _buildSleepTimerOption(
              '45 ط¯ظ‚ظٹظ‚ط©',
              const Duration(minutes: 45),
            ),
            _buildSleepTimerOption(
              'ط³ط§ط¹ط©',
              const Duration(minutes: 60),
            ),
            _buildSleepTimerOption(
              'ط³ط§ط¹طھظٹظ†',
              const Duration(minutes: 120),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(
                SolarLinearIcons.closeCircle,
                color: Colors.red,
              ),
              title: const Text(
                'ط¥ظ„ط؛ط§ط، ط§ظ„ظ…ط¤ظ‚طھ',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                context.read<AudioPlayerProvider>().cancelSleepTimer();
                AnimatedToast.info(context, 'طھظ… ط¥ظ„ط؛ط§ط، ظ…ط¤ظ‚طھ ط§ظ„ظ†ظˆظ…');
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
        AnimatedToast.success(context, 'طھظ… ط¶ط¨ط· ظ…ط¤ظ‚طھ ط§ظ„ظ†ظˆظ…: $label');
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
                // Account for basmala at index 0 (except for Surah 9)
                final index = widget.surahNumber == 9 ? currentVerse - 1 : currentVerse;
                _itemScrollController.scrollTo(
                  index: index,
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
              // Tafsir toggle button
              IconButton(
                icon: Icon(
                  quranProvider.showTafsir
                      ? SolarLinearIcons.eye
                      : SolarLinearIcons.eyeClosed,
                  color: quranProvider.showTafsir
                      ? AppColors.primary
                      : theme.colorScheme.onSurface,
                ),
                onPressed: () {
                  Haptics.lightTap();
                  quranProvider.toggleTafsir();
                },
                tooltip: quranProvider.showTafsir
                    ? 'ط¥ط®ظپط§ط، ط§ظ„طھظپط³ظٹط±'
                    : 'ط¥ط¸ظ‡ط§ط± ط§ظ„طھظپط³ظٹط±',
              ),
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
                    tooltip: (isPlaying && isCurrentSurah) ? 'ط¥ظٹظ‚ط§ظپ' : 'طھط´ط؛ظٹظ„',
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
                tooltip: 'ط§ظ„ظ…ط²ظٹط¯',
                onSelected: (value) {
                  switch (value) {
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
                    value: 'playback',
                    child: Row(
                      children: [
                        Icon(SolarLinearIcons.settings),
                        SizedBox(width: 12),
                        Text('ط¥ط¹ط¯ط§ط¯ط§طھ ط§ظ„طھط´ط؛ظٹظ„'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'jump',
                    child: Row(
                      children: [
                        Icon(SolarLinearIcons.arrowUp),
                        SizedBox(width: 12),
                        Text('ط§ظ„ط§ظ†طھظ‚ط§ظ„ ط¥ظ„ظ‰ ط¢ظٹط©'),
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
                            'ط§ظ„ظ‚ط§ط±ط¦',
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
                                  ? 'ط¢ط®ط± ظ‚ط±ط§ط،ط©: ط§ظ„ط¢ظٹط© $lastReadVerse ظ…ظ† $verseCount'
                                  : 'ط¢ط®ط± ظ‚ط±ط§ط،ط©: ط³ظˆط±ط© ${quran.getSurahNameArabic(provider.lastSurah!)}',
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
                      AnimatedToast.success(context, 'طھظ… ط§ظ„طھط­ط¯ظٹط«');
                    },
                    child: ScrollablePositionedList.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      itemCount: widget.surahNumber == 9 ? verseCount : verseCount + 1,
                      itemScrollController: _itemScrollController,
                      itemPositionsListener: _itemPositionsListener,
                      initialScrollIndex: widget.initialVerse != null
                          ? (widget.surahNumber == 9 ? widget.initialVerse! - 1 : widget.initialVerse!)
                          : 0,
                      itemBuilder: (context, index) {
                        // Index 0 is basmala (except for Surah 9), verses start from index 1
                        final verseNumber = widget.surahNumber == 9 ? index : index - 1;
                        
                        // Basmala header (except for Surah At-Tawbah #9)
                        if (widget.surahNumber != 9 && index == 0) {
                          return const Padding(
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
                          );
                        }
                        
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
                                        tooltip: 'ظ…ط´ط§ط±ظƒط© ط§ظ„ط¢ظٹط©',
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
                                        ? 'ط¥ط²ط§ظ„ط© ط§ظ„ط¹ظ„ط§ظ…ط©'
                                        : 'ط¥ط¶ط§ظپط© ط¹ظ„ط§ظ…ط©',
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
                                          'طھط¹ط°ط± طھط­ظ…ظٹظ„ ط§ظ„طھظپط³ظٹط± - طھط­ظ‚ظ‚ ظ…ظ† ط§طھطµط§ظ„ ط§ظ„ط¥ظ†طھط±ظ†طھ',
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
                                        child: const Text('ط¥ط¹ط§ط¯ط© ط§ظ„ظ…ط­ط§ظˆظ„ط©'),
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
      title: 'ط§ظ„ط§ظ†طھظ‚ط§ظ„ ط¥ظ„ظ‰ ط¢ظٹط©',
      message: 'ط£ط¯ط®ظ„ ط±ظ‚ظ… ط§ظ„ط¢ظٹط© (1 - $verseCount)',
      type: DialogType.input,
      confirmText: 'ط§ظ†طھظ‚ط§ظ„',
      cancelText: 'ط¥ظ„ط؛ط§ط،',
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
