import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

/// Экран терминального режима.
/// Хозяин переводит приложение в этот режим — продавцы входят по PIN.
class TerminalScreen extends StatefulWidget {
  final int companyId;
  final String companyName;
  final VoidCallback onExitTerminal; // хозяин вышел из терминального режима

  const TerminalScreen({
    super.key,
    required this.companyId,
    required this.companyName,
    required this.onExitTerminal,
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
      _users = users.where((u) => u['has_pin'] == true).toList();
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
        onSuccess: (token, role, username) async {
          // Сохраняем JWT и входим как продавец
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('jwt_token', token);
          await prefs.setString('user_role', role);
          await prefs.setString('username', username);
          await prefs.setBool('terminal_mode', true);

          if (!mounted) return;
          Navigator.of(context).pop(); // закрыть sheet
          Navigator.of(context).pop(); // закрыть terminal screen
          // Сообщаем main.dart перезагрузить состояние
          widget.onExitTerminal();
        },
      ),
    );
  }

  Future<void> _exitToOwner() async {
    // Хозяин хочет вернуться в свой аккаунт — просим ввести пароль
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _OwnerPasswordDialog(
        onConfirmed: () => Navigator.pop(ctx, true),
      ),
    );
    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('terminal_mode', false);
      widget.onExitTerminal();
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
                  // Кнопка выхода для хозяина
                  GestureDetector(
                    onLongPress: _exitToOwner,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.lock_outline, color: Colors.white54, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Удерж. для выхода',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
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
                      ? const Center(
                          child: Text(
                            'Нет сотрудников с PIN-кодом.\nПопросите владельца установить PIN.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
    final isOwner = role == 'owner';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF252B45),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isOwner
                ? const Color(0xFFFFD700).withOpacity(0.4)
                : Colors.white12,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: isOwner
                  ? const Color(0xFFFFD700).withOpacity(0.15)
                  : const Color(0xFF4F6EF7).withOpacity(0.2),
              child: Text(
                username.isNotEmpty ? username[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isOwner ? const Color(0xFFFFD700) : const Color(0xFF4F6EF7),
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
            Text(
              isOwner ? 'Владелец' : 'Продавец',
              style: TextStyle(
                color: isOwner ? const Color(0xFFFFD700) : Colors.white38,
                fontSize: 12,
              ),
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
  final void Function(String token, String role, String username) onSuccess;

  const _PinInputSheet({
    required this.userName,
    required this.userId,
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

  void _onKey(String digit) {
    if (_pin.length >= 4) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length == 4) _submit();
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    final result = await _api.pinLogin(widget.userId, _pin);
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
          // Ручка
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

          // Индикатор точек
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

          const SizedBox(height: 28),

          // Цифровая клавиатура
          if (_loading)
            const CircularProgressIndicator(color: Color(0xFF4F6EF7))
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

/// Диалог для выхода хозяина из терминального режима
class _OwnerPasswordDialog extends StatefulWidget {
  final VoidCallback onConfirmed;
  const _OwnerPasswordDialog({required this.onConfirmed});

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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jwt_token', result['token']);
      await prefs.setString('user_role', result['role']);
      await prefs.setString('username', result['username']);
      widget.onConfirmed();
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
            'Введите данные владельца для выхода',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _usernameCtrl,
            style: const TextStyle(color: Colors.white),
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
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _confirm,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F6EF7)),
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Войти', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
