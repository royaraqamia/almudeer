class PosCategory {
  final int? id;
  final String name;
  final String? nameEn;
  final String? description;
  final String? imagePath;
  final DateTime createdAt;
  final DateTime updatedAt;

  PosCategory({
    this.id,
    required this.name,
    this.nameEn,
    this.description,
    this.imagePath,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'nameEn': nameEn,
      'description': description,
      'imagePath': imagePath,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory PosCategory.fromMap(Map<String, dynamic> map) {
    return PosCategory(
      id: map['id'] as int?,
      name: map['name'] as String,
      nameEn: map['nameEn'] as String?,
      description: map['description'] as String?,
      imagePath: map['imagePath'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }

  PosCategory copyWith({
    int? id,
    String? name,
    String? nameEn,
    String? description,
    String? imagePath,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PosCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      nameEn: nameEn ?? this.nameEn,
      description: description ?? this.description,
      imagePath: imagePath ?? this.imagePath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}