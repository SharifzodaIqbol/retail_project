import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';

class ApiService {
  final String baseUrl = 'http://localhost:8080';

  // Вспомогательный метод для получения заголовков с токеном
  Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<Product?> getProductByBarcode(String barcode) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/products/$barcode'),
        headers: await _getHeaders(),
      );

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}'); // Посмотрим, что прислал Go

      if (response.statusCode == 200) {
        // Если тут будет ошибка в названиях полей, выполнение уйдет в catch
        return Product.fromJson(jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      print('ОШИБКА ПАРСИНГА: $e'); // <--- Это скажет, какое поле не совпало
      return null;
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
      print('Ошибка загрузки истории: $e');
      return [];
    }
  }

  // 2. Отправка продажи (чека)
  Future<bool> createSale(
    List<Map<String, dynamic>> items,
    double total,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/sales'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'items': items,
          'total_amount': total, // Было 'total', исправь на 'total_amount'
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Ошибка продажи: $e');
      return false;
    }
  }

  Future<List<Product>> searchProductsByName(String name) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/products/search?name=$name'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      List<dynamic> body = jsonDecode(response.body);
      return body.map((item) => Product.fromJson(item)).toList();
    }
    return [];
  }
}
