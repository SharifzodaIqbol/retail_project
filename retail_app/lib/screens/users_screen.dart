import 'package:flutter/material.dart';
import '../services/api_service.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
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
    final users = await _api.getUsers();
    setState(() {
      _users = users;
      _loading = false;
    });
  }

  /// Диалог добавления сотрудника.
  /// Продавцы входят ТОЛЬКО через PIN — пароль не нужен.
  void _showAddUserDialog() {
    final usernameCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    String role = 'seller';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Новый сотрудник'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: usernameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Имя сотрудника',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              // PIN — обязателен для seller, видим всегда
              TextField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'PIN-код (4 цифры)',
                  border: OutlineInputBorder(),
                  helperText: 'Продавец будет входить через PIN',
                ),
              ),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                value: role,
                decoration: const InputDecoration(
                  labelText: 'Роль',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'seller', child: Text('Продавец')),
                ],
                onChanged: (v) => setDialogState(() => role = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (usernameCtrl.text.isEmpty) return;
                if (pinCtrl.text.length != 4) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('PIN должен быть 4 цифры')),
                  );
                  return;
                }
                // Seller создаётся без пароля — только с PIN
                final ok = await _api.createUserWithPin(
                  usernameCtrl.text.trim(),
                  '', // пароль пустой — бэкенд сам разберётся по роли
                  role,
                  pin: pinCtrl.text,
                );
                if (ok && mounted) {
                  Navigator.pop(context);
                  _loadUsers();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Сотрудник добавлен!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ошибка. Возможно, имя уже занято.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F6EF7),
              ),
              child: const Text(
                'Создать',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteUser(int id, String username) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить сотрудника?'),
        content: Text('Пользователь "$username" будет удалён.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('Удалить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final ok = await _api.deleteUser(id);
      if (ok && mounted) {
        _loadUsers();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сотрудник удалён')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'Сотрудники',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadUsers),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddUserDialog,
        backgroundColor: const Color(0xFF4F6EF7),
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text(
          'Добавить',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadUsers,
              child: _users.isEmpty
                  ? const Center(child: Text('Нет сотрудников'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _users.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final u = _users[i];
                        final isOwner = u['role'] == 'owner';
                        final hasTg = (u['tg_chat_id'] ?? 0) != 0;
                        final hasPin = u['has_pin'] == true;

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: isOwner
                                    ? const Color(0xFFFFD700).withOpacity(0.15)
                                    : const Color(0xFF4F6EF7).withOpacity(0.1),
                                child: Icon(
                                  isOwner ? Icons.star : Icons.person,
                                  color: isOwner
                                      ? const Color(0xFFFFD700)
                                      : const Color(0xFF4F6EF7),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      u['username'] ?? '',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        Text(
                                          isOwner ? 'Владелец' : 'Продавец',
                                          style: TextStyle(
                                            color: isOwner
                                                ? const Color(0xFFFFD700)
                                                : Colors.grey,
                                            fontSize: 12,
                                          ),
                                        ),
                                        if (!isOwner) ...[
                                          const SizedBox(width: 8),
                                          Icon(
                                            hasPin ? Icons.pin : Icons.pin_outlined,
                                            size: 14,
                                            color: hasPin ? Colors.green : Colors.grey,
                                          ),
                                          Text(
                                            hasPin ? ' PIN ✓' : ' PIN не задан',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: hasPin ? Colors.green : Colors.grey,
                                            ),
                                          ),
                                        ],
                                        if (hasTg) ...[
                                          const SizedBox(width: 8),
                                          const Icon(
                                            Icons.telegram,
                                            size: 14,
                                            color: Color(0xFF0088CC),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (!isOwner)
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                  onPressed: () =>
                                      _deleteUser(u['id'], u['username']),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
