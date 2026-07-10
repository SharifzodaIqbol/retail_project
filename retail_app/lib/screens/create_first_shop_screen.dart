import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Экран, который владелец видит один раз — сразу после регистрации/первого
/// входа, пока у него нет ни одного магазина. Без названия магазина дальше
/// пройти нельзя: вся касса/склад/продажи/должники существуют в рамках
/// конкретного магазина, поэтому хотя бы один магазин обязателен.
class CreateFirstShopScreen extends StatefulWidget {
  final VoidCallback onDone;

  const CreateFirstShopScreen({super.key, required this.onDone});

  @override
  State<CreateFirstShopScreen> createState() => _CreateFirstShopScreenState();
}

class _CreateFirstShopScreenState extends State<CreateFirstShopScreen> {
  final _api = ApiService();
  final _nameCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Номи мағозаро ворид кунед');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final shop = await _api.createShop(name);
    if (!mounted) return;
    setState(() => _saving = false);
    if (shop == null) {
      setState(() => _error = 'Хатогӣ рух дод. Аз нав кӯшиш кунед.');
      return;
    }
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4F6EF7).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.add_business,
                    color: Color(0xFF4F6EF7),
                    size: 44,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Хуш омадед!',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Барои шурӯъ, номи мағозаи худро ворид кунед. Баъдтар шумо '
                  'метавонед боз чанд мағоза илова кунед ва байни онҳо '
                  'гузаред — ҳар мағоза анбор, фурӯш ва маълумоти худро дорад.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, height: 1.4),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _nameCtrl,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Номи мағоза',
                    hintText: 'Мисол: Мағозаи марказӣ',
                    errorText: _error,
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F6EF7),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'Идома',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
