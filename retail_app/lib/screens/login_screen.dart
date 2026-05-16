import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  // Добавляем обязательный параметр onLogin, который требует main.dart
  final Function(String role) onLogin;

  const LoginScreen({Key? key, required this.onLogin}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

void _handleLogin() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    // Теперь мы знаем, что success — это Map<String, dynamic>? (или null при ошибке)
    final success = await _authService.login(
      _usernameController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    // 1. Проверяем, что сервер вообще что-то вернул (Map не null)
    // 2. И проверяем, что внутри этой мапы есть ключ 'role'
    if (success != null && success.containsKey('role') && success['role'] != null) {
      
      // Достаем роль из мапы и приводим к строке
      final String userRole = success['role'].toString();
      
      // Передаем строковую роль в main.dart
      widget.onLogin(userRole); 
      
    } else {
      // Если success == null или в нем нет роли, показываем ошибку
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка: неверный логин или пароль')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Retail POS',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 30),
              TextField(
                controller: _usernameController,
                enabled: !_isLoading,
                decoration: const InputDecoration(
                  labelText: 'Логин',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _passwordController,
                obscureText: true,
                enabled: !_isLoading,
                decoration: const InputDecoration(
                  labelText: 'Пароль',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _handleLogin(),
              ),
              const SizedBox(height: 25),
              ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: _isLoading 
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Войти'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}