import 'dart:async';
import 'package:flutter/material.dart';
import 'package:barcode_widget/barcode_widget.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../services/data_refresh_service.dart';
import '../services/connectivity_service.dart';
import 'package:retail_app/widgets/barcode_scanner.dart';
import 'label_print_screen.dart';

/// Карточка с картинкой штрихкода под полем ввода (та же логика, что и в
/// add_product_screen.dart).
class _BarcodePreviewCard extends StatelessWidget {
  final String data;

  const _BarcodePreviewCard({required this.data});

  static const double _previewWidth = 260;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.grey.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Center(
          child: SizedBox(
            width: _previewWidth,
            height: 90,
            child: BarcodeWidget(
              barcode: Barcode.code128(),
              data: data,
              drawText: true,
              style: const TextStyle(fontSize: 12),
              errorBuilder: (context, error) => Text(
                'Ин рамз барои штрихкод мувофиқ нест',
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Строка НОВОЙ доп. единицы продажи, заводимой в ходе этой же сессии
/// редактирования (ещё не существует на сервере — id появится только
/// после того, как её отправят через addProductUnit при сохранении).
class _NewUnitRow {
  final labelController = TextEditingController();
  final factorController = TextEditingController();
  final priceController = TextEditingController();
  final barcodeController = TextEditingController();

  void dispose() {
    labelController.dispose();
    factorController.dispose();
    priceController.dispose();
    barcodeController.dispose();
  }
}

/// Карточка новой (ещё не сохранённой) доп. единицы — идентична форме
/// добавления товара: своя строка, можно убрать до сохранения без похода
/// на сервер.
class _NewUnitCard extends StatefulWidget {
  final _NewUnitRow row;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  final Future<String?> Function() onGenerateBarcode;

  const _NewUnitCard({
    required this.row,
    required this.onRemove,
    required this.onChanged,
    required this.onGenerateBarcode,
  });

  @override
  State<_NewUnitCard> createState() => _NewUnitCardState();
}

class _NewUnitCardState extends State<_NewUnitCard> {
  bool _generating = false;

  Future<void> _generateBarcode() async {
    setState(() => _generating = true);
    final barcode = await widget.onGenerateBarcode();
    if (!mounted) return;
    setState(() => _generating = false);
    if (barcode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Штрихкодро сохта натавонистем. Пайвастшавиро санҷед.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    widget.row.barcodeController.text = barcode;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    return Card(
      margin: const EdgeInsets.only(top: 10),
      color: Colors.blue.withOpacity(0.03),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: row.labelController,
                    decoration: const InputDecoration(
                      labelText: 'Ном',
                      hintText: 'мас: қуттӣ',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: widget.onRemove,
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: row.factorController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Чанд дона дар дохил',
                      hintText: 'мас: 20',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: row.priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Нархи ин воҳид',
                      hintText: 'мас: 180.00',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: row.barcodeController,
              decoration: InputDecoration(
                labelText: 'Штрихкоди ин воҳид (ихтиёрӣ)',
                prefixIcon: const Icon(Icons.qr_code),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _generating
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            tooltip: 'Штрихкоди худкор созед',
                            icon: const Icon(
                              Icons.auto_awesome,
                              color: Colors.blue,
                            ),
                            onPressed: _generateBarcode,
                          ),
                    IconButton(
                      tooltip: 'Бо камера сканер кунед',
                      icon: const Icon(Icons.camera_alt, color: Colors.blue),
                      onPressed: () async {
                        final String? scannedCode = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => BarcodeScannerWidget(),
                          ),
                        );
                        if (scannedCode != null) {
                          row.barcodeController.text = scannedCode;
                          widget.onChanged();
                        }
                      },
                    ),
                  ],
                ),
              ),
              onChanged: (_) => widget.onChanged(),
            ),
            if (row.barcodeController.text.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              _BarcodePreviewCard(data: row.barcodeController.text.trim()),
            ],
          ],
        ),
      ),
    );
  }
}

