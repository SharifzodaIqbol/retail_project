import 'package:flutter/material.dart';
import 'package:retail_app/services/api_service.dart';

/// Экран управления магазинами — задача #2
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final shops = await _api.getShops();
    setState(() {
      _shops = shops;
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
              } else {
                await _api.createShop(name);
              }
              _load();
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
      await _api.deleteShop(shop['id']);
      _load();
    }
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
      body: _loading
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
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Мағозаи аввал созед',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                      itemCount: _shops.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final shop = _shops[i];
                        return Container(
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
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4F6EF7).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.store,
                                color: Color(0xFF4F6EF7),
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
                              'ID: ${shop['id']}',
                              style: const TextStyle(color: Colors.grey),
                            ),
                            onTap: widget.onShopSelected != null
                                ? () => widget.onShopSelected!(shop)
                                : null,
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'edit') _showAddDialog(existing: shop);
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
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
