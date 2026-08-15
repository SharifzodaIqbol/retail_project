import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/rate_limit_banner.dart';
import 'register_screen.dart';

// ─── Цвета бренда (общие для всего приложения) ──────────────────────────────
const _kPrimary = Color(0xFF4F6EF7);
const _kPrimaryDeep = Color(0xFF6C4FF7);
const _kInk = Color(0xFF1A1A2E);
const _kBg = Color(0xFFF5F7FA);

class LoginScreen extends StatefulWidget {
  // Добавляем обязательный параметр onLogin, который требует main.dart
  final Function(String role) onLogin;
  // Необязательное сообщение, которое показывается баннером над формой —
  // используется, когда на этот экран вернули принудительно (истекла
  // сессия из-за протухшего JWT-токена, см. ApiService._handleAuthErrors),
  // а не потому что продавец сам нажал "выйти". Без этого продавец видел
  // бы просто пустой экран входа и не понимал, почему его вдруг сюда
  // вернуло посреди работы.
  final String? sessionMessage;

  const LoginScreen({Key? key, required this.onLogin, this.sessionMessage})
    : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

// Ограничения на ввод — просто здравые границы, чтобы поле не принимало
// бесконечную строку (вставка мегабайта текста, флуд по буферу и т.д.).
// Реальная валидация формата всё равно на бэкенде.
const int _kMaxUsernameLength = 50;
const int _kMinUsernameLength = 3;
const int _kMaxPasswordLength = 72; // bcrypt всё равно обрезает после 72 байт

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;

  // Заполняется, когда backend возвращает 429 — отображаем баннер с
  // обратным отсчётом и блокируем форму до истечения этого времени.
  int? _rateLimitSeconds;
  String _rateLimitMessage = '';

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (_isLoading || isRateLimited(_rateLimitSeconds)) return;