/// Карточка УЖЕ существующей доп. единицы продажи — редактируется и
/// сохраняется/удаляется независимо от основной формы, своей собственной
/// кнопкой (сразу через API), не дожидаясь общего "Сохранить".
class _ExistingUnitCard extends StatefulWidget {
  final ProductUnit unit;
  final Future<String?> Function(Map<String, dynamic> data) onSave;
  final Future<String?> Function() onDelete;
  final Future<String?> Function() onGenerateBarcode;
  final VoidCallback onDeleted;

  const _ExistingUnitCard({
    super.key,
    required this.unit,
    required this.onSave,
    required this.onDelete,
    required this.onGenerateBarcode,
    required this.onDeleted,
  });

  @override
  State<_ExistingUnitCard> createState() => _ExistingUnitCardState();
}

class _ExistingUnitCardState extends State<_ExistingUnitCard> {
  late final _labelCtrl = TextEditingController(text: widget.unit.label);
  late final _factorCtrl = TextEditingController(
    text: _trimNum(widget.unit.conversionFactor),
  );
  late final _priceCtrl = TextEditingController(
    text: widget.unit.price.toStringAsFixed(2),
  );
  late final _barcodeCtrl = TextEditingController(
    text: widget.unit.barcode ?? '',
  );

  bool _saving = false;
  bool _deleting = false;
  bool _generating = false;

  static String _trimNum(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toString();
  }

  double? _parseNum(String raw) =>
      double.tryParse(raw.trim().replaceAll(',', '.'));

  Future<void> _generateBarcode() async {
    setState(() => _generating = true);
    final barcode = await widget.onGenerateBarcode();
    if (!mounted) return;
    setState(() => _generating = false);
    if (barcode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Штрихкодро сохта натавонистем. Пайвастшавиро санҷед.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _barcodeCtrl.text = barcode);
  }

