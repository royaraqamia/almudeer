/// Customer model
class Customer {
  final int id;
  final String? name;
  final String? phone;
  final String? company;
  final String? notes;
  final String? tags;
  final String? lastContactAt;
  final bool isVip;
  final String createdAt;
  final bool? hasWhatsappServer;
  final bool? hasTelegramServer;
  final String? username;
  final String? image;
  final bool isAlmudeerUser;
  final String? syncStatus;
  final String? profilePicUrl;

  String get contact => username ?? phone ?? '';

  Customer({
    required this.id,
    this.name,
    this.phone,
    this.company,
    this.notes,
    this.tags,
    this.lastContactAt,
    this.isVip = false,
    required this.createdAt,
    this.hasWhatsappServer,
    this.hasTelegramServer,
    this.username,
    this.image,
    this.isAlmudeerUser = false,
    this.syncStatus,
    this.profilePicUrl,
  });

  bool get hasWhatsapp {
    if (hasWhatsappServer == true) return true;
    if (phone == null) return false;
    final digits = phone!.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length >= 10;
  }

  bool get hasTelegram {
    if (hasTelegramServer == true) return true;
    if (phone == null) return false;
    final digits = phone!.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length >= 10;
  }

  factory Customer.fromJson(Map<String, dynamic> json) {
    // sentimentHistory removed

    // Purchase history removed

    return Customer(
      id: (json['id'] ?? json['remote_id'] ?? json['local_id']) as int,
      name: json['name'] as String?,
      phone: json['phone'] as String?,
      company: json['company'] as String?,
      notes: json['notes'] as String?,
      tags: json['tags'] as String?,
      lastContactAt: json['last_contact_at'] as String?,
      isVip: json['is_vip'] is int
          ? (json['is_vip'] as int) == 1
          : (json['is_vip'] as bool? ?? false),
      createdAt: json['created_at'] as String? ?? '',
      hasWhatsappServer: json['has_whatsapp'] is int
          ? (json['has_whatsapp'] as int) == 1
          : (json['has_whatsapp'] as bool?),
      hasTelegramServer: json['has_telegram'] is int
          ? (json['has_telegram'] as int) == 1
          : (json['has_telegram'] as bool?),
      username: json['username'] as String?,
      image:
          (json['image'] ??
                  json['profile_image_url'] ??
                  json['profile_pic_url'])
              as String?,
      isAlmudeerUser:
          (json['is_almudeer_user'] == true ||
          json['is_almudeer_user'] == 1 ||
          json['isAlmudeerUser'] == true ||
          json['isAlmudeerUser'] == 1),
      syncStatus: json['sync_status'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'company': company,
      'notes': notes,
      'tags': tags,
      'last_contact_at': lastContactAt,
      'is_vip': isVip,
      'created_at': createdAt,
      'has_whatsapp': hasWhatsapp,
      'has_telegram': hasTelegram,
      'username': username,
      'image': image,
      'profile_pic_url': image,
      'is_warden_user':
          isAlmudeerUser, // Some places might still use old naming
      'is_almudeer_user': isAlmudeerUser,
      'sync_status': syncStatus,
    };
  }

  Customer copyWith({
    int? id,
    String? name,
    String? phone,
    String? company,
    String? notes,
    String? tags,
    String? lastContactAt,
    bool? isVip,
    String? createdAt,
    bool? hasWhatsapp,
    bool? hasTelegram,
    String? username,
    String? image,
    bool? isAlmudeerUser,
    String? profilePicUrl,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      company: company ?? this.company,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
      lastContactAt: lastContactAt ?? this.lastContactAt,
      isVip: isVip ?? this.isVip,
      createdAt: createdAt ?? this.createdAt,
      hasWhatsappServer: hasWhatsapp ?? hasWhatsappServer,
      hasTelegramServer: hasTelegram ?? hasTelegramServer,
      username: username ?? this.username,
      image: image ?? this.image,
      isAlmudeerUser: isAlmudeerUser ?? this.isAlmudeerUser,
      profilePicUrl: profilePicUrl ?? this.profilePicUrl,
    );
  }

  /// Get display name
  String get displayName {
    if (name != null && name!.isNotEmpty) return name!;
    if (phone != null && phone!.isNotEmpty) return phone!;
    return 'شخص #$id';
  }

  /// Get avatar initials
  String get avatarInitials {
    final displayText = displayName;
    if (displayText.startsWith('شخص')) return '?';

    final words = displayText.split(' ');
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}';
    }
    return displayText[0].toUpperCase();
  }

  /// Get parsed tags list
  List<String> get tagsList {
    if (tags == null || tags!.isEmpty) return [];
    return tags!
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
}

class CustomersResponse {
  final List<Customer> customers;
  final int total;
  final bool hasMore;

  CustomersResponse({
    required this.customers,
    required this.total,
    this.hasMore = false,
  });

  factory CustomersResponse.fromJson(Map<String, dynamic> json) {
    final rawList = (json['results'] ?? json['customers'] ?? json['data']);
    final customersList = rawList is List
        ? rawList
              .map((e) => Customer.fromJson(e as Map<String, dynamic>))
              .toList()
        : <Customer>[];

    final total = json['total'] ?? json['count'] ?? customersList.length;
    final hasMore = json['has_more'] as bool? ?? (json['next'] != null);

    return CustomersResponse(
      customers: customersList,
      total: total is int ? total : int.tryParse(total.toString()) ?? 0,
      hasMore: hasMore,
    );
  }
}
