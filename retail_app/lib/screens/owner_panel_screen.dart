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

  final TextEditingController _employeeSearchCtrl = TextEditingController();
  String _employeeSearchQuery = '';
  List<dynamic> _shops = [];
  int _filterShopId = 0; // 0 = все магазины

  List<dynamic> get _filteredUsers {
    var list = _users;
    if (_filterShopId != 0) {
      list = list.where((u) => u['shop_id'] == _filterShopId).toList();
    }
    if (_employeeSearchQuery.isEmpty) return list;
    return list
        .where(
          (u) => (u['username'] ?? '').toString().toLowerCase().contains(
            _employeeSearchQuery,
          ),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
    _employeeSearchCtrl.addListener(() {
      setState(() {
        _employeeSearchQuery = _employeeSearchCtrl.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _employeeSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    _ownerUsername = prefs.getString('username');

    final users = await _api.getUsers();
    final shops = await _api.getShops();
    final ownerData = users.firstWhere(
      (u) => u['role'] == 'owner',
      orElse: () => {},
    );
    setState(() {
      _users = users;
      _shops = shops;
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
        title: const Text('Пайванди Telegram'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Барои кушодани Telegram ва ба таври худкор пайваст кардани ҳисоб тугмаи зерро пахш кунед.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Пайванд 10 дақиқа эътибор дорад.',
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
                        const SnackBar(
                          content: Text('Пайванд нусхабардорӣ карда шуд'),
                        ),
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
            child: const Text('Бекор кардан'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.telegram, color: Colors.white),
            label: const Text(
              'Telegram-ро кушоед',
              style: TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0088CC),
            ),
            onPressed: () async {
              Navigator.pop(context);
              final uri = Uri.parse(deeplink);
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Кушодани Telegram муяссар нашуд: $e'),
                    ),
                  );
                }
              }
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
        title: const Text('Аз пайвасти Telegram бот мебароед?'),
        content: const Text(
          'Огоҳиномаҳо дар бораи фурӯш омаданро қатъ мекунед.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Бекор кардан'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Тасдиқ', style: TextStyle(color: Colors.white)),
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
        title: Text('PIN барои ${user['username']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'PIN 4-рақам барои воридшавӣ ба ҳолати терминал',
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
                labelText: 'PIN-код (4 рақам)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Бекор кардан'),
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
                    content: Text('PIN насб карда шудааст'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Хатоги шуд'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Насб', style: TextStyle(color: Colors.white)),
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
          content: Text('Аввалан, ками-кам барои як корманд PIN-код гузоред.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ҳолати терминал'),
        content: const Text(
          'Барнома ба ҳолати касса мегузарад.\nКормандон метавонанд ба PIN ворид шаванд.\nБарои баромадан тугмаро пахш кунед ва пароли худро ворид кунед.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Бекор кардан'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F6EF7),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Гузаштан',
              style: TextStyle(color: Colors.white),
            ),
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

  void _showAddUserDialog() async {
    final usernameCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    final shops = await _api.getShops();
    final prefs = await SharedPreferences.getInstance();
    int selectedShopId = prefs.getInt('shop_id') ?? 0;
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Фурӯшандаи нав'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Фурӯшандагон танҳо тавассути PIN ворид мешаванд парол лозим нест.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Номи фурӯшанда',
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
                    labelText: 'PIN-код (4 рақам)',
                    border: OutlineInputBorder(),
                    helperText:
                        'Фурӯшанда инро ҳангоми ворид шудан ворид мекунад',
                  ),
                ),
                if (shops.length > 1) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: shops.any((s) => s['id'] == selectedShopId)
                        ? selectedShopId
                        : shops.first['id'],
                    decoration: const InputDecoration(
                      labelText: 'Мағоза',
                      border: OutlineInputBorder(),
                    ),
                    items: shops
                        .map<DropdownMenuItem<int>>(
                          (s) => DropdownMenuItem<int>(
                            value: s['id'],
                            child: Text(s['name'] ?? ''),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => selectedShopId = v);
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Бекор кардан'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F6EF7),
              ),
              onPressed: () async {
                if (usernameCtrl.text.isEmpty) return;
                if (pinCtrl.text.length != 4) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('PIN бояд 4 рақам бошад')),
                  );
                  return;
                }
                // Seller создаётся без пароля, только с PIN
                final ok = await _api.createUserWithPin(
                  usernameCtrl.text.trim(),
                  '', // пароль пустой для seller'а
                  'seller',
                  pin: pinCtrl.text,
                  shopId: selectedShopId,
                );
                if (!mounted) return;
                if (ok) {
                  Navigator.pop(ctx);
                  _load();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Фурӯшанда илова карда шуд!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Хато. Ин ном аллакай ҳаст?'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Насб', style: TextStyle(color: Colors.white)),
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
        title: const Text('Корманд хориҷ карда шавад?'),
        content: Text('Фурӯшанда "$username" хориҷ карда мешавад.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Бекор кардан'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Хориҷ', style: TextStyle(color: Colors.white)),
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
          'Панели соҳиб',
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
                  _SectionHeader(title: 'Мағозаҳои ман'),
                  const SizedBox(height: 8),
                  _ActionCard(
                    icon: Icons.store,
                    iconColor: const Color(0xFF22C55E),
                    title: 'Идоракунии мағозаҳо',
                    subtitle: 'Илова кунед ва байни мағозаҳо гузаред',
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
                  _SectionHeader(title: 'Маҳсулотҳо'),
                  const SizedBox(height: 8),
                  _ActionCard(
                    icon: Icons.upload_file,
                    iconColor: const Color(0xFFF59E0B),
                    title: 'Даровардани маҳсулотҳо аз Excel',
                    subtitle:
                        'Бисёр маҳсулотҳоро даровардан ва азнавсозии маҳсулот агар штрихкод такрор шавад',
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
                  _SectionHeader(title: 'Ҳолати терминал'),
                  const SizedBox(height: 8),
                  _ActionCard(
                    icon: Icons.point_of_sale,
                    iconColor: const Color(0xFF4F6EF7),
                    title: 'Ба ҳолати кассавӣ гузаштан',
                    subtitle: 'Кормандон тавассути PIN-код ворид мешаванд',
                    onTap: _enterTerminalMode,
                    trailing: const Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: Colors.grey,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ─── Секция: Telegram ──────────────────────────────────
                  _SectionHeader(title: 'Огоҳиҳои аз Telegram-бот'),
                  const SizedBox(height: 8),
                  _ActionCard(
                    icon: Icons.telegram,
                    iconColor: const Color(0xFF0088CC),
                    title: _tgLinked
                        ? 'Telegram пайваст карда шудааст'
                        : 'Пайвастшавӣ ба Telegram',
                    subtitle: _tgLinked
                        ? 'Ба шумо огоҳиномаҳои фурӯш равно карда мешавад'
                        : 'Огоҳиномаҳои фурӯшро қабул кунед',
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
                      _SectionHeader(title: 'Коргарҳо'),
                      TextButton.icon(
                        onPressed: _showAddUserDialog,
                        icon: const Icon(Icons.person_add, size: 16),
                        label: const Text('Илова'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_shops.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SizedBox(
                        height: 34,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _ShopFilterChip(
                              label: 'Ҳама',
                              selected: _filterShopId == 0,
                              onTap: () => setState(() => _filterShopId = 0),
                            ),
                            ..._shops.map(
                              (s) => Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: _ShopFilterChip(
                                  label: s['name'] ?? '',
                                  selected: _filterShopId == s['id'],
                                  onTap: () =>
                                      setState(() => _filterShopId = s['id']),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_users.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: _employeeSearchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Ҷустуҷӯй аз руи ном...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _employeeSearchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () => _employeeSearchCtrl.clear(),
                                )
                              : null,
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 0,
                            horizontal: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                      ),
                    ),
                  if (_filteredUsers.isEmpty && _employeeSearchQuery.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'Ҷустуҷӯ натиҷа надод',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ),
                    )
                  else
                    ..._filteredUsers.map(
                      (u) => _UserTile(
                        user: u,
                        onSetPin: u['role'] != 'owner'
                            ? () => _showSetPinDialog(u)
                            : null,
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

class _ShopFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ShopFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF4F6EF7) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF4F6EF7) : Colors.grey.shade300,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}

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
  final VoidCallback? onSetPin;
  final VoidCallback? onDelete;

  const _UserTile({required this.user, this.onSetPin, this.onDelete});

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
                      isOwner ? 'Соҳибкор' : 'Фурӯшанда',
                      style: TextStyle(
                        color: isOwner ? const Color(0xFFFFD700) : Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                    if ((user['shop_name'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.store,
                        size: 13,
                        color: Color(0xFF4F6EF7),
                      ),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          user['shop_name'],
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF4F6EF7),
                          ),
                        ),
                      ),
                    ],
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
          // Кнопка PIN (недоступна для соҳибкор — вай метавонад бидуни PIN фурӯш кунад)
          if (onSetPin != null)
            IconButton(
              icon: Icon(
                hasPin ? Icons.pin_outlined : Icons.pin,
                color: hasPin ? Colors.green : Colors.grey,
                size: 22,
              ),
              tooltip: hasPin ? 'Тағйир додани PIN' : 'Насб кардани PIN',
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
