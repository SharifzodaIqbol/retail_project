import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Экран загрузки товаров из Excel-файла (.xlsx).
///
/// Ожидаемый формат файла (первая строка — заголовок, она пропускается):
/// Колонка A: название
/// Колонка B: штрихкод
/// Колонка C: цена закупки
/// Колонка D: цена продажи
/// Колонка E: остаток (для "кг" можно дробное число, напр. 2.5)
/// Колонка F: единица измерения — "шт" или "кг"
///
/// Товар с уже существующим в компании штрихкодом будет обновлён,
/// новый штрихкод — создаст новый товар.
class ImportProductsScreen extends StatefulWidget {
  const ImportProductsScreen({super.key});

  @override
  State<ImportProductsScreen> createState() => _ImportProductsScreenState();
}

class _ImportProductsScreenState extends State<ImportProductsScreen> {
  final _api = ApiService();
  bool _loading = false;
  String? _pickedFileName;
  Map<String, dynamic>? _result;
  String? _error;

  Future<void> _pickAndUpload() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.first;
    if (file.bytes == null) {
      setState(() => _error = 'Не удалось прочитать файл');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _pickedFileName = file.name;
    });

    final response = await _api.importProductsExcel(file.bytes!, file.name);

    setState(() {
      _loading = false;
      if (response == null) {
        _error = 'Не удалось загрузить файл. Проверьте соединение.';
      } else if (response.containsKey('error')) {
        _error = response['error'].toString();
      } else {
        _result = response;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'Загрузка товаров из Excel',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Формат файла (.xlsx)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Первая строка — заголовок, она пропускается. Дальше колонки в этом порядке:',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 8),
                const _ColumnRow(letter: 'A', label: 'Название'),
                const _ColumnRow(letter: 'B', label: 'Штрихкод'),
                const _ColumnRow(letter: 'C', label: 'Цена закупки'),
                const _ColumnRow(letter: 'D', label: 'Цена продажи'),
                const _ColumnRow(letter: 'E', label: 'Остаток (для кг — можно дробный, напр. 2.5)'),
                const _ColumnRow(letter: 'F', label: "Единица: 'шт' или 'кг'"),
                const SizedBox(height: 8),
                Text(
                  'Товар с уже существующим штрихкодом будет обновлён, остальные — добавлены как новые.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _pickAndUpload,
              icon: const Icon(Icons.upload_file),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F6EF7),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              label: Text(
                _loading ? 'Загрузка...' : 'Выбрать Excel-файл',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
          if (_pickedFileName != null) ...[
            const SizedBox(height: 8),
            Text(
              'Файл: $_pickedFileName',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
          if (_loading) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_error != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ),
          ],
          if (_result != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 8),
                      const Text(
                        'Импорт завершён',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Создано новых товаров: ${_result!['created'] ?? 0}'),
                  Text('Обновлено товаров: ${_result!['updated'] ?? 0}'),
                  if ((_result!['errors'] as List?)?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Строки с ошибками (${(_result!['errors'] as List).length}):',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...List<Widget>.from(
                      (_result!['errors'] as List).map(
                        (e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            'Строка ${e['row']}: ${e['message']}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ColumnRow extends StatelessWidget {
  final String letter;
  final String label;
  const _ColumnRow({required this.letter, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF4F6EF7).withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              letter,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF4F6EF7),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}
