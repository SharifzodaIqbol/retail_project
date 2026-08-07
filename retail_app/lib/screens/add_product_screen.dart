import 'package:flutter/material.dart';
import 'package:barcode_widget/barcode_widget.dart';
import '../services/api_service.dart';
import '../services/data_refresh_service.dart';
import 'package:retail_app/widgets/barcode_scanner.dart';

/// Карточка одной доп. единицы продажи в форме добавления товара:
/// название ("упаковка"), сколько штук внутри, и НЕЗАВИСИМАЯ цена за неё.
class _ExtraUnitCard extends StatefulWidget {
  final _ExtraUnitRow row;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  final Future<String?> Function() onGenerateBarcode;

  const _ExtraUnitCard({
    required this.row,
    required this.onRemove,
    required this.onChanged,
    required this.onGenerateBarcode,
  });

  @override
  State<_ExtraUnitCard> createState() => _ExtraUnitCardState();
}

class _ExtraUnitCardState extends State<_ExtraUnitCard> {
  // Свой индикатор загрузки на каждую карточку — чтобы генерация
  // штрихкода для одной доп. единицы не блокировала кнопки у остальных.
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
              // Перерисовываем карточку при вводе, чтобы превью снизу
              // появлялось/исчезало и обновлялось само — так же, как это
              // уже работает для основного штрихкода товара.
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

/// Карточка с картинкой штрихкода под полем ввода — и для отсканированного,
/// и для сгенерированного, и для введённого вручную кода. Смысл: продавец
/// сразу видит готовое изображение, которое можно сфотографировать и
/// распечатать/наклеить на товар, не открывая товар заново после сохранения.
/// Code128 выбран вместо EAN13, потому что он кодирует ЛЮБУЮ строку
/// (сканер может вернуть код другого формата, не только 13-значный).
class _BarcodePreviewCard extends StatelessWidget {
  final String data;

  const _BarcodePreviewCard({required this.data});

  // Фиксированная ширина превью, одинаковая на телефоне, ноуте и вебе.
  // Без явного width BarcodeWidget растягивается на всю ширину родителя,
  // а на широких экранах (десктоп/веб) это даёт нечитаемый, "размазанный"
  // штрихкод с огромными промежутками между штрихами.
  static const double _previewWidth = 260;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.grey.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Center(
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
          ],
        ),
      ),
    );
  }
}

class AddProductScreen extends StatefulWidget {
  @override
  _AddProductScreenState createState() => _AddProductScreenState();
}

/// Одна строка "дополнительной единицы продажи" (упаковка/блок/коробка...)
/// в форме создания товара. Цена вводится независимо от базовой цены за
/// штуку — на практике штука иногда стоит даже дороже 1/N от упаковки.
class _ExtraUnitRow {
  final labelController = TextEditingController();
  final factorController = TextEditingController(); // сколько штук в упаковке
  final priceController = TextEditingController(); // цена за ВСЮ упаковку
  final barcodeController = TextEditingController();

  void dispose() {
    labelController.dispose();
    factorController.dispose();
    priceController.dispose();
    barcodeController.dispose();
  }
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ApiService();
  bool _loading = false;

  final _nameController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _buyPriceController = TextEditingController();
  final _sellPriceController = TextEditingController();
  final _stockController = TextEditingController();

  String _unit = 'pcs';

  // Доп. единицы продажи (упаковка и т.п.), заводимые вместе с товаром.
  final List<_ExtraUnitRow> _extraUnits = [];

  // Больше 3 доп. единиц продавцу практически никогда не нужно (штука +
  // упаковка + блок), а бесконечный список ломает форму и усложняет
  // сохранение/печать штрихкодов. Тот же лимит применяется и на сервере
  // (createProductUnit, импорт из Excel) — так что даже если это значение
  // случайно разойдётся, сервер всё равно не даст завести больше.
  static const int _maxExtraUnits = 3;

  // true, пока идёт запрос свободного штрихкода на сервер — блокирует кнопку
  // "Сохтан" (сгенерировать), чтобы продавец не наплодил параллельных
  // запросов повторными тапами.
  bool _generatingBarcode = false;

  @override
  void initState() {
    super.initState();
    // Перерисовываем экран при любом изменении штрихкода (вручную,
    // сканером или генератором), чтобы карточка-превью со штрихкодом под
    // полем появлялась/исчезала и обновлялась сама, без отдельной кнопки
    // "показать".
    _barcodeController.addListener(_onBarcodeChanged);
  }

  void _onBarcodeChanged() => setState(() {});

