/// Точка истории цены товара.
class PricePoint {
  const PricePoint({required this.price, required this.currency, required this.observedAt});

  final double price;
  final String currency;
  final DateTime observedAt;

  Map<String, dynamic> toJson() => {
        'price': price,
        'currency': currency,
        'observedAt': observedAt.toIso8601String(),
      };

  factory PricePoint.fromJson(Map<String, dynamic> json) => PricePoint(
        price: (json['price'] as num?)?.toDouble() ?? 0,
        currency: json['currency'] as String? ?? '₽',
        observedAt: DateTime.tryParse(json['observedAt'] as String? ?? '') ?? DateTime.now(),
      );
}
