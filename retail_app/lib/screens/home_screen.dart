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
    // Синхронизацию неотправленных чеков теперь делает только
    // SyncService (запускается один раз в main() на уровне всего
    // приложения). Раньше здесь тоже вызывался _syncOfflineSales — но
    // HomeScreen создаётся один раз и живёт внутри IndexedStack, поэтому
    // при старте приложения оба места почти одновременно читали одну и
    // ту же очередь pending-чеков и параллельно отправляли одни и те же
    // чеки на сервер — гонка, которая могла привести к задвоенной
    // продаже одного чека (два POST на /api/sales по одному и тому же
    // sale_data). SyncService.start() и так вызывает syncNow() сразу при
    // запуске, так что для этого экрана ничего специально дублировать
    // не нужно.
    _loadUserInfo();

    // Запрашиваем фокус сразу после того, как кадр построится
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestScannerFocus();
    });
  }

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
          _requestScannerFocus();
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

    _debounce = Timer(const Duration(milliseconds: 150), () async {
      if (query.length < 2) {
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

    FocusManager.instance.primaryFocus?.unfocus();
    _requestScannerFocus();
  }

  void _checkout(BuildContext context) async {
    final cart = Provider.of<CartProvider>(context, listen: false);
    if (cart.items.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => _PaymentDialog(totalAmount: cart.totalAmount),
    );

    _requestScannerFocus();

    if (confirm != true) return;

    // Страховка: если у какого-то товара в корзине не подгрузились units
    // (например, сбой сети при сканировании), product.baseUnit тихо
    // подставит синтетическую единицу с id = 0 (см. product.dart), которой
    // нет в product_units на сервере — сервер отклонит весь чек с ошибкой
    // "единица продажи не найдена: 0". Ловим это здесь, ДО отправки, чтобы
    // кассир увидел понятную причину, а не общую ошибку оплаты.
    final brokenItem = cart.items.values
        .where((i) => i.product.baseUnit.id == 0)
        .toList();
    if (brokenItem.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Хатогӣ бо "${brokenItem.first.product.name}": маълумоти '
              'воҳиди фурӯш пурра нашудааст. Маҳсулотро аз сабад хориҷ '
              'карда, дубора скан кунед.',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      return;
    }

    final saleData = {
      // Корзина сейчас не хранит выбранную единицу продажи по позиции —
      // добавление товара в корзину всегда происходит по его базовой
      // единице (см. addProduct/addWeighedAmount), поэтому здесь явно
      // берём i.product.baseUnit. Ключи JSON должны точно совпадать с
      // domain.SaleItem на сервере: unit_id (обязателен, без него сервер
      // видит id = 0 и отклоняет чек "единица продажи не найдена: 0") и
      // quantity_display (а не quantity).
      'items': cart.items.values
          .map(
            (i) => {
              'product_id': i.product.id,
              'unit_id': i.product.baseUnit.id,
              'quantity_display': i.quantity,
              'price': i.product.sellPrice,
            },
          )
          .toList(),
      'total_amount': cart.totalAmount,
    };

    final result = await _apiService.createSale(saleData);

    switch (result.status) {
      case SaleSendStatus.success:
        DataRefreshService.instance.notifySaleChanged();
        DataRefreshService.instance.notifyProductChanged();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Фурӯш ба расмият дароварда шуд!'),
              backgroundColor: Colors.green,
            ),
          );
        }
        break;

      case SaleSendStatus.networkError:
        // Реального ответа от сервера не было — это настоящий обрыв связи,
        // чек можно безопасно поставить в офлайн-очередь на автоповтор.
        await DatabaseHelper.instance.insertOfflineSale(saleData);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Шабака нест! Чек дар хотираи телефон сабт шуд'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        break;

      case SaleSendStatus.rejected:
        // Сервер ответил и отклонил чек по существу (например, недостаточно
        // товара на складе). Повторная идентичная отправка даст ту же
        // ошибку, поэтому НЕ кладём чек в офлайн-очередь на автоповтор —
        // вместо этого явно показываем причину, чтобы продавец/владелец
        // мог её устранить (пополнить остатки, поправить количество и т.п.).
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Чек рад карда шуд: ${result.errorMessage ?? "номаълум"}',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        break;
    }

    cart.clearCart();
  }

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
    final isKg = item.product.unit == 'kg';
    final controller = TextEditingController(
      text: isKg
          ? item.quantity.toString()
          : item.quantity.truncate().toString(),
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Маҳсулот: ${item.product.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.numberWithOptions(decimal: isKg),
          decoration: InputDecoration(
            labelText: isKg ? 'Миқдор (кг), масалан. 0.5' : 'Миқдор (дона)',
            helperText: isKg ? null : 'Танҳо ададҳои бутун',
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
              if (newQty == null || newQty <= 0) return;
              if (!isKg && newQty != newQty.truncateToDouble()) return;
              cart.updateQuantity(item.product.id, newQty);
              Navigator.pop(context);
            },
            child: const Text('Тайер'),
          ),
        ],
      ),
    ).then((_) {
      _requestScannerFocus();
    });
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

    return GestureDetector(
      onTap: _requestScannerFocus,
      child: KeyboardListener(
        focusNode: _scannerFocusNode,
        autofocus: true,
        onKeyEvent: _handleHardwareKey,
        child: Scaffold(
          resizeToAvoidBottomInset:
              false, // Игнорируем сжатие экрана клавиатурой
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
                  ).then((_) => _requestScannerFocus());
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
          body: Stack(
            children: [
              // СЛОЙ 1: Основное содержимое (Поиск + Список Корзины + Панель оплаты)
              Column(
                children: [
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: TextField(
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
                            _requestScannerFocus();
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
                                                padding:
                                                    const EdgeInsets.symmetric(
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
                                                  _promptWeightAndAdd(
                                                    item.product,
                                                  );
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
                                            (item.product.sellPrice *
                                                    item.quantity)
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

              // СЛОЙ 2: Абсолютно позиционированное выпадающее окно подсказок поиска
              if (_suggestions.isNotEmpty)
                Positioned(
                  top:
                      68, // Располагаем ровно под TextField (высота паддингов верхнего контейнера)
                  left: 16,
                  right: 16,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    constraints: const BoxConstraints(maxHeight: 250),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: _suggestions.length,
                      itemBuilder: (ctx, i) {
                        final p = _suggestions[i];
                        return ListTile(
                          title: Text(p.name),
                          subtitle: Text(
                            '${p.sellPrice.toStringAsFixed(2)} сомонӣ.',
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
                            setState(() {
                              _suggestions = [];
                              _searchController.clear();
                            });
                            if (p.unit == 'kg') {
                              _promptWeightAndAdd(p);
                            } else {
                              cart.addProduct(p);
                              _requestScannerFocus();
                            }
                          },
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentDialog extends StatefulWidget {
  final double totalAmount;
  const _PaymentDialog({required this.totalAmount});
  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final TextEditingController _receivedCtrl = TextEditingController();
  static const List<int> _quickBills = [10, 20, 50, 100, 200, 500];

  @override
  void dispose() {
    _receivedCtrl.dispose();
    super.dispose();
  }

  double? get _received =>
      double.tryParse(_receivedCtrl.text.trim().replaceAll(',', '.'));

  double? get _change {
    final r = _received;
    if (r == null) return null;
    final c = r - widget.totalAmount;
    return c >= 0 ? c : null;
  }

  bool get _isInsufficient {
    final r = _received;
    return r != null && r < widget.totalAmount;
  }

  void _setReceived(double amount) {
    setState(() {
      _receivedCtrl.text = amount % 1 == 0
          ? amount.toStringAsFixed(0)
          : amount.toStringAsFixed(2);
    });
  }

  void _addToReceived(int bill) {
    final current = _received ?? 0;
    _setReceived(current + bill);
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isKeyboardOpen = mediaQuery.viewInsets.bottom > 0;

    return AlertDialog(
      // Поднимаем диалог вверх при открытой клавиатуре
      alignment: isKeyboardOpen ? Alignment.topCenter : Alignment.center,
      insetPadding: EdgeInsets.symmetric(
        horizontal: 16,
        // Если клавиатура открыта, уменьшаем внешний отступ диалога до 10 пикселей сверху
        vertical: isKeyboardOpen ? 10 : 24,
      ),
      title: const Text('Тасдиқи пардохт'),
      content: SizedBox(
        width: mediaQuery.size.width * 0.9,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Итоговая сумма
            const Text(
              'Дар маҷмӯъ',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              '${widget.totalAmount.toStringAsFixed(2)} сомонӣ',
              style: const TextStyle(
                fontSize: 22, // Слегка уменьшили с 24, чтобы сэкономить место
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E),
              ),
            ),

            // Динамический отступ: экономим место при открытой клавиатуре
            SizedBox(height: isKeyboardOpen ? 6 : 16),

            const Text(
              'Аз харидор гирифта шуд (нақд)',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _receivedCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: '0.00',
                errorText: _isInsufficient ? 'Маблағ аз чек камтар аст' : null,
                errorMaxLines: 1,
                suffixIcon: _receivedCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => _receivedCtrl.clear()),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                // Делаем поле ввода более компактным по высоте
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),

            SizedBox(height: isKeyboardOpen ? 6 : 12),

            // Быстрые купюры в одну строчку (горизонтальный скролл)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _quickBills
                    .map(
                      (bill) => Padding(
                        padding: const EdgeInsets.only(right: 6.0),
                        child: OutlinedButton(
                          onPressed: () => _addToReceived(bill),
                          style: OutlinedButton.styleFrom(
                            // Сжали кнопки по высоте (vertical: 4), освобождая около 15 пикселей
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text('+$bill'),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),

            // Динамический отступ перед блоком сдачи
            SizedBox(height: isKeyboardOpen ? 10 : 18),

            // Блок сдачи — полностью на виду
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ), // Сделали чуть тоньше
              decoration: BoxDecoration(
                color: _change != null
                    ? Colors.green.shade50
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Бозгашт',
                    style: TextStyle(
                      fontSize: 13,
                      color: _change != null
                          ? Colors.green.shade700
                          : Colors.grey,
                    ),
                  ),
                  Text(
                    _change != null
                        ? '${_change!.toStringAsFixed(2)} сомонӣ'
                        : '— сомонӣ',
                    style: TextStyle(
                      fontSize:
                          18, // 18 пикселей вместо 20 гарантирует вместимость
                      fontWeight: FontWeight.w800,
                      color: _change != null
                          ? Colors.green.shade700
                          : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Бекор кардан'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          onPressed: _isInsufficient
              ? null
              : () => Navigator.pop(context, true),
          child: const Text('Пардохт', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
