import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quran/quran.dart' as quran;
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/constants/dimensions.dart';
import 'package:almudeer_mobile_app/presentation/providers/quran_provider.dart';
import 'package:almudeer_mobile_app/presentation/screens/library/tools/quran/surah_detail_screen.dart';
import 'package:almudeer_mobile_app/presentation/widgets/common_widgets.dart';

class QuranScreen extends StatefulWidget {
  const QuranScreen({super.key});

  @override
  State<QuranScreen> createState() => _QuranScreenState();
}

class _QuranScreenState extends State<QuranScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<int> _filteredSurahs = [];
  Timer? _debounceTimer;
  final List<Map<String, String>> _surahNamesCache = [];

  @override
  void initState() {
    super.initState();
    _filteredSurahs = List.generate(114, (index) => index + 1);
    _preloadSurahNames();
    _searchController.addListener(_onSearchChanged);
  }

  void _preloadSurahNames() {
    for (int i = 1; i <= 114; i++) {
      _surahNamesCache.add({
        'nameEn': quran.getSurahName(i).toLowerCase(),
        'nameAr': quran.getSurahNameArabic(i),
        'nameEnglish': quran.getSurahNameEnglish(i).toLowerCase(),
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch(_searchController.text);
    });
  }

  void _performSearch(String query) {
    final lowerQuery = query.toLowerCase();
    setState(() {
      if (lowerQuery.isEmpty) {
        _filteredSurahs = List.generate(114, (index) => index + 1);
      } else {
        _filteredSurahs = List.generate(114, (index) => index + 1).where((surahNumber) {
          final names = _surahNamesCache[surahNumber - 1];
          return names['nameEn']!.contains(lowerQuery) ||
              names['nameAr']!.contains(lowerQuery) ||
              names['nameEnglish']!.contains(lowerQuery);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quranProvider = context.watch<QuranProvider>();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'القرآن الكريم',
          style: TextStyle(
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
      ),
      body: Column(
        children: [
          // Last Read Card
          if (quranProvider.lastSurah != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.paddingMedium,
                AppDimensions.spacing8,
                AppDimensions.paddingMedium,
                0,
              ),
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SurahDetailScreen(
                        surahNumber: quranProvider.lastSurah!,
                        initialVerse: quranProvider.lastVerse,
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
                child: Container(
                  padding: const EdgeInsets.all(AppDimensions.paddingLarge),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, Color(0xFF537FFD)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: AppDimensions.spacing16,
                        offset: Offset(0, AppDimensions.spacing10),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        SolarBoldIcons.reorder,
                        color: Colors.white,
                        size: 32,
                      ),
                      const SizedBox(width: AppDimensions.paddingMedium),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'آخر قراءة',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontFamily: 'IBM Plex Sans Arabic',
                              ),
                            ),
                            Text(
                              quran.getSurahNameArabic(
                                quranProvider.lastSurah!,
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'IBM Plex Sans Arabic',
                              ),
                            ),
                            Text(
                              'الآية رقم ${quranProvider.lastVerse}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontFamily: 'IBM Plex Sans Arabic',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        SolarLinearIcons.altArrowLeft,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(AppDimensions.paddingMedium),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(
                fontFamily: 'IBM Plex Sans Arabic',
              ),
              decoration: InputDecoration(
                hintText: 'بحث عن سورة...',
                hintStyle: const TextStyle(
                  fontFamily: 'IBM Plex Sans Arabic',
                ),
                prefixIcon: const Icon(SolarLinearIcons.magnifer),
                filled: true,
                fillColor: theme.cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.paddingMedium,
                  vertical: AppDimensions.paddingMedium,
                ),
              ),
            ),
          ),
          Expanded(
            child: _filteredSurahs.isEmpty
                ? EmptyStateWidget(
                    icon: SolarLinearIcons.magnifer,
                    iconColor: theme.colorScheme.primary,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimensions.paddingMedium,
                      vertical: AppDimensions.spacing8,
                    ),
                    physics: const BouncingScrollPhysics(),
                    itemCount: _filteredSurahs.length,
                    itemBuilder: (context, index) {
                      final surahNumber = _filteredSurahs[index];
                      final isLastRead = surahNumber == quranProvider.lastSurah;

                      return Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppDimensions.spacing12,
                        ),
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    SurahDetailScreen(surahNumber: surahNumber),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
                          child: Container(
                            padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                            decoration: BoxDecoration(
                              color: theme.cardColor,
                              borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
                              border: isLastRead
                                  ? Border.all(
                                      color: AppColors.primary.withValues(alpha: 0.5),
                                      width: 2,
                                    )
                                  : null,
                              boxShadow: [
                                if (theme.brightness == Brightness.light)
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: AppDimensions.spacing12,
                                    offset: Offset(0, AppDimensions.spacing6),
                                  ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Icon(
                                      SolarLinearIcons.star,
                                      color: AppColors.primary.withValues(alpha: 0.1),
                                      size: 44,
                                    ),
                                    Text(
                                      '$surahNumber',
                                      style: const TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        fontFamily: 'IBM Plex Sans Arabic',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: AppDimensions.paddingMedium),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        quran.getSurahNameArabic(surahNumber),
                                        style: const TextStyle(
                                          fontFamily: 'IBM Plex Sans Arabic',
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          Text(
                                            quran.getPlaceOfRevelation(surahNumber) ==
                                                    'Makkah'
                                                ? 'مكية'
                                                : 'مدنية',
                                            style: TextStyle(
                                              fontFamily: 'IBM Plex Sans Arabic',
                                              color: theme.textTheme.bodySmall?.color,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(width: AppDimensions.spacing8),
                                          Container(
                                            width: 4,
                                            height: 4,
                                            decoration: BoxDecoration(
                                              color: theme.dividerColor,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: AppDimensions.spacing8),
                                          Text(
                                            '${quran.getVerseCount(surahNumber)} آية',
                                            style: TextStyle(
                                              fontFamily: 'IBM Plex Sans Arabic',
                                              color: theme.textTheme.bodySmall?.color,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  quran.getSurahName(surahNumber),
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    fontFamily: 'IBM Plex Sans Arabic',
                                  ),
                                ),
                                const SizedBox(width: AppDimensions.spacing8),
                                Icon(
                                  SolarLinearIcons.altArrowLeft,
                                  size: 20,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ],
                            ),
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
