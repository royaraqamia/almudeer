/// Integration account model
class IntegrationAccount {
  final String id;
  final String channelType;
  final String displayName;
  final bool isActive;
  final String? details;

  IntegrationAccount({
    required this.id,
    required this.channelType,
    required this.displayName,
    required this.isActive,
    this.details,
  });

  factory IntegrationAccount.fromJson(Map<String, dynamic> json) {
    return IntegrationAccount(
      id: json['id'] as String? ?? '',
      channelType: json['channel_type'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? false,
      details: json['details'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'channel_type': channelType,
      'display_name': displayName,
      'is_active': isActive,
      'details': details,
    };
  }

  /// Get channel display name in Arabic
  String get channelDisplayName {
    switch (channelType.toLowerCase()) {
      case 'whatsapp':
        return 'واتساب للأعمال';
      case 'telegram_bot':
        return 'بوت تيليجرام';
      case 'telegram_phone':
        return 'تيليجرام (حساب شخصي)';
      case 'email':
        return 'البريد الإلكتروني';
      default:
        return channelType;
    }
  }

  /// Get channel icon name
  String get channelIconName {
    switch (channelType.toLowerCase()) {
      case 'whatsapp':
        return 'whatsapp';
      case 'telegram_bot':
      case 'telegram_phone':
        return 'telegram';
      case 'email':
        return 'email';
      default:
        return 'integration';
    }
  }
}

/// Email configuration model
class EmailConfig {
  final int id;
  final String emailAddress;
  final String imapServer;
  final String smtpServer;
  final int imapPort;
  final int smtpPort;
  final bool isActive;
  final int checkIntervalMinutes;
  final String? lastCheckedAt;

  EmailConfig({
    required this.id,
    required this.emailAddress,
    required this.imapServer,
    required this.smtpServer,
    required this.imapPort,
    required this.smtpPort,
    required this.isActive,
    required this.checkIntervalMinutes,
    this.lastCheckedAt,
  });

  factory EmailConfig.fromJson(Map<String, dynamic> json) {
    return EmailConfig(
      id: json['id'] as int,
      emailAddress: json['email_address'] as String? ?? '',
      imapServer: json['imap_server'] as String? ?? '',
      smtpServer: json['smtp_server'] as String? ?? '',
      imapPort: json['imap_port'] as int? ?? 993,
      smtpPort: json['smtp_port'] as int? ?? 587,
      isActive: json['is_active'] as bool? ?? false,
      checkIntervalMinutes: json['check_interval_minutes'] as int? ?? 5,
      lastCheckedAt: json['last_checked_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email_address': emailAddress,
      'imap_server': imapServer,
      'smtp_server': smtpServer,
      'imap_port': imapPort,
      'smtp_port': smtpPort,
      'is_active': isActive,
      'check_interval_minutes': checkIntervalMinutes,
      'last_checked_at': lastCheckedAt,
    };
  }

  EmailConfig copyWith({
    int? id,
    String? emailAddress,
    String? imapServer,
    String? smtpServer,
    int? imapPort,
    int? smtpPort,
    bool? isActive,
    int? checkIntervalMinutes,
    String? lastCheckedAt,
  }) {
    return EmailConfig(
      id: id ?? this.id,
      emailAddress: emailAddress ?? this.emailAddress,
      imapServer: imapServer ?? this.imapServer,
      smtpServer: smtpServer ?? this.smtpServer,
      imapPort: imapPort ?? this.imapPort,
      smtpPort: smtpPort ?? this.smtpPort,
      isActive: isActive ?? this.isActive,
      checkIntervalMinutes: checkIntervalMinutes ?? this.checkIntervalMinutes,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    );
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
