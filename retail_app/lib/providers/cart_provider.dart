import 'package:flutter/material.dart';
import '../models/product.dart';

class CartItem {
  final Product product;
  // selectedUnit — какую единицу продажи выбрал кассир (шт/упаковка/блок).
  // Цена и то, что уходит в чек, считаются по НЕЙ, а не по product.sellPrice
  // напрямую — у товара может не быть единой "цены", если у разных единиц
  // продажи цена задана независимо.
  ProductUnit selectedUnit;
  // quantity — сколько единиц ПРОДАЖИ (selectedUnit) выбрал кассир, т.е.
  // ровно то же самое, что уйдёт на сервер как quantity_display. Пересчёт в
  // базовые единицы (quantity_base = quantity * selectedUnit.conversionFactor)
  // делает бэкенд при оформлении продажи — на клиенте это число никогда не
  // используется для списания склада.
  double quantity;

  CartItem({required this.product, ProductUnit? unit, double? quantity})
    : selectedUnit = unit ?? product.baseUnit,
      quantity = quantity ?? 1;
}

class CartProvider with ChangeNotifier {
  Map<int, CartItem> _items = {};

  Map<int, CartItem> get items => _items;

  double get totalAmount {
    double total = 0.0;
    _items.forEach((key, item) {
      total += item.selectedUnit.price * item.quantity;
    });
    return total;
  }

  /// Добавляет товар в корзину в единице продажи [unit] (по умолчанию —
  /// базовая единица товара, "шт"/"кг"). Если товар уже в корзине В ТОЙ ЖЕ
  /// единице продажи — увеличивает количество на 1, иначе создаёт новую
  /// позицию. Для дробных количеств (вес и т.п.) использовать
  /// [addWeighedAmount].
  void addProduct(Product product, {ProductUnit? unit}) {
    final chosenUnit = unit ?? product.baseUnit;
    final existing = _items[product.id];
    if (existing != null && existing.selectedUnit.id == chosenUnit.id) {
      existing.quantity += 1;
    } else {
      // Смена единицы продажи для уже лежащего в корзине товара — заменяем
      // позицию новой единицей, а не складываем количество вслепую: "1 шт"
      // и "1 упаковка" — разные вещи и их нельзя суммировать в одном числе.
      _items[product.id] = CartItem(
        product: product,
        unit: chosenUnit,
        quantity: 1,
      );
    }
    notifyListeners();
  }

  void addWeighedAmount(Product product, double weight, {ProductUnit? unit}) {
    if (weight <= 0) return;
    final chosenUnit = unit ?? product.baseUnit;
    final existing = _items[product.id];
    if (existing != null && existing.selectedUnit.id == chosenUnit.id) {
      final updated = existing.quantity + weight;
      existing.quantity = double.parse(updated.toStringAsFixed(3));
    } else {
      _items[product.id] = CartItem(
        product: product,
        unit: chosenUnit,
        quantity: weight,
      );
    }
    notifyListeners();
  }

  void removeOneItem(int productId) {
    if (!_items.containsKey(productId)) return;
    final item = _items[productId]!;
    if (item.quantity > 1) {
      item.quantity -= 1;
    } else {
      _items.remove(productId);
    }
    notifyListeners();
  }

  void clearCart() {
    _items = {};
    notifyListeners();
  }

  void updateQuantity(int productId, double newQuantity) {
    if (newQuantity <= 0) {
      _items.remove(productId);
    } else if (_items.containsKey(productId)) {
      _items[productId]!.quantity = newQuantity;
    }
    notifyListeners();
  }

  /// Меняет единицу продажи уже лежащего в корзине товара (кассир выбрал
  /// другую карточку — например, "упаковка" вместо "шт"). Количество не
  /// пересчитывается автоматически (1 шт не превращается в 1 упаковку) —
  /// сбрасывается на 1, чтобы не создать у кассира ложное впечатление, что
  /// это то же самое количество товара.
  void changeUnit(int productId, ProductUnit unit) {
    final item = _items[productId];
    if (item == null) return;
    item.selectedUnit = unit;
    item.quantity = 1;
    notifyListeners();
  }

  void deleteProduct(int productId) {
    _items.remove(productId);
    notifyListeners();
  }
}
