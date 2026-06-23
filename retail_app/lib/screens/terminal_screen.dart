import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../widgets/rate_limit_banner.dart';

/// Экран терминального режима.
/// Показывается когда terminal_mode=true и пользователь не залогинен.
/// Продавцы входят по PIN. Хозяин может вернуться в свою учётку через долгое нажатие.
class TerminalScreen extends StatefulWidget {
  final int companyId;
  final String companyName;

  /// Продавец успешно вошёл по PIN
  final void Function(String token, String role, String username) onSellerLogin;

  /// Хозяин вышел из терминального режима (уже авторизован)
  final VoidCallback onOwnerExitTerminal;

  const TerminalScreen({
    super.key,
    required this.companyId,
    required this.companyName,
    required this.onSellerLogin,
    required this.onOwnerExitTerminal,
  });

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final _api = ApiService();
  List<dynamic> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    final users = await _api.getTerminalUsers(widget.companyId);
    setState(() {
      _users = users; // бэкенд уже фильтрует только seller'ов с PIN
      _loading = false;
    });
  }

  void _selectUser(Map<String, dynamic> user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PinInputSheet(
        userName: user['username'],
        userId: user['id'],
        companyId: widget.companyId,
        onSuccess: (token, role, username) async {
          if (!mounted) return;
          Navigator.of(context).pop(); // закрыть sheet
          widget.onSellerLogin(token, role, username);
        },
      ),
    );
  }

  /// Хозяин хочет вернуться в свой аккаунт — вводит логин/пароль
  Future<void> _exitToOwner() async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) => _OwnerPasswordDialog(),
    );

    if (result != null) {
      // Сохраняем данные owner'а и выходим из терминала
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jwt_token', result['token']);
      await prefs.setString('user_role', result['role']);
      await prefs.setString('username', result['username']);
      await prefs.setBool('terminal_mode', false);
      widget.onOwnerExitTerminal();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1F36),
      body: SafeArea(
        child: Column(
          children: [
            // Заголовок
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Режим терминала',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.companyName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  // Кнопка выхода для хозяина (долгое нажатие)
                  GestureDetector(
                    onLongPress: _exitToOwner,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.lock_outline,
                            color: Colors.white54,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Удерж. для выхода',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            const Text(
              'Выберите своё имя',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Затем введите PIN-код',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),

            const SizedBox(height: 32),

            // Список продавцов
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white54),
                    )
                  : _users.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Нет сотрудников с PIN-кодом.\nПопросите владельца добавить продавца с PIN.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white54),
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: _loadUsers,
                            child: const Text(
                              'Обновить',
                              style: TextStyle(color: Colors.white38),
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadUsers,
                      child: GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 16,
                              childAspectRatio: 1.3,
                            ),
                        itemCount: _users.length,
                        itemBuilder: (context, i) {
                          final u = _users[i];
                          return _UserCard(
                            username: u['username'],
                            role: u['role'],
                            onTap: () => _selectUser(u),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final String username;
  final String role;
  final VoidCallback onTap;

  const _UserCard({
    required this.username,
    required this.role,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF252B45),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: const Color(0xFF4F6EF7).withOpacity(0.2),
              child: Text(
                username.isNotEmpty ? username[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4F6EF7),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              username,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            const Text(
              'Продавец',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Нижний лист с PIN-клавиатурой
class _PinInputSheet extends StatefulWidget {
  final String userName;
  final int userId;
  final int companyId;
  final void Function(String token, String role, String username) onSuccess;

  const _PinInputSheet({
    required this.userName,
    required this.userId,
    required this.companyId,
    required this.onSuccess,
  });

  @override
  State<_PinInputSheet> createState() => _PinInputSheetState();
}

class _PinInputSheetState extends State<_PinInputSheet> {
  final _api = ApiService();
  String _pin = '';
  bool _loading = false;
  String? _error;

  // Заполняется при 429 от backend — баннер с обратным отсчётом и
  // блокировка клавиатуры до истечения этого времени.
  int? _rateLimitSeconds;
  String _rateLimitMessage = '';

  void _onKey(String digit) {
    if (isRateLimited(_rateLimitSeconds)) return;
    if (_pin.length >= 4) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length == 4) _submit();
  }

  void _onBackspace() {
    if (isRateLimited(_rateLimitSeconds)) return;
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final result = await _api.pinLogin(widget.userId, widget.companyId, _pin);
      if (!mounted) return;
      if (result != null) {
        widget.onSuccess(result['token'], result['role'], result['username']);
      } else {
        setState(() {
          _error = 'Неверный PIN';
          _pin = '';
          _loading = false;
        });
      }
    } on RateLimitException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _pin = '';
        _error = null;
        _rateLimitSeconds = e.retryAfterSeconds;
        _rateLimitMessage = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1F36),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          Text(
            widget.userName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Введите PIN-код',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),

          const SizedBox(height: 24),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) {
              final filled = i < _pin.length;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _error != null
                      ? Colors.red
                      : filled
                      ? const Color(0xFF4F6EF7)
                      : Colors.white24,
                ),
              );
            }),
          ),

          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ],

          if (_rateLimitSeconds != null) ...[
            const SizedBox(height: 16),
            RateLimitBanner(
              initialSeconds: _rateLimitSeconds!,
              message: _rateLimitMessage,
              onExpired: () {
                if (!mounted) return;
                setState(() => _rateLimitSeconds = null);
              },
            ),
          ],

          const SizedBox(height: 28),

          if (_loading)
            const CircularProgressIndicator(color: Color(0xFF4F6EF7))
          else if (isRateLimited(_rateLimitSeconds))
            Opacity(opacity: 0.35, child: _buildKeypad())
          else
            _buildKeypad(),
        ],
      ),
    );
  }

  Widget _buildKeypad() {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.6,
      ),
      itemCount: keys.length,
      itemBuilder: (_, i) {
        final key = keys[i];
        if (key.isEmpty) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => key == '⌫' ? _onBackspace() : _onKey(key),
          child: Container(
            decoration: BoxDecoration(
              color: key == '⌫' ? Colors.white10 : const Color(0xFF252B45),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              key,
              style: TextStyle(
                color: key == '⌫' ? Colors.white54 : Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Диалог для выхода хозяина из терминального режима.
/// Возвращает Map с token/role/username при успехе, null при отмене.
class _OwnerPasswordDialog extends StatefulWidget {
  const _OwnerPasswordDialog();

  @override
  State<_OwnerPasswordDialog> createState() => _OwnerPasswordDialogState();
}

class _OwnerPasswordDialogState extends State<_OwnerPasswordDialog> {
  final _api = ApiService();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _confirm() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _api.ownerLogin(
      _usernameCtrl.text.trim(),
      _passwordCtrl.text,
    );
    if (!mounted) return;
    if (result != null && result['role'] == 'owner') {
      Navigator.pop(context, result); // возвращаем данные owner'а
    } else {
      setState(() {
        _error = 'Неверный логин или пароль';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E2235),
      title: const Text(
        'Выход из терминала',
        style: TextStyle(color: Colors.white),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Введите данные владельца',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _usernameCtrl,
            style: const TextStyle(color: Colors.white),
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Логин',
              labelStyle: TextStyle(color: Colors.white54),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF4F6EF7)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordCtrl,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _confirm(),
            decoration: const InputDecoration(
              labelText: 'Пароль',
              labelStyle: TextStyle(color: Colors.white54),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF4F6EF7)),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _confirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4F6EF7),
          ),
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Войти', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
