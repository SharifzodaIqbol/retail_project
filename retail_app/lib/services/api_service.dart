import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';

class ApiService {
  // Замените на реальный URL при деплое
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:8080',
  );

  Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ?? '';
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
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
      if (response.statusCode == 200) {
        final List<dynamic> body = jsonDecode(response.body);
        return body.map((item) => Product.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<Product>> searchProductsByName(String name) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/products/search?name=$name'),
        headers: await _getHeaders(),
      );
      if (response.statusCode == 200) {
        final List<dynamic> body = jsonDecode(response.body);
        return body.map((item) => Product.fromJson(item)).toList();
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
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateInventory(
    int productId,
    int amount,
    double sellPrice,
    double buyPrice,
  ) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/api/products/$productId/inventory'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'amount': amount,
          'sell_price': sellPrice,
          'buy_price': buyPrice,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteProduct(int productId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/products/$productId'),
        headers: await _getHeaders(),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ─── Продажи ─────────────────────────────────────────────

  Future<bool> createSale(
    List<Map<String, dynamic>> items,
    double total,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/sales'),
            headers: await _getHeaders(),
            body: jsonEncode({'items': items, 'total_amount': total}),
          )
          .timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> createSaleFromRawData(Map<String, dynamic> saleData) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/sales'),
        headers: await _getHeaders(),
        body: jsonEncode(saleData),
      );
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
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<bool> cancelSale(int saleId, String reason) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/sales/cancel'),
        headers: await _getHeaders(),
        body: jsonEncode({'sale_id': saleId, 'reason': reason}),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ─── Аналитика ────────────────────────────────────────────

  Future<Map<String, dynamic>?> getAnalyticsSummary(String period) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/analytics/summary?period=$period'),
        headers: await _getHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<List<dynamic>> getTopProducts({int limit = 10}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/analytics/top-products?limit=$limit'),
        headers: await _getHeaders(),
      );
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
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<dynamic>> getLowStockProducts({int threshold = 10}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/analytics/low-stock?threshold=$threshold'),
        headers: await _getHeaders(),
      );
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
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteUser(int userId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/users/$userId'),
        headers: await _getHeaders(),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
