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

/// Карточка УЖЕ существующей доп. единицы продажи — редактируется и
/// сохраняется/удаляется независимо от основной формы, своей собственной
/// кнопкой (сразу через API).
class ExistingUnitCard extends StatefulWidget {
  final ProductUnit unit;
  final Future<String?> Function(Map<String, dynamic> data) onSave;
  final Future<String?> Function() onDelete;
  final Future<String?> Function() onGenerateBarcode;
  final VoidCallback onDeleted;

  const ExistingUnitCard({
    super.key,
    required this.unit,
    required this.onSave,
    required this.onDelete,
    required this.onGenerateBarcode,
    required this.onDeleted,
  });

  @override
  State<ExistingUnitCard> createState() => _ExistingUnitCardState();
}

class _ExistingUnitCardState extends State<ExistingUnitCard> {
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
              BarcodePreviewCard(data: _barcodeCtrl.text.trim()),
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
