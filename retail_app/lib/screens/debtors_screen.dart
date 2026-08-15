import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';

class DebtorsScreen extends StatefulWidget {
  final String role; // 'owner' | 'seller'

  const DebtorsScreen({super.key, required this.role});

  @override
  State<DebtorsScreen> createState() => _DebtorsScreenState();
}

class _DebtorsScreenState extends State<DebtorsScreen> {
  final _api = ApiService();
  List<dynamic> _debtors = [];
  bool _loading = true;

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() {
      setState(() {
        _searchQuery = _searchCtrl.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // Список должников с учётом поиска по имени (или телефону).
  List<dynamic> get _filteredDebtors {
    if (_searchQuery.isEmpty) return _debtors;
    return _debtors.where((d) {
      final name = (d['full_name'] ?? '').toString().toLowerCase();
      final phone = (d['phone'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery) || phone.contains(_searchQuery);
    }).toList();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _api.getDebtors();
    setState(() {
      _debtors = data;
      _loading = false;
    });
  }

  // Функция для красивого отображения телефона в карточке (+992 918 12-34-56)
  String _formatDisplayPhone(String phone) {
    if (phone.isEmpty) return '';
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    if (clean.length == 12 && clean.startsWith('992')) {
      return '+992 ${clean.substring(3, 6)} ${clean.substring(6, 8)}-${clean.substring(8, 10)}-${clean.substring(10, 12)}';
    }
    return phone;
  }

  // ─── Добавить должника ──────────────────────────────────────────────────

  void _showAddDebtorDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String? nameError;
    String? phoneError;
    String? amountError;
    bool saving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Илова кардани қарздор'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  maxLength: 50,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  onChanged: (_) => setDialogState(() => nameError = null),
                  decoration: InputDecoration(
                    labelText: 'Номи қарздор *',
                    border: const OutlineInputBorder(),
                    errorText: nameError,
                    counterText: '',
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  maxLength: 12,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  inputFormatters: [PhoneInputFormatter()],
                  onChanged: (_) => setDialogState(() => phoneError = null),
                  decoration: InputDecoration(
                    labelText: 'Телефон (ихтиёрӣ)',
                    border: const OutlineInputBorder(),
                    errorText: phoneError,
                    counterText: '',
                    hintText: '918 12-34-56',
                    prefixIcon: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 12),
                        Text('🇹🇯 +992 ', style: TextStyle(fontSize: 16)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  maxLength: 12,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                  ],
                  onChanged: (_) => setDialogState(() => amountError = null),
                  decoration: InputDecoration(
                    labelText: 'Миқдори қарз (сомонӣ)',
                    border: const OutlineInputBorder(),
                    helperText: '0 — агар қарз ҳоло нест',
                    errorText: amountError,
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  maxLength: 200,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  decoration: const InputDecoration(
                    labelText: 'Фаҳмондадиҳи (ихтиёрӣ)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('Бекор кардан'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F6EF7),
              ),
              onPressed: saving
                  ? null
                  : () async {
                      bool hasError = false;

                      // Очистка от лишних пробелов в имени
                      final cleanName = nameCtrl.text.trim().replaceAll(
                        RegExp(r'\s+'),
                        ' ',
                      );
                      // Извлекаем строго только цифры из телефона для валидации и базы
                      final phoneDigits = phoneCtrl.text.replaceAll(
                        RegExp(r'\D'),
                        '',
                      );
                      final formattedPhone = phoneDigits.isEmpty
                          ? ''
                          : '+992$phoneDigits';

                      // 1. Валидация имени
                      if (cleanName.isEmpty) {
                        setDialogState(
                          () => nameError = 'Номи қарздорро ворид кунед',
                        );
                        hasError = true;
                      } else if (cleanName.length < 2) {
                        setDialogState(() => nameError = 'Ном хеле кӯтоҳ аст');
                        hasError = true;
                      }

                      // 2. Валидация длины телефона
                      if (phoneDigits.isNotEmpty && phoneDigits.length != 9) {
                        setDialogState(
                          () =>
                              phoneError = 'Рақам бояд аз 9 рақам иборат бошад',
                        );
                        hasError = true;
                      }

                      // 3. Проверка на дубликаты в существующей базе (локально)
                      if (!hasError) {
                        final lowercaseName = cleanName.toLowerCase();
                        for (var debtor in _debtors) {
                          final existingName = (debtor['full_name'] ?? '')
                              .toString()
                              .trim()
                              .toLowerCase();
                          final existingPhone = (debtor['phone'] ?? '')
                              .toString()
                              .trim()
                              .replaceAll(RegExp(r'\D'), '');

                          if (existingName == lowercaseName) {
                            setDialogState(
                              () =>
                                  nameError = 'Қарздор бо ин ном аллакай ҳаст',
                            );
                            hasError = true;
                            break;
                          }
                          if (phoneDigits.isNotEmpty &&
                              existingPhone == '992$phoneDigits') {
                            setDialogState(
                              () => phoneError =
                                  'Қарздор бо ин телефон аллакай ҳаст',
                            );
                            hasError = true;
                            break;
                          }
                        }
                      }

                      // 4. Валидация числового ввода суммы
                      final rawAmount = amountCtrl.text.trim().isEmpty
                          ? '0'
                          : amountCtrl.text.trim().replaceAll(',', '.');

                      final dotCount = '.'.allMatches(rawAmount).length;
                      final amount = dotCount <= 1
                          ? double.tryParse(rawAmount)
                          : null;

                      if (amount == null) {
                        setDialogState(
                          () => amountError = 'Рақами нодуруст (мас: 150.00)',
                        );
                        hasError = true;
                      } else if (amount < 0) {
                        setDialogState(
                          () => amountError = 'Қарз манфӣ буда наметавонад',
                        );
                        hasError = true;
                      } else if (amount > 10000000) {
                        setDialogState(
                          () => amountError = 'Маблағ хеле калон аст',
                        );
                        hasError = true;
                      }

                      if (hasError) return;

                      setDialogState(() => saving = true);

                      final result = await _api.createDebtor(
                        fullName: cleanName,
                        phone: formattedPhone,
                        initialDebt: amount!,
                        note: noteCtrl.text.trim(),
                      );

                      if (!mounted) return;
                      setDialogState(() => saving = false);
                      Navigator.pop(context);

                      if (result != null) {
                        _load();
                        _showSnack('Қарздор илова карда шуд', Colors.green);
                      } else {
                        _showSnack(
                          'Хатогӣ дар илова. Пайвастшавиро санҷед.',
                          Colors.red,
                        );
                      }
                    },
              child: saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Захира', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Операция: оплата или добавление долга ──────────────────────────────

  void _showOperationDialog(Map<String, dynamic> debtor, String type) {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final isPay = type == 'pay';
    final totalDebt = (debtor['total_debt'] as num).toDouble();
    String? amountError;
    bool saving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            isPay ? '💳 Пардохтро ворид кунед' : '➕ Илова кардани қарз',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  debtor['full_name'],
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'Қарзи ҳозира: ${totalDebt.toStringAsFixed(2)} сомонӣ',
                  style: TextStyle(
                    color: totalDebt > 0 ? Colors.red.shade600 : Colors.green,
                    fontSize: 13,
                  ),
                ),
                if (isPay && totalDebt <= 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'Қарз пурра пардохта шудааст',
                          style: TextStyle(color: Colors.green, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: amountCtrl,
                  autofocus: true,
                  maxLength: 12,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                  ],
                  onChanged: (_) => setDialogState(() => amountError = null),
                  decoration: InputDecoration(
                    labelText: 'Маблағ (сомонӣ) *',
                    border: const OutlineInputBorder(),
                    errorText: amountError,
                    counterText: '',
                    suffix: isPay && totalDebt > 0
                        ? TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: () {
                              amountCtrl.text = totalDebt.toStringAsFixed(2);
                              setDialogState(() => amountError = null);
                            },
                            child: const Text('Ҳамааш'),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  maxLength: 200,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  decoration: const InputDecoration(
                    labelText: 'Фаҳмондадиҳи (ихтиёрӣ)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('Бекор кардан'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isPay ? Colors.green : const Color(0xFF4F6EF7),
              ),
              onPressed: saving || (isPay && totalDebt <= 0)
                  ? null
                  : () async {
                      final raw = amountCtrl.text.trim().replaceAll(',', '.');
                      final dotCount = '.'.allMatches(raw).length;
                      final amount = dotCount <= 1
                          ? double.tryParse(raw)
                          : null;

                      if (raw.isEmpty || amount == null) {
                        setDialogState(
                          () => amountError =
                              'Маблағро дуруст ворид кунед (мас: 50.00)',
                        );
                        return;
                      }
                      if (amount <= 0) {
                        setDialogState(
                          () => amountError = 'Маблағ бояд аз нол зиёд бошад',
                        );
                        return;
                      }
                      if (amount > 10000000) {
                        setDialogState(
                          () => amountError = 'Маблағ хеле калон аст',
                        );
                        return;
                      }
                      if (isPay && amount > totalDebt) {
                        setDialogState(
                          () => amountError =
                              'Пардохт (${amount.toStringAsFixed(2)}) аз қарз (${totalDebt.toStringAsFixed(2)}) зиёд аст',
                        );
                        return;
                      }

                      setDialogState(() => saving = true);

                      final result = await _api.debtOperation(
                        debtor['id'],
                        amount: amount,
                        type: type,
                        note: noteCtrl.text.trim(),
                      );

                      if (!mounted) return;
                      setDialogState(() => saving = false);
                      Navigator.pop(context);

                      if (result != null) {
                        _load();
                        _showSnack(
                          isPay
                              ? 'Пардохт сабт шудааст'
                              : 'Қарз илова карда шуд',
                          isPay ? Colors.green : Colors.orange,
                        );
                      } else {
                        _showSnack(
                          'Хатои амалиёт. Пайвастшавиро санҷед.',
                          Colors.red,
                        );
                      }
                    },
              child: saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      isPay ? 'Пардохтро сабт кунед' : 'Иловаи қарз',
                      style: const TextStyle(color: Colors.white),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── История операций ───────────────────────────────────────────────────

  void _showHistory(Map<String, dynamic> debtor) async {
    final history = await _api.getDebtHistory(debtor['id']);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.history, color: Color(0xFF4F6EF7)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Таърих: ${debtor['full_name']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: history.isEmpty
                  ? const Center(child: Text('Амалиёт нест'))
                  : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: history.length,
                      itemBuilder: (_, i) {
                        final h = history[i];
                        final isPay = h['type'] == 'pay';
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isPay
                                ? Colors.green.shade50
                                : Colors.red.shade50,
                            child: Icon(
                              isPay ? Icons.arrow_downward : Icons.arrow_upward,
                              color: isPay ? Colors.green : Colors.red,
                              size: 18,
                            ),
                          ),
                          title: Text(
                            '${isPay ? '−' : '+'}${(h['amount'] as num).toStringAsFixed(2)} сомонӣ',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isPay
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((h['note'] ?? '').isNotEmpty)
                                Text(
                                  h['note'],
                                  style: const TextStyle(fontSize: 12),
                                ),
                              Text(
                                _formatDate(h['created_at'] ?? ''),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Удалить должника ───────────────────────────────────────────────────

  Future<void> _deleteDebtor(Map<String, dynamic> debtor) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Номи қарздорро нест кунем?'),
        content: Text(
          '«${debtor['full_name']}» бо тамоми таърих нест карда мешавад.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Бекор кардан'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Нест кардан',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final ok = await _api.deleteDebtor(debtor['id']);
      if (ok && mounted) {
        _load();
        _showSnack('Номи қарздор нест шуд', Colors.grey);
      }
    }
  }

  // ─── Вспомогательные ────────────────────────────────────────────────────

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}  '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final totalDebt = _debtors.fold<double>(
      0,
      (sum, d) => sum + (d['total_debt'] as num).toDouble(),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'Дафтарчаи қарз',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDebtorDialog,
        backgroundColor: const Color(0xFF4F6EF7),
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text(
          'Илова кардан',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: Column(
                children: [
                  // ─── Итоговый баннер ──────────────────────────
                  if (_debtors.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.red.shade400, Colors.red.shade700],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.account_balance_wallet,
                            color: Colors.white,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Умуми қарз',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                '${totalDebt.toStringAsFixed(2)} сомонӣ',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            '${_debtors.length} одам',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ─── Поиск по имени ───────────────────────────
                  if (_debtors.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText:
                              'Исм ё шумора телефони қарздорро ворид кунед...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () => _searchCtrl.clear(),
                                )
                              : null,
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 0,
                            horizontal: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                      ),
                    ),

                  // ─── Список ──────────────────────────────────
                  Expanded(
                    child: _debtors.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.book_outlined,
                                  size: 64,
                                  color: Colors.grey.shade300,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Ҳеҷ кас қарздор нест',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _filteredDebtors.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.search_off,
                                  size: 64,
                                  color: Colors.grey.shade300,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Ҷустуҷӯ натиҷа надод',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                            itemCount: _filteredDebtors.length,
                            itemBuilder: (_, i) {
                              final debtor = _filteredDebtors[i];
                              return _DebtorCard(
                                debtor: debtor,
                                isOwner: widget.role == 'owner',
                                onPay: () =>
                                    _showOperationDialog(debtor, 'pay'),
                                onTake: () =>
                                    _showOperationDialog(debtor, 'take'),
                                onHistory: () => _showHistory(debtor),
                                onDelete: () => _deleteDebtor(debtor),
                                formattedPhone: _formatDisplayPhone(
                                  debtor['phone'] ?? '',
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ─── Карточка одного должника ─────────────────────────────────────────────────

class _DebtorCard extends StatelessWidget {
  final Map<String, dynamic> debtor;
  final bool isOwner;
  final VoidCallback onPay;
  final VoidCallback onTake;
  final VoidCallback onHistory;
  final VoidCallback onDelete;
  final String formattedPhone; // Передаем уже отформатированный номер

  const _DebtorCard({
    required this.debtor,
    required this.isOwner,
    required this.onPay,
    required this.onTake,
    required this.onHistory,
    required this.onDelete,
    required this.formattedPhone,
  });

  @override
  Widget build(BuildContext context) {
    final debt = (debtor['total_debt'] as num).toDouble();
    final isPaid = debt <= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        children: [
          // ─── Шапка карточки ─────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: isPaid
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  child: Text(
                    (debtor['full_name'] as String).isNotEmpty
                        ? (debtor['full_name'] as String)[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: isPaid ? Colors.green : Colors.red.shade700,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        debtor['full_name'],
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      if (formattedPhone.isNotEmpty)
                        Text(
                          formattedPhone,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                // Долг
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      isPaid
                          ? '✅ Пардохт шуд'
                          : '${debt.toStringAsFixed(2)} сомонӣ',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: isPaid ? Colors.green : Colors.red.shade700,
                      ),
                    ),
                    const Text(
                      'қарз',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ─── Кнопки действий ──────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                // Оплата
                Expanded(
                  child: _ActionBtn(
                    label: 'Пардохт',
                    icon: Icons.payments_outlined,
                    color: Colors.green,
                    onTap: onPay,
                  ),
                ),
                const SizedBox(width: 8),
                // Добавить долг
                Expanded(
                  child: _ActionBtn(
                    label: '+ Қарз',
                    icon: Icons.add_circle_outline,
                    color: const Color(0xFF4F6EF7),
                    onTap: onTake,
                  ),
                ),
                const SizedBox(width: 8),
                // История
                _IconBtn(
                  icon: Icons.history,
                  color: Colors.grey.shade600,
                  tooltip: 'Таърих',
                  onTap: onHistory,
                ),
                // Удалить (только owner)
                if (isOwner)
                  _IconBtn(
                    icon: Icons.delete_outline,
                    color: Colors.red,
                    tooltip: 'Тоза кардан',
                    onTap: onDelete,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

// ─── Исправленный форматтер маски для удобного ввода номера ─────────────────

class PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // 1. Извлекаем только цифры
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    // 2. Если пользователь ввел больше 9 цифр, отклоняем ввод нового символа
    if (digits.length > 9) {
      return oldValue;
    }

    // 3. Форматируем маску (918 12-34-56)
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      if (i == 2) {
        buffer.write(' ');
      } else if (i == 4 || i == 6) {
        buffer.write('-');
      }
    }

    final formatted = buffer.toString();

    // 4. Корректный расчёт позиции курсора без перескока в начало
    int digitsBeforeCursor = 0;
    for (
      int i = 0;
      i < newValue.selection.end && i < newValue.text.length;
      i++
    ) {
      if (RegExp(r'\d').hasMatch(newValue.text[i])) {
        digitsBeforeCursor++;
      }
    }

    int cursorIndex = 0;
    int currentDigits = 0;
    while (cursorIndex < formatted.length &&
        currentDigits < digitsBeforeCursor) {
      if (RegExp(r'\d').hasMatch(formatted[cursorIndex])) {
        currentDigits++;
      }
      cursorIndex++;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursorIndex),
    );
  }
}
