import 'package:flutter/material.dart';
import 'package:barcode_widget/barcode_widget.dart';
import '../models/product.dart';
import 'barcode_scanner.dart';

/// Карточка с картинкой штрихкода под полем ввода.
class BarcodePreviewCard extends StatelessWidget {
  final String data;

  const BarcodePreviewCard({super.key, required this.data});

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
/// редактирования (ещё не существует на сервере).
class NewUnitRow {
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

/// Карточка новой (ещё не сохранённой) доп. единицы.
class NewUnitCard extends StatefulWidget {
  final NewUnitRow row;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  final Future<String?> Function() onGenerateBarcode;

  const NewUnitCard({
    super.key,
    required this.row,
    required this.onRemove,
    required this.onChanged,
    required this.onGenerateBarcode,
  });

  @override
  State<NewUnitCard> createState() => _NewUnitCardState();
}

class _NewUnitCardState extends State<NewUnitCard> {
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
              BarcodePreviewCard(data: row.barcodeController.text.trim()),
            ],
          ],
        ),
      ),
    );
  }
}

/// Строка УЖЕ существующей доп. единицы продажи — контроллеры живут здесь
/// (а не внутри карточки), чтобы родительский диалог мог прочитать текущие
/// значения и решить, что именно изменилось, когда нажата ОБЩАЯ кнопка
/// "Захира кардан". Своей кнопки сохранения у карточки больше нет —
/// см. ExistingUnitCard.
class ExistingUnitRow {
  final ProductUnit unit;
  late final TextEditingController labelController;
  late final TextEditingController factorController;
  late final TextEditingController priceController;
  late final TextEditingController barcodeController;

  ExistingUnitRow(this.unit)
    : labelController = TextEditingController(text: unit.label),
      factorController = TextEditingController(
        text: _trimNum(unit.conversionFactor),
      ),
      priceController = TextEditingController(
        text: unit.price.toStringAsFixed(2),
      ),
      barcodeController = TextEditingController(text: unit.barcode ?? '');

  static String _trimNum(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toString();
  }

  double? _parseNum(String raw) =>
      double.tryParse(raw.trim().replaceAll(',', '.'));

  /// true, если поля отличаются от исходных значений юнита — используется,
  /// чтобы не слать PUT на сервер зря, если ничего не поменяли.
  bool get isChanged {
    final label = labelController.text.trim();
    final factor = _parseNum(factorController.text);
    final price = _parseNum(priceController.text);
    final barcode = barcodeController.text.trim().isEmpty
        ? null
        : barcodeController.text.trim();
    return label != unit.label ||
        factor != unit.conversionFactor ||
        price != unit.price ||
        barcode != unit.barcode;
  }

  /// null, если поля некорректны (пустое имя/коэффициент/цена) — вызывающий
  /// код должен считать это ошибкой ввода, а не "нечего сохранять".
  Map<String, dynamic>? toUpdateData() {
    final label = labelController.text.trim();
    if (label.isEmpty) return null;
    final factor = _parseNum(factorController.text);
    if (factor == null || factor <= 0) return null;
    final price = _parseNum(priceController.text);
    if (price == null || price < 0) return null;
    return {
      'label': label,
      'conversion_factor': factor,
      'price': price,
      'barcode': barcodeController.text.trim().isEmpty
          ? null
          : barcodeController.text.trim(),
    };
  }

  void dispose() {
    labelController.dispose();
    factorController.dispose();
    priceController.dispose();
    barcodeController.dispose();
  }
}

/// Карточка уже существующей доп. единицы продажи. Только редактирование
/// полей "на месте" — сохранение и удаление происходят централизованно,
/// когда нажата общая кнопка "Захира кардан" в родительском диалоге.
/// "Нест кардан" здесь лишь убирает карточку из списка (родитель запомнит
/// unit.id и удалит его на сервере при сохранении); реальный API-вызов
/// происходит только после подтверждения общего сохранения.
class ExistingUnitCard extends StatefulWidget {
  final ExistingUnitRow row;
  final Future<String?> Function() onGenerateBarcode;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const ExistingUnitCard({
    super.key,
    required this.row,
    required this.onGenerateBarcode,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  State<ExistingUnitCard> createState() => _ExistingUnitCardState();
}

class _ExistingUnitCardState extends State<ExistingUnitCard> {
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

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Нест кардани воҳид'),
        content: Text(
          '"${widget.row.unit.label}"-ро нест кардан мехоҳед? Тағйирот бо тугмаи "Захира кардан" татбиқ мешавад.',
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
    if (confirmed == true) widget.onRemove();
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
                    decoration: const InputDecoration(labelText: 'Ном'),
                    onChanged: (_) => widget.onChanged(),
                  ),
                ),
                IconButton(
                  tooltip: 'Нест кардан',
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: _remove,
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
                    ),
                    onChanged: (_) => widget.onChanged(),
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
                    ),
                    onChanged: (_) => widget.onChanged(),
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
              BarcodePreviewCard(data: row.barcodeController.text.trim()),
            ],
          ],
        ),
      ),
    );
  }
}
