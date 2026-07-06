import 'package:flutter/material.dart';
import '../services/api_service.dart';

enum _DatePreset { all, today, yesterday, week, month }

class HistoryScreen extends StatefulWidget {
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final ApiService _apiService = ApiService();

  // Какие секции-дни сейчас развёрнуты. По умолчанию открыт только сегодняшний день.
  final Set<String> _expandedDays = {};
  bool _initializedExpansion = false;

  // ─── Пагинация ────────────────────────────────────────────────────────────
  final ScrollController _scrollCtrl = ScrollController();
  List<dynamic> _allSales = [];
  bool _loading = true;
  bool _loadingMore = false;
  int _page = 1;
  int _totalPages = 1;
  static const int _limit = 50;

  // ─── Фильтр ─────────────────────────────────────────────────────────────
  bool _filterPanelOpen = false;
  _DatePreset _datePreset = _DatePreset.all;
  final TextEditingController _minAmountCtrl = TextEditingController();
  final TextEditingController _maxAmountCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSales(reset: true);
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _minAmountCtrl.dispose();
    _maxAmountCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSales({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _page = 1;
        _allSales = [];
        _initializedExpansion = false;
      });
    } else {
      if (_loadingMore || _page >= _totalPages) return;
      setState(() => _loadingMore = true);
    }

    final result = await _apiService.getSalesPage(page: _page, limit: _limit);

    if (!mounted) return;
    setState(() {
      _allSales.addAll(result.data);
      _totalPages = result.totalPages;
      _loading = false;
      _loadingMore = false;
      if (result.hasNextPage) _page++;
    });
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _loadSales();
    }
  }

  bool get _hasActiveFilters =>
      _datePreset != _DatePreset.all ||
      _minAmountCtrl.text.trim().isNotEmpty ||
      _maxAmountCtrl.text.trim().isNotEmpty;

  void _resetFilters() {
    setState(() {
      _datePreset = _DatePreset.all;
      _minAmountCtrl.clear();
      _maxAmountCtrl.clear();
    });
  }

  DateTime? _parseSaleDate(dynamic sale) {
    // created_at в формате 'DD.MM.YYYY HH24:MI'
    final raw = (sale['created_at'] ?? '').toString();
    if (raw.length < 10) return null;
    final parts = raw.substring(0, 10).split('.');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }

  List<dynamic> _applyFilters(List<dynamic> sales) {
    final minAmount = double.tryParse(
      _minAmountCtrl.text.trim().replaceAll(',', '.'),
    );
    final maxAmount = double.tryParse(
      _maxAmountCtrl.text.trim().replaceAll(',', '.'),
    );

    DateTime? from;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_datePreset) {
      case _DatePreset.today:
        from = today;
        break;
      case _DatePreset.yesterday:
        from = today.subtract(const Duration(days: 1));
        break;
      case _DatePreset.week:
        from = today.subtract(const Duration(days: 6));
        break;
      case _DatePreset.month:
        from = today.subtract(const Duration(days: 29));
        break;
      case _DatePreset.all:
        from = null;
        break;
    }
    final to = _datePreset == _DatePreset.yesterday
        ? today.subtract(const Duration(days: 1))
        : today;

    return sales.where((sale) {
      if (from != null) {
        final saleDate = _parseSaleDate(sale);
        if (saleDate == null) return false;
        if (saleDate.isBefore(from)) return false;
        if (saleDate.isAfter(to)) return false;
      }

      if (minAmount != null || maxAmount != null) {
        final amount = (sale['total_amount'] as num?)?.toDouble() ?? 0;
        if (minAmount != null && amount < minAmount) return false;
        if (maxAmount != null && amount > maxAmount) return false;
      }

      return true;
    }).toList();
  }

  void _showCancelDialog(int saleId) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Бекор кардани чек №$saleId'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Сабаби бекоркунӣ'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Қафо'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              bool ok = await _apiService.cancelSale(saleId, controller.text);
              if (ok) {
                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                }
              }
            },
            child: const Text(
              'БЕКОР КАРДАН',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // Бэкенд отдаёт created_at в формате 'DD.MM.YYYY HH24:MI'.
  // Берём первые 10 символов как ключ дня и отображаем как 'DD.MM.YYYY'.
  String _dayKey(dynamic sale) {
    final createdAt = (sale['created_at'] ?? '').toString();
    if (createdAt.length >= 10) return createdAt.substring(0, 10);
    return 'Санаи рӯз нест';
  }

  String _dayLabel(String dayKey) {
    final now = DateTime.now();
    final today =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
    final yesterdayDt = now.subtract(const Duration(days: 1));
    final yesterday =
        '${yesterdayDt.day.toString().padLeft(2, '0')}.${yesterdayDt.month.toString().padLeft(2, '0')}.${yesterdayDt.year}';

    if (dayKey == today) return 'Имрӯз: $dayKey';
    if (dayKey == yesterday) return 'Дирӯз: $dayKey';
    return dayKey;
  }

  // Группируем продажи по дням, сохраняя исходный порядок (сервер уже сортирует по id DESC).
  Map<String, List<dynamic>> _groupByDay(List<dynamic> sales) {
    final Map<String, List<dynamic>> grouped = {};
    for (final sale in sales) {
      final key = _dayKey(sale);
      grouped.putIfAbsent(key, () => []).add(sale);
    }
    return grouped;
  }

  double _dayTotal(List<dynamic> daySales) {
    double total = 0;
    for (final sale in daySales) {
      final isCanceled = sale['is_canceled'] ?? false;
      if (isCanceled) continue;
      total += (sale['total_amount'] as num?)?.toDouble() ?? 0;
    }
    return total;
  }

  // ─── Панель фильтра ────────────────────────────────────────────────────

  Widget _datePresetChip(String label, _DatePreset preset) {
    final selected = _datePreset == preset;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _datePreset = preset),
      selectedColor: const Color(0xFF4F6EF7),
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.black87,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        fontSize: 13,
      ),
      backgroundColor: Colors.grey.shade100,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide.none,
      ),
      showCheckmark: false,
    );
  }

  Widget _buildFilterPanel() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      color: Colors.white,
      child: _filterPanelOpen
          ? Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Сана',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _datePresetChip('Ҳама', _DatePreset.all),
                      _datePresetChip('Имрӯз', _DatePreset.today),
                      _datePresetChip('Дирӯз', _DatePreset.yesterday),
                      _datePresetChip('7 рӯзи охир', _DatePreset.week),
                      _datePresetChip('30 рӯзи охир', _DatePreset.month),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Маблағи чек (сомонӣ)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _minAmountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'аз',
                            isDense: true,
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('—', style: TextStyle(color: Colors.grey)),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _maxAmountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'то',
                            isDense: true,
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_hasActiveFilters) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => setState(_resetFilters),
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Тоза кардани филтр'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Таърихи фурӯш'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Навсозӣ',
            onPressed: () => _loadSales(reset: true),
          ),
          IconButton(
            icon: Icon(
              _hasActiveFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
              color: _hasActiveFilters ? const Color(0xFF4F6EF7) : null,
            ),
            tooltip: 'Филтр',
            onPressed: () =>
                setState(() => _filterPanelOpen = !_filterPanelOpen),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterPanel(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Builder(
                    builder: (context) {
                      final filteredSales = _applyFilters(_allSales);

                      if (filteredSales.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _allSales.isEmpty
                                    ? Icons.receipt_long_outlined
                                    : Icons.search_off,
                                size: 56,
                                color: Colors.grey.shade300,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _allSales.isEmpty
                                    ? 'Ҳанӯз фурӯш нашудааст'
                                    : 'Бо ин филтр чек ёфт нашуд',
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 15,
                                ),
                              ),
                              if (_allSales.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: () => setState(_resetFilters),
                                  child: const Text('Тоза кардани филтр'),
                                ),
                              ],
                            ],
                          ),
                        );
                      }

                      final grouped = _groupByDay(filteredSales);
                      final dayKeys = grouped.keys.toList();

                      // Открываем самый свежий день по умолчанию (только один раз).
                      if (!_initializedExpansion) {
                        _initializedExpansion = true;
                        if (dayKeys.isNotEmpty)
                          _expandedDays.add(dayKeys.first);
                      }

                      return RefreshIndicator(
                        onRefresh: () => _loadSales(reset: true),
                        child: ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          // +1 для индикатора подгрузки
                          itemCount: dayKeys.length + (_loadingMore ? 1 : 0),
                          itemBuilder: (context, dayIndex) {
                            // Индикатор подгрузки следующей страницы
                            if (dayIndex == dayKeys.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            }
                            final dayKey = dayKeys[dayIndex];
                            final daySales = grouped[dayKey]!;
                            final dayTotal = _dayTotal(daySales);
                            final canceledCount = daySales
                                .where((s) => s['is_canceled'] ?? false)
                                .length;

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: ExpansionTile(
                                initiallyExpanded: _expandedDays.contains(
                                  dayKey,
                                ),
                                onExpansionChanged: (expanded) {
                                  setState(() {
                                    if (expanded) {
                                      _expandedDays.add(dayKey);
                                    } else {
                                      _expandedDays.remove(dayKey);
                                    }
                                  });
                                },
                                leading: const Icon(
                                  Icons.calendar_today,
                                  color: Color(0xFF4F6EF7),
                                ),
                                title: Text(
                                  _dayLabel(dayKey),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  '${daySales.length} чек'
                                  '${canceledCount > 0 ? ' · бекор карда шуд: $canceledCount' : ''}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                trailing: Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Text(
                                    '${dayTotal.toStringAsFixed(2)} Сомонӣ',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF27AE60),
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                children: daySales.map<Widget>((sale) {
                                  final bool isCanceled =
                                      sale['is_canceled'] ?? false;

                                  return ListTile(
                                    leading: Icon(
                                      Icons.receipt_long,
                                      color: isCanceled
                                          ? Colors.grey
                                          : Colors.blue,
                                    ),
                                    title: Text(
                                      'Чек №${sale['id']} — ${sale['total_amount']} Сомонӣ',
                                    ),
                                    subtitle: Text(
                                      isCanceled
                                          ? 'БЕКОР КАРДА ШУД: ${sale['cancel_reason']}'
                                          : 'Фурӯшанда: ${sale['seller_name'] ?? sale['seller_id']}',
                                    ),

                                    // КНОПКА ВЫЗОВА ДИАЛОГА
                                    trailing: isCanceled
                                        ? const Icon(
                                            Icons.cancel,
                                            color: Colors.red,
                                          )
                                        : IconButton(
                                            icon: const Icon(
                                              Icons.undo,
                                              color: Colors.orange,
                                            ),
                                            onPressed: () =>
                                                _showCancelDialog(sale['id']),
                                          ),
                                  );
                                }).toList(),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
