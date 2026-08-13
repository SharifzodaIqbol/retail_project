import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  ///
  /// Ограничение: не более [_maxSellersPerShop] продавцов на один магазин.
  /// Кнопка "Сохтан" блокируется заранее (тот же паттерн, что и лимит
  /// доп. единиц в add_product_screen), а не просто показывает ошибку
  /// снизу экрана — иначе владелец не понимает, почему создание не удалось.
  static const int _maxSellersPerShop = 5;

  void _showAddUserDialog() async {
    final usernameCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    String role = 'seller';
    String? formError;

    final prefs = await SharedPreferences.getInstance();
    final currentShopId = prefs.getInt('shop_id') ?? 0;
    final sellersInShop = _users
        .where(
          (u) => u['role'] == 'seller' && (u['shop_id'] ?? 0) == currentShopId,
        )
        .length;
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final limitReached = sellersInShop >= _maxSellersPerShop;
          return AlertDialog(
            title: const Text('Коргари нав'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (limitReached)
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Дар ин мағоза аллакай ҳадди аксар $_maxSellersPerShop '
                        'фурӯшанда ҳаст. Барои иловаи нав, аввал каси дигарро '
                        'хориҷ кунед.',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  TextField(
                    controller: usernameCtrl,
                    enabled: !limitReached,
                    decoration: const InputDecoration(
                      labelText: 'Номи коргар',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // PIN — обязателен для seller, видим всегда
                  TextField(
                    controller: pinCtrl,
                    enabled: !limitReached,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'PIN-код (4 рақам)',
                      border: OutlineInputBorder(),
                      helperText: 'Фурӯшанда тавассути PIN ворид мешавад',
                    ),
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: role,
                    decoration: const InputDecoration(
                      labelText: 'Вазифа',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'seller',
                        child: Text('Фурӯшанда'),
                      ),
                    ],
                    onChanged: limitReached
                        ? null
                        : (v) => setDialogState(() => role = v!),
                  ),
                  if (formError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      formError!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Бекор кардан'),
              ),
              ElevatedButton(
                onPressed: limitReached
                    ? null
                    : () async {
                        if (usernameCtrl.text.isEmpty) return;
                        if (pinCtrl.text.length != 4) {
                          setDialogState(
                            () => formError = 'PIN бояд 4 рақам бошад',
                          );
                          return;
                        }
                        setDialogState(() => formError = null);
                        // Seller создаётся без пароля — только с PIN
                        final error = await _api.createUserWithPin(
                          usernameCtrl.text.trim(),
                          '', // пароль пустой — бэкенд сам разберётся по роли
                          role,
                          pin: pinCtrl.text,
                        );
                        if (error == null && mounted) {
                          Navigator.pop(context);
                          _loadUsers();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Корманд илова карда шуд!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } else if (mounted) {
                          setDialogState(
                            () => formError =
                                error ??
                                'Хато. Шояд ном аллакай гирифта шудааст.',
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F6EF7),
                ),
                child: const Text(
                  'Сохтан',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteUser(int id, String username) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Кормандро хориҷ мекунед?'),
        content: Text('Корманд "$username" хориҷ карда мешавад..'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Бекор кардан'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Тоза кардан',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final ok = await _api.deleteUser(id);
      if (ok && mounted) {
        _loadUsers();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Корманд хориҷ карда шуд')),
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
          'Кормандон',
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
          'Илова кардан',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadUsers,
              child: _users.isEmpty
                  ? const Center(child: Text('Корманд нест'))
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
                                          isOwner ? 'Соҳибкор' : 'Фурӯшанда',
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
                                            hasPin
                                                ? Icons.pin
                                                : Icons.pin_outlined,
                                            size: 14,
                                            color: hasPin
                                                ? Colors.green
                                                : Colors.grey,
                                          ),
                                          Text(
                                            hasPin
                                                ? ' PIN ✓'
                                                : ' PIN дода нашудааст',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: hasPin
                                                  ? Colors.green
                                                  : Colors.grey,
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
