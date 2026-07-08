import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:retail_app/helpers/database_helper.dart';
import 'package:retail_app/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data_refresh_service.dart';
import 'connectivity_service.dart';
import '../helpers/database_helper.dart';
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

/// Универсальный контейнер для ответов с пагинацией от сервера.
class PaginatedResult<T> {
  final List<T> data;
  final int total;
  final int page;
  final int limit;
  final int totalPages;

  const PaginatedResult({
    required this.data,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  bool get hasNextPage => page < totalPages;
}

class ApiService {
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:8080',
  );

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  final _db = DatabaseHelper.instance;

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
    if (ConnectivityService.instance.isOnline) {
      try {
        final response = await http
            .get(
              Uri.parse('$baseUrl/api/products/$barcode'),
              headers: await _getHeaders(),
            )
            // Таймаут снижен с 10 до 3 секунд: это горячий путь кассы
            // (сканирование штрихкода на каждый товар), и при реальном
            // отсутствии сети/сервера продавец не должен ждать долго
            // прежде чем сработает офлайн-фолбэк на локальный кэш.
            .timeout(const Duration(seconds: 3));
        _checkSubscription(response.statusCode);
        if (response.statusCode == 200) {
          final json = jsonDecode(response.body);
          return Product.fromJson(json);
        }
      } catch (e) {
        debugPrint('API ERROR: $e');
        // Сетевая ошибка — сразу помечаем "нет сети", чтобы следующий
        // скан/поиск не повторял тот же таймаут, а сразу шёл в кэш.
        ConnectivityService.instance.markOffline();
      }
    }

    // Офлайн или ошибка — ищем в кэше
    final cached = await _db.getCachedProductByBarcode(barcode);
    if (cached != null) return Product.fromJson(cached);
    return null;
  }

  /// Возвращает все товары.
  /// Онлайн: запрашивает API и обновляет полный кэш.
  /// Офлайн: возвращает товары из SQLite-кэша.
  /// Получает страницу товаров с сервера.
  /// Возвращает [PaginatedResult] с полями data, total, page, limit, totalPages.
  /// При офлайне возвращает кэшированные данные без пагинации (page=1).
  Future<PaginatedResult<Product>> getProducts({
    int page = 1,
    int limit = 50,
  }) async {
    if (ConnectivityService.instance.isOnline) {
      try {
        final uri = Uri.parse(
          '$baseUrl/api/products',
        ).replace(queryParameters: {'page': '$page', 'limit': '$limit'});
        final response = await http.get(uri, headers: await _getHeaders());
        _checkSubscription(response.statusCode);
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final items = (body['data'] as List)
              .map((j) => Product.fromJson(j as Map<String, dynamic>))
              .toList();
          // Точечно освежаем в кэше только просмотренные товары — не
          // затираем остальной офлайн-каталог и не ломаем его порядок.
          // Полную пересборку кэша (весь каталог целиком, той же
          // сортировкой, что и на сервере) делает refreshOfflineCache().
          await _db.upsertCachedProducts(
            (body['data'] as List).cast<Map<String, dynamic>>(),
          );
          return PaginatedResult(
            data: items,
            total: body['total'] as int,
            page: body['page'] as int,
            limit: body['limit'] as int,
            totalPages: body['total_pages'] as int,
          );
        }
      } catch (_) {
        // Сетевая ошибка — пробуем кэш
        ConnectivityService.instance.markOffline();
      }
    }

