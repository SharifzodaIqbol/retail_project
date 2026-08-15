import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retail_app/helpers/device_info_helper.dart';
import 'api_service.dart';

/// Бросается, когда запрос вообще не дошёл до сервера (нет интернета,
/// сервер недоступен, таймаут). Отдельно от "неверный логин/пароль",
/// чтобы экран входа мог показать пользователю понятное сообщение
/// ("нет соединения"), а не пугать его тем, будто он ошибся в пароле.
class NetworkException implements Exception {
  final String message;
  const NetworkException([
    this.message = 'Пайваст ба интернет нест. Пайвасти худро санҷед.',
  ]);

  @override
  String toString() => message;
}

/// Бросается, когда сервер ответил, но не так, как ожидалось (5xx или
/// незнакомый код) — это не вина пользователя и не "неверный пароль".
class ServerException implements Exception {
  final int statusCode;
  final String message;
  const ServerException(
    this.statusCode, [
    this.message = 'Хатои сервер. Лутфан баъдтар аз нав кӯшиш кунед.',
  ]);

  @override
  String toString() => message;
}

class AuthService {
  /// Возвращает данные пользователя при успешном входе, `null` — если
  /// сервер явно отверг логин/пароль (401), и бросает исключение во
  /// всех остальных случаях (нет сети, таймаут, 429, 5xx), чтобы
  /// вызывающий код мог показать точную причину, а не общее
  /// "неверный логин или пароль".
  Future<Map<String, dynamic>?> login(String username, String password) async {
    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/login'),
            body: jsonEncode({'username': username, 'password': password}),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const NetworkException(
        'Сервер ҷавоб намедиҳад. Пайвасти интернети худро санҷед.',
      );
    } catch (e) {
      // Нет сети / DNS / сокет закрыт и т.д. — не считаем это неудачной
      // попыткой входа, а сообщаем пользователю реальную причину.
      throw const NetworkException();
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jwt_token', data['token']);

      if (data['refresh_token'] != null) {
        await prefs.setString('refresh_token', data['refresh_token']);
      }
      await prefs.setString('user_role', data['role']);
      await prefs.setString('username', data['username'] ?? username);
      await prefs.setInt('company_id', data['company_id'] ?? 0);
      await prefs.setString('company_name', data['company_name'] ?? '');
      await prefs.setInt('shop_id', data['shop_id'] ?? 0);
      await prefs.setString('shop_name', data['shop_name'] ?? '');
      await prefs.setBool(
        'needs_shop_setup',
        data['needs_shop_setup'] ?? false,
      );
      return data;
    }

    if (response.statusCode == 429) {
      final data = jsonDecode(response.body);
      throw RateLimitException(
        (data['retry_after_seconds'] as num?)?.toInt() ?? 60,
        (data['message'] as String?) ??
            'Кӯшишҳои аз ҳад зиёд. Баъдтар дубора кӯшиш кунед.',
      );
    }

    // 401/400 — сервер реально проверил логин/пароль и отверг их. Это
    // единственный случай, когда честно вернуть "неверный логин или
    // пароль".
    if (response.statusCode == 401 || response.statusCode == 400) {
      return null;
    }

    // Любой другой код (5xx, неожиданный ответ) — это не ошибка ввода
    // пользователя, а проблема сервера, и должна показываться отдельно.
    throw ServerException(response.statusCode);
  }

  // Регистрация компании.
  // Бросает [NetworkException] при отсутствии сети/таймауте и
  // [ServerException] при 5xx — вызывающий код показывает точную
  // причину вместо общего "логин занят".
  Future<bool> register(
    String companyName,
    String username,
    String password,
  ) async {
    http.Response response;
    try {
      final deviceId = await DeviceInfoHelper.getDeviceId();
      final url = '${ApiService.baseUrl}/register';

      final Map<String, String> requestBody = {
        'company_name': companyName,
        'username': username,
        'password': password,
        'device_id': deviceId,
      };

      response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(requestBody),
          )
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const NetworkException(
        'Сервер ҷавоб намедиҳад. Пайвасти интернети худро санҷед.',
      );
    } catch (e) {
      throw const NetworkException();
    }

    if (response.statusCode == 201) {
      return true;
    }

    // 400/409 — сервер реально проверил данные (например, логин занят).
    // Это законный "отказ", не сетевая проблема.
    if (response.statusCode == 400 || response.statusCode == 409) {
      return false;
    }

    // Всё остальное (5xx и т.п.) — проблема сервера, не пользователя.
    throw ServerException(response.statusCode);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refresh_token');

    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await http
            .post(
              Uri.parse('${ApiService.baseUrl}/logout'),
              body: jsonEncode({'refresh_token': refreshToken}),
              headers: {'Content-Type': 'application/json'},
            )
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        // Нет сети/таймаут — не блокируем локальный выход.
      }
    }

    await prefs.remove('jwt_token');
    await prefs.remove('refresh_token');
    await prefs.remove('user_role');
    await prefs.remove('username');
    await prefs.remove('company_id');
    await prefs.remove('company_name');
    await prefs.remove('shop_id');
    await prefs.remove('shop_name');
    await prefs.remove('needs_shop_setup');
    await prefs.remove('terminal_mode');
    await prefs.remove('offline_session_active');
  }

  Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_role');
  }

  Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('username');
  }
}