    // Не даём даже дойти до сети с пустыми/слишком длинными полями —
    // это чисто клиентская проверка ввода, не про сеть.
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    Map<String, dynamic>? success;
    try {
      success = await _authService.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );
    } on RateLimitException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _rateLimitSeconds = e.retryAfterSeconds;
        _rateLimitMessage = e.message;
      });
      return;
    } on NetworkException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(e.message);
      return;
    } on ServerException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(e.message);
      return;
    }

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    // 1. Проверяем, что сервер вообще что-то вернул (Map не null)
    // 2. И проверяем, что внутри этой мапы есть ключ 'role'
    if (success != null &&
        success.containsKey('role') &&
        success['role'] != null) {
      // Достаем роль из мапы и приводим к строке
      final String userRole = success['role'].toString();

      // Передаем строковую роль в main.dart
      widget.onLogin(userRole);
    } else {
      // Сюда попадаем только когда сервер реально ответил "неверный
      // логин или пароль" (см. AuthService.login) — сетевые и
      // серверные ошибки обработаны отдельно выше.
      _showError('Логин ё рамз нодуруст аст!');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFE74C3C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                // ClampingScrollPhysics вместо BouncingScrollPhysics: без
                // iOS-эффекта "резинки", из-за которого весь экран уезжал
                // вниз при потягивании, даже когда контент и так помещается.
                physics: const ClampingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        _BrandHeader(),
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(28),
                              ),
                            ),
                            transform: Matrix4.translationValues(0, -20, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Хуш омадед!',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: _kInk,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Шумо метавонед ба аккаунти худ ворид шавед.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                if (widget.sessionMessage != null) ...[
                                  const SizedBox(height: 16),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF4E5),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFFFFD8A8),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.info_outline_rounded,
                                          color: Color(0xFFB8730A),
                                          size: 20,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            widget.sessionMessage!,
                                            style: const TextStyle(
                                              color: Color(0xFFB8730A),
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 28),

                                _FieldLabel('Логин'),
                                const SizedBox(height: 8),
                                _AuthTextField(
                                  controller: _usernameController,
                                  enabled:
                                      !_isLoading &&
                                      !isRateLimited(_rateLimitSeconds),
                                  hint: 'Логинатонро ворид кунед',
                                  icon: Icons.person_outline,
                                  textInputAction: TextInputAction.next,
                                  maxLength: _kMaxUsernameLength,
                                  validator: (v) {
                                    final value = v?.trim() ?? '';
                                    if (value.isEmpty) {
                                      return 'Логинро ворид кунед';
                                    }
                                    if (value.length < _kMinUsernameLength) {
                                      return 'Логин бояд ками-кам аз $_kMinUsernameLength аломат иборат бошад';
                                    }
                                    if (value.length > _kMaxUsernameLength) {
                                      return 'Логин аз $_kMaxUsernameLength аломат зиёд аст';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 18),

                                _FieldLabel('Рамз'),
                                const SizedBox(height: 8),
                                _AuthTextField(
                                  controller: _passwordController,
                                  enabled:
                                      !_isLoading &&
                                      !isRateLimited(_rateLimitSeconds),
                                  hint: 'Рамзатонро ворид кунед',
                                  icon: Icons.lock_outline,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _handleLogin(),
                                  maxLength: _kMaxPasswordLength,
                                  validator: (v) {
                                    final value = v ?? '';
                                    if (value.isEmpty) {
                                      return 'Рамзро ворид кунед';
                                    }
                                    if (value.length > _kMaxPasswordLength) {
                                      return 'Рамз аз $_kMaxPasswordLength аломат зиёд аст';
                                    }
                                    return null;
                                  },
                                  suffix: IconButton(
                                    splashRadius: 20,
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: Colors.grey[500],
                                      size: 20,
                                    ),
                                    onPressed: () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                  ),
                                ),

                                if (_rateLimitSeconds != null) ...[
                                  RateLimitBanner(
                                    initialSeconds: _rateLimitSeconds!,
                                    message: _rateLimitMessage,
                                    onExpired: () {
                                      if (!mounted) return;
                                      setState(() => _rateLimitSeconds = null);
                                    },
                                  ),
                                  const SizedBox(height: 18),
                                ],

                                const SizedBox(height: 28),
                                SizedBox(
                                  height: 54,
                                  child: ElevatedButton(
                                    onPressed:
                                        (_isLoading ||
                                            isRateLimited(_rateLimitSeconds))
                                        ? null
                                        : _handleLogin,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _kPrimary,
                                      disabledBackgroundColor: _kPrimary
                                          .withOpacity(0.5),
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(
                                            height: 22,
                                            width: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.4,
                                              valueColor:
                                                  AlwaysStoppedAnimation(
                                                    Colors.white,
                                                  ),
                                            ),
                                          )
                                        : const Text(
                                            'Дохил',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                  ),
                                ),

                                const Spacer(),
                                const SizedBox(height: 16),
                                Center(
                                  child: TextButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const RegisterScreen(),
                                        ),
                                      );
                                    },
                                    style: TextButton.styleFrom(
                                      foregroundColor: _kPrimary,
                                    ),
                                    child: RichText(
                                      text: const TextSpan(
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          color: Colors.grey,
                                        ),
                                        children: [
                                          TextSpan(text: 'Ширкати нав?'),
                                          TextSpan(
                                            text: ' Бақайдгирии 14 рӯз ройгон',
                                            style: TextStyle(
                                              color: _kPrimary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─── Фирменная "шапка" с градиентом и штрихкод-узором ───────────────────────
// Сигнатурный элемент экранов входа/регистрации: узор из полос разной
// толщины как у штрихкода — прямая отсылка к кассовому/розничному приложению.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 56),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kPrimary, _kPrimaryDeep],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -10,
            right: -20,
            child: Opacity(
              opacity: 0.18,
              child: _BarcodeStripe(height: 90, barCount: 22),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  'assets/images/savidor.png', // <-- ОБЯЗАТЕЛЬНО замените на PNG или SVG
                  // Если логотип квадратный, используйте cover, чтобы он заполнил всё место
                  fit: BoxFit.cover,
                  // Можно явно указать размеры, чтобы Flutter не гадал:
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Савдо + Идора = Савидор',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Касса ва анбор дар як ҷо',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Декоративный узор из вертикальных полос переменной ширины,
/// напоминающий штрихкод. Используется как фирменный знак на экранах входа.
class _BarcodeStripe extends StatelessWidget {
  final double height;
  final int barCount;

  const _BarcodeStripe({required this.height, required this.barCount});

  // Детерминированный псевдо-узор (без Random — чтобы выглядел стабильно).
  static const List<double> _widths = [
    2,
    5,
    2,
    8,
    3,
    2,
    6,
    2,
    4,
    2,
    9,
    2,
    3,
    5,
    2,
    7,
    2,
    4,
    2,
    6,
    3,
    2,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(barCount, (i) {
          final w = _widths[i % _widths.length];
          return Container(
            width: w,
            height: height,
            margin: const EdgeInsets.only(left: 3),
            color: Colors.white,
          );
        }),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: _kInk,
      ),
    );
  }
}

/// Единый стиль текстовых полей для форм входа/регистрации.
class _AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool enabled;
  final bool obscureText;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final int? maxLength;

  const _AuthTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.enabled = true,
    this.obscureText = false,
    this.textInputAction,
    this.onSubmitted,
    this.suffix,
    this.validator,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    final field = TextFormField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      maxLength: maxLength,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      style: const TextStyle(fontSize: 15, color: _kInk),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14.5),
        prefixIcon: Icon(icon, color: Colors.grey[500], size: 21),
        suffixIcon: suffix,
        counterText: '', // прячем счётчик символов "0/50" под полем
        filled: true,
        fillColor: _kBg,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _kPrimary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE74C3C), width: 1.4),
        ),
      ),
    );
    return field;
  }
}
