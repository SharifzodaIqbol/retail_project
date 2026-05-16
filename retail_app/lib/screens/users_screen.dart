import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

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

  void _showAddUserDialog() {
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
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
                  labelText: 'Логин',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Пароль',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: role,
                decoration: const InputDecoration(
                  labelText: 'Роль',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'seller', child: Text('Продавец')),
                  DropdownMenuItem(value: 'owner', child: Text('Владелец')),
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
                if (usernameCtrl.text.isEmpty || passwordCtrl.text.isEmpty) {
                  return;
                }
                final ok = await _api.createUser(
                  usernameCtrl.text.trim(),
                  passwordCtrl.text,
                  role,
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
                                        if (hasTg) ...[
                                          const SizedBox(width: 8),
                                          const Icon(
                                            Icons.telegram,
                                            size: 14,
                                            color: Color(0xFF0088CC),
                                          ),
                                          const Text(
                                            ' Привязан',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF0088CC),
                                            ),
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
