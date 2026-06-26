import 'package:flutter/material.dart';
import '../models/product.dart';

class CartItem {
  final Product product;
  // double — для товаров с unit == 'kg' нужно поддерживать дробное
  // количество (например, 0.5 кг). Для штучных товаров остаётся целым.
  double quantity;

  CartItem({required this.product, double? quantity})
    : quantity = quantity ?? 1;
}

class CartProvider with ChangeNotifier {
  Map<int, CartItem> _items = {};

  Map<int, CartItem> get items => _items;

  double get totalAmount {
    double total = 0.0;
    _items.forEach((key, item) {
      total += item.product.sellPrice * item.quantity;
    });
    return total;
  }

  /// Добавляет штучный товар (unit == 'pcs') в корзину, увеличивая
  /// количество на 1. Для товаров с unit == 'kg' не использовать —
  /// вес должен вводиться вручную через [addWeighedAmount].
  void addProduct(Product product) {
    if (_items.containsKey(product.id)) {
      _items[product.id]!.quantity += 1;
    } else {
      _items[product.id] = CartItem(product: product, quantity: 1);
    }
    notifyListeners(); // Обновляет экран
  }

  /// Добавляет вручную введённый вес (кг) к товару в корзине.
  /// Если товара ещё нет в корзине — создаёт строку с этим весом,
  /// если уже есть — добавляет к текущему количеству (например,
  /// продавец взвесил товар во второй раз для того же покупателя).
  void addWeighedAmount(Product product, double weight) {
    if (weight <= 0) return;
    if (_items.containsKey(product.id)) {
      final updated = _items[product.id]!.quantity + weight;
      _items[product.id]!.quantity = double.parse(updated.toStringAsFixed(3));
    } else {
      _items[product.id] = CartItem(product: product, quantity: weight);
    }
    notifyListeners();
  }

  /// Убирает 1 шт. для штучных товаров. Для весовых товаров эта функция
  /// не вызывается — там используется удаление всей строки или ручное
  /// редактирование количества.
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

  void deleteProduct(int productId) {
    _items.remove(productId);
    notifyListeners();
  }
}
