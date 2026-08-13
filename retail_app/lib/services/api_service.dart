import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:retail_app/helpers/database_helper.dart';
import 'package:retail_app/services/connectivity_service.dart';
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

/// Результат попытки отправить чек на сервер. Раньше sendSale возвращал
/// голый bool, из-за чего реальный обрыв сети и бизнес-отказ сервера
/// (например, "недостаточно товара ID: 12") обрабатывались одинаково —
/// чек молча уходил в офлайн-очередь с пометкой "нет сети" и затем вечно
/// повторял ту же самую попытку при каждом запуске приложения, никогда
/// не сообщая пользователю о реальной причине.
enum SaleSendStatus {
  success,
  networkError, // нет соединения / таймаут — имеет смысл повторить позже
  rejected, // сервер ответил 4xx/5xx с конкретной бизнес-ошибкой — повторять бессмысленно без вмешательства человека
}

class SaleSendResult {
  final SaleSendStatus status;
  final String? errorMessage;

  const SaleSendResult(this.status, {this.errorMessage});

  bool get isSuccess => status == SaleSendStatus.success;
  bool get isNetworkError => status == SaleSendStatus.networkError;
  bool get isRejected => status == SaleSendStatus.rejected;
}

/// Результат создания товара: при успехе несёт id (нужен, чтобы сразу же
/// добавить доп. единицы продажи через addProductUnit), при неудаче — текст
/// ошибки для показа продавцу.
class ProductCreateResult {
  final int? productId;
  final String? errorMessage;

  const ProductCreateResult._(this.productId, this.errorMessage);

  factory ProductCreateResult.success(int productId) =>
      ProductCreateResult._(productId, null);

  factory ProductCreateResult.failure(String errorMessage) =>
      ProductCreateResult._(null, errorMessage);

  bool get isSuccess => productId != null;
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

  // Флаг на уровне класса (не инстанса — ApiService создаётся заново на
  // каждом экране через ApiService(), см. `final _apiService = ApiService();`
  // по всему коду), чтобы при одновременном 401 сразу с нескольких
  // параллельных запросов (например, фоновая синхронизация каталога и
  // действие продавца совпали по времени) не запускать разлогин дважды
  // и не показывать сообщение об истечении сессии несколько раз подряд.
  static bool _handlingSessionExpiry = false;

