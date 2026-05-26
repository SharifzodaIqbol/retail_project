import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';
import '../screens/subscription_expired_screen.dart';

class ApiService {
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:8080',
  );

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ?? '';
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // Вспомогательный метод контроля подписки
  void _checkSubscription(int statusCode) {
    if (statusCode == 402) {
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => const SubscriptionExpiredScreen(),
        ),
        (route) => false,
      );
    }
  }

  // ─── Товары ──────────────────────────────────────────────

  Future<Product?> getProductByBarcode(String barcode) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/products/$barcode'),
            headers: await _getHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      _checkSubscription(response.statusCode);

      if (response.statusCode == 200) {
        return Product.fromJson(jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<List<Product>> getAllProducts() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/products'),
        headers: await _getHeaders(),
      );

      _checkSubscription(response.statusCode);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => Product.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<bool> addProduct(Map<String, dynamic> productData) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/products'),
        headers: await _getHeaders(),
        body: jsonEncode(productData),
      );

      _checkSubscription(response.statusCode);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateInventory(
    int id,
    int addStock,
    double sellPrice,
    double buyPrice,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/products/update-inventory'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'id': id,
          'add_stock': addStock,
          'sell_price': sellPrice,
          'buy_price': buyPrice,
        }),
      );

      _checkSubscription(response.statusCode);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ─── Продажи ─────────────────────────────────────────────

  Future<bool> sendSale(Map<String, dynamic> saleData) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/sales'),
        headers: await _getHeaders(),
        body: jsonEncode(saleData),
      );

      _checkSubscription(response.statusCode);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<List<dynamic>> getSalesHistory() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/sales'),
        headers: await _getHeaders(),
      );

      _checkSubscription(response.statusCode);
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  // ─── Аналитика ───────────────────────────────────────────

  Future<List<dynamic>> getTopProducts({int limit = 5}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/analytics/top-products?limit=$limit'),
        headers: await _getHeaders(),
      );

      _checkSubscription(response.statusCode);
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<dynamic>> getSalesByDay({int days = 7}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/analytics/sales-by-day?days=$days'),
        headers: await _getHeaders(),
      );

      _checkSubscription(response.statusCode);
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<dynamic>> getLowStockProducts({int threshold = 5}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/analytics/low-stock?threshold=$threshold'),
        headers: await _getHeaders(),
      );

      _checkSubscription(response.statusCode);
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<dynamic>> getSellerStats() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/analytics/sellers'),
        headers: await _getHeaders(),
      );

      _checkSubscription(response.statusCode);
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  // ─── Пользователи ────────────────────────────────────────

  Future<List<dynamic>> getUsers() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/users'),
        headers: await _getHeaders(),
      );

      _checkSubscription(response.statusCode);
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<bool> createUser(String username, String password, String role) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/users'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'username': username,
          'password': password,
          'role': role,
        }),
      );

      _checkSubscription(response.statusCode);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteUser(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/users/$id'),
        headers: await _getHeaders(),
      );

      _checkSubscription(response.statusCode);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ─── МЕТОДЫ СИНХРОНИЗАЦИИ С HOME / HISTORY / ANALYTICS SCREENS ───

  /// 1. Создание продажи
  Future<bool> createSale(Map<String, dynamic> saleData) async {
    return await sendSale(saleData);
  }

  /// 2. Создание продажи из оффлайн-логов
  Future<bool> createSaleFromRawData(Map<String, dynamic> saleData) async {
    return await sendSale(saleData);
  }

  /// 3. Поиск товаров по имени на бэкенде
  Future<List<Product>> searchProductsByName(String query) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '$baseUrl/api/products/search?q=${Uri.encodeComponent(query)}',
            ),
            headers: await _getHeaders(),
          )
          .timeout(const Duration(seconds: 5));

      _checkSubscription(response.statusCode);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => Product.fromJson(json)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// 4. Отмена чека
  Future<bool> cancelSale(int saleId, String reason) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/sales/$saleId/cancel'),
        headers: await _getHeaders(),
        body: jsonEncode({'reason': reason}),
      );

      _checkSubscription(response.statusCode);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 5. Сводная аналитика за период
  Future<Map<String, dynamic>?> getAnalyticsSummary(String period) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/analytics/summary?period=$period'),
        headers: await _getHeaders(),
      );

      _checkSubscription(response.statusCode);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
