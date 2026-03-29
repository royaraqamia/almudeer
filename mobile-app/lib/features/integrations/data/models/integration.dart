enum IntegrationChannel {
  whatsapp,
  telegram,
  telegramBot,
  almudeer,
  unknown;

  static IntegrationChannel fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'whatsapp':
        return IntegrationChannel.whatsapp;
      case 'telegram':
      case 'telegram_phone':
        return IntegrationChannel.telegram;
      case 'telegram_bot':
        return IntegrationChannel.telegramBot;
      case 'almudeer':
        return IntegrationChannel.almudeer;
      default:
        return IntegrationChannel.unknown;
    }
  }

  String get value {
    switch (this) {
      case IntegrationChannel.whatsapp:
        return 'whatsapp';
      case IntegrationChannel.telegram:
        return 'telegram';
      case IntegrationChannel.telegramBot:
        return 'telegram_bot';
      case IntegrationChannel.almudeer:
        return 'almudeer';
      default:
        return 'unknown';
    }
  }
}

/// Integration account model
class IntegrationAccount {
  final int id;
  final IntegrationChannel channelType;
  final String displayName;
  final bool isActive;
  final Map<String, dynamic>? details;

  IntegrationAccount({
    required this.id,
    required this.channelType,
    required this.displayName,
    required this.isActive,
    this.details,
  });

  factory IntegrationAccount.fromJson(Map<String, dynamic> json) {
    return IntegrationAccount(
      id: json['id'] as int? ?? 0,
      channelType: IntegrationChannel.fromString(json['channel_type'] as String?),
      displayName: json['display_name'] as String? ?? 'Integration',
      isActive: json['is_active'] as bool? ?? false,
      details: json['details'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'channel_type': channelType.value,
      'display_name': displayName,
      'is_active': isActive,
      'details': details,
    };
  }

  /// Get channel display name in Arabic
  String get channelDisplayName {
    switch (channelType) {
      case IntegrationChannel.whatsapp:
        return 'واتساب للأعمال';
      case IntegrationChannel.telegramBot:
        return 'بوت تيليجرام';
      case IntegrationChannel.telegram:
        return 'تيليجرام (حساب شخصي)';
      case IntegrationChannel.almudeer:
        return 'المدير';
      case IntegrationChannel.unknown:
        return 'غير معروف';
    }
  }

  /// Get channel icon name
  String get channelIconName {
    switch (channelType) {
      case IntegrationChannel.whatsapp:
        return 'whatsapp';
      case IntegrationChannel.telegramBot:
      case IntegrationChannel.telegram:
        return 'telegram';
      case IntegrationChannel.almudeer:
        return 'almudeer';
      default:
        return 'integration';
    }
  }
}


/// Telegram bot configuration model
class TelegramConfig {
  final int id;
  final String? botUsername;
  final String? botTokenMasked;
  final bool isActive;
  final String? webhookSecret;

  TelegramConfig({
    required this.id,
    this.botUsername,
    this.botTokenMasked,
    required this.isActive,
    this.webhookSecret,
  });

  factory TelegramConfig.fromJson(Map<String, dynamic> json) {
    return TelegramConfig(
      id: json['id'] as int,
      botUsername: json['bot_username'] as String?,
      botTokenMasked: json['bot_token_masked'] as String?,
      isActive: json['is_active'] as bool? ?? false,
      webhookSecret: json['webhook_secret'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bot_username': botUsername,
      'bot_token_masked': botTokenMasked,
      'is_active': isActive,
      'webhook_secret': webhookSecret,
    };
  }

  TelegramConfig copyWith({
    int? id,
    String? botUsername,
    String? botTokenMasked,
    bool? isActive,
    String? webhookSecret,
  }) {
    return TelegramConfig(
      id: id ?? this.id,
      botUsername: botUsername ?? this.botUsername,
      botTokenMasked: botTokenMasked ?? this.botTokenMasked,
      isActive: isActive ?? this.isActive,
      webhookSecret: webhookSecret ?? this.webhookSecret,
    );
  }
}

/// WhatsApp configuration model
class WhatsAppConfig {
  final int id;
  final String phoneNumberId;
  final String businessAccountId;
  final bool isActive;
  final String? displayPhoneNumber;

  WhatsAppConfig({
    required this.id,
    required this.phoneNumberId,
    required this.businessAccountId,
    required this.isActive,
    this.displayPhoneNumber,
  });

  factory WhatsAppConfig.fromJson(Map<String, dynamic> json) {
    return WhatsAppConfig(
      id: json['id'] as int,
      phoneNumberId: json['phone_number_id'] as String? ?? '',
      businessAccountId: json['business_account_id'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? false,
      displayPhoneNumber: json['display_phone_number'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phone_number_id': phoneNumberId,
      'business_account_id': businessAccountId,
      'is_active': isActive,
      'display_phone_number': displayPhoneNumber,
    };
  }

  WhatsAppConfig copyWith({
    int? id,
    String? phoneNumberId,
    String? businessAccountId,
    bool? isActive,
    String? displayPhoneNumber,
  }) {
    return WhatsAppConfig(
      id: id ?? this.id,
      phoneNumberId: phoneNumberId ?? this.phoneNumberId,
      businessAccountId: businessAccountId ?? this.businessAccountId,
      isActive: isActive ?? this.isActive,
      displayPhoneNumber: displayPhoneNumber ?? this.displayPhoneNumber,
    );
  }
}

/// Integration accounts list response
class IntegrationAccountsResponse {
  final List<IntegrationAccount> accounts;

  IntegrationAccountsResponse({required this.accounts});

  factory IntegrationAccountsResponse.fromJson(Map<String, dynamic> json) {
    final accountsList =
        (json['accounts'] as List<dynamic>?)
            ?.map((e) => IntegrationAccount.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    return IntegrationAccountsResponse(accounts: accountsList);
  }
}
