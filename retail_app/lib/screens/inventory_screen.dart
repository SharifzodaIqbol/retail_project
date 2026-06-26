import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/data_refresh_service.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with AutoRefreshMixin<InventoryScreen> {
  final _api = ApiService();
  final _authService = AuthService();
  final _searchCtrl = TextEditingController();

  List<Product> _allProducts = [];
  List<Product> _filtered = [];
  bool _loading = true;
  String _role = '';

  @override
  Stream<void> get refreshStream =>
      DataRefreshService.instance.onProductChanged;

  @override
  Future<void> loadData() => _loadProducts();

  @override
  void initState() {
    super.initState();
    _loadRole();
    _searchCtrl.addListener(_filter);
  }

  Future<void> _loadRole() async {
    final role = await _authService.getRole() ?? '';
    if (mounted) setState(() => _role = role);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _loading = true);
    final products = await _api.getAllProducts();
    setState(() {
      _allProducts = products;
      _filtered = products;
      _loading = false;
    });
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _allProducts
          .where(
            (p) => p.name.toLowerCase().contains(q) || p.barcode.contains(q),
          )
          .toList();
    });
  }

  void _showRestockDialog(Product product) {
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final sellCtrl = TextEditingController(
      text: product.sellPrice.toStringAsFixed(2),
    );
    final buyCtrl = TextEditingController(
      text: product.buyPrice.toStringAsFixed(2),
    );
    final isSeller = _role == 'seller';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          String? reasonError;
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Миқдори ҳозира: ${product.stock} ${product.unitLabel}.',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Илова кардан (${product.unitLabel})',
                    prefixIcon: Icon(Icons.add_box),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: buyCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Нархи харид',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: sellCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Нархи фурӯш',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                if (isSeller) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Сабаби тағиребии анбор',
                      hintText:
                          'Мисол: илова кардани маҳсулот, дигар сабабҳо...',
                      prefixIcon: const Icon(Icons.edit_note),
                      border: const OutlineInputBorder(),
                      errorText: reasonError,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Соҳибкор аз тағирот огоҳӣ мейобад.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F6EF7),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      if (isSeller && reasonCtrl.text.trim().isEmpty) {
                        setSheetState(
                          () => reasonError = 'Сабаби тағиротро нависед.',
                        );
                        return;
                      }

                      final amount =
                          double.tryParse(
                            amountCtrl.text.replaceAll(',', '.'),
                          ) ??
                          0;
                      final sell = double.tryParse(sellCtrl.text) ?? 0;
                      final buy = double.tryParse(buyCtrl.text) ?? 0;

                      final ok = await _api.updateInventory(
                        product.id,
                        amount,
                        sell,
                        buy,
                        reason: isSeller ? reasonCtrl.text.trim() : null,
                      );

                      if (ok && mounted) {
                        Navigator.pop(context);
                        _loadProducts();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isSeller
                                  ? 'Анбор тағир ёфт! Соҳибкор огоҳ карда шудааст.'
                                  : 'Анбор тағир ёфт!',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } else if (!ok && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Тағири анбор муяссар нашуд.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    child: const Text(
                      'Насб',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Color _stockColor(double stock) {
    if (stock <= 3) return Colors.red;
    if (stock <= 10) return Colors.orange;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'Склад',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadProducts),
        ],
      ),
      body: Column(
        children: [
          // Поиск
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Ҷустуҷӯ аз рӯи ном ё штрих-код...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _filter();
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF5F7FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Список товаров
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadProducts,
                    child: _filtered.isEmpty
                        ? const Center(child: Text('Ягон чиз ёфт нашуд'))
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final p = _filtered[i];
                              final stockColor = _stockColor(p.stock);
                              final margin = p.sellPrice > 0 && p.buyPrice > 0
                                  ? ((p.sellPrice - p.buyPrice) /
                                            p.sellPrice *
                                            100)
                                        .toStringAsFixed(0)
                                  : '0';

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
                                  title: Text(
                                    p.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Харид: ${p.buyPrice.toStringAsFixed(2)} | Фурӯш: ${p.sellPrice.toStringAsFixed(2)} | Маржа: $margin%',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      Text(
                                        '📦 ${p.barcode}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: stockColor.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          '${p.stock.toStringAsFixed(p.unit == 'kg' ? 2 : 0)} ${p.unitLabel}.',
                                          style: TextStyle(
                                            color: stockColor,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.edit,
                                          color: Color(0xFF4F6EF7),
                                        ),
                                        onPressed: () => _showRestockDialog(p),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
