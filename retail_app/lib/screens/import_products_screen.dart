import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../services/api_service.dart';

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
    List<int>? bytes = file.bytes;

    // Читаем байты с диска, если они равны null (актуально для Android/iOS при больших файлах)
    if (bytes == null && file.path != null && !kIsWeb) {
      try {
        bytes = await File(file.path!).readAsBytes();
      } catch (e) {
        bytes = null;
      }
    }

    if (bytes == null) {
      if (!mounted) return;
      setState(() => _error = 'Файлро хонда нашуд.');
      return;
    }

    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _pickedFileName = file.name;
    });

    final response = await _api.importProductsExcel(bytes, file.name);

    // Безопасный вызов setState после асинхронного запроса к API
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (response == null) {
        _error = 'Файл боргузорӣ нашуд. Шояд шумо ба интернет пайваст нестед.';
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
          'Ворид кардани маҳсулот аз Excel',
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
                  'Формати файл (.xlsx)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Сатри аввал сарлавҳа аст; аз он ҳисобида намешавад ҳамчун маҳсулот. Сутунҳо бо ин тартиб пайравӣ мекунанд:',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 8),
                const _ColumnRow(letter: 'A', label: 'Ном'),
                const _ColumnRow(letter: 'B', label: 'Штрихкод'),
                const _ColumnRow(letter: 'C', label: 'Нархи харид'),
                const _ColumnRow(letter: 'D', label: 'Нархи фурӯш'),
                const _ColumnRow(
                  letter: 'E',
                  label:
                      'Миқдор (метавонед адади касрӣ низ дохил кунед, масалан, 2,5)',
                ),
                const _ColumnRow(letter: 'F', label: "Воҳид: 'дона' ё 'кг'"),
                const SizedBox(height: 8),
                Text(
                  'Маҳсулоте ки штрих-кодаш мавҷуд аст нав карда мешавад, дигар маҳсулотҳо ҳамчун нав илова карда мешаванд.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Воҳидҳои иловагӣ (масалан, упаковка/блок)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Агар маҳсулот на танҳо донагӣ, балки ҳамчун упаковка ё блок ҳам фурӯхта шавад, '
                  'пас аз сутуни F метавонед гурӯҳҳои 4-сутунаро илова кунед (ҳар воҳиди иловагӣ — '
                  'як гурӯҳ). Метавонед якчанд гурӯҳ пай дар пай нависед, агар якчанд воҳид лозим бошад:',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 8),
                const _ColumnRow(
                  letter: 'G',
                  label: 'Номи воҳид (масалан, "упаковка")',
                ),
                const _ColumnRow(
                  letter: 'H',
                  label: 'Дар як воҳид чанд дона (масалан, 20)',
                ),
                const _ColumnRow(letter: 'I', label: 'Нархи фурӯши ин воҳид'),
                const _ColumnRow(
                  letter: 'J',
                  label: 'Штрихкоди ин воҳид (ихтиёрӣ)',
                ),
                const SizedBox(height: 6),
                Text(
                  'Барои воҳиди дуюми иловагӣ ҳамин гурӯҳро дар сутунҳои K, L, M, N нависед, '
                  'барои сеюм — дар O, P, Q, R. Ҳамагӣ на бештар аз 3 воҳиди иловагӣ барои як '
                  'маҳсулот: агар дар сутунҳои аз R зиёд боз як гурӯҳ нависед, ин сатр бо хато рад '
                  'карда мешавад. Агар сутуни номи воҳид (G, K, O) холи бошад, маънои онро дорад, ки '
                  'воҳиди иловагӣ дар ин сатр нест — ин хато нест.',
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
                _loading ? 'Боркунӣ...' : 'Файли Excel-ро интихоб кунед',
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
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
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
                        'Воридот анҷом ёфт',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Маҳсулоти нав сохта шуд: ${_result!['created'] ?? 0}'),
                  Text('Маҳсулотҳои тағйир ёфта: ${_result!['updated'] ?? 0}'),
                  if ((_result!['errors'] as List?)?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Старҳои хато (${(_result!['errors'] as List).length}):',
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
                            'Сатр ${e['row']}: ${e['message']}',
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
