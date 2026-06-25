import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'package:retail_app/widgets/barcode_scanner.dart';

class AddProductScreen extends StatefulWidget {
  @override
  _AddProductScreenState createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ApiService();

  // Контроллеры для полей
  final _nameController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _buyPriceController = TextEditingController();
  final _sellPriceController = TextEditingController();
  final _stockController = TextEditingController();

  // Единица измерения: 'pcs' (шт) или 'kg' (кг)
  String _unit = 'pcs';

  void _submitData() async {
    if (!_formKey.currentState!.validate()) return;

    final productData = {
      "name": _nameController.text,
      "barcode": _barcodeController.text,
      "buy_price": double.parse(_buyPriceController.text),
      "sell_price": double.parse(_sellPriceController.text),
      // Остаток теперь double — для "кг" допускаются дробные значения (например, 2.5)
      "stock": double.parse(_stockController.text.replaceAll(',', '.')),
      "unit": _unit,
    };

    final success = await _apiService.addProduct(productData);

    if (success) {
      Navigator.pop(context); // Возвращаемся назад
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Товар успешно добавлен!')));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ошибка при сохранении')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новый товар')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Название товара'),
                validator: (v) => v!.isEmpty ? 'Введите название' : null,
              ),
              TextFormField(
                controller: _barcodeController,
                decoration: InputDecoration(
                  labelText: 'Штрихкод',
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
                        setState(() {
                          _barcodeController.text = scannedCode;
                        });
                      }
                    },
                  ),
                ),
                validator: (v) =>
                    v!.isEmpty ? 'Сканируйте или введите код' : null,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _buyPriceController,
                      decoration: const InputDecoration(
                        labelText: 'Цена закупа',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) => v!.isEmpty ? '?' : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _sellPriceController,
                      decoration: const InputDecoration(
                        labelText: 'Цена продажи',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) => v!.isEmpty ? '?' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _stockController,
                      decoration: InputDecoration(
                        labelText: 'Количество на складе',
                        helperText: _unit == 'kg'
                            ? 'Можно указать дробное значение, напр. 2.5'
                            : null,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Введите остаток';
                        final parsed = double.tryParse(v.replaceAll(',', '.'));
                        if (parsed == null) return 'Неверное число';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 1,
                    child: DropdownButtonFormField<String>(
                      value: _unit,
                      decoration: const InputDecoration(labelText: 'Единица'),
                      items: const [
                        DropdownMenuItem(value: 'pcs', child: Text('шт')),
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
                onPressed: _submitData,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: Colors.blue,
                ),
                child: const Text(
                  'СОХРАНИТЬ',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
