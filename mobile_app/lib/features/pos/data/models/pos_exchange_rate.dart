class ExchangeRate {
  final int? id;
  final double rate;
  final String? notes;
  final DateTime effectiveDate;
  final DateTime createdAt;

  ExchangeRate({
    this.id,
    required this.rate,
    this.notes,
    DateTime? effectiveDate,
    DateTime? createdAt,
  })  : effectiveDate = effectiveDate ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'rate': rate,
      'notes': notes,
      'effectiveDate': effectiveDate.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ExchangeRate.fromMap(Map<String, dynamic> map) {
    return ExchangeRate(
      id: map['id'] as int?,
      rate: (map['rate'] as num).toDouble(),
      notes: map['notes'] as String?,
      effectiveDate: DateTime.parse(map['effectiveDate'] as String),
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}