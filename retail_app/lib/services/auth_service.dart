import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class AuthService {
  Future<Map<String, dynamic>?> login(
    String username,
    String password,
  ) async {
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
