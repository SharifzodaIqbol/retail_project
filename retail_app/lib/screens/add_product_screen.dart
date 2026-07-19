import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/data_refresh_service.dart';
import 'package:retail_app/widgets/barcode_scanner.dart';

class AddProductScreen extends StatefulWidget {
  @override
  _AddProductScreenState createState() => _AddProductScreenState();
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

  @override
  void dispose() {
    _nameController.dispose();
    _barcodeController.dispose();
    _buyPriceController.dispose();
    _sellPriceController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  /// Нормализует ввод: заменяет запятую на точку и убирает пробелы.
  double? _parseNumber(String raw) =>
      double.tryParse(raw.trim().replaceAll(',', '.'));

  void _submitData() async {
    if (!_formKey.currentState!.validate()) return;

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

    final error = await _apiService.addProduct(productData);

    if (!mounted) return;
    setState(() => _loading = false);

    if (error == null) {
      // Сообщаем складу (InventoryScreen), что каталог изменился — без
      // этого новый товар был виден только после ручного pull-to-refresh,
      // потому что список товаров кэшируется в состоянии экрана и не
      // перечитывается сам по себе.
      DataRefreshService.instance.notifyProductChanged();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Маҳсулот бо муваффақият илова карда шуд!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
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
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.camera_alt, color: Colors.blue),
                    onPressed: () async {
                      final String? scannedCode = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => BarcodeScannerWidget(),
                        ),
                      );
                      if (scannedCode != null) {
                        setState(() => _barcodeController.text = scannedCode);
                      }
                    },
                  ),
                ),
                // Валидатор удален или возвращает null, поэтому ругаться не будет
              ),
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
