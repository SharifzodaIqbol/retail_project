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
        if (product.unit == 'kg') {
          _promptWeightAndAdd(product);
        } else {
          Provider.of<CartProvider>(context, listen: false).addProduct(product);
          _requestScannerFocus(); // Держим фокус после добавления товара
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Маҳсулот ёфт нашуд'),
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
      final found = _suggestions.first;
      if (found.unit == 'kg') {
        _promptWeightAndAdd(found);
      } else {
        Provider.of<CartProvider>(context, listen: false).addProduct(found);
      }
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
        title: const Text('Тасдиқи пардохт?'),
        content: Text(
          'Дар маҷмӯъ: ${cart.totalAmount.toStringAsFixed(2)} сомонӣ\n',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Бекор кардан'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Пардохт', style: TextStyle(color: Colors.white)),
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
            content: Text('Шабака нест! Чек дар хотираи телефон сабт шуд'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Фурӯш ба расмият дароварда шуд!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
    cart.clearCart();
  }

  /// Запрашивает у продавца вес товара вручную (для unit == 'kg').
  /// Введённый вес добавляется к товару в корзине (если товар уже есть —
  /// суммируется с текущим количеством).
  void _promptWeightAndAdd(Product product) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Вазн: ${product.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Вазнро ворид кунед, кг (масалан 0.5)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Бекор кардан'),
          ),
          ElevatedButton(
            onPressed: () {
              final weight = double.tryParse(
                controller.text.replaceAll(',', '.'),
              );
              if (weight != null && weight > 0) {
                Provider.of<CartProvider>(
                  context,
                  listen: false,
                ).addWeighedAmount(product, weight);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Вазнро дуруст ворид кунед.')),
                );
                return;
              }
              Navigator.pop(context);
            },
            child: const Text('Илова кардан'),
          ),
        ],
      ),
    ).then((_) {
      _requestScannerFocus();
    });
  }

  void _showQuantityDialog(
    BuildContext context,
    CartProvider cart,
    dynamic item,
  ) {
    final controller = TextEditingController(text: item.quantity.toString());
    final isKg = item.product.unit == 'kg';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Маҳсулот: ${item.product.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: isKg ? 'Миқдор (кг), масалан. 0.5' : 'Миқдор (дона)',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Бекор кардан'),
          ),
          ElevatedButton(
            onPressed: () {
              final newQty = double.tryParse(
                controller.text.replaceAll(',', '.'),
              );
              if (newQty != null) {
                cart.updateQuantity(item.product.id, newQty);
              }
              Navigator.pop(context);
            },
            child: const Text('Тайер'),
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
          content: Text('☁️ Квитансияҳо ҳамоҳанг карда шудаанд: $successCount'),
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
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color.fromARGB(255, 130, 138, 101),
                    ),
                  ),
              ],
            ),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.add_box_outlined),
                tooltip: 'Маҳсулотро илова кардан',
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
                  tooltip: 'Тоза кардан',
                  onPressed: () {
                    cart.clearCart();
                    _requestScannerFocus();
                  },
                ),
              if (_role == 'owner')
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Баромад',
                  onPressed: _logout,
                ),
              if (_role == 'seller' && widget.onSellerLogout != null)
                TextButton.icon(
                  onPressed: widget.onSellerLogout,
                  icon: const Icon(Icons.logout, size: 18, color: Colors.red),
                  label: const Text(
                    'Баромад',
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
                        hintText: 'Ҷустуҷӯи маҳсулот аз рӯи ном...',
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
                                '${p.sellPrice.toStringAsFixed(2)} сомонӣ. ${p.stock} ${p.unitLabel}.',
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
                                setState(() {
                                  _suggestions = [];
                                  _searchController.clear();
                                });
                                if (p.unit == 'kg') {
                                  _promptWeightAndAdd(p);
                                } else {
                                  cart.addProduct(p);
                                  _requestScannerFocus(); // Возвращаем фокус после клика по списку
                                }
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
                              'Сабад холӣ аст',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Штрих-кодро дар вақти дилхоҳ скан кунед.',
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
                                            '${item.product.sellPrice.toStringAsFixed(2)} сомонӣ',
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
                                            if (item.product.unit == 'kg') {
                                              // Для весовых товаров нет
                                              // фиксированного шага — убираем строку целиком,
                                              // точный вес правится тапом по количеству.
                                              cart.deleteProduct(
                                                item.product.id,
                                              );
                                            } else {
                                              cart.removeOneItem(
                                                item.product.id,
                                              );
                                            }
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
                                              item.product.unit == 'kg'
                                                  ? '${item.quantity.toStringAsFixed(item.quantity.truncateToDouble() == item.quantity ? 0 : 2)} кг'
                                                  : '${item.quantity.toStringAsFixed(0)}',
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
                                            if (item.product.unit == 'kg') {
                                              // Просим продавца ввести вес вручную,
                                              // а не молча прибавляем фиксированный шаг.
                                              _promptWeightAndAdd(item.product);
                                            } else {
                                              cart.addProduct(item.product);
                                              _requestScannerFocus();
                                            }
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
                          'ДАР МАҶМӮЪ',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          '${cart.totalAmount.toStringAsFixed(2)} сомонӣ',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A1A2E),
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
                          'ПАРДОХТ',
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
