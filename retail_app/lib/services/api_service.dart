import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'data_refresh_service.dart';
import '../models/product.dart';
import '../screens/subscription_expired_screen.dart';

/// Бросается, когда backend вернул 429 (rate limit) на вход по
/// паролю/PIN — несёт время в секундах, через которое можно повторить
/// попытку, и человекочитаемое сообщение от сервера.
class RateLimitException implements Exception {
  final int retryAfterSeconds;
  final String message;

  RateLimitException(this.retryAfterSeconds, this.message);

  @override
  String toString() => message;
}

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

  // ─── Товары ──────────────────────────────────────────────────────────────

  Future<Product?> getProductByBarcode(String barcode) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/products/$barcode'),
            headers: await _getHeaders(),
          )
          .timeout(const Duration(seconds: 10));
      _checkSubscription(response.statusCode);
      if (response.statusCode == 200)
        return Product.fromJson(jsonDecode(response.body));
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
    double addStock,
    double sellPrice,
    double buyPrice, {
    String? reason,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/api/products/$id/inventory'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'id': id,
          'add_stock': addStock,
          'sell_price': sellPrice,
          'buy_price': buyPrice,
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        }),
      );

      _checkSubscription(response.statusCode);

      if (response.statusCode == 200) {
        DataRefreshService.instance.notifyProductChanged();
        DataRefreshService.instance.notifyAnalyticsChanged();
        return true;
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Загружает Excel-файл (.xlsx) со списком товаров.
  /// Ожидаемые колонки (без заголовка в результате — заголовок пропускается
  /// на backend'е): название | штрихкод | цена закупки | цена продажи | остаток | единица ('шт' или 'кг').
  /// Возвращает разобранный JSON-ответ {created, updated, errors: [{row, message}]}.
  /// При сетевой/неожиданной ошибке возвращает null.
  Future<Map<String, dynamic>?> importProductsExcel(
    List<int> fileBytes,
    String fileName,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/products/import'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(
        http.MultipartFile.fromBytes('file', fileBytes, filename: fileName),
      );

      final streamed = await request.send().timeout(
        const Duration(seconds: 60),
      );
      final response = await http.Response.fromStream(streamed);

      _checkSubscription(response.statusCode);

      if (response.statusCode == 200) {
        DataRefreshService.instance.notifyProductChanged();
        DataRefreshService.instance.notifyAnalyticsChanged();
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      try {
        return {
          'error': (jsonDecode(response.body)['error'] ?? 'Ошибка импорта')
              .toString(),
        };
      } catch (_) {
        return {'error': 'Ошибка импорта'};
      }
    } catch (e) {
      return null;
    }
  }

  // ─── Продажи ─────────────────────────────────────────────────────────────

  Future<bool> sendSale(Map<String, dynamic> saleData) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/sales'),
        headers: await _getHeaders(),
        body: jsonEncode(saleData),
      );
      _checkSubscription(response.statusCode);
      if (response.statusCode == 200) {
        DataRefreshService.instance.notifySaleChanged();
        DataRefreshService.instance.notifyAnalyticsChanged();
        return true;
      }
      return false;
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

  // ─── Аналитика ───────────────────────────────────────────────────────────

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

  // ─── Пользователи ────────────────────────────────────────────────────────

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
    return createUserWithPin(username, password, role);
  }

  /// Создание сотрудника с опциональным PIN
  Future<bool> createUserWithPin(
    String username,
    String password,
    String role, {
    String? pin,
  }) async {
    try {
      final body = {
        'username': username,
        'password': password,
        'role': role,
        if (pin != null && pin.isNotEmpty) 'pin': pin,
      };
      final response = await http.post(
        Uri.parse('$baseUrl/api/users'),
        headers: await _getHeaders(),
        body: jsonEncode(body),
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

  /// Установить / изменить PIN сотруднику (только owner)
  Future<bool> setUserPin(int userId, String pin) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/users/$userId/pin'),
        headers: await _getHeaders(),
        body: jsonEncode({'pin': pin}),
      );
      _checkSubscription(response.statusCode);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ─── Терминальный режим ───────────────────────────────────────────────────

  /// Получить список сотрудников для выбора в терминальном режиме (без JWT)
  Future<List<dynamic>> getTerminalUsers(int companyId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/terminal/users?company_id=$companyId'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Войти по PIN (терминальный режим) — возвращает токен, роль, имя.
  /// company_id обязателен: PIN проверяется в паре с компанией, иначе
  /// подбор 4-значного PIN сработал бы против пользователя любой компании.
  ///
  /// Бросает [RateLimitException], если backend ответил 429 (слишком много
  /// неверных попыток подряд) — экран должен показать пользователю обратный
  /// отсчёт из `retryAfterSeconds` и заблокировать клавиатуру PIN на это время.
  Future<Map<String, dynamic>?> pinLogin(
    int userId,
    int companyId,
    String pin,
  ) async {
    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$baseUrl/terminal/pin-login'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': userId,
              'company_id': companyId,
              'pin': pin,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      // Сетевая ошибка/таймаут — не считаем это неудачной попыткой входа.
      return null;
    }

    if (response.statusCode == 200) return jsonDecode(response.body);

    if (response.statusCode == 429) {
      final data = jsonDecode(response.body);
      throw RateLimitException(
        (data['retry_after_seconds'] as num?)?.toInt() ?? 60,
        (data['message'] as String?) ??
            'Слишком много попыток. Попробуйте позже.',
      );
    }

    return null;
  }

  /// Войти как владелец (для выхода из терминального режима)
  Future<Map<String, dynamic>?> ownerLogin(
    String username,
    String password,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/login'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return jsonDecode(response.body);
      return null;
    } catch (e) {
      return null;
    }
  }

  // ─── Telegram ─────────────────────────────────────────────────────────────

  /// Сгенерировать deeplink-токен для привязки Telegram (только owner)
  Future<Map<String, dynamic>?> generateTgLinkToken() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/telegram/link-token'),
        headers: await _getHeaders(),
      );
      _checkSubscription(response.statusCode);
      if (response.statusCode == 200) return jsonDecode(response.body);
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Отвязать Telegram (только owner)
  Future<bool> unlinkTelegram() async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/telegram/link'),
        headers: await _getHeaders(),
      );
      _checkSubscription(response.statusCode);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ─── Вспомогательные ─────────────────────────────────────────────────────

  Future<bool> createSale(Map<String, dynamic> saleData) async =>
      sendSale(saleData);
  Future<bool> createSaleFromRawData(Map<String, dynamic> saleData) async =>
      sendSale(saleData);

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

  Future<Map<String, dynamic>?> getAnalyticsSummary(String period) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/analytics/summary?period=$period'),
        headers: await _getHeaders(),
      );
      _checkSubscription(response.statusCode);
      if (response.statusCode == 200)
        return jsonDecode(response.body) as Map<String, dynamic>;
      return null;
    } catch (_) {
      return null;
    }
  }

  // ─── Магазины (#2) ────────────────────────────────────────────────────────

  Future<List<dynamic>> getShops() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/shops'), headers: await _getHeaders())
          .timeout(const Duration(seconds: 10));
      _checkSubscription(response.statusCode);
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> createShop(String name) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/shops'),
        headers: await _getHeaders(),
        body: jsonEncode({'name': name}),
      );
      _checkSubscription(response.statusCode);
      if (response.statusCode == 201) return jsonDecode(response.body);
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<bool> updateShop(int id, String name) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/shops/$id'),
        headers: await _getHeaders(),
        body: jsonEncode({'name': name}),
      );
      _checkSubscription(response.statusCode);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteShop(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/shops/$id'),
        headers: await _getHeaders(),
      );
      _checkSubscription(response.statusCode);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<List<dynamic>> getDebtors() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/debtors'), headers: await _getHeaders())
          .timeout(const Duration(seconds: 10));
      _checkSubscription(response.statusCode);
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> createDebtor({
    required String fullName,
    String phone = '',
    double initialDebt = 0,
    String note = '',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/debtors'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'full_name': fullName,
          'phone': phone,
          'initial_debt': initialDebt,
          'note': note,
        }),
      );
      _checkSubscription(response.statusCode);
      if (response.statusCode == 201) return jsonDecode(response.body);
      return null;
    } catch (e) {
      return null;
    }
  }

  /// type: 'pay' — внёс деньги, 'take' — добавить долг
  Future<Map<String, dynamic>?> debtOperation(
    int debtorId, {
    required double amount,
    required String type,
    String note = '',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/debtors/$debtorId/operation'),
        headers: await _getHeaders(),
        body: jsonEncode({'amount': amount, 'type': type, 'note': note}),
      );
      _checkSubscription(response.statusCode);
      if (response.statusCode == 200) return jsonDecode(response.body);
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<bool> deleteDebtor(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/debtors/$id'),
        headers: await _getHeaders(),
      );
      _checkSubscription(response.statusCode);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<List<dynamic>> getDebtHistory(int debtorId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/debtors/$debtorId/history'),
            headers: await _getHeaders(),
          )
          .timeout(const Duration(seconds: 10));
      _checkSubscription(response.statusCode);
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }
}