    // Офлайн — читаем из кэша (без пагинации, весь кэш)
    final cached = await _db.getCachedProducts();
    final items = cached.map((j) => Product.fromJson(j)).toList();
    return PaginatedResult(
      data: items,
      total: items.length,
      page: 1,
      limit: items.length,
      totalPages: 1,
    );
  }

  /// Оставляем для обратной совместимости (HomeScreen, кэш штрихкодов).
  Future<List<Product>> getAllProducts() async {
    final result = await getProducts(page: 1, limit: 200);
    return result.data;
  }

  /// Полностью обновляет офлайн-кэш каталога товаров.
  ///
  /// Раньше в кэш попадала только первая страница (максимум 200 товаров),
  /// поэтому если склад был больше — офлайн-режим показывал не весь
  /// каталог. Кроме того, кэш сохранял порядок только той страницы,
  /// которая была загружена последней, что и приводило к ощущению
  /// "всё перемешано" в офлайне.
  ///
  /// Здесь мы последовательно обходим все страницы (как их отдаёт
  /// сервер, т.е. в том же порядке ORDER BY stock ASC, что и в онлайне)
  /// и один раз перезаписываем локальный кэш целиком — так порядок и
  /// состав товаров в офлайне полностью совпадают с онлайн-режимом.
  /// Ничего не делает, если нет сети — вызывается на старте и при
  /// восстановлении связи через [SyncService].
  Future<void> refreshOfflineCache() async {
    if (!ConnectivityService.instance.isOnline) return;

    const pageSize = 200;
    final all = <Map<String, dynamic>>[];
    try {
      int page = 1;
      int totalPages = 1;
      do {
        final uri = Uri.parse(
          '$baseUrl/api/products',
        ).replace(queryParameters: {'page': '$page', 'limit': '$pageSize'});
        final response = await http
            .get(uri, headers: await _getHeaders())
            .timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) break;

        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final items = (body['data'] as List).cast<Map<String, dynamic>>();
        all.addAll(items);

        totalPages = (body['total_pages'] as num?)?.toInt() ?? 1;
        page++;
        // Защита от аномального total_pages — не уходим в бесконечный
        // обход (10000 товаров более чем достаточно для офлайн-кэша).
      } while (page <= totalPages && page <= 50);

      if (all.isNotEmpty || page > 1) {
        await _db.cacheProducts(all);
      }
    } catch (_) {
      // Сетевая ошибка в процессе обхода страниц — оставляем то, что
      // успели скачать в предыдущий раз; частичного/битого кэша не будет,
      // т.к. cacheProducts перезаписывает всё одним batch-ом.
    }

    // Заодно освежаем кэш продавцов терминала (для офлайн-входа по PIN),
    // чтобы он не зависел от того, заходил ли кто-то на экран терминала
    // онлайн после последнего обновления.
    try {
      final prefs = await SharedPreferences.getInstance();
      final companyId = prefs.getInt('company_id') ?? 0;
      if (companyId != 0) {
        await getTerminalUsers(companyId);
      }
    } catch (_) {}
  }

  /// Добавляет товар. Возвращает null при успехе, иначе — строку с ошибкой.
  Future<String?> addProduct(Map<String, dynamic> productData) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/products'),
            headers: await _getHeaders(),
            body: jsonEncode(productData),
          )
          .timeout(const Duration(seconds: 15));
      _checkSubscription(response.statusCode);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return null; // успех
      }
      // Пробуем достать сообщение из тела ответа
      try {
        final body = jsonDecode(response.body);
        final msg = body['error'] ?? body['message'] ?? body['detail'];
        if (msg != null) return msg.toString();
      } catch (_) {}
      // Fallback по статус-коду
      switch (response.statusCode) {
        case 400:
          return 'Нодурустии додаҳо (400)';
        case 401:
          return 'Ваколат нест. Лутфан аз нав ворид шавед (401)';
        case 403:
          return 'Дастрасӣ манъ аст (403)';
        case 409:
          return 'Маҳсулот бо ин штрихкод аллакай мавҷуд аст (409)';
        case 422:
          return 'Маълумот дуруст нест. Нархҳо ва миқдорро санҷед (422)';
        case 500:
          return 'Хатогии сервер. Каме дер кӯшиш кунед (500)';
        default:
          return 'Хатогӣ: ${response.statusCode}';
      }
    } on TimeoutException {
      return 'Вақт тамом шуд. Пайвастшавии интернетро санҷед';
    } catch (e) {
      return 'Хатогии пайвастшавӣ: $e';
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
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/sales'),
            headers: await _getHeaders(),
            body: jsonEncode(saleData),
          )
          // Важно: без таймаута телефон, "формально" подключённый к Wi-Fi
          // без реального интернета (например, роутер без аплинка или
          // captive-портал), мог зависать на системном таймауте на
          // десятки секунд прямо на экране оплаты, вместо быстрого
          // перехода в офлайн-режим и сохранения чека локально.
          .timeout(const Duration(seconds: 8));
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

  /// Получает страницу истории продаж.
  Future<PaginatedResult<dynamic>> getSalesPage({
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/api/sales',
      ).replace(queryParameters: {'page': '$page', 'limit': '$limit'});
      final response = await http.get(uri, headers: await _getHeaders());
      _checkSubscription(response.statusCode);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return PaginatedResult(
          data: body['data'] as List<dynamic>,
          total: body['total'] as int,
          page: body['page'] as int,
          limit: body['limit'] as int,
          totalPages: body['total_pages'] as int,
        );
      }
    } catch (_) {}
    return PaginatedResult(
      data: [],
      total: 0,
      page: page,
      limit: limit,
      totalPages: 0,
    );
  }

  /// Оставляем для обратной совместимости.
  Future<List<dynamic>> getSalesHistory() async {
    final result = await getSalesPage(page: 1, limit: 200);
    return result.data;
  }

  // ─── Аналитика ───────────────────────────────────────────────────────────

  Future<List<dynamic>> getTopProducts({int limit = 5, int? shopId}) async {
    try {
      final shopParam = shopId != null ? '&shop_id=$shopId' : '';
      final response = await http.get(
        Uri.parse('$baseUrl/api/analytics/top-products?limit=$limit$shopParam'),
        headers: await _getHeaders(),
      );
      _checkSubscription(response.statusCode);
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<dynamic>> getSalesByDay({int days = 7, int? shopId}) async {
    try {
      final shopParam = shopId != null ? '&shop_id=$shopId' : '';
      final response = await http.get(
        Uri.parse('$baseUrl/api/analytics/sales-by-day?days=$days$shopParam'),
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

  Future<List<dynamic>> getSellerStats({int? shopId}) async {
    try {
      final shopParam = shopId != null ? '?shop_id=$shopId' : '';
      final response = await http.get(
        Uri.parse('$baseUrl/api/analytics/sellers$shopParam'),
        headers: await _getHeaders(),
      );
      _checkSubscription(response.statusCode);
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Сводка по каждому магазину компании за период (для экрана
  /// "Все магазины"): выручка, прибыль, число чеков, средний чек.
  Future<List<dynamic>> getShopsSummary(String period) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/analytics/by-shop?period=$period'),
        headers: await _getHeaders(),
      );
      _checkSubscription(response.statusCode);
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Назначить (shopId != null) или снять (shopId == null) магазин
  /// сотруднику.
  Future<bool> assignUserShop(int userId, int? shopId) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/users/$userId/shop'),
        headers: await _getHeaders(),
        body: jsonEncode({'shop_id': shopId}),
      );
      _checkSubscription(response.statusCode);
      return response.statusCode == 200;
    } catch (e) {
      return false;
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

  /// Создание сотрудника с опциональным PIN и опциональной привязкой к магазину
  Future<bool> createUserWithPin(
    String username,
    String password,
    String role, {
    String? pin,
    int? shopId,
  }) async {
    try {
      final body = {
        'username': username,
        'password': password,
        'role': role,
        if (pin != null && pin.isNotEmpty) 'pin': pin,
        if (shopId != null) 'shop_id': shopId,
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

  /// Загружает список продавцов для терминала.
  /// Онлайн: API + кэшируем результат.
  /// Офлайн: возвращает кэшированный список из SQLite.
  Future<List<dynamic>> getTerminalUsers(int companyId) async {
    if (ConnectivityService.instance.isOnline) {
      try {
        final response = await http
            .get(Uri.parse('$baseUrl/terminal/users?company_id=$companyId'))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as List<dynamic>;
          // Кэшируем список пользователей
          await _db.cacheTerminalUsers(data.cast<Map<String, dynamic>>());
          return data;
        }
      } catch (_) {}
    }

    // Офлайн — берём из кэша
    return await _db.getCachedTerminalUsers();
  }

  /// Вход по PIN.
  /// Онлайн: запрос к API + сохраняем хэш PIN для офлайн-входа.
  /// Офлайн: проверяем PIN по хэшу в SQLite.
  ///
  /// Бросает [RateLimitException] при 429 (только онлайн).
  Future<Map<String, dynamic>?> pinLogin(
    int userId,
    int companyId,
    String pin,
  ) async {
    if (ConnectivityService.instance.isOnline) {
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
        // Сетевая ошибка в момент запроса — пробуем офлайн
        return _pinLoginOffline(userId, pin);
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        // Сохраняем хэш PIN для будущего офлайн-входа
        await _db.savePinHash(userId, pin);
        return data;
      }

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

    // Офлайн
    return _pinLoginOffline(userId, pin);
  }

  Future<Map<String, dynamic>?> _pinLoginOffline(int userId, String pin) async {
    final user = await _db.verifyPinOffline(userId, pin);
    if (user == null) return null;

    // Формируем ответ аналогично серверному (без настоящего JWT)
    // Используем сохранённый токен из SharedPreferences если есть,
    // иначе возвращаем заглушку — экран покажет офлайн-метку.
    return {
      'user_id': user['id'],
      'username': user['username'],
      'role': user['role'],
      'token': 'offline_token', // фиктивный токен для офлайн-сессии
      'offline': true,
    };
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

  /// Поиск по названию.
  /// Онлайн: запрос к API.
  /// Офлайн: LIKE-поиск по SQLite-кэшу.
  Future<List<Product>> searchProductsByName(String query) async {
    if (ConnectivityService.instance.isOnline) {
      try {
        final response = await http
            .get(
              Uri.parse(
                '$baseUrl/api/products/search?q=${Uri.encodeComponent(query)}',
              ),
              headers: await _getHeaders(),
            )
            // Таймаут снижен с 5 до 2 секунд: это самый "горячий" путь —
            // запрос уходит на каждое нажатие клавиши (после debounce).
            // Если сети реально нет, продавец не должен ждать по 5 сек
            // на каждую букву прежде чем увидит результат из кэша.
            .timeout(const Duration(seconds: 2));
        _checkSubscription(response.statusCode);
        if (response.statusCode == 200) {
          final List<dynamic> data = jsonDecode(response.body);
          return data.map((json) => Product.fromJson(json)).toList();
        }
      } catch (_) {
        // Сетевая ошибка — сразу помечаем "нет сети". Иначе следующая
        // буква, введённая продавцом, снова наткнётся на тот же таймаут
        // до срабатывания фонового пробника ConnectivityService.
        ConnectivityService.instance.markOffline();
      }
    }

    // Офлайн — ищем в кэше
    final cached = await _db.searchCachedProductsByName(query);
    return cached.map((json) => Product.fromJson(json)).toList();
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

  Future<Map<String, dynamic>?> getAnalyticsSummary(
    String period, {
    int? shopId,
  }) async {
    try {
      final shopParam = shopId != null ? '&shop_id=$shopId' : '';
      final response = await http.get(
        Uri.parse('$baseUrl/api/analytics/summary?period=$period$shopParam'),
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

  /// Получает страницу должников.
  Future<PaginatedResult<dynamic>> getDebtorsPage({
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/api/debtors',
      ).replace(queryParameters: {'page': '$page', 'limit': '$limit'});
      final response = await http.get(uri, headers: await _getHeaders());
      _checkSubscription(response.statusCode);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return PaginatedResult(
          data: body['data'] as List<dynamic>,
          total: body['total'] as int,
          page: body['page'] as int,
          limit: body['limit'] as int,
          totalPages: body['total_pages'] as int,
        );
      }
    } catch (_) {}
    return PaginatedResult(
      data: [],
      total: 0,
      page: page,
      limit: limit,
      totalPages: 0,
    );
  }

  /// Оставляем для обратной совместимости.
  Future<List<dynamic>> getDebtors() async {
    final result = await getDebtorsPage(page: 1, limit: 200);
    return result.data;
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
