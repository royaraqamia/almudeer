"""
Quran data constants - verse counts for each Surah.
Source: Standard Uthmani Quran text.
"""

# Number of verses in each Surah (1-114)
# Al-Baqarah (2) has the most verses: 286
# Al-Kawthar (108) has the fewest: 3
SURAHS_VERSE_COUNT = {
    1: 7,     # Al-Fatihah
    2: 286,   # Al-Baqarah
    3: 200,   # Ali 'Imran
    4: 176,   # An-Nisa
    5: 120,   # Al-Ma'idah
    6: 165,   # Al-An'am
    7: 206,   # Al-A'raf
    8: 75,    # Al-Anfal
    9: 129,   # At-Tawbah
    10: 109,  # Yunus
    11: 123,  # Hud
    12: 111,  # Yusuf
    13: 43,   # Ar-Ra'd
    14: 52,   # Ibrahim
    15: 99,   # Al-Hijr
    16: 128,  # An-Nahl
    17: 111,  # Al-Isra
    18: 110,  # Al-Kahf
    19: 98,   # Maryam
    20: 135,  # Ta-Ha
    21: 112,  # Al-Anbya
    22: 78,   # Al-Hajj
    23: 118,  # Al-Mu'minun
    24: 64,   # An-Nur
    25: 77,   # Al-Furqan
    26: 227,  # Ash-Shu'ara
    27: 93,   # An-Naml
    28: 88,   # Al-Qasas
    29: 69,   # Al-'Ankabut
    30: 60,   # Ar-Rum
    31: 34,   # Luqman
    32: 30,   # As-Sajdah
    33: 73,   # Al-Ahzab
    34: 54,   # Saba
    35: 45,   # Fatir
    36: 83,   # Ya-Sin
    37: 182,  # As-Saffat
    38: 88,   # Sad
    39: 75,   # Az-Zumar
    40: 85,   # Ghafir
    41: 54,   # Fussilat
    42: 53,   # Ash-Shuraa
    43: 89,   # Az-Zukhruf
    44: 59,   # Ad-Dukhan
    45: 37,   # Al-Jathiyah
    46: 35,   # Al-Ahqaf
    47: 38,   # Muhammad
    48: 29,   # Al-Fath
    49: 18,   # Al-Hujurat
    50: 45,   # Qaf
    51: 60,   # Adh-Dhariyat
    52: 49,   # At-Tur
    53: 62,   # An-Najm
    54: 55,   # Al-Qamar
    55: 78,   # Ar-Rahman
    56: 96,   # Al-Waqi'ah
    57: 29,   # Al-Hadid
    58: 22,   # Al-Mujadila
    59: 24,   # Al-Hashr
    60: 13,   # Al-Mumtahanah
    61: 14,   # As-Saff
    62: 11,   # Al-Jumu'ah
    63: 11,   # Al-Munafiqun
    64: 18,   # At-Taghabun
    65: 12,   # At-Talaq
    66: 12,   # At-Tahrim
    67: 30,   # Al-Mulk
    68: 52,   # Al-Qalam
    69: 52,   # Al-Haqqah
    70: 44,   # Al-Ma'arij
    71: 28,   # Nuh
    72: 28,   # Al-Jinn
    73: 20,   # Al-Muzzammil
    74: 56,   # Al-Muddaththir
    75: 40,   # Al-Qiyamah
    76: 31,   # Al-Insan
    77: 50,   # Al-Mursalat
    78: 40,   # An-Naba
    79: 46,   # An-Nazi'at
    80: 42,   # 'Abasa
    81: 29,   # At-Takwir
    82: 19,   # Al-Infitar
    83: 36,   # Al-Mutaffifin
    84: 25,   # Al-Inshiqaq
    85: 22,   # Al-Buruj
    86: 17,   # At-Tariq
    87: 19,   # Al-A'la
    88: 26,   # Al-Ghashiyah
    89: 30,   # Al-Fajr
    90: 20,   # Al-Balad
    91: 15,   # Ash-Shams
    92: 21,   # Al-Layl
    93: 11,   # Ad-Duhaa
    94: 8,    # Ash-Sharh
    95: 8,    # At-Tin
    96: 19,   # Al-'Alaq
    97: 5,    # Al-Qadr
    98: 8,    # Al-Bayyinah
    99: 8,    # Az-Zalzalah
    100: 11,  # Al-'Adiyat
    101: 11,  # Al-Qari'ah
    102: 8,   # At-Takathur
    103: 3,   # Al-'Asr
    104: 9,   # Al-Humazah
    105: 5,   # Al-Fil
    106: 4,   # Quraysh
    107: 7,   # Al-Ma'un
    108: 3,   # Al-Kawthar
    109: 6,   # Al-Kafirun
    110: 3,   # An-Nasr
    111: 5,   # Al-Masad
    112: 4,   # Al-Ikhlas
    113: 5,   # Al-Falaq
    114: 6,   # An-Nas
}