  /// Централизованная реакция на два вида ошибок авторизации, общих для
  /// всего API, — вызывается после каждого запроса, сразу как получен
  /// response.statusCode:
  ///
  ///  - 402 (Payment Required) — подписка компании истекла, кидаем на
  ///    экран "Обуна ба охир расид" (было и раньше, без изменений).
  ///
  ///  - 401 (Unauthorized) — JWT-токен невалиден или истёк. Токен живёт
  ///    ровно 24 часа (см. backend/internal/auth/jwt.go), а в приложении
  ///    НЕТ автообновления токена — если сессия не была обновлена входом
  ///    заново, токен тихо умирает, и любой следующий запрос падает с
  ///    сырым "Неверный токен" от сервера. Раньше это сообщение просто
  ///    показывалось как обычная ошибка на том экране, где кассир
  ///    случайно на него наткнулся (например, при добавлении товара) —
  ///    без объяснения и без выхода из тупика, кроме случайно
  ///    угаданного "выйти и зайти заново". Теперь при 401 приложение
  ///    само делает ровно это: тихо разлогинивает (чистит токен и кэш
  ///    товаров — см. комментарий про clearProductCache в logout()) и
  ///    возвращает на экран входа с понятным сообщением вместо тупика.
  void _handleAuthErrors(int statusCode) {
    if (statusCode == 402) {
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => const SubscriptionExpiredScreen(),
        ),
        (route) => false,
      );
      return;
    }

    if (statusCode == 401) {
      if (_handlingSessionExpiry) return;
      _handlingSessionExpiry = true;
      unawaited(_forceReLoginAfterSessionExpiry());
    }
  }

  /// Чистит сессию (токен, роль, company/shop_id — те же ключи, что и
  /// обычный logout) и кэш товаров, затем сообщает всему приложению
  /// через DataRefreshService, что нужно вернуться на экран входа.
  ///
  /// Не переиспользует AuthService.logout() напрямую, чтобы не заводить
  /// циклический импорт api_service.dart <-> auth_service.dart (последний
  /// уже импортирует api_service.dart ради ProductCreateResult и т.п.) —
  /// набор очищаемых ключей и вызов clearProductCache() продублирован
  /// намеренно, это буквально три строки.
  Future<void> _forceReLoginAfterSessionExpiry() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('jwt_token');
      await prefs.remove('user_role');
      await prefs.remove('username');
      await prefs.remove('company_id');
      await prefs.remove('company_name');
      await prefs.remove('shop_id');
      await prefs.remove('shop_name');
      await prefs.remove('needs_shop_setup');
      await prefs.remove('terminal_mode');
      await _db.clearProductCache();

      DataRefreshService.instance.notifySessionExpired(
        'Сессия истекла. Пожалуйста, войдите снова.',
      );

      // Если продавец в этот момент был глубоко в каком-то экране,
      // открытом поверх кассы (Navigator.push, например "Добавить товар"
      // или "Склад") — одной перерисовки корневого AppBootstrapper
      // недостаточно: открытый поверх экран так и останется висеть на
      // стеке навигации, а событие onSessionExpired просто изменит
      // состояние ПОД ним, невидимо для продавца. Схлопываем стек до
      // самого корня, чтобы экран входа реально стал виден, а не просто
      // "готов появиться", если продавец сам вручную закроет все экраны.
      navigatorKey.currentState?.popUntil((route) => route.isFirst);
    } finally {
      _handlingSessionExpiry = false;
    }
  }

  // ─── Товары ──────────────────────────────────────────────────────────────

  /// Просит сервер подобрать свободный (ещё никем не занятый в рамках
  /// компании) внутренний штрихкод для товара без своего кода — см.
  /// generateBarcode на бэкенде. Ничего не сохраняет, просто предлагает
  /// значение, которым можно заполнить поле "Штрихкод" перед сохранением
  /// товара. Возвращает null при любой ошибке — вызывающий код должен
  /// показать это как обычную сетевую/серверную ошибку.
  Future<String?> generateBarcode() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/products/generate-barcode'),
            headers: await _getHeaders(),
          )
          .timeout(const Duration(seconds: 10));
      _handleAuthErrors(response.statusCode);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return json['barcode'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Ищет товар по штрихкоду для горячего пути кассы (каждый скан).
  ///
  /// ВАЖНО: раньше это был запрос на сервер НА КАЖДЫЙ скан (с фолбэком в
  /// кэш только при ошибке/офлайне). Сервер у нас в другом регионе от
  /// магазинов, поэтому каждый такой запрос — это полный сетевой
  /// round-trip, который кассир ощущал как задержку перед тем, как товар
  /// попадёт в корзину.
  //
  // Теперь порядок обратный — локальный кэш ВСЕГДА проверяется первым,
  // синхронно и мгновенно (in-memory индекс в DatabaseHelper), а сеть
  // используется только если товара в кэше нет (новый товар, ещё не
  // попавший в каталог кассы) — чтобы не отвечать кассиру ложным "товар
  // не найден" только из-за того, что фоновая синхронизация каталога
  // ещё не успела подхватить новинку. Если товар найден в кэше — сеть
  // вообще не трогаем: цена/остаток на экране могут на несколько минут
  // отставать от сервера, но это не страшно, т.к. финальная проверка
  // остатка и цены всё равно происходит на сервере в момент оформления
  // чека (см. sync_service.dart — чек с нехваткой товара отклоняется
  // сервером и требует ручного решения, а не тихо проходит).
  Future<Product?> getProductByBarcode(String barcode) async {
    final cached = await _db.getCachedProductByBarcode(barcode);
    // units пустой у кэшированного товара — признак "битой"/устаревшей
    // записи (например, кэш от версии до появления единиц продажи).
    // Такой товар нельзя молча добавить в корзину (см. комментарий ниже
    // про синтетическую единицу id = 0), поэтому для него всё равно
    // идём в сеть — как будто это cache miss.
    if (cached != null && (cached['units'] as List? ?? const []).isNotEmpty) {
      return Product.fromJson(cached);
    }

    if (!ConnectivityService.instance.isOnline) {
      // Офлайн и в кэше товара нет (или кэш "битый") — честно говорим,
      // что не нашли, а не гадаем.
      return null;
    }

    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/products/barcode/$barcode'),
            headers: await _getHeaders(),
          )
          // Таймаут снижен с 10 до 3 секунд: сюда попадают только новые,
          // ещё не закэшированные товары, но продавец всё равно не
          // должен ждать долго прежде чем сработает явная ошибка "не
          // найден" вместо зависшего интерфейса.
          .timeout(const Duration(seconds: 3));
      _handleAuthErrors(response.statusCode);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        // Кладём найденный товар в кэш сразу — повторный скан этого же
        // штрихкода (или его единицы) в этой же смене будет уже
        // мгновенным, из кэша.
        unawaited(_db.upsertCachedProducts([json]));
        return Product.fromJson(json);
      }
    } catch (e) {
      debugPrint('API ERROR: $e');
      // Сетевая ошибка — сразу помечаем "нет сети", чтобы следующий
      // скан/поиск не повторял тот же таймаут.
      ConnectivityService.instance.markOffline();
    }

    return null;
  }

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
        _handleAuthErrors(response.statusCode);
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final items = (body['data'] as List)
              .map((j) => Product.fromJson(j as Map<String, dynamic>))
              .toList();
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

    try {
      final prefs = await SharedPreferences.getInstance();
      final companyId = prefs.getInt('company_id') ?? 0;
      final shopId = prefs.getInt('shop_id') ?? 0;
      if (companyId != 0) {
        await getTerminalUsers(companyId, shopId: shopId);
      }
    } catch (_) {}

    // Полностью пересобираем офлайн-кэш Истории продаж и Должников — тем же
    // способом, что и каталог товаров выше: последовательно обходим все
    // страницы, чтобы состав и порядок совпадали с онлайн-режимом.
    await _refreshSalesCache();
    await _refreshDebtorsCache();
  }

  Future<void> _refreshSalesCache() async {
    if (!ConnectivityService.instance.isOnline) return;
    const pageSize = 200;
    final all = <Map<String, dynamic>>[];
    try {
      int page = 1;
      int totalPages = 1;
      do {
        final uri = Uri.parse(
          '$baseUrl/api/sales',
        ).replace(queryParameters: {'page': '$page', 'limit': '$pageSize'});
        final response = await http
            .get(uri, headers: await _getHeaders())
            .timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) break;
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        all.addAll((body['data'] as List).cast<Map<String, dynamic>>());
        totalPages = (body['total_pages'] as num?)?.toInt() ?? 1;
        page++;
      } while (page <= totalPages && page <= 50);

      if (all.isNotEmpty || page > 1) {
        await _db.cacheSales(all);
      }
    } catch (_) {
      // Оставляем то, что уже было закэшировано ранее.
    }
  }

  Future<void> _refreshDebtorsCache() async {
    if (!ConnectivityService.instance.isOnline) return;
    const pageSize = 200;
    final all = <Map<String, dynamic>>[];
    try {
      int page = 1;
      int totalPages = 1;
      do {
        final uri = Uri.parse(
          '$baseUrl/api/debtors',
        ).replace(queryParameters: {'page': '$page', 'limit': '$pageSize'});
        final response = await http
            .get(uri, headers: await _getHeaders())
            .timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) break;
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        all.addAll((body['data'] as List).cast<Map<String, dynamic>>());
        totalPages = (body['total_pages'] as num?)?.toInt() ?? 1;
        page++;
      } while (page <= totalPages && page <= 50);

      if (all.isNotEmpty || page > 1) {
        await _db.cacheDebtors(all);
      }
    } catch (_) {
      // Оставляем то, что уже было закэшировано ранее.
    }
  }

  /// Добавляет товар. Возвращает null при успехе, иначе — строку с ошибкой.
  /// Возвращает id созданного товара при успехе (product_id нужен, чтобы
  /// следом одним заходом добавить доп. единицы продажи через
  /// [addProductUnit]), либо текст ошибки, если создание не удалось.
  Future<ProductCreateResult> addProduct(
    Map<String, dynamic> productData,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/products'),
            headers: await _getHeaders(),
            body: jsonEncode(productData),
          )
          .timeout(const Duration(seconds: 15));
      _handleAuthErrors(response.statusCode);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = jsonDecode(response.body);
        return ProductCreateResult.success(body['id'] as int);
      }
      // Пробуем достать сообщение из тела ответа
      try {
        final body = jsonDecode(response.body);
        final msg = body['error'] ?? body['message'] ?? body['detail'];
        if (msg != null) return ProductCreateResult.failure(msg.toString());
      } catch (_) {}
      // Fallback по статус-коду
      switch (response.statusCode) {
        case 400:
          return ProductCreateResult.failure('Нодурустии додаҳо (400)');
        case 401:
          return ProductCreateResult.failure(
            'Ваколат нест. Лутфан аз нав ворид шавед (401)',
          );
        case 403:
          return ProductCreateResult.failure('Дастрасӣ манъ аст (403)');
        case 409:
          return ProductCreateResult.failure(
            'Маҳсулот бо ин штрихкод аллакай мавҷуд аст (409)',
          );
        case 422:
          return ProductCreateResult.failure(
            'Маълумот дуруст нест. Нархҳо ва миқдорро санҷед (422)',
          );
        case 500:
          return ProductCreateResult.failure(
            'Хатогии сервер. Каме дер кӯшиш кунед (500)',
          );
        default:
          return ProductCreateResult.failure('Хатогӣ: ${response.statusCode}');
      }
    } on TimeoutException {
      return ProductCreateResult.failure(
        'Вақт тамом шуд. Пайвастшавии интернетро санҷед',
      );
    } catch (e) {
      return ProductCreateResult.failure('Хатогии пайвастшавӣ: $e');
    }
  }

  /// Добавляет дополнительную единицу продажи (упаковка/блок/коробка...)
  /// уже существующему товару. Возвращает null при успехе, иначе — текст
  /// ошибки (например, штрихкод уже занят другой единицей).
  Future<String?> addProductUnit(
    int productId,
    Map<String, dynamic> unitData,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/products/$productId/units'),
            headers: await _getHeaders(),
            body: jsonEncode(unitData),
          )
          .timeout(const Duration(seconds: 15));
      _handleAuthErrors(response.statusCode);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return null; // успех
      }
      try {
        final body = jsonDecode(response.body);
        final msg = body['error'] ?? body['message'] ?? body['detail'];
        if (msg != null) return msg.toString();
      } catch (_) {}
      return 'Хатогӣ: ${response.statusCode}';
    } on TimeoutException {
      return 'Вақт тамом шуд. Пайвастшавии интернетро санҷед';
    } catch (e) {
      return 'Хатогии пайвастшавӣ: $e';
    }
  }

  /// Редактирует уже существующую единицу продажи (её название, коэффициент
  /// пересчёта, цену, штрихкод). Возвращает null при успехе, иначе — текст
  /// ошибки с сервера.
  Future<String?> updateProductUnit(
    int productId,
    int unitId,
    Map<String, dynamic> unitData,
  ) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/products/$productId/units/$unitId'),
            headers: await _getHeaders(),
            body: jsonEncode(unitData),
          )
          .timeout(const Duration(seconds: 15));
      _handleAuthErrors(response.statusCode);
      if (response.statusCode == 200) return null;
      try {
        final body = jsonDecode(response.body);
        final msg = body['error'] ?? body['message'] ?? body['detail'];
        if (msg != null) return msg.toString();
      } catch (_) {}
      return 'Хатогӣ: ${response.statusCode}';
    } on TimeoutException {
      return 'Вақт тамом шуд. Пайвастшавии интернетро санҷед';
    } catch (e) {
      return 'Хатогии пайвастшавӣ: $e';
    }
  }

  /// Удаляет доп. единицу продажи товара (базовую единицу удалить нельзя —
  /// сервер это тоже проверяет). Возвращает null при успехе, иначе — текст
  /// ошибки с сервера.
  Future<String?> deleteProductUnit(int productId, int unitId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/products/$productId/units/$unitId'),
            headers: await _getHeaders(),
          )
          .timeout(const Duration(seconds: 15));
      _handleAuthErrors(response.statusCode);
      if (response.statusCode == 200) return null;
      try {
        final body = jsonDecode(response.body);
        final msg = body['error'] ?? body['message'] ?? body['detail'];
        if (msg != null) return msg.toString();
      } catch (_) {}
      return 'Хатогӣ: ${response.statusCode}';
    } on TimeoutException {
      return 'Вақт тамом шуд. Пайвастшавии интернетро санҷед';
    } catch (e) {
      return 'Хатогии пайвастшавӣ: $e';
    }
  }

  /// Редактирует карточку товара (название, штрихкод, цены, базовую единицу
  /// измерения). НЕ меняет остаток склада — для этого используется
  /// [updateInventory]. Возвращает null при успехе, иначе — текст ошибки.
  Future<String?> updateProduct(
    int id,
    Map<String, dynamic> productData, {
    String? reason,
  }) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/products/$id'),
            headers: await _getHeaders(),
            body: jsonEncode({
              ...productData,
              if (reason != null && reason.isNotEmpty) 'reason': reason,
            }),
          )
          .timeout(const Duration(seconds: 15));
      _handleAuthErrors(response.statusCode);
      if (response.statusCode == 200) return null;
      try {
        final body = jsonDecode(response.body);
        final msg = body['error'] ?? body['message'] ?? body['detail'];
        if (msg != null) return msg.toString();
      } catch (_) {}
      return 'Хатогӣ: ${response.statusCode}';
    } on TimeoutException {
      return 'Вақт тамом шуд. Пайвастшавии интернетро санҷед';
    } catch (e) {
      return 'Хатогии пайвастшавӣ: $e';
    }
  }

  /// [barcode] — штрихкод товара (если есть), нужен ТОЛЬКО чтобы после
  /// успешного обновления сразу освежить его в локальном кэше кассы
  /// (product_cache) — см. комментарий ниже. На сам PATCH-запрос никак
  /// не влияет.
  Future<bool> updateInventory(
    int id,
    double addStock,
    double sellPrice,
    double buyPrice, {
    String? reason,
    String? barcode,
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

      _handleAuthErrors(response.statusCode);

      if (response.statusCode == 200) {
        DataRefreshService.instance.notifyProductChanged();
        DataRefreshService.instance.notifyAnalyticsChanged();
        // Как и в addProduct: ответ сервера здесь — просто {status: ok},
        // без самого товара, поэтому нельзя обновить кэш "по данным
        // ответа". Вместо ожидания плановой синхронизации (до 5 минут)
        // или случайного захода на склад — сразу же дёргаем товар по
        // его штрихкоду (если он есть), тот же метод сам кладёт свежую
        // цену/остаток в product_cache. Без этого кассир мог бы после
        // "экстренной" смены цены прямо во время смены ещё несколько
        // минут продавать по старой цене.
        if (barcode != null && barcode.isNotEmpty) {
          unawaited(getProductByBarcode(barcode));
        }
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

      _handleAuthErrors(response.statusCode);

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

  /// Отправляет чек на сервер и различает, ПОЧЕМУ не получилось:
  /// - [SaleSendStatus.networkError] — реального ответа от сервера не было
  ///   (обрыв связи, таймаут) — имеет смысл повторить позже автоматически.
  /// - [SaleSendStatus.rejected] — сервер ответил, но отклонил чек
  ///   (например 500 "недостаточно товара ID: 12", или 400/409 и т.п.) —
  ///   повторная идентичная отправка даст ту же ошибку, поэтому вызывающий
  ///   код не должен ретраить её молча.
  Future<SaleSendResult> sendSale(Map<String, dynamic> saleData) async {
    http.Response response;
    try {
      response = await http
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
    } catch (e) {
      // Исключение здесь означает, что ответа от сервера не было вообще
      // (DNS/сокет/таймаут) — это настоящий сетевой сбой.
      return const SaleSendResult(SaleSendStatus.networkError);
    }

    _handleAuthErrors(response.statusCode);
    if (response.statusCode == 200) {
      DataRefreshService.instance.notifySaleChanged();
      DataRefreshService.instance.notifyAnalyticsChanged();
      return const SaleSendResult(SaleSendStatus.success);
    }

    // Сервер ответил (пусть и ошибкой) — значит связь есть, и это не
    // сетевая проблема, а осознанный отказ бизнес-логики бэкенда.
    String message = 'Сервер чекро рад кард (код ${response.statusCode})';
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error'] != null) {
        message = body['error'].toString();
      }
    } catch (_) {
      // Тело ответа не JSON — оставляем сообщение по умолчанию.
    }
    return SaleSendResult(SaleSendStatus.rejected, errorMessage: message);
  }

  /// Получает страницу истории продаж.
  /// Онлайн: запрашивает API и точечно освежает офлайн-кэш этой страницей.
  /// Офлайн (или сетевая ошибка): отдаёт весь кэшированный список одной
  /// "страницей", как это уже сделано для товаров в [getProducts].
  Future<PaginatedResult<dynamic>> getSalesPage({
    int page = 1,
    int limit = 50,
  }) async {
    if (ConnectivityService.instance.isOnline) {
      try {
        final uri = Uri.parse(
          '$baseUrl/api/sales',
        ).replace(queryParameters: {'page': '$page', 'limit': '$limit'});
        final response = await http.get(uri, headers: await _getHeaders());
        _handleAuthErrors(response.statusCode);
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final items = (body['data'] as List).cast<Map<String, dynamic>>();
          await _db.upsertCachedSales(items);
          return PaginatedResult(
            data: items,
            total: body['total'] as int,
            page: body['page'] as int,
            limit: body['limit'] as int,
            totalPages: body['total_pages'] as int,
          );
        }
      } catch (_) {
        ConnectivityService.instance.markOffline();
      }
    }

    final cached = await _db.getCachedSales();
    return PaginatedResult(
      data: cached,
      total: cached.length,
      page: 1,
      limit: cached.length,
      totalPages: 1,
    );
  }

  /// Оставляем для обратной совместимости.
  Future<List<dynamic>> getSalesHistory() async {
    final result = await getSalesPage(page: 1, limit: 200);
    return result.data;
  }

  // ─── Аналитика ───────────────────────────────────────────────────────────

  Future<List<dynamic>> getTopProducts({
    int limit = 5,
    String period = 'today',
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final query = _periodQuery(period, from, to);
      final response = await http.get(
        Uri.parse('$baseUrl/api/analytics/top-products?limit=$limit&$query'),
        headers: await _getHeaders(),
      );
      _handleAuthErrors(response.statusCode);
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
      _handleAuthErrors(response.statusCode);
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
      _handleAuthErrors(response.statusCode);
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<dynamic>> getSellerStats({
    String period = 'today',
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final query = _periodQuery(period, from, to);
      final response = await http.get(
        Uri.parse('$baseUrl/api/analytics/sellers?$query'),
        headers: await _getHeaders(),
      );
      _handleAuthErrors(response.statusCode);
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
      _handleAuthErrors(response.statusCode);
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<bool> createUser(String username, String password, String role) async {
    final err = await createUserWithPin(username, password, role);
    return err == null;
  }

  /// Создание сотрудника с опциональным PIN.
  /// Возвращает null при успехе, иначе — текст ошибки с сервера
  /// (например, "В этом магазине уже максимум продавцов (5)...").
  Future<String?> createUserWithPin(
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
        if (shopId != null && shopId != 0) 'shop_id': shopId,
      };
      final response = await http.post(
        Uri.parse('$baseUrl/api/users'),
        headers: await _getHeaders(),
        body: jsonEncode(body),
      );
      _handleAuthErrors(response.statusCode);
      if (response.statusCode == 200) {
        return null; // успех
      }
      try {
        final decoded = jsonDecode(response.body);
        final msg = decoded['error'] ?? decoded['message'] ?? decoded['detail'];
        if (msg != null) return msg.toString();
      } catch (_) {}
      return 'Хатогӣ: ${response.statusCode}';
    } catch (e) {
      return 'Хатогии пайвастшавӣ: $e';
    }
  }

  Future<bool> deleteUser(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/users/$id'),
        headers: await _getHeaders(),
      );
      _handleAuthErrors(response.statusCode);
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
      _handleAuthErrors(response.statusCode);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ─── Терминальный режим ───────────────────────────────────────────────────

  /// Загружает список продавцов для терминала.
  /// Онлайн: API + кэшируем результат.
  /// Офлайн: возвращает кэшированный список из SQLite.
  Future<List<dynamic>> getTerminalUsers(int companyId, {int? shopId}) async {
    if (ConnectivityService.instance.isOnline) {
      try {
        final shopParam = (shopId != null && shopId != 0)
            ? '&shop_id=$shopId'
            : '';
        final response = await http
            .get(
              Uri.parse(
                '$baseUrl/terminal/users?company_id=$companyId$shopParam',
              ),
            )
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
      _handleAuthErrors(response.statusCode);
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
      _handleAuthErrors(response.statusCode);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ─── Вспомогательные ─────────────────────────────────────────────────────

  /// Раньше возвращал bool; теперь возвращает [SaleSendResult], чтобы
  /// вызывающий код (HomeScreen._checkout, _syncOfflineSales) мог отличить
  /// сетевой сбой от отказа сервера и не прятать реальную причину под
  /// общим "нет сети".
  Future<SaleSendResult> createSale(Map<String, dynamic> saleData) async =>
      sendSale(saleData);
  Future<SaleSendResult> createSaleFromRawData(
    Map<String, dynamic> saleData,
  ) async => sendSale(saleData);

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
        _handleAuthErrors(response.statusCode);
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
      _handleAuthErrors(response.statusCode);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Собирает query-параметры периода: либо готовый period=today/week/month,
  /// либо period=custom&from=YYYY-MM-DD&to=YYYY-MM-DD для произвольного диапазона.
  String _periodQuery(String period, DateTime? from, DateTime? to) {
    if (period == 'custom' && from != null && to != null) {
      String d(DateTime x) =>
          '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
      return 'period=custom&from=${d(from)}&to=${d(to)}';
    }
    return 'period=$period';
  }

  Future<Map<String, dynamic>?> getAnalyticsSummary(
    String period, {
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final query = _periodQuery(period, from, to);
      final response = await http.get(
        Uri.parse('$baseUrl/api/analytics/summary?$query'),
        headers: await _getHeaders(),
      );
      _handleAuthErrors(response.statusCode);
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
      _handleAuthErrors(response.statusCode);
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Сохраняет токен и данные выбранного магазина после создания/переключения —
  /// все последующие запросы (товары, продажи, склад, должники, аналитика)
  /// автоматически пойдут в рамках этого магазина, так как shop_id зашит в JWT.
  Future<void> _applyShopSwitch(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final previousShopId = prefs.getInt('shop_id');
    if (data['token'] != null) {
      await prefs.setString('jwt_token', data['token']);
    }
    if (data['shop_id'] != null) {
      await prefs.setInt('shop_id', data['shop_id']);
    }
    final shopName = data['shop']?['name'] ?? data['name'];
    if (shopName != null) {
      await prefs.setString('shop_name', shopName);
    }
    await prefs.setBool('needs_shop_setup', false);

    // Кэш товаров (product_cache) теперь основной путь поиска при
    // сканировании — он привязан к тому магазину, из которого был
    // синхронизирован. При переключении на другой магазин ОБЯЗАТЕЛЬНО
    // чистим его: иначе кассир на новом магазине какое-то время видел
    // бы (и мог продать!) товары и цены из ПРЕДЫДУЩЕГО магазина —
    // до следующей полной синхронизации каталога. Дублирующийся вызов
    // с тем же shop_id (например, повторный switch на текущий магазин)
    // пропускаем — не имеет смысла чистить кэш магазина сам в себя.
    final newShopId = data['shop_id'] as int?;
    if (newShopId != null && newShopId != previousShopId) {
      await _db.clearProductCache();
      // Сразу тянем каталог нового магазина, не дожидаясь ближайшего
      // тика периодической синхронизации (следующие 5 минут) — иначе
      // первые сканы после переключения магазина будут словно "офлайн"
      // (кэш пуст, значит каждый скан уйдёт в сеть, что нормально, но
      // лучше сразу прогреть кэш, раз уж мы точно сейчас онлайн).
      unawaited(refreshOfflineCache());
    }
  }

  /// Создать новый магазин. Он сразу становится активным (владелец получает
  /// новый токен в рамках этого магазина и переключается на него).
  Future<Map<String, dynamic>?> createShop(String name) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/shops'),
        headers: await _getHeaders(),
        body: jsonEncode({'name': name}),
      );
      _handleAuthErrors(response.statusCode);
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await _applyShopSwitch(data);
        return data;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Переключиться на другой уже существующий магазин.
  Future<bool> switchShop(int id) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/shops/$id/switch'),
        headers: await _getHeaders(),
      );
      _handleAuthErrors(response.statusCode);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await _applyShopSwitch(data);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateShop(int id, String name) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/shops/$id'),
        headers: await _getHeaders(),
        body: jsonEncode({'name': name}),
      );
      _handleAuthErrors(response.statusCode);
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
      _handleAuthErrors(response.statusCode);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Получает страницу должников.
  /// Онлайн: запрашивает API и точечно освежает офлайн-кэш этой страницей
  /// (не трогая должников, добавленных офлайн и ещё не синхронизированных).
  /// Офлайн (или сетевая ошибка): отдаёт кэш целиком, включая должников и
  /// суммы долга, ещё не отправленные на сервер (см. createDebtor/debtOperation).
  Future<PaginatedResult<dynamic>> getDebtorsPage({
    int page = 1,
    int limit = 50,
  }) async {
    if (ConnectivityService.instance.isOnline) {
      try {
        final uri = Uri.parse(
          '$baseUrl/api/debtors',
        ).replace(queryParameters: {'page': '$page', 'limit': '$limit'});
        final response = await http.get(uri, headers: await _getHeaders());
        _handleAuthErrors(response.statusCode);
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final items = (body['data'] as List).cast<Map<String, dynamic>>();
          await _db.upsertCachedDebtors(items);
          return PaginatedResult(
            data: items,
            total: body['total'] as int,
            page: body['page'] as int,
            limit: body['limit'] as int,
            totalPages: body['total_pages'] as int,
          );
        }
      } catch (_) {
        ConnectivityService.instance.markOffline();
      }
    }

    final cached = await _db.getCachedDebtors();
    return PaginatedResult(
      data: cached,
      total: cached.length,
      page: 1,
      limit: cached.length,
      totalPages: 1,
    );
  }

  /// Оставляем для обратной совместимости.
  Future<List<dynamic>> getDebtors() async {
    final result = await getDebtorsPage(page: 1, limit: 200);
    return result.data;
  }

  /// Создаёт нового должника.
  /// Онлайн: обычный запрос к серверу.
  /// Сетевая ошибка (нет соединения/таймаут): должник ставится в офлайн-
  /// очередь ([DatabaseHelper.insertOfflineDebtorOp]) и сразу появляется в
  /// локальном кэше с временным (отрицательным) id, помеченным как
  /// ожидающий синхронизации — так UI ведёт себя одинаково и офлайн, и
  /// онлайн (result != null ⇒ "успех", как и раньше).
  Future<Map<String, dynamic>?> createDebtor({
    required String fullName,
    String phone = '',
    double initialDebt = 0,
    String note = '',
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/debtors'),
            headers: await _getHeaders(),
            body: jsonEncode({
              'full_name': fullName,
              'phone': phone,
              'initial_debt': initialDebt,
              'note': note,
            }),
          )
          .timeout(const Duration(seconds: 8));
      _handleAuthErrors(response.statusCode);
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await _db.upsertCachedDebtors([data]);
        return data;
      }
      // Сервер ответил, но отклонил запрос (валидация/дубликат и т.п.) —
      // реальная ошибка, повторять её офлайн-очередью бессмысленно.
      return null;
    } catch (e) {
      // Ответа от сервера не было вообще — реальный сетевой сбой.
      ConnectivityService.instance.markOffline();
    }

    final tempId = -DateTime.now().millisecondsSinceEpoch;
    final localDebtor = <String, dynamic>{
      'id': tempId,
      'company_id': 0,
      'shop_id': 0,
      'full_name': fullName,
      'phone': phone,
      'total_debt': initialDebt,
      'updated_at': DateTime.now().toIso8601String(),
    };
    await _db.insertLocalDebtor(localDebtor);
    await _db.insertOfflineDebtorOp('create', {
      'full_name': fullName,
      'phone': phone,
      'initial_debt': initialDebt,
      'note': note,
    }, localDebtorId: tempId);
    return localDebtor;
  }

  /// type: 'pay' — внёс деньги, 'take' — добавить долг
  ///
  /// Онлайн: обычный запрос к серверу.
  /// Сетевая ошибка: операция ставится в офлайн-очередь и сразу применяется
  /// к закэшированной сумме долга (оптимистично), чтобы список должников
  /// офлайн показывал актуальную сумму без ожидания синхронизации.
  /// Операции над должником, который сам ещё не синхронизирован (временный
  /// отрицательный id), в офлайне не принимаются — сервер о таком должнике
  /// пока не знает, и порядок операций мог бы разъехаться.
  Future<Map<String, dynamic>?> debtOperation(
    int debtorId, {
    required double amount,
    required String type,
    String note = '',
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/debtors/$debtorId/operation'),
            headers: await _getHeaders(),
            body: jsonEncode({'amount': amount, 'type': type, 'note': note}),
          )
          .timeout(const Duration(seconds: 8));
      _handleAuthErrors(response.statusCode);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await _db.upsertCachedDebtors([data]);
        return data;
      }
      return null;
    } catch (e) {
      ConnectivityService.instance.markOffline();
    }

    if (debtorId < 0) {
      // Должник сам ещё не синхронизирован — операцию над ним пока
      // отложить нельзя, т.к. сервер о нём не знает.
      return null;
    }

    await _db.applyLocalDebtOperation(debtorId, amount, type);
    final payload = {
      'debtor_id': debtorId,
      'amount': amount,
      'type': type,
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
    };
    await _db.insertOfflineDebtorOp(
      'operation',
      payload,
      localDebtorId: debtorId,
    );
    _pendingOpsSnapshot.add(payload);
    return payload;
  }

  /// Удаляет товар (soft delete на бэкенде — is_active = false).
  /// Разрешено только владельцу магазина; сервер сам проверяет роль
  /// (403, если вызвал продавец) — здесь достаточно передать результат.
  /// Как и другие "владельческие" операции (deleteUser/deleteShop/
  /// deleteDebtor), в офлайн-очередь не ставится: удаление — редкое
  /// действие, требующее подтверждения от сервера, а не то, что
  /// нужно применять оптимистично при отсутствии сети.
  ///
  Future<bool> deleteProduct(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/products/$id'),
        headers: await _getHeaders(),
      );
      _handleAuthErrors(response.statusCode);
      if (response.statusCode == 200) {
        await _db.removeCachedProduct(id);
        DataRefreshService.instance.notifyProductChanged();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteDebtor(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/debtors/$id'),
        headers: await _getHeaders(),
      );
      _handleAuthErrors(response.statusCode);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<List<dynamic>> getDebtHistory(int debtorId) async {
    if (ConnectivityService.instance.isOnline) {
      try {
        final response = await http
            .get(
              Uri.parse('$baseUrl/api/debtors/$debtorId/history'),
              headers: await _getHeaders(),
            )
            .timeout(const Duration(seconds: 10));
        _handleAuthErrors(response.statusCode);
        if (response.statusCode == 200) {
          final items = (jsonDecode(response.body) as List)
              .cast<Map<String, dynamic>>();
          await _db.cacheDebtHistory(debtorId, items);
          return [...items, ..._pendingHistoryEntries(debtorId)];
        }
      } catch (_) {
        ConnectivityService.instance.markOffline();
      }
    }

    final cached = await _db.getCachedDebtHistory(debtorId);
    return [..._pendingHistoryEntries(debtorId), ...cached];
  }

  /// Синтетические записи истории для ещё не отправленных на сервер
  /// операций с этим должником — чтобы пользователь сразу видел их в
  /// истории (с пометкой "офлайн"), не дожидаясь синхронизации.
  /// Заполняется синхронно из in-memory снимка очереди — см. [_pendingOpsSnapshot].
  List<Map<String, dynamic>> _pendingHistoryEntries(int debtorId) {
    return _pendingOpsSnapshot
        .where((op) => op['debtor_id'] == debtorId)
        .map(
          (op) => {
            'id': -1,
            'debtor_id': debtorId,
            'amount': op['amount'],
            'type': op['type'],
            'note': '${op['note'] ?? ''} (офлайн, дар навбати ирсол)'.trim(),
            'created_at': op['created_at'],
          },
        )
        .toList();
  }

  /// Снимок ожидающих отправки операций по должникам, обновляется при
  /// каждом успешном/неудачном вызове createDebtor/debtOperation, чтобы
  /// [getDebtHistory] мог синхронно (без похода в БД) показать их в
  /// истории. Живёт только в памяти текущей сессии приложения.
  final List<Map<String, dynamic>> _pendingOpsSnapshot = [];

  /// Отправляет на сервер все накопленные офлайн операции с должниками
  /// (создание должника, оплата/добавление долга). Вызывается из
  /// [SyncService] при восстановлении связи — аналог _syncOfflineSales
  /// для чеков. Порядок отправки — по времени постановки в очередь, чтобы
  /// операция над только что созданным офлайн должником ушла уже после
  /// того, как сам должник появился на сервере.
  Future<void> syncOfflineDebtorOps() async {
    final ops = await _db.getUnsyncedDebtorOps();
    if (ops.isEmpty) return;

    for (final row in ops) {
      if (!ConnectivityService.instance.isOnline) break;

      final id = row['id'] as int;
      final opType = row['op_type'] as String;
      final payload =
          jsonDecode(row['payload'] as String) as Map<String, dynamic>;

      try {
        if (opType == 'create') {
          final response = await http
              .post(
                Uri.parse('$baseUrl/api/debtors'),
                headers: await _getHeaders(),
                body: jsonEncode(payload),
              )
              .timeout(const Duration(seconds: 15));
          if (response.statusCode == 201) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final tempId = row['local_debtor_id'] as int?;
            if (tempId != null) await _db.removeLocalDebtor(tempId);
            await _db.upsertCachedDebtors([data]);
            await _db.markDebtorOpSynced(id);
          } else {
            // Сервер ответил и отклонил (например, дубликат имени/телефона,
            // появившийся, пока мы были офлайн) — не ретраим бесконечно.
            String message = 'Сервер рад кард (${response.statusCode})';
            try {
              final body = jsonDecode(response.body);
              if (body is Map && body['error'] != null) {
                message = body['error'].toString();
              }
            } catch (_) {}
            await _db.markDebtorOpFailed(id, message);
          }
        } else if (opType == 'operation') {
          final debtorId = payload['debtor_id'] as int;
          final response = await http
              .post(
                Uri.parse('$baseUrl/api/debtors/$debtorId/operation'),
                headers: await _getHeaders(),
                body: jsonEncode({
                  'amount': payload['amount'],
                  'type': payload['type'],
                  'note': payload['note'] ?? '',
                }),
              )
              .timeout(const Duration(seconds: 15));
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            await _db.upsertCachedDebtors([data]);
            await _db.markDebtorOpSynced(id);
            _pendingOpsSnapshot.removeWhere(
              (op) =>
                  op['debtor_id'] == payload['debtor_id'] &&
                  op['created_at'] == payload['created_at'],
            );
          } else {
            String message = 'Сервер рад кард (${response.statusCode})';
            try {
              final body = jsonDecode(response.body);
              if (body is Map && body['error'] != null) {
                message = body['error'].toString();
              }
            } catch (_) {}
            await _db.markDebtorOpFailed(id, message);
          }
        }
      } catch (_) {
        // Сетевая ошибка посреди отправки очереди — оставляем 'pending',
        // попробуем снова при следующем восстановлении связи.
        ConnectivityService.instance.markOffline();
        break;
      }
    }

    await _db.cleanupSyncedDebtorOps();
  }
}
