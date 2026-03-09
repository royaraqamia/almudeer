/// User preferences model matching backend structure
class UserPreferences {
  final bool notificationsEnabled;
  final bool darkMode;
  final bool notificationSound;
  final bool onboardingCompleted;

  final String tone; // 'formal', 'friendly', 'professional', 'custom'
  final String? customToneGuidelines;
  final List<String> preferredLanguages;
  final String? replyLength; // '', 'short', 'medium'
  final String? formalityLevel;

  final String autoDownloadMedia; // 'never', 'wifi', 'always'
  final bool autoDownloadVoiceNotes;
  final int maxAutoDownloadSize; // in bytes
  final List<String> calculatorHistory;

  UserPreferences({
    this.notificationsEnabled = false,
    this.darkMode = false,
    this.notificationSound = true,
    this.onboardingCompleted = false,
    this.tone = 'friendly',
    this.customToneGuidelines,
    this.preferredLanguages = const [],
    this.replyLength,
    this.formalityLevel,
    this.autoDownloadMedia = 'wifi',
    this.autoDownloadVoiceNotes = true,
    this.maxAutoDownloadSize = 2 * 1024 * 1024, // 2MB default
    this.calculatorHistory = const [],
  });

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    // Robust parsing for preferred_languages which might come as a csv string or list
    List<String> parseLanguages(dynamic value) {
      if (value is List) {
        return value.map((e) => e.toString()).toList();
      } else if (value is String) {
        if (value.isEmpty) return [];
        return value
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return [];
    }

    return UserPreferences(
      notificationsEnabled: json['notifications_enabled'] as bool? ?? true,
      darkMode: json['dark_mode'] as bool? ?? false,
      notificationSound: json['notification_sound'] as bool? ?? true,
      onboardingCompleted: json['onboarding_completed'] as bool? ?? false,

      tone: json['tone'] as String? ?? 'friendly',
      customToneGuidelines: json['custom_tone_guidelines'] as String?,
      preferredLanguages: parseLanguages(json['preferred_languages']),
      replyLength: json['reply_length'] as String?,
      formalityLevel: json['formality_level'] as String?,

      // Auto-download preferences (safe parsing)
      autoDownloadMedia: json['auto_download_media'] as String? ?? 'wifi',
      autoDownloadVoiceNotes:
          json['auto_download_voice_notes'] as bool? ?? true,
      maxAutoDownloadSize:
          json['max_auto_download_size'] as int? ?? 2 * 1024 * 1024,
      calculatorHistory:
          (json['calculator_history'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'notifications_enabled': notificationsEnabled,
      'dark_mode': darkMode,
      'notification_sound': notificationSound,
      'onboarding_completed': onboardingCompleted,
      'tone': tone,
      'custom_tone_guidelines': customToneGuidelines,
      'preferred_languages': preferredLanguages,
      'reply_length': replyLength,
      'formality_level': formalityLevel,
      'auto_download_media': autoDownloadMedia,
      'auto_download_voice_notes': autoDownloadVoiceNotes,
      'max_auto_download_size': maxAutoDownloadSize,
      'calculator_history': calculatorHistory,
    };
  }

  UserPreferences copyWith({
    bool? notificationsEnabled,
    bool? darkMode,
    bool? notificationSound,
    bool? onboardingCompleted,
    String? tone,
    String? customToneGuidelines,
    List<String>? preferredLanguages,
    String? replyLength,
    String? formalityLevel,
    String? autoDownloadMedia,
    bool? autoDownloadVoiceNotes,
    int? maxAutoDownloadSize,
    List<String>? calculatorHistory,
  }) {
    return UserPreferences(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      darkMode: darkMode ?? this.darkMode,
      notificationSound: notificationSound ?? this.notificationSound,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      tone: tone ?? this.tone,
      customToneGuidelines: customToneGuidelines ?? this.customToneGuidelines,
      preferredLanguages: preferredLanguages ?? this.preferredLanguages,
      replyLength: replyLength ?? this.replyLength,
      formalityLevel: formalityLevel ?? this.formalityLevel,
      autoDownloadMedia: autoDownloadMedia ?? this.autoDownloadMedia,
      autoDownloadVoiceNotes:
          autoDownloadVoiceNotes ?? this.autoDownloadVoiceNotes,
      maxAutoDownloadSize: maxAutoDownloadSize ?? this.maxAutoDownloadSize,
      calculatorHistory: calculatorHistory ?? this.calculatorHistory,
    );
  }
}
