class DeviceSession {
  final String familyId;
  final String? ipAddress;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;

  DeviceSession({
    required this.familyId,
    this.ipAddress,
    this.createdAt,
    this.lastUsedAt,
  });

  factory DeviceSession.fromJson(Map<String, dynamic> json) {
    return DeviceSession(
      familyId: json['family_id'],
      ipAddress: json['ip_address'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      lastUsedAt: json['last_used_at'] != null
          ? DateTime.parse(json['last_used_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'family_id': familyId,
      'ip_address': ipAddress,
      'created_at': createdAt?.toIso8601String(),
      'last_used_at': lastUsedAt?.toIso8601String(),
    };
  }
}
