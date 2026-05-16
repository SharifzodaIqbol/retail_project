import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers/database_helper.dart';
import '../models/product.dart';
import '../screens/add_product_screen.dart';
import '../widgets/barcode_scanner.dart';
import '../providers/cart_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();

  List<Product> _suggestions = [];
  Timer? _debounce;
  String _username = '';
  String _role = '';

  @override
  void initState() {
    super.initState();
    _syncOfflineSales();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final username = await _authService.getUsername() ?? '';
    final role = await _authService.getRole() ?? '';
    setState(() {
      _username = username;
      _role = role;
    });
  }

  void _searchProduct(BuildContext context) async {
    final barcode = _searchController.text.trim();
    if (barcode.isEmpty) return;

    final product = await _apiService.getProductByBarcode(barcode);

    if (product != null) {
      Provider.of<CartProvider>(context, listen: false).addProduct(product);
      _searchController.clear();
      setState(() => _suggestions = []);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Товар не найден'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (query.length < 2) {
        setState(() => _suggestions = []);
        return;
      }
      final results = await _apiService.searchProductsByName(query);
      setState(() => _suggestions = results);
    });
  }

  void _checkout(BuildContext context) async {
    final cart = Provider.of<CartProvider>(context, listen: false);
    if (cart.items.isEmpty) return;

    // Показываем диалог подтверждения
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Подтвердить оплату?'),
        content: Text(
          'Итого: ${cart.totalAmount.toStringAsFixed(2)} сомони\n'
          '${cart.items.length} позиций',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Оплатить',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final saleData = {
      'items': cart.items.values
          .map((i) => {
                'product_id': i.product.id,
                'quantity': i.quantity,
                'price': i.product.sellPrice,
              })
          .toList(),
      'total_amount': cart.totalAmount,
    };

    bool success = await _apiService.createSale(
      cart.items.values
          .map((i) => {
                'product_id': i.product.id,
                'quantity': i.quantity,
                'price': i.product.sellPrice,
              })
          .toList(),
      cart.totalAmount,
    );

    if (!success) {
      await DatabaseHelper.instance.insertOfflineSale(saleData);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Нет сети! Чек сохранён в памяти телефона'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Продажа оформлена!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }

    cart.clearCart();
  }

  void _showQuantityDialog(BuildContext context, CartProvider cart, dynamic item) {
    final controller = TextEditingController(text: item.quantity.toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Количество: ${item.product.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Количество',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              final newQty = int.tryParse(controller.text);
              if (newQty != null) {
                cart.updateQuantity(item.product.id, newQty);
              }
              Navigator.pop(context);
            },
            child: const Text('Готово'),
          ),
        ],
      ),
    );
  }

  Future<void> _syncOfflineSales() async {
    final unsynced = await DatabaseHelper.instance.getUnsyncedSales();
    if (unsynced.isEmpty) return;

    int successCount = 0;
    for (var row in unsynced) {
      final saleData = jsonDecode(row['sale_data']);
      bool success = await _apiService.createSaleFromRawData(saleData);
      if (success) {
        await DatabaseHelper.instance.markSaleAsSynced(row['id']);
        successCount++;
      }
    }

    if (successCount > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('☁️ Синхронизировано чеков: $successCount'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  void _logout() async {
    await _authService.logout();
    if (mounted) {
      // Перезапустить приложение (вернуться к логину)
      Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Касса',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            if (_username.isNotEmpty)
              Text(
                _username,
                style:
                    const TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          // Кнопка добавить товар
          IconButton(
            icon: const Icon(Icons.add_box_outlined),
            tooltip: 'Добавить товар',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AddProductScreen()),
              );
            },
          ),
          // Очистить корзину
          if (cart.items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
              tooltip: 'Очистить',
              onPressed: () => cart.clearCart(),
            ),
          // Выход
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Выйти',
            onPressed: _logout,
          ),
        ],
      ),
      body: Column(
        children: [
          // Поле поиска
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Штрихкод или название товара...',
                    prefixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner,
                          color: Color(0xFF4F6EF7)),
                      onPressed: () async {
                        final code = await Navigator.push<String>(
                          context,
                          MaterialPageRoute(
                              builder: (_) => BarcodeScannerWidget()),
                        );
                        if (code != null) {
                          _searchController.text = code;
                          _searchProduct(context);
                        }
                      },
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () => _searchProduct(context),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF5F7FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: _onSearchChanged,
                  onSubmitted: (_) => _searchProduct(context),
                ),

                // Выпадающий список подсказок
                if (_suggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _suggestions.length,
                      itemBuilder: (ctx, i) {
                        final p = _suggestions[i];
                        return ListTile(
                          title: Text(p.name),
                          subtitle: Text(
                            '${p.sellPrice.toStringAsFixed(2)} сом. • ${p.stock} шт.',
                            style: const TextStyle(fontSize: 12),
                          ),
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFF4F6EF7).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.shopping_bag,
                              color: Color(0xFF4F6EF7),
                              size: 18,
                            ),
                          ),
                          onTap: () {
                            cart.addProduct(p);
                            setState(() {
                              _suggestions = [];
                              _searchController.clear();
                            });
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // Список товаров в корзине
          Expanded(
            child: cart.items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_cart_outlined,
                          size: 80,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Корзина пуста',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Сканируйте штрихкод или введите название',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    itemCount: cart.items.length,
                    itemBuilder: (context, index) {
                      final item = cart.items.values.toList()[index];

                      return Dismissible(
                        key: Key(item.product.id.toString()),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) => cart.deleteProduct(item.product.id),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
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
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.product.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        '${item.product.sellPrice.toStringAsFixed(2)} сом.',
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Кол-во
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                        color: Colors.red,
                                      ),
                                      onPressed: () =>
                                          cart.removeOneItem(item.product.id),
                                    ),
                                    GestureDetector(
                                      onTap: () => _showQuantityDialog(
                                          context, cart, item),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF4F6EF7)
                                              .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '${item.quantity}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF4F6EF7),
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                        color: Color(0xFF27AE60),
                                      ),
                                      onPressed: () =>
                                          cart.addProduct(item.product),
                                    ),
                                  ],
                                ),
                                // Итог позиции
                                SizedBox(
                                  width: 80,
                                  child: Text(
                                    '${(item.product.sellPrice * item.quantity).toStringAsFixed(2)}',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Панель оплаты
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'ИТОГО',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      '${cart.totalAmount.toStringAsFixed(2)} сом.',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    Text(
                      '${cart.items.length} позиций',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: ElevatedButton(
                    onPressed: cart.items.isEmpty
                        ? null
                        : () => _checkout(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF27AE60),
                      disabledBackgroundColor: Colors.grey[200],
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'ОПЛАТИТЬ',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
