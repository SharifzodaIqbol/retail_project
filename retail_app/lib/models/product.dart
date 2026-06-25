class Product {
  final int id;
  final String name;
  final String barcode;
  final double buyPrice;
  final double sellPrice;
  double stock;
  final String unit; // 'pcs' (шт) или 'kg' (кг)

  Product({
    required this.id,
    required this.name,
    required this.barcode,
    required this.buyPrice,
    required this.sellPrice,
    required this.stock,
    this.unit = 'pcs',
  });

  /// Человекочитаемое название единицы измерения для UI.
  String get unitLabel => unit == 'kg' ? 'кг' : 'шт';

  // Теперь мапим ключи именно так, как они приходят из Go
  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      barcode: json['barcode'] ?? '',
      buyPrice: (json['buy_price'] as num?)?.toDouble() ?? 0.0,
      sellPrice: (json['sell_price'] as num?)?.toDouble() ?? 0.0,
      stock: (json['stock'] as num?)?.toDouble() ?? 0.0,
      unit: (json['unit'] as String?) ?? 'pcs',
    );
  }
}