# Surah names in Arabic for error messages
SURAHS_NAMES_ARABIC = {
    1: "الفاتحة",
    2: "البقرة",
    3: "آل عمران",
    4: "النساء",
    5: "المائدة",
    6: "الأنعام",
    7: "الأعراف",
    8: "الأنفال",
    9: "التوبة",
    10: "يونس",
    11: "هود",
    12: "يوسف",
    13: "الرعد",
    14: "إبراهيم",
    15: "الحجر",
    16: "النحل",
    17: "الإسراء",
    18: "الكهف",
    19: "مريم",
    20: "طه",
    21: "الأنبياء",
    22: "الحج",
    23: "المؤمنون",
    24: "النور",
    25: "الفرقان",
    26: "الشعراء",
    27: "النمل",
    28: "القصص",
    29: "العنكبوت",
    30: "الروم",
    31: "لقمان",
    32: "السجدة",
    33: "الأحزاب",
    34: "سبأ",
    35: "فاطر",
    36: "يس",
    37: "الصافات",
    38: "ص",
    39: "الزمر",
    40: "غافر",
    41: "فصلت",
    42: "الشورى",
    43: "الزخرف",
    44: "الدخان",
    45: "الجاثية",
    46: "الأحقاف",
    47: "محمد",
    48: "الفتح",
    49: "الحجرات",
    50: "ق",
    51: "الذاريات",
    52: "الطور",
    53: "النجم",
    54: "القمر",
    55: "الرحمن",
    56: "الواقعة",
    57: "الحديد",
    58: "المجادلة",
    59: "الحشر",
    60: "الممتحنة",
    61: "الصف",
    62: "الجمعة",
    63: "المنافقون",
    64: "التغابن",
    65: "الطلاق",
    66: "التحريم",
    67: "الملك",
    68: "القلم",
    69: "الحاقة",
    70: "المعارج",
    71: "نوح",
    72: "الجن",
    73: "المزمل",
    74: "المدثر",
    75: "القيامة",
    76: "الإنسان",
    77: "المرسلات",
    78: "النبأ",
    79: "النازعات",
    80: "عبس",
    81: "التكوير",
    82: "الإنفطار",
    83: "المطففين",
    84: "الإنشقاق",
    85: "البروج",
    86: "الطارق",
    87: "الأعلى",
    88: "الغاشية",
    89: "الفجر",
    90: "البلد",
    91: "الشمس",
    92: "الليل",
    93: "الضحى",
    94: "الشرح",
    95: "التين",
    96: "العلق",
    97: "القدر",
    98: "البينة",
    99: "الزلزلة",
    100: "العاديات",
    101: "القارعة",
    102: "التكاثر",
    103: "العصر",
    104: "الهمزة",
    105: "الفيل",
    106: "قريش",
    107: "الماعون",
    108: "الكوثر",
    109: "الكافرون",
    110: "النصر",
    111: "المسد",
    112: "الإخلاص",
    113: "الفلق",
    114: "الناس",
}