  Future<void> _save() async {
    final label = _labelCtrl.text.trim();
    if (label.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Номи воҳидро нависед')));
      return;
    }
    final factor = _parseNum(_factorCtrl.text);
    if (factor == null || factor <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Коэффисиенти нодуруст')));
      return;
    }
    final price = _parseNum(_priceCtrl.text);
    if (price == null || price < 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Нархи нодуруст')));
      return;
    }

    setState(() => _saving = true);
    final error = await widget.onSave({
      'label': label,
      'conversion_factor': factor,
      'price': price,
      'barcode': _barcodeCtrl.text.trim().isEmpty
          ? null
          : _barcodeCtrl.text.trim(),
    });
    if (!mounted) return;
    setState(() => _saving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'Воҳид нигоҳ дошта шуд!'),
        backgroundColor: error == null ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Нест кардани воҳид'),
        content: Text(
          '"${widget.unit.label}"-ро нест кардан мехоҳед? Ин амалро баргардонидан мумкин нест.',
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

    setState(() => _deleting = true);
    final error = await widget.onDelete();
    if (!mounted) return;

    if (error == null) {
      widget.onDeleted();
    } else {
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _factorCtrl.dispose();
    _priceCtrl.dispose();
    _barcodeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _labelCtrl,
                    decoration: const InputDecoration(labelText: 'Ном'),
                  ),
                ),
                _deleting
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        tooltip: 'Нест кардан',
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        onPressed: _delete,
                      ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _factorCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Чанд дона дар дохил',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Нархи ин воҳид',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _barcodeCtrl,
              decoration: InputDecoration(
                labelText: 'Штрихкоди ин воҳид (ихтиёрӣ)',
                prefixIcon: const Icon(Icons.qr_code),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _generating
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            tooltip: 'Штрихкоди худкор созед',
                            icon: const Icon(
                              Icons.auto_awesome,
                              color: Colors.blue,
                            ),
                            onPressed: _generateBarcode,
                          ),
                    IconButton(
                      tooltip: 'Бо камера сканер кунед',
                      icon: const Icon(Icons.camera_alt, color: Colors.blue),
                      onPressed: () async {
                        final String? scannedCode = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => BarcodeScannerWidget(),
                          ),
                        );
                        if (scannedCode != null) {
                          setState(() => _barcodeCtrl.text = scannedCode);
                        }
                      },
                    ),
                  ],
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_barcodeCtrl.text.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              _BarcodePreviewCard(data: _barcodeCtrl.text.trim()),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('Нигоҳ доштани ин воҳид'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Экран редактирования уже существующего товара: название, штрихкод,
/// цены, базовая единица измерения, а также все связанные с ним доп.
/// единицы продажи (упаковка/блок/коробка...).
///
/// Форма построена как ListView (не Column внутри SizedBox) — поэтому если
/// поля (особенно доп. единицы) не помещаются на экран, появляется
/// вертикальный скролл сам собой, ничего дополнительно оборачивать не
/// нужно.
class EditProductScreen extends StatefulWidget {
  final Product product;

  const EditProductScreen({super.key, required this.product});

  @override
  State<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends State<EditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ApiService();
  bool _loading = false;

  late final _nameController = TextEditingController(text: widget.product.name);
  late final _barcodeController = TextEditingController(
    text: widget.product.barcode,
  );
  late final _buyPriceController = TextEditingController(
    text: widget.product.buyPrice.toStringAsFixed(2),
  );
  late final _sellPriceController = TextEditingController(
    text: widget.product.sellPrice.toStringAsFixed(2),
  );

  late String _unit = widget.product.unit;

  // Уже существующие доп. единицы (не базовая) — редактируются/удаляются
  // сразу через API своей собственной кнопкой на карточке.
  late List<ProductUnit> _existingExtraUnits = widget.product.units
      .where((u) => !u.isBase)
      .toList();

  // Новые единицы, добавляемые в этой сессии — создаются на сервере только
  // при нажатии общей кнопки "Сохранить".
  final List<_NewUnitRow> _newUnits = [];

  static const int _maxExtraUnits = 3;

  int get _totalExtraUnits => _existingExtraUnits.length + _newUnits.length;

  bool _lastKnownOnline = true;
  StreamSubscription<void>? _connectivityRestoredSub;
  Timer? _connectivityPollTimer;

  @override
  void initState() {
    super.initState();
    _barcodeController.addListener(_onBarcodeChanged);

    _lastKnownOnline = ConnectivityService.instance.isOnline;
    _connectivityRestoredSub = ConnectivityService.instance.onConnectionRestored
        .listen((_) {
          if (!mounted) return;
          setState(() => _lastKnownOnline = true);
        });
    _connectivityPollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      final isOnline = ConnectivityService.instance.isOnline;
      if (isOnline != _lastKnownOnline && mounted) {
        setState(() => _lastKnownOnline = isOnline);
      }
    });
  }

  void _onBarcodeChanged() => setState(() {});

  double? _parseNumber(String raw) =>
      double.tryParse(raw.trim().replaceAll(',', '.'));

  Future<void> _generateBarcode() async {
    final barcode = await _apiService.generateBarcode();
    if (!mounted) return;
    if (barcode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Штрихкодро сохта натавонистем. Пайвастшавиро санҷед.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _barcodeController.text = barcode);
  }

  void _addNewUnitRow() {
    if (_totalExtraUnits >= _maxExtraUnits) return;
    setState(() => _newUnits.add(_NewUnitRow()));
  }

  void _removeNewUnitRow(int index) {
    setState(() => _newUnits.removeAt(index).dispose());
  }

  String? _validatePrice(String? v, String label) {
    if (v == null || v.trim().isEmpty) return '$label ворид кунед';
    final parsed = _parseNumber(v);
    if (parsed == null) return 'Рақами нодуруст (масалан: 12.50)';
    if (parsed < 0) return '$label манфӣ буда наметавонад';
    return null;
  }

  String? _validateNewUnits() {
    for (final row in _newUnits) {
      final label = row.labelController.text.trim();
      if (label.isEmpty) continue;
      final factor = _parseNumber(row.factorController.text);
      if (factor == null || factor <= 0) {
        return '«$label»: дуруст нависед, чанд дона дар як воҳид (мас: 20)';
      }
      final price = _parseNumber(row.priceController.text);
      if (price == null || price < 0) {
        return '«$label»: нархро дуруст нависед';
      }
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (!ConnectivityService.instance.isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⚠️ Ба интернет дастраси надоред. Тағиротро офлайн захира кардан мумкин нест',
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    final newUnitsError = _validateNewUnits();
    if (newUnitsError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newUnitsError),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    final buyPrice = _parseNumber(_buyPriceController.text)!;
    final sellPrice = _parseNumber(_sellPriceController.text)!;

    if (sellPrice < buyPrice) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нархи фурӯш аз нархи харид камтар буда наметавонад!'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _loading = true);

    final productData = {
      "name": _nameController.text.trim(),
      "barcode": _barcodeController.text.trim(),
      "buy_price": buyPrice,
      "sell_price": sellPrice,
      "unit": _unit,
    };

    final error = await _apiService.updateProduct(
      widget.product.id,
      productData,
    );

    if (error != null) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    // Основные данные товара сохранены — теперь по очереди добавляем НОВЫЕ
    // доп. единицы продажи (существующие сохраняются/удаляются отдельно,
    // своей кнопкой на карточке). Ошибка здесь — это ошибка одной единицы,
    // а не всего сохранения целиком.
    final unitErrors = <String>[];
    for (final row in _newUnits) {
      final label = row.labelController.text.trim();
      if (label.isEmpty) continue;

      final unitData = {
        "label": label,
        "conversion_factor": _parseNumber(row.factorController.text),
        "price": _parseNumber(row.priceController.text),
        "barcode": row.barcodeController.text.trim().isEmpty
            ? null
            : row.barcodeController.text.trim(),
      };
      final unitError = await _apiService.addProductUnit(
        widget.product.id,
        unitData,
      );
      if (unitError != null) {
        unitErrors.add('$label: $unitError');
      }
    }

    if (!mounted) return;
    setState(() => _loading = false);

    // Склад (InventoryScreen) кэширует список товаров в своём состоянии —
    // без явного уведомления изменения были бы видны только после
    // ручного pull-to-refresh.
    DataRefreshService.instance.notifyProductChanged();

    Navigator.pop(context);

    if (unitErrors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Маҳсулот бо муваффақият нигоҳ дошта шуд!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Маҳсулот нигоҳ дошта шуд, аммо баъзе воҳидҳо не: ${unitErrors.join("; ")}',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  @override
  void dispose() {
    _connectivityRestoredSub?.cancel();
    _connectivityPollTimer?.cancel();
    _barcodeController.removeListener(_onBarcodeChanged);
    _nameController.dispose();
    _barcodeController.dispose();
    _buyPriceController.dispose();
    _sellPriceController.dispose();
    for (final row in _newUnits) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Таҳрири маҳсулот'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Чопи этикетка',
            onPressed: widget.product.barcode.trim().length != 13
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LabelPrintScreen(
                        products: [widget.product],
                        autoSelectAll: true,
                      ),
                    ),
                  ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        // ListView — форма сама скроллится, если поля (особенно список
        // доп. единиц) не помещаются на экран целиком.
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              if (!_lastKnownOnline)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    border: Border.all(color: Colors.orange),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.wifi_off, color: Colors.orange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ба интернет дастраси надоред. Тағир додани маҳсулот '
                          'дороии интернетро талаб мекунад.',
                          style: TextStyle(color: Colors.orange),
                        ),
                      ),
                    ],
                  ),
                ),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Номи маҳсулот'),
                textCapitalization: TextCapitalization.sentences,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Номро нависед';
                  if (v.trim().length < 2) return 'Ном хеле кӯтоҳ аст';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _barcodeController,
                decoration: InputDecoration(
                  labelText: 'Штрихкод (ихтиёрӣ)',
                  prefixIcon: const Icon(Icons.qr_code),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Штрихкоди худкор созед',
                        icon: const Icon(
                          Icons.auto_awesome,
                          color: Colors.blue,
                        ),
                        onPressed: _generateBarcode,
                      ),
                      IconButton(
                        tooltip: 'Бо камера сканер кунед',
                        icon: const Icon(Icons.camera_alt, color: Colors.blue),
                        onPressed: () async {
                          final String? scannedCode = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => BarcodeScannerWidget(),
                            ),
                          );
                          if (scannedCode != null) {
                            setState(
                              () => _barcodeController.text = scannedCode,
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              if (_barcodeController.text.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                _BarcodePreviewCard(data: _barcodeController.text.trim()),
              ],
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _buyPriceController,
                      decoration: const InputDecoration(
                        labelText: 'Нархи харид',
                        hintText: '0.00',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) => _validatePrice(v, 'Нархи харид'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _sellPriceController,
                      decoration: const InputDecoration(
                        labelText: 'Нархи фурӯш',
                        hintText: '0.00',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        final baseError = _validatePrice(v, 'Нархи фурӯш');
                        if (baseError != null) return baseError;
                        final sell = _parseNumber(v!)!;
                        final buy = _parseNumber(_buyPriceController.text);
                        if (buy != null && sell < buy) {
                          return 'Нархи фурӯш аз нархи харид (${buy.toStringAsFixed(2)}) кам аст';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _unit,
                decoration: const InputDecoration(labelText: 'Воҳиди асосӣ'),
                items: const [
                  DropdownMenuItem(value: 'pcs', child: Text('дона')),
                  DropdownMenuItem(value: 'kg', child: Text('кг')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _unit = v);
                },
              ),
              const SizedBox(height: 4),
              Text(
                'Тағир додани воҳиди асосӣ ба миқдори анбори мавҷуда таъсир намерасонад.',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'Воҳидҳои иловагии мавҷуда',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              if (_existingExtraUnits.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Ин маҳсулот воҳиди иловагӣ надорад.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              for (final unit in _existingExtraUnits)
                _ExistingUnitCard(
                  key: ValueKey('existing-unit-${unit.id}'),
                  unit: unit,
                  onGenerateBarcode: _apiService.generateBarcode,
                  onSave: (data) => _apiService.updateProductUnit(
                    widget.product.id,
                    unit.id,
                    data,
                  ),
                  onDelete: () =>
                      _apiService.deleteProductUnit(widget.product.id, unit.id),
                  onDeleted: () {
                    setState(() => _existingExtraUnits.remove(unit));
                    DataRefreshService.instance.notifyProductChanged();
                  },
                ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Илова кардани воҳиди нав',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextButton.icon(
                    onPressed: _totalExtraUnits >= _maxExtraUnits
                        ? null
                        : _addNewUnitRow,
                    icon: const Icon(Icons.add),
                    label: const Text('Илова кардан'),
                  ),
                ],
              ),
              Text(
                _totalExtraUnits >= _maxExtraUnits
                    ? 'Ҳадди аксар $_maxExtraUnits воҳиди иловагӣ барои як маҳсулот.'
                    : 'Воҳиди навро ҳамроҳ бо тугмаи "Нигоҳ доштан" дар поён захира кунед.',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              for (int i = 0; i < _newUnits.length; i++)
                _NewUnitCard(
                  row: _newUnits[i],
                  onRemove: () => _removeNewUnitRow(i),
                  onChanged: () => setState(() {}),
                  onGenerateBarcode: _apiService.generateBarcode,
                ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: Colors.blue,
                ),
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Нигоҳ доштан',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
