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
  final _scrollCtrl = ScrollController();

  // ── Ошибки диалога пополнения ──
  String? _amountError;
  String? _buyError;
  String? _sellError;
  String? _reasonError;
  bool _saving = false;

  // ── Данные ──
  List<Product> _products = [];
  bool _loading = true;
  bool _loadingMore = false;
  int _page = 1;
  int _totalPages = 1;
  static const int _limit = 50;

  String _role = '';
  String _searchQuery = '';

  @override
  Stream<void> get refreshStream =>
      DataRefreshService.instance.onProductChanged;

  @override
  Future<void> loadData() => _loadProducts(reset: true);

  @override
  void initState() {
    super.initState();
    _loadRole();
    _searchCtrl.addListener(_onSearchChanged);
    _scrollCtrl.addListener(_onScroll);
  }

  Future<void> _loadRole() async {
    final role = await _authService.getRole() ?? '';
    if (mounted) setState(() => _role = role);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // Загружает страницу товаров.
  // reset=true — начать с первой страницы (pull-to-refresh или первый запуск).
  Future<void> _loadProducts({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _page = 1;
        _products = [];
      });
    } else {
      if (_loadingMore || _page >= _totalPages) return;
      setState(() => _loadingMore = true);
    }

    final result = await _api.getProducts(page: _page, limit: _limit);

    if (!mounted) return;
    setState(() {
      _products.addAll(result.data);
      _totalPages = result.totalPages;
      _loading = false;
      _loadingMore = false;
      if (result.hasNextPage) _page++;
    });
  }

  // При скролле к концу списка — подгружаем следующую страницу.
  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _loadProducts();
    }
  }

  void _onSearchChanged() {
    setState(() => _searchQuery = _searchCtrl.text.toLowerCase());
  }

  // Локальная фильтрация уже загруженных данных.
  // При пустом запросе показываем всё, иначе фильтруем по имени/штрихкоду.
  List<Product> get _filtered {
    if (_searchQuery.isEmpty) return _products;
    return _products
        .where(
          (p) =>
              p.name.toLowerCase().contains(_searchQuery) ||
              p.barcode.contains(_searchQuery),
        )
        .toList();
  }

  double? _parseNum(String raw) =>
      double.tryParse(raw.trim().replaceAll(',', '.'));

  void _clearErrors() {
    _amountError = null;
    _buyError = null;
    _sellError = null;
    _reasonError = null;
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

    _clearErrors();
    _saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
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
                    signed: true,
                  ),
                  onChanged: (_) {
                    _amountError = null;
                    setSheetState(() {});
                  },
                  decoration: InputDecoration(
                    labelText:
                        'Тағйири анбор (${product.unitLabel}) — 0 барои тағир надодан',
                    prefixIcon: const Icon(Icons.sync_alt),
                    border: const OutlineInputBorder(),
                    errorText: _amountError,
                    helperText:
                        'Барои илова "+10", барои кам кардан "-5" нависед'
                        '${product.unit == 'kg' ? ' (адади касрӣ иҷозат аст, мас: -2.5)' : ''}',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: buyCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) {
                          _buyError = null;
                          setSheetState(() {});
                        },
                        decoration: InputDecoration(
                          labelText: 'Нархи харид',
                          border: const OutlineInputBorder(),
                          errorText: _buyError,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: sellCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) {
                          _sellError = null;
                          setSheetState(() {});
                        },
                        decoration: InputDecoration(
                          labelText: 'Нархи фурӯш',
                          border: const OutlineInputBorder(),
                          errorText: _sellError,
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
                    onChanged: (_) {
                      _reasonError = null;
                      setSheetState(() {});
                    },
                    decoration: InputDecoration(
                      labelText: 'Сабаби тағирёбии анбор',
                      hintText: 'Мисол: илова кардани маҳсулот...',
                      prefixIcon: const Icon(Icons.edit_note),
                      border: const OutlineInputBorder(),
                      errorText: _reasonError,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Соҳибкор аз тағирот огоҳӣ мегирад.',
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
                    onPressed: _saving
                        ? null
                        : () async {
                            bool hasError = false;
                            _clearErrors();

                            final amount = _parseNum(
                              amountCtrl.text.isEmpty ? '0' : amountCtrl.text,
                            );
                            if (amount == null) {
                              _amountError =
                                  'Рақами нодуруст (мас: 10, -5 ё 2.5)';
                              hasError = true;
                            } else if (product.unit == 'pcs' &&
                                amount != amount.truncateToDouble()) {
                              _amountError = 'Барои "дона" танҳо ададҳои бутун';
                              hasError = true;
                            } else if (product.stock + amount < 0) {
                              _amountError =
                                  'Миқдор аз анбори мавҷуда (${product.stock}) зиёд аст';
                              hasError = true;
                            }

                            final buy = _parseNum(buyCtrl.text);
                            if (buy == null) {
                              _buyError = 'Нархи харидро дуруст ворид кунед';
                              hasError = true;
                            } else if (buy < 0) {
                              _buyError = 'Нарх манфӣ буда наметавонад';
                              hasError = true;
                            }

                            final sell = _parseNum(sellCtrl.text);
                            if (sell == null) {
                              _sellError = 'Нархи фурӯшро дуруст ворид кунед';
                              hasError = true;
                            } else if (sell < 0) {
                              _sellError = 'Нарх манфӣ буда наметавонад';
                              hasError = true;
                            } else if (buy != null && sell < buy) {
                              _sellError =
                                  'Нархи фурӯш аз нархи харид (${buy.toStringAsFixed(2)}) кам аст';
                              hasError = true;
                            }

                            if (isSeller && reasonCtrl.text.trim().isEmpty) {
                              _reasonError = 'Сабаби тағиротро нависед';
                              hasError = true;
                            }

                            setSheetState(() {});
                            if (hasError) return;

                            setSheetState(() => _saving = true);

                            final ok = await _api.updateInventory(
                              product.id,
                              amount!,
                              sell!,
                              buy!,
                              reason: isSeller ? reasonCtrl.text.trim() : null,
                            );

                            if (!mounted) return;
                            setSheetState(() => _saving = false);

                            if (ok) {
                              Navigator.pop(context);
                              _loadProducts(reset: true);
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
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Тағири анбор муяссар нашуд. Пайвастшавиро санҷед.',
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Захира кардан',
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

  // Удаление товара — только для владельца (сервер тоже это проверяет и
  // вернёт 403 продавцу, но кнопку продавцу лучше вообще не показывать).
  Future<void> _confirmDeleteProduct(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Нест кардани маҳсулот'),
        content: Text(
          '"${product.name}"-ро аз анбор нест кардан мехоҳед? Ин амалро баргардонидан мумкин нест.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Бекор кардан'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Нест кардан'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final ok = await _api.deleteProduct(product.id);
    if (!mounted) return;

    if (ok) {
      setState(() => _products.removeWhere((p) => p.id == product.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Маҳсулот нест карда шуд.'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нест кардан муяссар нашуд. Пайвастшавиро санҷед.'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
          'Анбор',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadProducts(reset: true),
          ),
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
                    onRefresh: () => _loadProducts(reset: true),
                    child: _filtered.isEmpty
                        ? const Center(child: Text('Ягон чиз ёфт нашуд'))
                        : ListView.separated(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.all(16),
                            // +1 для индикатора загрузки в конце
                            itemCount:
                                _filtered.length + (_loadingMore ? 1 : 0),
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              // Индикатор подгрузки следующей страницы
                              if (i == _filtered.length) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              }

                              final p = _filtered[i];
                              final stockColor = _stockColor(p.stock);

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
                                        'Харид: ${p.buyPrice.toStringAsFixed(2)} | Фурӯш: ${p.sellPrice.toStringAsFixed(2)}',
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
                                      if (_role == 'owner')
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: Colors.red,
                                          ),
                                          onPressed: () =>
                                              _confirmDeleteProduct(p),
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
