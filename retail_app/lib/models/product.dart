/// ProductUnit — одна единица продажи товара (штука/упаковка/блок/коробка).
///
/// price задаётся НЕЗАВИСИМО от цены других единиц того же товара — никогда
/// не вычисляется на клиенте как priceBase * conversionFactor, т.к. сервер
/// хранит и отдаёт именно свою, отдельную цену за эту единицу.
///
/// barcode принадлежит именно единице продажи, а не товару в целом — так
/// сканер на кассе может найти товар и по штрихкоду штуки, и по штрихкоду
/// упаковки.
class ProductUnit {
  final int id;
  final int productId;
  final String label; // "шт", "упаковка", "блок"...
  final double
  conversionFactor; // сколько базовых единиц (шт/кг) в этой единице
  final double price;
  final String? barcode;
  final bool isBase;
  final bool isActive;

  const ProductUnit({
    required this.id,
    required this.productId,
    required this.label,
    required this.conversionFactor,
    required this.price,
    required this.isBase,
    this.isActive = true,
    this.barcode,
  });

  factory ProductUnit.fromJson(Map<String, dynamic> json) {
    return ProductUnit(
      id: json['id'] ?? 0,
      productId: json['product_id'] ?? 0,
      label: json['label'] ?? '',
      conversionFactor: (json['conversion_factor'] as num?)?.toDouble() ?? 1.0,
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      barcode: json['barcode'] as String?,
      isBase: json['is_base'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'product_id': productId,
    'label': label,
    'conversion_factor': conversionFactor,
    'price': price,
    'barcode': barcode,
    'is_base': isBase,
    'is_active': isActive,
  };
}

class Product {
  final int id;
  final String name;
  final String barcode;
  final double buyPrice;
  final double sellPrice;
  double stock;
  final String unit; // 'pcs' (шт) или 'kg' (кг) — базовая единица учёта склада
  final List<ProductUnit> units;

  Product({
    required this.id,
    required this.name,
    required this.barcode,
    required this.buyPrice,
    required this.sellPrice,
    required this.stock,
    this.unit = 'pcs',
    List<ProductUnit>? units,
  }) : units = units ?? const [];

  /// Человекочитаемое название единицы измерения для UI.
  String get unitLabel => unit == 'kg' ? 'кг' : 'дона';

  /// Базовая единица продажи товара ("шт"/"кг", conversion_factor = 1).
  /// Существует всегда — создаётся автоматически при создании товара.
  /// Фолбэк на синтетический ProductUnit нужен только для товаров, кэш
  /// которых был создан ДО появления product_units (units == []) —
  /// сам сервер такого не отдаёт.
  ProductUnit get baseUnit => units.firstWhere(
    (u) => u.isBase,
    orElse: () => ProductUnit(
      id: 0,
      productId: id,
      label: unitLabel,
      conversionFactor: 1,
      price: sellPrice,
      isBase: true,
    ),
  );

  /// true, если у товара кроме базовой единицы ("шт"/"кг") есть хотя бы
  /// одна доп. единица продажи (упаковка/блок/коробка...). Экран кассы
  /// использует это, чтобы решить, нужно ли вообще спрашивать продавца,
  /// в какой единице он продаёт товар, или добавлять сразу по умолчанию.
  bool get hasMultipleUnits => units.where((u) => u.isActive).length > 1;

  /// Находит единицу продажи по её СОБСТВЕННОМУ штрихкоду (не по штрихкоду
  /// товара в целом) — например, кассир отсканировал штрихкод именно на
  /// упаковке. Возвращает null, если ни у одной единицы нет такого кода.
  ProductUnit? unitByBarcode(String barcode) {
    for (final u in units) {
      if (u.barcode != null && u.barcode == barcode) return u;
    }
    return null;
  }

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
      units: ((json['units'] as List?) ?? const [])
          .map((u) => ProductUnit.fromJson(u as Map<String, dynamic>))
          .toList(),
    );
  }
}
