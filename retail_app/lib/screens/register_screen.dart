import 'package:flutter/material.dart';
import '../services/auth_service.dart';

// ─── Цвета бренда (те же, что в login_screen.dart) ──────────────────────────
const _kPrimary = Color(0xFF4F6EF7);
const _kPrimaryDeep = Color(0xFF6C4FF7);
const _kInk = Color(0xFF1A1A2E);
const _kBg = Color(0xFFF5F7FA);

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _companyController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _companyController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final success = await _authService.register(
      _companyController.text.trim(),
      _usernameController.text.trim(),
      _passwordController.text,
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF27AE60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          content: const Text('Бизнес зарегистрирован! Войдите.'),
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFE74C3C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          content: const Text('Ошибка регистрации. Возможно, логин занят.'),
        ),
      );
    }
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
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        _RegisterHeader(),
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
                                  'Создать аккаунт',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: _kInk,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '14 дней бесплатно — без привязки карты',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 28),

                                // ── Шаг 1 ──────────────────────────────
                                _StepLabel(
                                  number: '1',
                                  text: 'О вашем бизнесе',
                                ),
                                const SizedBox(height: 12),
                                _AuthTextField(
                                  controller: _companyController,
                                  hint: 'Название магазина или компании',
                                  icon: Icons.storefront_outlined,
                                  textInputAction: TextInputAction.next,
                                  validator: (v) => v!.trim().isEmpty
                                      ? 'Введите название'
                                      : null,
                                ),

                                const SizedBox(height: 24),

                                // ── Шаг 2 ──────────────────────────────
                                _StepLabel(
                                  number: '2',
                                  text: 'Данные для входа',
                                ),
                                const SizedBox(height: 12),
                                _AuthTextField(
                                  controller: _usernameController,
                                  hint: 'Логин администратора',
                                  icon: Icons.person_outline,
                                  textInputAction: TextInputAction.next,
                                  validator: (v) => v!.trim().isEmpty
                                      ? 'Введите логин'
                                      : null,
                                ),
                                const SizedBox(height: 14),
                                _AuthTextField(
                                  controller: _passwordController,
                                  hint: 'Пароль (от 6 символов)',
                                  icon: Icons.lock_outline,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _handleRegister(),
                                  validator: (v) => v!.length < 6
                                      ? 'Минимум 6 символов'
                                      : null,
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

                                const SizedBox(height: 28),
                                SizedBox(
                                  height: 54,
                                  child: ElevatedButton(
                                    onPressed: _isLoading
                                        ? null
                                        : _handleRegister,
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
                                            'Зарегистрировать бизнес',
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
                                    onPressed: () => Navigator.pop(context),
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
                                          TextSpan(text: 'Уже есть аккаунт? '),
                                          TextSpan(
                                            text: 'Войти',
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

// ─── Шапка с тем же стилем, но с другим акцентом ────────────────────────────
class _RegisterHeader extends StatelessWidget {
  const _RegisterHeader();

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
                child: const Icon(
                  Icons.store_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Retail POS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Зарегистрируйте свой магазин',
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

class _BarcodeStripe extends StatelessWidget {
  final double height;
  final int barCount;

  const _BarcodeStripe({required this.height, required this.barCount});

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

// ─── Нумерованный заголовок шага ─────────────────────────────────────────────
class _StepLabel extends StatelessWidget {
  final String number;
  final String text;

  const _StepLabel({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _kPrimary.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: _kPrimary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: _kInk,
          ),
        ),
      ],
    );
  }
}

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
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      style: const TextStyle(fontSize: 15, color: _kInk),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14.5),
        prefixIcon: Icon(icon, color: Colors.grey[500], size: 21),
        suffixIcon: suffix,
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
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE74C3C), width: 1.4),
        ),
      ),
    );
  }
}
