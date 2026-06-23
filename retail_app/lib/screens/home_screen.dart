import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../helpers/database_helper.dart';
import '../models/product.dart';
import '../screens/add_product_screen.dart';
import '../widgets/barcode_scanner.dart';
import '../providers/cart_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/data_refresh_service.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onSellerLogout;
  const HomeScreen({Key? key, this.onSellerLogout}) : super(key: key);
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final FocusNode _scannerFocusNode = FocusNode(); // Узел фокуса для сканера

  List<Product> _suggestions = [];
  Timer? _debounce;
  String _username = '';
  String _scannerBuffer = '';
  String _role = '';

  @override
  void initState() {
    super.initState();
    _syncOfflineSales();
    _loadUserInfo(); // Вызов метода загрузки пользователя

    // Запрашиваем фокус сразу после того, как кадр построится
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestScannerFocus();
    });
  }

  // Метод загрузки информации о пользователе (исправляет вашу ошибку)
  Future<void> _loadUserInfo() async {
    try {
      final username = await _authService.getUsername() ?? '';
      final role = await _authService.getRole() ?? '';
      setState(() {
        _username = username;
        _role = role;
      });
    } catch (e) {
      debugPrint('Ошибка загрузки имени пользователя: $e');
    }
  }

  // Метод для безопасного возврата фокуса сканеру
  void _requestScannerFocus() {
    if (!_scannerFocusNode.hasFocus) {
      FocusScope.of(context).requestFocus(_scannerFocusNode);
    }
  }

  void _handleHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final character = event.character;
    final logicalKey = event.logicalKey;

    if (logicalKey == LogicalKeyboardKey.enter ||
        logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_scannerBuffer.isNotEmpty) {
        _processScannedBarcode(_scannerBuffer.trim());
        _scannerBuffer = '';
      }
      return;
    }

    if (character != null && character.isNotEmpty) {
      _scannerBuffer += character;
    }
  }

  void _processScannedBarcode(String barcode) async {
    if (barcode.isEmpty) return;

    final product = await _apiService.getProductByBarcode(barcode);

    if (product != null) {
      if (mounted) {
        Provider.of<CartProvider>(context, listen: false).addProduct(product);
        _requestScannerFocus(); // Держим фокус после добавления товара
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Товар не найден'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (RegExp(r'^\d+$').hasMatch(query) && query.length >= 5) {
      setState(() => _suggestions = []);
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 250), () async {
      if (query.length < 1) {
        setState(() => _suggestions = []);
        return;
      }
      final results = await _apiService.searchProductsByName(query);
      if (!mounted) return;
      setState(() => _suggestions = results);
    });
  }

  void _onManualSearchSubmit() {
    final text = _searchController.text.trim();
    if (text.isEmpty) return;

    if (RegExp(r'^\d+$').hasMatch(text)) {
      _processScannedBarcode(text);
    } else if (_suggestions.isNotEmpty) {
      Provider.of<CartProvider>(
        context,
        listen: false,
      ).addProduct(_suggestions.first);
    }

    _searchController.clear();
    setState(() => _suggestions = []);

    // Скрываем клавиатуру поиска и возвращаем фокус сканеру
    FocusManager.instance.primaryFocus?.unfocus();
    _requestScannerFocus();
  }

  void _checkout(BuildContext context) async {
    final cart = Provider.of<CartProvider>(context, listen: false);
    if (cart.items.isEmpty) return;

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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Оплатить',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    // После закрытия диалога оплаты возвращаем фокус
    _requestScannerFocus();

    if (confirm != true) return;

    final saleData = {
      'items': cart.items.values
          .map(
            (i) => {
              'product_id': i.product.id,
              'quantity': i.quantity,
              'price': i.product.sellPrice,
            },
          )
          .toList(),
      'total_amount': cart.totalAmount,
    };

    bool success = await _apiService.createSale(saleData);

    if (success) {
      // Сообщаем всем подписанным экранам (склад, история и т.д.),
      // что нужно перезагрузить данные с сервера.
      DataRefreshService.instance.notifySaleChanged();
      DataRefreshService.instance.notifyProductChanged();
    }

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

  void _showQuantityDialog(
    BuildContext context,
    CartProvider cart,
    dynamic item,
  ) {
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
    ).then((_) {
      // Когда диалог изменения количества закрылся, возвращаем фокус на сканер
      _requestScannerFocus();
    });
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

    if (successCount > 0) {
      DataRefreshService.instance.notifySaleChanged();
      DataRefreshService.instance.notifyProductChanged();
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
      Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scannerFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);

    // Клик в любом пустом месте экрана будет возвращать фокус сканеру
    return GestureDetector(
      onTap: _requestScannerFocus,
      child: KeyboardListener(
        focusNode: _scannerFocusNode,
        autofocus: true,
        onKeyEvent: _handleHardwareKey,
        child: Scaffold(
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
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.add_box_outlined),
                tooltip: 'Добавить товар',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => AddProductScreen()),
                  ).then(
                    (_) => _requestScannerFocus(),
                  ); // Возвращаем фокус после закрытия экрана добавления
                },
              ),
              if (cart.items.isNotEmpty)
                IconButton(
                  icon: const Icon(
                    Icons.delete_sweep_outlined,
                    color: Colors.red,
                  ),
                  tooltip: 'Очистить',
                  onPressed: () {
                    cart.clearCart();
                    _requestScannerFocus();
                  },
                ),
              if (_role == 'owner')
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Выход',
                  onPressed: _logout,
                ),
              if (_role == 'seller' && widget.onSellerLogout != null)
                TextButton.icon(
                  onPressed: widget.onSellerLogout,
                  icon: const Icon(Icons.logout, size: 18, color: Colors.red),
                  label: const Text(
                    'Выйти',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
          body: Column(
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Поиск товара по названию...',
                        prefixIcon: IconButton(
                          icon: const Icon(
                            Icons.qr_code_scanner,
                            color: Color(0xFF4F6EF7),
                          ),
                          onPressed: () async {
                            final code = await Navigator.push<String>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => BarcodeScannerWidget(),
                              ),
                            );
                            if (code != null) {
                              _processScannedBarcode(code);
                            }
                            _requestScannerFocus(); // Возвращаем фокус после камеры
                          },
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: _onManualSearchSubmit,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF5F7FA),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: _onSearchChanged,
                      onSubmitted: (_) => _onManualSearchSubmit(),
                    ),
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
                                  color: const Color(
                                    0xFF4F6EF7,
                                  ).withOpacity(0.1),
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
                                _requestScannerFocus(); // Возвращаем фокус после клика по списку
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
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
                              'Сканируйте штрихкод в любой момент',
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
                              child: const Icon(
                                Icons.delete,
                                color: Colors.white,
                              ),
                            ),
                            onDismissed: (_) {
                              cart.deleteProduct(item.product.id);
                              _requestScannerFocus();
                            },
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
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.remove_circle_outline,
                                            color: Colors.red,
                                          ),
                                          onPressed: () {
                                            cart.removeOneItem(item.product.id);
                                            _requestScannerFocus();
                                          },
                                        ),
                                        GestureDetector(
                                          onTap: () => _showQuantityDialog(
                                            context,
                                            cart,
                                            item,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(
                                                0xFF4F6EF7,
                                              ).withOpacity(0.1),
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
                                          onPressed: () {
                                            cart.addProduct(item.product);
                                            _requestScannerFocus();
                                          },
                                        ),
                                      ],
                                    ),
                                    SizedBox(
                                      width: 80,
                                      child: Text(
                                        (item.product.sellPrice * item.quantity)
                                            .toStringAsFixed(2),
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
        ),
      ),
    );
  }
}
