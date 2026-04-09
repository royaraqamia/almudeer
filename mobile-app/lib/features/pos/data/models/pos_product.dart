class Product {
  final int? id;
  final String barcode;
  final String name;
  final String? nameEn;
  final double costPrice;
  final double sellingPriceUSD;
  final int? categoryId;
  final int stock;
  final int minStock;
  final String? imagePath;
  final String? description;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Product({
    this.id,
    required this.barcode,
    required this.name,
    this.nameEn,
    this.costPrice = 0.0,
    this.sellingPriceUSD = 0.0,
    this.categoryId,
    this.stock = 0,
    this.minStock = 5,
    this.imagePath,
    this.description,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  double getPriceInSYP(double exchangeRate) {
    return sellingPriceUSD * exchangeRate;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'barcode': barcode,
      'name': name,
      'nameEn': nameEn,
      'costPrice': costPrice,
      'sellingPriceUSD': sellingPriceUSD,
      'categoryId': categoryId,
      'stock': stock,
      'minStock': minStock,
      'imagePath': imagePath,
      'description': description,
      'isActive': isActive ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as int?,
      barcode: map['barcode'] as String,
      name: map['name'] as String,
      nameEn: map['nameEn'] as String?,
      costPrice: (map['costPrice'] as num).toDouble(),
      sellingPriceUSD: (map['sellingPriceUSD'] as num).toDouble(),
      categoryId: map['categoryId'] as int?,
      stock: map['stock'] as int,
      minStock: map['minStock'] as int,
      imagePath: map['imagePath'] as String?,
      description: map['description'] as String?,
      isActive: (map['isActive'] as int) == 1,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }

  Product copyWith({
    int? id,
    String? barcode,
    String? name,
    String? nameEn,
    double? costPrice,
    double? sellingPriceUSD,
    int? categoryId,
    int? stock,
    int? minStock,
    String? imagePath,
    String? description,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      barcode: barcode ?? this.barcode,
      name: name ?? this.name,
      nameEn: nameEn ?? this.nameEn,
      costPrice: costPrice ?? this.costPrice,
      sellingPriceUSD: sellingPriceUSD ?? this.sellingPriceUSD,
      categoryId: categoryId ?? this.categoryId,
      stock: stock ?? this.stock,
      minStock: minStock ?? this.minStock,
      imagePath: imagePath ?? this.imagePath,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}