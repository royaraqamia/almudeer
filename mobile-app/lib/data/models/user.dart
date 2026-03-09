/// User model for Almudeer users
class User {
  final int id;
  final String? username;
  final String? name;
  final String? email;
  final String? image;
  final bool isActive;
  final String? createdAt;
  final String? lastSeenAt;
  final bool isCustomer;
  final bool? isVip;

  User({
    required this.id,
    this.username,
    this.name,
    this.email,
    this.image,
    this.isActive = true,
    this.createdAt,
    this.lastSeenAt,
    this.isCustomer = false,
    this.isVip,
  });

  /// Get display name (username, name, or email)
  String get displayName => username ?? name ?? email ?? 'Unknown User';

  /// Get contact identifier (username preferred, then email)
  String get contact => username ?? email ?? '';

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      username: json['username'] as String?,
      name: json['name'] as String?,
      email: json['email'] as String?,
      image: (json['image'] ?? json['profile_image_url']) as String?,
      isActive: json['is_active'] is int
          ? (json['is_active'] as int) == 1
          : (json['is_active'] as bool? ?? true),
      createdAt: json['created_at'] as String?,
      lastSeenAt: json['last_seen_at'] as String?,
      isCustomer: json['is_customer'] as bool? ?? false,
      isVip: json['is_vip'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'name': name,
      'email': email,
      'image': image,
      'is_active': isActive,
      'created_at': createdAt,
      'last_seen_at': lastSeenAt,
      'is_customer': isCustomer,
      'is_vip': isVip,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is User && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'User(id: $id, username: $username, name: $name, email: $email)';
}
