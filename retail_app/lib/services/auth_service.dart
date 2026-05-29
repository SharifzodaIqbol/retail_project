import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:retail_app/device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class AuthService {
  // Существующий метод login остается без изменений...
  Future<Map<String, dynamic>?> login(String username, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/login'),
            body: jsonEncode({'username': username, 'password': password}),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', data['token']);
        await prefs.setString('user_role', data['role']);
        await prefs.setString('username', data['username'] ?? username);
        return data;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Регистрация компании
  Future<bool> register(
    String companyName,
    String username,
    String password,
  ) async {
    try {
      final deviceId = await DeviceService.getDeviceId();
      final url = '${ApiService.baseUrl}/register';

      final Map<String, String> requestBody = {
        'company_name': companyName,
        'username': username,
        'password': password,
        'device_id': deviceId,
      };

      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(requestBody),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 201) {
        return true;
      } else {
        // Если опять 400, мы увидим, что именно пришло в ответ
        print(
          "Бэкенд отклонил запрос: ${response.statusCode} -> ${response.body}",
        );
        return false;
      }
    } catch (e) {
      print("Критическая ошибка отправки: $e");
      return false;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('user_role');
    await prefs.remove('username');
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