  /// Просит сервер подобрать свободный внутренний штрихкод и подставляет
  /// его в поле — сразу видно и значение, и штрихкод-картинку снизу, можно
  /// сфотографировать/распечатать и наклеить на товар до сохранения.
  Future<void> _generateBarcode() async {
    setState(() => _generatingBarcode = true);
    final barcode = await _apiService.generateBarcode();
    if (!mounted) return;
    setState(() => _generatingBarcode = false);

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

  void _addExtraUnitRow() {
    if (_extraUnits.length >= _maxExtraUnits) return;
    setState(() => _extraUnits.add(_ExtraUnitRow()));
  }

  void _removeExtraUnitRow(int index) {
    setState(() => _extraUnits.removeAt(index).dispose());
  }

  @override
  void dispose() {
    _barcodeController.removeListener(_onBarcodeChanged);
    _nameController.dispose();
    _barcodeController.dispose();
    _buyPriceController.dispose();
    _sellPriceController.dispose();
    _stockController.dispose();
    for (final row in _extraUnits) {
      row.dispose();
    }
    super.dispose();
  }

  /// Нормализует ввод: заменяет запятую на точку и убирает пробелы.
  double? _parseNumber(String raw) =>
      double.tryParse(raw.trim().replaceAll(',', '.'));

  /// Валидирует строки доп. единиц продажи. Возвращает текст первой найденной
  /// ошибки, либо null если всё заполнено корректно. Строки с полностью
  /// пустым названием пропускаются (значит продавец начал добавлять строку,
  /// но передумал — не считаем это ошибкой).
  String? _validateExtraUnits() {
    for (final row in _extraUnits) {
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

  void _submitData() async {
    if (!_formKey.currentState!.validate()) return;

    final extraUnitsError = _validateExtraUnits();
    if (extraUnitsError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(extraUnitsError),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    final buyPrice = _parseNumber(_buyPriceController.text)!;
    final sellPrice = _parseNumber(_sellPriceController.text)!;
    final stock = _parseNumber(_stockController.text)!;

    // Дополнительная межполевая проверка
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
      "stock": stock,
      "unit": _unit,
    };

    final result = await _apiService.addProduct(productData);

    if (!result.isSuccess) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage!),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    // Базовый товар создан — теперь по очереди добавляем доп. единицы
    // продажи (упаковка/блок...), если продавец их заполнил. Товар уже
    // существует на сервере, поэтому ошибка здесь — это ошибка ОДНОЙ
    // единицы, а не всего товара целиком, и не откатывает уже созданный товар.
    final unitErrors = <String>[];
    for (final row in _extraUnits) {
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
        result.productId!,
        unitData,
      );
      if (unitError != null) {
        unitErrors.add('$label: $unitError');
      }
    }

    if (!mounted) return;
    setState(() => _loading = false);

    // Сообщаем складу (InventoryScreen), что каталог изменился — без
    // этого новый товар был виден только после ручного pull-to-refresh,
    // потому что список товаров кэшируется в состоянии экрана и не
    // перечитывается сам по себе.
    DataRefreshService.instance.notifyProductChanged();
    Navigator.pop(context);

    if (unitErrors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Маҳсулот бо муваффақият илова карда шуд!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      // Товар создан, но какие-то доп. единицы не сохранились (например,
      // штрихкод уже занят) — продавец должен об этом узнать явно, а не
      // молча остаться без второй единицы продажи.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Маҳсулот илова шуд, аммо баъзе воҳидҳо не: ${unitErrors.join("; ")}',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  String? _validatePrice(String? v, String label) {
    if (v == null || v.trim().isEmpty) return '$label ворид кунед';
    final parsed = _parseNumber(v);
    if (parsed == null) return 'Рақами нодуруст (масалан: 12.50)';
    if (parsed < 0) return '$label манфӣ буда наметавонад';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Маҳсулоти нав')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
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
                  labelText:
                      'Штрихкод (ихтиёрӣ)', // Можно добавить надпись "необязательно"
                  prefixIcon: const Icon(Icons.qr_code),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Товар без штрихкода — самый частый случай для
                      // местных/весовых товаров без заводской упаковки.
                      // Одним тапом получаем от сервера свободный код,
                      // ничего не печатая руками.
                      _generatingBarcode
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
                            setState(
                              () => _barcodeController.text = scannedCode,
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
                // Валидатор удален или возвращает null, поэтому ругаться не будет
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
                      onChanged: (_) =>
                          setState(() {}), // обновить sell validator
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _stockController,
                      decoration: InputDecoration(
                        labelText: 'Миқдор',
                        hintText: _unit == 'kg' ? '0.000' : '0',
                        helperText: _unit == 'kg'
                            ? 'Адади касрӣ иҷозат дода мешавад, мас: 2.5'
                            : null,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Миқдорро ворид кунед';
                        }
                        final parsed = _parseNumber(v);
                        if (parsed == null) {
                          return 'Рақами нодуруст (мас: 10 ё 2.5)';
                        }
                        if (parsed < 0) {
                          return 'Миқдор манфӣ буда наметавонад';
                        }
                        if (_unit == 'pcs' &&
                            parsed != parsed.truncateToDouble()) {
                          return 'Барои "дона" танҳо ададҳои бутун';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: DropdownButtonFormField<String>(
                      value: _unit,
                      decoration: const InputDecoration(labelText: 'Воҳид'),
                      items: const [
                        DropdownMenuItem(value: 'pcs', child: Text('дона')),
                        DropdownMenuItem(value: 'kg', child: Text('кг')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _unit = v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Воҳидҳои иловагӣ (масалан, қуттӣ)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextButton.icon(
                    onPressed: _extraUnits.length >= _maxExtraUnits
                        ? null
                        : _addExtraUnitRow,
                    icon: const Icon(Icons.add),
                    label: const Text('Илова кардан'),
                  ),
                ],
              ),
              Text(
                _extraUnits.length >= _maxExtraUnits
                    ? 'Ҳадди аксар $_maxExtraUnits воҳиди иловагӣ барои як маҳсулот.'
                    : 'Ихтиёрӣ: агар маҳсулот ҳам донагӣ, ҳам қуттигӣ фурӯхта шавад — '
                          'нархи қуттиро мустақилона нависед (на ба таври автоматӣ '
                          'ҳисобшуда аз нархи як дона).',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              for (int i = 0; i < _extraUnits.length; i++)
                _ExtraUnitCard(
                  row: _extraUnits[i],
                  onRemove: () => _removeExtraUnitRow(i),
                  onChanged: () => setState(() {}),
                  onGenerateBarcode: _apiService.generateBarcode,
                ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _loading ? null : _submitData,
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
                        'Илова кардан',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
