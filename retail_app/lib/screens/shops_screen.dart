import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retail_app/services/api_service.dart';
import '../main.dart';

/// Экран управления магазинами — задача #2.
/// Показывает список магазинов владельца, позволяет создавать новые,
/// переименовывать/удалять их и переключаться между ними (тап по карточке).
/// При переключении бэкенд выдаёт новый JWT со shop_id выбранного магазина —
/// после этого все данные (касса, склад, продажи, должники, аналитика)
/// автоматически относятся к выбранному магазину.
class ShopsScreen extends StatefulWidget {
  final void Function(Map<String, dynamic> shop)? onShopSelected;

  const ShopsScreen({super.key, this.onShopSelected});

  @override
  State<ShopsScreen> createState() => _ShopsScreenState();
}

class _ShopsScreenState extends State<ShopsScreen> {
  final _api = ApiService();
  List<dynamic> _shops = [];
  bool _loading = true;
  bool _switching = false;
  int _currentShopId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    final shops = await _api.getShops();
    if (!mounted) return;
    setState(() {
      _shops = shops;
      _currentShopId = prefs.getInt('shop_id') ?? 0;
      _loading = false;
    });
  }

  void _showAddDialog({Map<String, dynamic>? existing}) {
    final nameCtrl = TextEditingController(text: existing?['name'] ?? '');
    final isEdit = existing != null;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isEdit ? 'Номи мағозаро иваз кардан' : 'Мағозаи нав'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Номи мағоза',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Бекор кардан'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(context);
              if (isEdit) {
                await _api.updateShop(existing['id'], name);
                _load();
              } else {
                // Янги мағоза дарҳол фаъол мешавад — бинобар ин баъд аз
                // сохтан ба системаи асосӣ бо маълумоти ин мағоза бармегардем.
                setState(() => _switching = true);
                final shop = await _api.createShop(name);
                if (!mounted) return;
                setState(() => _switching = false);
                if (shop != null) {
                  _restartApp();
                } else {
                  _load();
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F6EF7),
            ),
            child: Text(
              isEdit ? 'Насб' : 'Сохтан',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(Map<String, dynamic> shop) async {
    if (_shops.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ин ягона мағозаи шумост, онро нест кардан мумкин нест',
          ),
        ),
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Мағозаро нест мекунед?'),
        content: Text(
          '«${shop['name']}» нест карда мешавад. Фурӯшандагони мағоза дар ширкат мемонанд.',
        ),
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
      final wasCurrent = shop['id'] == _currentShopId;
      await _api.deleteShop(shop['id']);
      if (wasCurrent) {
        // Магазин, в котором мы находились, удалён — переключаемся на
        // любой из оставшихся, иначе токен будет указывать в никуда.
        final remaining = await _api.getShops();
        if (remaining.isNotEmpty) {
          setState(() => _switching = true);
          await _api.switchShop(remaining.first['id']);
          if (!mounted) return;
          setState(() => _switching = false);
          _restartApp();
          return;
        }
      }
      _load();
    }
  }

  /// Переключиться на другой магазин: получаем новый токен и полностью
  /// перезапускаем приложение с самого начала — так все экраны (касса,
  /// склад, история, должники, аналитика) заново загружают данные и
  /// показывают именно тот магазин, который выбрал владелец.
  Future<void> _selectShop(Map<String, dynamic> shop) async {
    if (shop['id'] == _currentShopId) return;
    setState(() => _switching = true);
    final ok = await _api.switchShop(shop['id']);
    if (!mounted) return;
    setState(() => _switching = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Хатогӣ ҳангоми гузариш ба мағоза')),
      );
      return;
    }
    if (widget.onShopSelected != null) {
      widget.onShopSelected!(shop);
    }
    _restartApp();
  }

  void _restartApp() {
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppBootstrapper()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'Мағозаҳои ман',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(),
        backgroundColor: const Color(0xFF4F6EF7),
        icon: const Icon(Icons.add_business, color: Colors.white),
        label: const Text(
          'Илова кардани мағоза',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Stack(
        children: [
          _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _shops.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.store_outlined,
                                size: 64,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Мағоза нест',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Мағозаи аввалро созед',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                          itemCount: _shops.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final shop = _shops[i];
                            final isCurrent = shop['id'] == _currentShopId;
                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: isCurrent
                                    ? Border.all(
                                        color: const Color(0xFF4F6EF7),
                                        width: 1.5,
                                      )
                                    : null,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                leading: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF4F6EF7,
                                    ).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isCurrent ? Icons.storefront : Icons.store,
                                    color: const Color(0xFF4F6EF7),
                                  ),
                                ),
                                title: Text(
                                  shop['name'] ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                                subtitle: Text(
                                  isCurrent ? 'Фаъол ҳозир' : 'Гузаштан',
                                  style: TextStyle(
                                    color: isCurrent
                                        ? const Color(0xFF4F6EF7)
                                        : Colors.grey,
                                    fontWeight: isCurrent
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                                onTap: () => _selectShop(shop),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isCurrent)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 4),
                                        child: Icon(
                                          Icons.check_circle,
                                          color: Color(0xFF22C55E),
                                        ),
                                      ),
                                    PopupMenuButton<String>(
                                      onSelected: (v) {
                                        if (v == 'edit') {
                                          _showAddDialog(existing: shop);
                                        }
                                        if (v == 'delete') _delete(shop);
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Тағйири ном'),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Text(
                                            'Нест кардан',
                                            style: TextStyle(color: Colors.red),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
          if (_switching)
            Container(
              color: Colors.black.withOpacity(0.15),
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFF4F6EF7)),
              ),
            ),
        ],
      ),
    );
  }
}
