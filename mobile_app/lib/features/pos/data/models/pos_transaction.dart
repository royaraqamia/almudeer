enum PaymentMethod {
  cash,
  mobileWallet,
  qrCode,
}

class TransactionItem {
  final int productId;
  final String productName;
  final String barcode;
  final int quantity;
  final double unitPriceUSD;
  final double unitPriceSYP;
  final double totalUSD;
  final double totalSYP;

  TransactionItem({
    required this.productId,
    required this.productName,
    required this.barcode,
    required this.quantity,
    required this.unitPriceUSD,
    required this.unitPriceSYP,
    required this.totalUSD,
    required this.totalSYP,
  });

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productName': productName,
      'barcode': barcode,
      'quantity': quantity,
      'unitPriceUSD': unitPriceUSD,
      'unitPriceSYP': unitPriceSYP,
      'totalUSD': totalUSD,
      'totalSYP': totalSYP,
    };
  }

  factory TransactionItem.fromMap(Map<String, dynamic> map) {
    return TransactionItem(
      productId: map['productId'] as int,
      productName: map['productName'] as String,
      barcode: map['barcode'] as String,
      quantity: map['quantity'] as int,
      unitPriceUSD: (map['unitPriceUSD'] as num).toDouble(),
      unitPriceSYP: (map['unitPriceSYP'] as num).toDouble(),
      totalUSD: (map['totalUSD'] as num).toDouble(),
      totalSYP: (map['totalSYP'] as num).toDouble(),
    );
  }
}

class Transaction {
  final int? id;
  final List<TransactionItem> items;
  final double subtotalUSD;
  final double subtotalSYP;
  final double discount;
  final double totalUSD;
  final double totalSYP;
  final double exchangeRate;
  final PaymentMethod paymentMethod;
  final int? customerId;
  final String? notes;
  final DateTime createdAt;

  Transaction({
    this.id,
    required this.items,
    required this.subtotalUSD,
    required this.subtotalSYP,
    this.discount = 0.0,
    required this.totalUSD,
    required this.totalSYP,
    required this.exchangeRate,
    this.paymentMethod = PaymentMethod.cash,
    this.customerId,
    this.notes,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'items': items.map((e) => e.toMap()).toList(),
      'subtotalUSD': subtotalUSD,
      'subtotalSYP': subtotalSYP,
      'discount': discount,
      'totalUSD': totalUSD,
      'totalSYP': totalSYP,
      'exchangeRate': exchangeRate,
      'paymentMethod': paymentMethod.name,
      'customerId': customerId,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Transaction.fromMap(Map<String, dynamic> map) {
    final itemsList = (map['items'] as List)
        .map((e) => TransactionItem.fromMap(Map<String, dynamic>.from(e)))
        .toList();

    return Transaction(
      id: map['id'] as int?,
      items: itemsList,
      subtotalUSD: (map['subtotalUSD'] as num).toDouble(),
      subtotalSYP: (map['subtotalSYP'] as num).toDouble(),
      discount: (map['discount'] as num?)?.toDouble() ?? 0.0,
      totalUSD: (map['totalUSD'] as num).toDouble(),
      totalSYP: (map['totalSYP'] as num).toDouble(),
      exchangeRate: (map['exchangeRate'] as num).toDouble(),
      paymentMethod: PaymentMethod.values.firstWhere(
        (e) => e.name == map['paymentMethod'],
        orElse: () => PaymentMethod.cash,
      ),
      customerId: map['customerId'] as int?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}