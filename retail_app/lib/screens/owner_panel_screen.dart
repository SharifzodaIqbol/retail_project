import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import 'shops_screen.dart';
import 'import_products_screen.dart';

/// Панель владельца: управление сотрудниками, PIN, Telegram, терминальный режим
class OwnerPanelScreen extends StatefulWidget {
  final VoidCallback onEnterTerminal;

  const OwnerPanelScreen({super.key, required this.onEnterTerminal});

  @override
  State<OwnerPanelScreen> createState() => _OwnerPanelScreenState();
}

class _OwnerPanelScreenState extends State<OwnerPanelScreen> {
  final _api = ApiService();
  List<dynamic> _users = [];
  bool _loading = true;
  String? _ownerUsername;
  bool _tgLinked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    _ownerUsername = prefs.getString('username');

    final users = await _api.getUsers();
    final ownerData = users.firstWhere(
      (u) => u['role'] == 'owner',
      orElse: () => {},
    );
    setState(() {
      _users = users;
      _tgLinked = (ownerData['tg_chat_id'] ?? 0) != 0;
      _loading = false;
    });
  }

  // ─── Telegram ────────────────────────────────────────────────────────────

  Future<void> _linkTelegram() async {
    final result = await _api.generateTgLinkToken();
    if (result == null || !mounted) return;

    final token = result['token'] as String;
    final botName = result['bot_name'] as String? ?? '';
    final deeplink = 'https://t.me/$botName?start=$token';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Привязать Telegram'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Нажмите кнопку ниже, чтобы открыть Telegram и привязать аккаунт автоматически.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Ссылка действительна 10 минут.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),
            // Показываем deeplink для копирования
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      deeplink,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: deeplink));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Ссылка скопирована')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.telegram, color: Colors.white),
            label: const Text(
              'Открыть Telegram',
              style: TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0088CC),
            ),
            onPressed: () async {
              Navigator.pop(context);
              final uri = Uri.parse(deeplink);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
              // После открытия обновляем статус через небольшую задержку
              await Future.delayed(const Duration(seconds: 3));
              _load();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _unlinkTelegram() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Отвязать Telegram?'),
        content: const Text('Уведомления о продажах перестанут приходить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Отвязать',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _api.unlinkTelegram();
      _load();
    }
  }

  // ─── PIN ─────────────────────────────────────────────────────────────────

  void _showSetPinDialog(Map<String, dynamic> user) {
    final pinCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('PIN для ${user['username']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '4-значный PIN для входа в терминальном режиме',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'PIN-код (4 цифры)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F6EF7),
            ),
            onPressed: () async {
              if (pinCtrl.text.length != 4) return;
              final ok = await _api.setUserPin(user['id'], pinCtrl.text);
              if (!mounted) return;
              Navigator.pop(context);
              if (ok) {
                _load();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('PIN установлен'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Ошибка'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text(
              'Сохранить',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Терминальный режим ───────────────────────────────────────────────────

  Future<void> _enterTerminalMode() async {
    final sellers = _users.where((u) => u['has_pin'] == true).toList();
    if (sellers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сначала установите PIN хотя бы одному сотруднику'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Режим терминала'),
        content: const Text(
          'Приложение перейдёт в режим кассы.\nСотрудники смогут входить по PIN.\nДля выхода удержите кнопку и введите ваш пароль.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F6EF7),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Перейти', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('terminal_mode', true);
      widget.onEnterTerminal();
    }
  }

  // ─── Добавление сотрудника ────────────────────────────────────────────────

  void _showAddUserDialog() {
    final usernameCtrl = TextEditingController();
    final pinCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Новый продавец'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Продавцы входят только через PIN — пароль не нужен.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Имя продавца',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pinCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  obscureText: true,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'PIN-код (4 цифры)',
                    border: OutlineInputBorder(),
                    helperText: 'Продавец введёт это при входе',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F6EF7),
              ),
              onPressed: () async {
                if (usernameCtrl.text.isEmpty) return;
                if (pinCtrl.text.length != 4) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('PIN должен быть 4 цифры')),
                  );
                  return;
                }
                // Seller создаётся без пароля, только с PIN
                final ok = await _api.createUserWithPin(
                  usernameCtrl.text.trim(),
                  '', // пароль пустой для seller'а
                  'seller',
                  pin: pinCtrl.text,
                );
                if (!mounted) return;
                if (ok) {
                  Navigator.pop(ctx);
                  _load();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Продавец добавлен!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ошибка. Имя уже занято?'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
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
      builder: (_) => AlertDialog(
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
            child: const Text('Удалить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final ok = await _api.deleteUser(id);
      if (ok && mounted) _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'Панель владельца',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ─── Секция: Магазины ──────────────────────────────────
                  _SectionHeader(title: 'Мои магазины'),
                  const SizedBox(height: 8),
                  _ActionCard(
                    icon: Icons.store,
                    iconColor: const Color(0xFF22C55E),
                    title: 'Управление магазинами',
                    subtitle: 'Добавляйте и переключайтесь между магазинами',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ShopsScreen()),
                      );
                    },
                    trailing: const Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: Colors.grey,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ─── Секция: Товары ────────────────────────────────────
                  _SectionHeader(title: 'Товары'),
                  const SizedBox(height: 8),
                  _ActionCard(
                    icon: Icons.upload_file,
                    iconColor: const Color(0xFFF59E0B),
                    title: 'Загрузить товары из Excel',
                    subtitle: 'Массовое добавление и обновление по штрихкоду',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ImportProductsScreen(),
                        ),
                      );
                    },
                    trailing: const Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: Colors.grey,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ─── Секция: Режим терминала ───────────────────────────
                  _SectionHeader(title: 'Терминальный режим'),
                  const SizedBox(height: 8),
                  _ActionCard(
                    icon: Icons.point_of_sale,
                    iconColor: const Color(0xFF4F6EF7),
                    title: 'Перевести в кассовый режим',
                    subtitle: 'Сотрудники входят по PIN-коду',
                    onTap: _enterTerminalMode,
                    trailing: const Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: Colors.grey,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ─── Секция: Telegram ──────────────────────────────────
                  _SectionHeader(title: 'Telegram уведомления'),
                  const SizedBox(height: 8),
                  _ActionCard(
                    icon: Icons.telegram,
                    iconColor: const Color(0xFF0088CC),
                    title: _tgLinked
                        ? 'Telegram привязан'
                        : 'Привязать Telegram',
                    subtitle: _tgLinked
                        ? 'Вы получаете уведомления о продажах'
                        : 'Получайте уведомления о продажах',
                    onTap: _tgLinked ? _unlinkTelegram : _linkTelegram,
                    trailing: _tgLinked
                        ? const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 20,
                          )
                        : const Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: Colors.grey,
                          ),
                    subtitleColor: _tgLinked ? Colors.green : null,
                  ),

                  const SizedBox(height: 24),

                  // ─── Секция: Сотрудники ────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _SectionHeader(title: 'Сотрудники'),
                      TextButton.icon(
                        onPressed: _showAddUserDialog,
                        icon: const Icon(Icons.person_add, size: 16),
                        label: const Text('Добавить'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._users.map(
                    (u) => _UserTile(
                      user: u,
                      onSetPin: () => _showSetPinDialog(u),
                      onDelete: u['role'] != 'owner'
                          ? () => _deleteUser(u['id'], u['username'])
                          : null,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ─── Вспомогательные виджеты ─────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) => Text(
    title.toUpperCase(),
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: Colors.grey,
      letterSpacing: 1.2,
    ),
  );
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final Color? subtitleColor;

  const _ActionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.subtitleColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: subtitleColor ?? Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback onSetPin;
  final VoidCallback? onDelete;

  const _UserTile({required this.user, required this.onSetPin, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isOwner = user['role'] == 'owner';
    final hasPin = user['has_pin'] == true;
    final hasTg = (user['tg_chat_id'] ?? 0) != 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
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
                  user['username'] ?? '',
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
                        color: isOwner ? const Color(0xFFFFD700) : Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                    if (hasPin) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.pin, size: 13, color: Colors.green),
                      const Text(
                        ' PIN',
                        style: TextStyle(fontSize: 12, color: Colors.green),
                      ),
                    ],
                    if (hasTg) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.telegram,
                        size: 13,
                        color: Color(0xFF0088CC),
                      ),
                      const Text(
                        ' TG',
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
          // Кнопка PIN
          IconButton(
            icon: Icon(
              hasPin ? Icons.pin_outlined : Icons.pin,
              color: hasPin ? Colors.green : Colors.grey,
              size: 22,
            ),
            tooltip: hasPin ? 'Изменить PIN' : 'Установить PIN',
            onPressed: onSetPin,
          ),
          if (onDelete != null)
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                color: Colors.red,
                size: 22,
              ),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}
