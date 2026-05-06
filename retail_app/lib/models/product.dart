class Product {
  final int id;
  final String name;
  final String barcode;
  final double buyPrice;
  final double sellPrice;
  final int stock;

  Product({
    required this.id,
    required this.name,
    required this.barcode,
    required this.buyPrice,
    required this.sellPrice,
    required this.stock,
  });

  // Теперь мапим ключи именно так, как они приходят из Go
  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      barcode: json['barcode'] ?? '',
      buyPrice: (json['buy_price'] as num?)?.toDouble() ?? 0.0,
      sellPrice: (json['sell_price'] as num?)?.toDouble() ?? 0.0,
      stock: json['stock'] ?? 0,
    );
  }
}