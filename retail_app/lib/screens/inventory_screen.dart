import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/data_refresh_service.dart';
import '../widgets/product_unit_editor.dart';
import '../widgets/barcode_scanner.dart';
import 'label_print_screen.dart';

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

  // ── Ошибки единого диалога тағйир/таҳрир ──
  String? _amountError;
  String? _buyError;
  String? _sellError;
  String? _reasonError;
  String? _nameError;
  bool _saving = false;

  // ── Данные ──
  List<Product> _products = [];
  bool _loading = true;

  // Токен поколения загрузки. Каждый reset=true увеличивает его; ответ
  // от уже устаревшего вызова (например, обновление списка запустилось
  // одновременно из двух мест — явно после сохранения и через поток
  // DataRefreshService.onProductChanged, на который тоже подписан этот
  // экран через AutoRefreshMixin) игнорируется, чтобы товары не
  // задваивались в списке.
  int _loadGeneration = 0;

  String _role = '';
  String _searchQuery = '';

  // Фильтр по единице измерения: '' — все, 'pcs' — штучные, 'kg' — весовые.
  String _filterUnit = '';

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

  // Загружает весь список товаров одним запросом (без пагинации).
  Future<void> _loadProducts({bool reset = false}) async {
    final myGeneration = ++_loadGeneration;
    setState(() => _loading = true);

    final products = await _api.getAllProducts();

    if (!mounted) return;
    // Пока шёл запрос, успел стартовать более новый reset (или экран
    // ушёл в офлайн/переоткрылся) — этот ответ уже устарел, применять
    // его нельзя, иначе список продублируется или перепутается порядок.
    if (myGeneration != _loadGeneration) return;

    setState(() {
      _products = products;
      _loading = false;
    });
  }

  void _onSearchChanged() {
    setState(() => _searchQuery = _searchCtrl.text.toLowerCase());
  }

  // Локальная фильтрация уже загруженных данных.
  // Фильтруем по единице измерения (кг/шт) и по имени/штрихкоду.
  List<Product> get _filtered {
    var list = _products;
    if (_filterUnit.isNotEmpty) {
      list = list.where((p) => p.unit == _filterUnit).toList();
    }
    if (_searchQuery.isEmpty) return list;
    return list
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
    _nameError = null;
  }

  // Единое окно "Тағйир/Таҳрири маҳсулот" — доступно и продавцу, и
  // хозяину. Показывает все детали товара (номи, штрихкод, воҳиди
  // ченак, нархҳо, доп. единицы продажи) плюс тағйири анбор. Агар
  // продавец тағйир диҳад — сабаб ҳатмист ва хозяин дар Telegram огоҳ
  // мешавад; агар худи хозяин тағйир диҳад — сабаб лозим нест ва
  // огоҳинома фиристода намешавад (мувофиқи манфиати логика дар
  // backend: isSeller && h.tgBot != nil).
  Future<bool?> _showRestockDialog(Product product) async {
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final nameCtrl = TextEditingController(text: product.name);
    final barcodeCtrl = TextEditingController(text: product.barcode);
    final sellCtrl = TextEditingController(
      text: product.sellPrice.toStringAsFixed(2),
    );
    final buyCtrl = TextEditingController(
      text: product.buyPrice.toStringAsFixed(2),
    );
    final isSeller = _role == 'seller';
    String unit = product.unit;

    final origName = product.name;
    final origBarcode = product.barcode;
    final origUnit = product.unit;
    final origBuy = product.buyPrice;
    final origSell = product.sellPrice;

    final existingUnitRows = product.units
        .where((u) => !u.isBase)
        .map((u) => ExistingUnitRow(u))
        .toList();
    final removedUnitIds = <int>{};
    final newUnits = <NewUnitRow>[];
    const maxExtraUnits = 3;

    _clearErrors();
    _saving = false;

    return await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled:
          true, // Позволяет диалогу подниматься вместе с клавиатурой
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final totalExtraUnits = existingUnitRows.length + newUnits.length;

          // Отступ от клавиатуры динамически поднимает диалог вверх
          final bottomInset = MediaQuery.of(context).viewInsets.bottom;

          return Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: SafeArea(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight:
                      MediaQuery.of(context).size.height *
                      0.85, // Ограничение по высоте
                ),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Заголовок и информация
                    Text(
                      'Таҳрири маҳсулот',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Миқдори ҳозира: ${product.stock} ${product.unitLabel}.',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),

                    // Прокручиваемый список со всеми полями
                    Expanded(
                      child: ListView(
                        children: [
                          TextField(
                            controller: nameCtrl,
                            textCapitalization: TextCapitalization.sentences,
                            onChanged: (_) {
                              _nameError = null;
                              setSheetState(() {});
                            },
                            decoration: InputDecoration(
                              labelText: 'Номи маҳсулот',
                              border: const OutlineInputBorder(),
                              errorText: _nameError,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: barcodeCtrl,
                            decoration: InputDecoration(
                              labelText: 'Штрихкод (ихтиёрӣ)',
                              prefixIcon: const Icon(Icons.qr_code),
                              border: const OutlineInputBorder(),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Штрихкоди худкор созед',
                                    icon: const Icon(
                                      Icons.auto_awesome,
                                      color: Colors.blue,
                                    ),
                                    onPressed: () async {
                                      final barcode = await _api
                                          .generateBarcode();
                                      if (barcode != null) {
                                        barcodeCtrl.text = barcode;
                                        setSheetState(() {});
                                      }
                                    },
                                  ),
                                  IconButton(
                                    tooltip: 'Бо камера сканер кунед',
                                    icon: const Icon(
                                      Icons.camera_alt,
                                      color: Colors.blue,
                                    ),
                                    onPressed: () async {
                                      final String? scanned =
                                          await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  BarcodeScannerWidget(),
                                            ),
                                          );
                                      if (scanned != null) {
                                        barcodeCtrl.text = scanned;
                                        setSheetState(() {});
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: unit,
                            decoration: const InputDecoration(
                              labelText: 'Воҳиди асосӣ',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'pcs',
                                child: Text('дона'),
                              ),
                              DropdownMenuItem(value: 'kg', child: Text('кг')),
                            ],
                            onChanged: (v) {
                              if (v != null) setSheetState(() => unit = v);
                            },
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
                                  'Илова "+", кам кардан "-"'
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
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
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
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
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
                          const SizedBox(height: 20),
                          const Divider(),
                          const SizedBox(height: 8),
                          const Text(
                            'Воҳидҳои иловагии мавҷуда',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (existingUnitRows.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text(
                                'Ин маҳсулот воҳиди иловагӣ надорад.',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          for (final row in existingUnitRows)
                            ExistingUnitCard(
                              key: ValueKey('existing-unit-${row.unit.id}'),
                              row: row,
                              onGenerateBarcode: _api.generateBarcode,
                              onChanged: () => setSheetState(() {}),
                              onRemove: () => setSheetState(() {
                                removedUnitIds.add(row.unit.id);
                                existingUnitRows.remove(row);
                                row.dispose();
                              }),
                            ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Илова кардани воҳиди нав',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              TextButton.icon(
                                onPressed: totalExtraUnits >= maxExtraUnits
                                    ? null
                                    : () => setSheetState(
                                        () => newUnits.add(NewUnitRow()),
                                      ),
                                icon: const Icon(Icons.add),
                                label: const Text('Илова'),
                              ),
                            ],
                          ),
                          for (int i = 0; i < newUnits.length; i++)
                            NewUnitCard(
                              row: newUnits[i],
                              onRemove: () => setSheetState(
                                () => newUnits.removeAt(i).dispose(),
                              ),
                              onChanged: () => setSheetState(() {}),
                              onGenerateBarcode: _api.generateBarcode,
                            ),
                          if (isSeller) ...[
                            const SizedBox(height: 20),
                            const Divider(),
                            const SizedBox(height: 8),
                            TextField(
                              controller: reasonCtrl,
                              maxLines: 2,
                              onChanged: (_) {
                                _reasonError = null;
                                setSheetState(() {});
                              },
                              decoration: InputDecoration(
                                labelText: 'Сабаби тағирот',
                                hintText: 'Мисол: илова кардани маҳсулот...',
                                prefixIcon: const Icon(Icons.edit_note),
                                border: const OutlineInputBorder(),
                                errorText: _reasonError,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Соҳибкор аз тағирот огоҳӣ мегирад.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Фиксированные кнопки снизу (не уезжают при скролле)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _saving
                                ? null
                                : () {
                                    for (final row in newUnits) {
                                      row.dispose();
                                    }
                                    for (final row in existingUnitRows) {
                                      row.dispose();
                                    }
                                    Navigator.pop(context, false);
                                  },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Бекор кардан',
                              style: TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
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
                                    _clearErrors();
                                    bool hasError = false;

                                    double? parseNum(String raw) =>
                                        double.tryParse(
                                          raw.trim().replaceAll(',', '.'),
                                        );

                                    final name = nameCtrl.text.trim();
                                    if (name.isEmpty) {
                                      _nameError =
                                          'Номи маҳсулотро ворид кунед';
                                      hasError = true;
                                    }

                                    final buyPrice = parseNum(buyCtrl.text);
                                    if (buyPrice == null || buyPrice < 0) {
                                      _buyError =
                                          'Нархи харидро дуруст ворид кунед';
                                      hasError = true;
                                    }

                                    final sellPrice = parseNum(sellCtrl.text);
                                    if (sellPrice == null || sellPrice < 0) {
                                      _sellError =
                                          'Нархи фурӯшро дуруст ворид кунед';
                                      hasError = true;
                                    }

                                    final amountText = amountCtrl.text.trim();
                                    double addStock = 0;
                                    if (amountText.isNotEmpty) {
                                      final parsed = parseNum(amountText);
                                      if (parsed == null) {
                                        _amountError =
                                            'Миқдорро дуруст ворид кунед';
                                        hasError = true;
                                      } else {
                                        addStock = parsed;
                                      }
                                    }

                                    // Изменённые доп. единицы — некорректные
                                    // данные тоже блокируют сохранение.
                                    final unitsToUpdate =
                                        <
                                          ExistingUnitRow,
                                          Map<String, dynamic>
                                        >{};
                                    for (final row in existingUnitRows) {
                                      if (!row.isChanged) continue;
                                      final data = row.toUpdateData();
                                      if (data == null) {
                                        hasError = true;
                                        continue;
                                      }
                                      unitsToUpdate[row] = data;
                                    }

                                    // Новые доп. единицы — пустую карточку
                                    // (нажали "Илова", но ничего не заполнили)
                                    // просто игнорируем.
                                    final unitsToCreate =
                                        <Map<String, dynamic>>[];
                                    for (final row in newUnits) {
                                      final label = row.labelController.text
                                          .trim();
                                      final factor = parseNum(
                                        row.factorController.text,
                                      );
                                      final price = parseNum(
                                        row.priceController.text,
                                      );
                                      final untouched =
                                          label.isEmpty &&
                                          row.factorController.text
                                              .trim()
                                              .isEmpty &&
                                          row.priceController.text
                                              .trim()
                                              .isEmpty;
                                      if (untouched) continue;
                                      if (label.isEmpty ||
                                          factor == null ||
                                          factor <= 0 ||
                                          price == null ||
                                          price < 0) {
                                        hasError = true;
                                        continue;
                                      }
                                      unitsToCreate.add({
                                        'label': label,
                                        'conversion_factor': factor,
                                        'price': price,
                                        'barcode':
                                            row.barcodeController.text
                                                .trim()
                                                .isEmpty
                                            ? null
                                            : row.barcodeController.text.trim(),
                                      });
                                    }

                                    final trimmedBarcode = barcodeCtrl.text
                                        .trim();
                                    final nameChanged = name != origName;
                                    final barcodeChanged =
                                        trimmedBarcode != origBarcode;
                                    final unitChanged = unit != origUnit;
                                    final buyChanged =
                                        buyPrice != null && buyPrice != origBuy;
                                    final sellChanged =
                                        sellPrice != null &&
                                        sellPrice != origSell;
                                    final productDetailsChanged =
                                        nameChanged ||
                                        barcodeChanged ||
                                        unitChanged;

                                    final reason = reasonCtrl.text.trim();
                                    final anyChange =
                                        productDetailsChanged ||
                                        buyChanged ||
                                        sellChanged ||
                                        addStock != 0 ||
                                        unitsToUpdate.isNotEmpty ||
                                        removedUnitIds.isNotEmpty ||
                                        unitsToCreate.isNotEmpty;

                                    if (isSeller &&
                                        anyChange &&
                                        reason.isEmpty) {
                                      _reasonError = 'Сабабро нависед';
                                      hasError = true;
                                    }

                                    if (hasError) {
                                      setSheetState(() {});
                                      return;
                                    }

                                    if (!anyChange) {
                                      Navigator.pop(context, false);
                                      return;
                                    }

                                    setSheetState(() => _saving = true);

                                    String? error;

                                    if (productDetailsChanged) {
                                      error = await _api
                                          .updateProduct(product.id, {
                                            'name': name,
                                            'barcode': trimmedBarcode.isEmpty
                                                ? null
                                                : trimmedBarcode,
                                            'unit': unit,
                                          }, reason: isSeller ? reason : null);
                                    }

                                    if (error == null &&
                                        (addStock != 0 ||
                                            buyChanged ||
                                            sellChanged)) {
                                      final ok = await _api.updateInventory(
                                        product.id,
                                        addStock,
                                        sellPrice ?? origSell,
                                        buyPrice ?? origBuy,
                                        reason: isSeller ? reason : null,
                                        barcode: trimmedBarcode.isEmpty
                                            ? null
                                            : trimmedBarcode,
                                      );
                                      if (!ok) {
                                        error = 'Хатогӣ ҳангоми навсозии анбор';
                                      }
                                    }

                                    if (error == null) {
                                      for (final entry
                                          in unitsToUpdate.entries) {
                                        final err = await _api
                                            .updateProductUnit(
                                              product.id,
                                              entry.key.unit.id,
                                              entry.value,
                                            );
                                        if (err != null) {
                                          error = err;
                                          break;
                                        }
                                      }
                                    }

                                    if (error == null) {
                                      for (final unitId in removedUnitIds) {
                                        final err = await _api
                                            .deleteProductUnit(
                                              product.id,
                                              unitId,
                                            );
                                        if (err != null) {
                                          error = err;
                                          break;
                                        }
                                      }
                                    }

                                    if (error == null) {
                                      for (final data in unitsToCreate) {
                                        final err = await _api.addProductUnit(
                                          product.id,
                                          data,
                                        );
                                        if (err != null) {
                                          error = err;
                                          break;
                                        }
                                      }
                                    }

                                    if (!mounted) return;

                                    if (error != null) {
                                      setSheetState(() => _saving = false);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(content: Text(error!)),
                                      );
                                      return;
                                    }

                                    DataRefreshService.instance
                                        .notifyProductChanged();
                                    for (final row in newUnits) {
                                      row.dispose();
                                    }
                                    for (final row in existingUnitRows) {
                                      row.dispose();
                                    }
                                    Navigator.pop(context, true);
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
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Чопи этикетка',
            onPressed: _products.isEmpty
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LabelPrintScreen(products: _products),
                    ),
                  ),
          ),
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

          // Фильтр по единице измерения (кг/шт)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _UnitFilterChip(
                    label: 'Ҳама',
                    selected: _filterUnit.isEmpty,
                    onTap: () => setState(() => _filterUnit = ''),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _UnitFilterChip(
                      label: 'Дона',
                      selected: _filterUnit == 'pcs',
                      onTap: () => setState(() => _filterUnit = 'pcs'),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _UnitFilterChip(
                      label: 'Кг',
                      selected: _filterUnit == 'kg',
                      onTap: () => setState(() => _filterUnit = 'kg'),
                    ),
                  ),
                ],
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
                            padding: const EdgeInsets.all(16),
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) {
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
                                        tooltip: 'Тағйири маҳсулот',
                                        onPressed: () async {
                                          final updated =
                                              await _showRestockDialog(p);
                                          if (updated == true && mounted) {
                                            _loadProducts(reset: true);
                                          }
                                        },
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

// ─── Вспомогательные виджеты ─────────────────────────────────────────────────

class _UnitFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _UnitFilterChip({
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
