import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/data_refresh_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with SingleTickerProviderStateMixin, AutoRefreshMixin<AnalyticsScreen> {
  final _api = ApiService();
  late TabController _tabController;

  String _period = 'today';
  DateTime? _customFrom;
  DateTime? _customTo;
  bool _loading = true;

  Map<String, dynamic>? _summary;
  List<dynamic> _topProducts = [];
  List<dynamic> _salesByDay = [];
  List<dynamic> _sellers = [];

  @override
  Stream<void> get refreshStream =>
      DataRefreshService.instance.onAnalyticsChanged;

  @override
  Future<void> loadData() => _loadAll();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDialog<DateTimeRange>(
      context: context,
      builder: (_) => _CustomRangeDialog(
        initialFrom: _customFrom ?? now.subtract(const Duration(days: 6)),
        initialTo: _customTo ?? now,
        maxDate: now,
      ),
    );
    if (picked == null) return;
    setState(() {
      _period = 'custom';
      _customFrom = picked.start;
      _customTo = picked.end;
    });
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _api.getAnalyticsSummary(_period, from: _customFrom, to: _customTo),
      _api.getTopProducts(
        limit: 10,
        period: _period,
        from: _customFrom,
        to: _customTo,
      ),
      _api.getSalesByDay(days: 7),
      _api.getSellerStats(period: _period, from: _customFrom, to: _customTo),
    ]);
    if (!mounted) return;
    setState(() {
      _summary = results[0] as Map<String, dynamic>?;
      _topProducts = results[1] as List<dynamic>;
      _salesByDay = results[2] as List<dynamic>;
      _sellers = List<dynamic>.from(results[3] as List<dynamic>)
        ..sort(
          (a, b) => ((b['total_revenue'] ?? 0) as num).compareTo(
            (a['total_revenue'] ?? 0) as num,
          ),
        );
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'Таҳлилҳо',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: _PeriodSelector(
              selected: _period,
              customFrom: _customFrom,
              customTo: _customTo,
              onChanged: (p) {
                setState(() => _period = p);
                _loadAll();
              },
              onPickCustomRange: _pickCustomRange,
            ),
          ),
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF4F6EF7),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFF4F6EF7),
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              tabs: const [
                Tab(text: 'Шарҳи умумӣ'),
                Tab(text: 'Маҳсулот'),
                Tab(text: 'Фурӯшандагон'),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildOverview(),
                      _buildTopProducts(),
                      _buildSellers(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ── Вкладка: Обзор ──────────────────────────────────────────
  Widget _buildOverview() {
    final revenue = (_summary?['revenue'] as num?)?.toDouble() ?? 0;
    final profit = (_summary?['profit'] as num?)?.toDouble() ?? 0;

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Главная карточка — доход владельца сразу бросается в глаза,
            // без необходимости искать его среди одинаковых плиток.
            _HeroRevenueCard(
              revenue: revenue,
              profit: profit,
              salesCount: (_summary?['sales_count'] ?? 0).toString(),
              periodLabel: _periodLabel(),
            ),

            const SizedBox(height: 24),
            const Text(
              'Фурӯш дар 7 рӯзи охир',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _buildBarChart(),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChart() {
    if (_salesByDay.isEmpty) {
      return const _EmptyState(
        icon: Icons.show_chart,
        text: 'Маълумот барои график нест',
      );
    }

    final maxRevenue = _salesByDay
        .map((d) => (d['revenue'] as num).toDouble())
        .fold<double>(0, (a, b) => a > b ? a : b);

    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: _salesByDay.map((day) {
          final revenue = (day['revenue'] as num).toDouble();
          final ratio = maxRevenue > 0 ? revenue / maxRevenue : 0.0;
          final isToday = day == _salesByDay.last;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      revenue > 0 ? _fmtShort(revenue) : '',
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: FractionallySizedBox(
                      heightFactor: ratio.clamp(0.05, 1.0),
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: isToday
                                ? const [Color(0xFF27AE60), Color(0xFF6FE0A0)]
                                : const [Color(0xFF4F6EF7), Color(0xFF82A3FF)],
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      day['date'] ?? '',
                      style: TextStyle(
                        fontSize: 9,
                        color: isToday ? const Color(0xFF27AE60) : Colors.grey,
                        fontWeight: isToday
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Вкладка: Топ товары ─────────────────────────────────────
  Widget _buildTopProducts() {
    if (_topProducts.isEmpty) {
      return const _EmptyState(
        icon: Icons.inventory_2_outlined,
        text: 'Ҳанӯз фурӯш нест',
      );
    }

    final maxQty = _topProducts
        .map((p) => (p['total_qty'] as num).toDouble())
        .fold<double>(0, (a, b) => a > b ? a : b);

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: _topProducts.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (i == 0) {
          return _ScopeLabel(text: _periodLabel());
        }
        final p = _topProducts[i - 1];
        final rank = i - 1;
        final qty = (p['total_qty'] as num).toDouble();
        final ratio = maxQty > 0 ? qty / maxQty : 0.0;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _rankColor(rank).withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${rank + 1}',
                        style: TextStyle(
                          color: _rankColor(rank),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      p['name'] ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${qty.toInt()} дона',
                    style: const TextStyle(
                      color: Color(0xFF4F6EF7),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  backgroundColor: Colors.grey[100],
                  valueColor: AlwaysStoppedAnimation(_rankColor(rank)),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: _statChip(
                      'Фурӯш',
                      _fmt(p['total_revenue']),
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: _statChip(
                      'Фоида',
                      _fmt(p['total_profit']),
                      Colors.green,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Вкладка: Продавцы ───────────────────────────────────────
  Widget _buildSellers() {
    if (_sellers.isEmpty) {
      return const _EmptyState(
        icon: Icons.groups_outlined,
        text: 'Барои ин давра фурӯш нест',
      );
    }

    final totalRevenue = _sellers.fold<double>(
      0,
      (a, s) => a + ((s['total_revenue'] ?? 0) as num).toDouble(),
    );
    final totalSales = _sellers.fold<int>(
      0,
      (a, s) => a + ((s['sales_count'] ?? 0) as num).toInt(),
    );
    final maxRevenue = _sellers
        .map((s) => ((s['total_revenue'] ?? 0) as num).toDouble())
        .fold<double>(0, (a, b) => a > b ? a : b);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        _ScopeLabel(text: _periodLabel()),
        const SizedBox(height: 8),
        _TeamSummaryCard(totalRevenue: totalRevenue, totalSales: totalSales),
        const SizedBox(height: 16),
        ..._sellers.asMap().entries.map((entry) {
          final rank = entry.key;
          final s = entry.value;
          final revenue = ((s['total_revenue'] ?? 0) as num).toDouble();
          final salesCount = ((s['sales_count'] ?? 0) as num).toInt();
          final avgCheck = salesCount > 0 ? revenue / salesCount : 0.0;
          final ratio = maxRevenue > 0 ? revenue / maxRevenue : 0.0;
          final share = totalRevenue > 0 ? (revenue / totalRevenue * 100) : 0.0;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: const Color(
                              0xFF4F6EF7,
                            ).withOpacity(0.1),
                            child: Text(
                              (s['username'] as String? ?? '?')[0]
                                  .toUpperCase(),
                              style: const TextStyle(
                                color: Color(0xFF4F6EF7),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (rank < 3)
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: _rankColor(rank),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1.5,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.emoji_events,
                                  size: 10,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s['username'] ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              '$salesCount фурӯш · ${_fmt(avgCheck)} сомонӣ/чек',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${_fmt(revenue)} с.',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: Color(0xFF27AE60),
                            ),
                          ),
                          Text(
                            '${share.toStringAsFixed(0)}% аз фурӯш',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      backgroundColor: Colors.grey[100],
                      valueColor: AlwaysStoppedAnimation(_rankColor(rank)),
                      minHeight: 5,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  String _periodLabel() {
    switch (_period) {
      case 'week':
        return 'Натиҷаи ҳафта';
      case 'month':
        return 'Натиҷаи моҳ';
      case 'custom':
        if (_customFrom != null && _customTo != null) {
          String d(DateTime x) =>
              '${x.day.toString().padLeft(2, '0')}.${x.month.toString().padLeft(2, '0')}.${x.year}';
          return 'Натиҷа: ${d(_customFrom!)} — ${d(_customTo!)}';
        }
        return 'Натиҷаи давра';
      default:
        return 'Натиҷаи имрӯз';
    }
  }

  // ── Вспомогательные ─────────────────────────────────────────

  Widget _statChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '$label: $value',
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Color _rankColor(int i) {
    switch (i) {
      case 0:
        return const Color(0xFFFFD700);
      case 1:
        return const Color(0xFFC0C0C0);
      case 2:
        return const Color(0xFFCD7F32);
      default:
        return const Color(0xFF4F6EF7);
    }
  }

  String _fmt(dynamic value) {
    if (value == null) return '0';
    final d = (value as num).toDouble();
    return d.toStringAsFixed(2);
  }

  String _fmtShort(double value) {
    return value.toStringAsFixed(0);
  }
}

// ── Вспомогательные виджеты ──────────────────────────────────

/// Диалог ввода произвольного диапазона дат вручную (ДД / ММ / ГГГГ),
/// полностью на таджикском, без визуального календаря.
class _CustomRangeDialog extends StatefulWidget {
  final DateTime initialFrom;
  final DateTime initialTo;
  final DateTime maxDate;

  const _CustomRangeDialog({
    required this.initialFrom,
    required this.initialTo,
    required this.maxDate,
  });

  @override
  State<_CustomRangeDialog> createState() => _CustomRangeDialogState();
}

class _CustomRangeDialogState extends State<_CustomRangeDialog> {
  late final TextEditingController _fromDay;
  late final TextEditingController _fromMonth;
  late final TextEditingController _fromYear;
  late final TextEditingController _toDay;
  late final TextEditingController _toMonth;
  late final TextEditingController _toYear;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fromDay = TextEditingController(text: _p(widget.initialFrom.day));
    _fromMonth = TextEditingController(text: _p(widget.initialFrom.month));
    _fromYear = TextEditingController(text: '${widget.initialFrom.year}');
    _toDay = TextEditingController(text: _p(widget.initialTo.day));
    _toMonth = TextEditingController(text: _p(widget.initialTo.month));
    _toYear = TextEditingController(text: '${widget.initialTo.year}');
  }

  String _p(int v) => v.toString().padLeft(2, '0');

  @override
  void dispose() {
    for (final c in [
      _fromDay,
      _fromMonth,
      _fromYear,
      _toDay,
      _toMonth,
      _toYear,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime? _parse(
    TextEditingController d,
    TextEditingController m,
    TextEditingController y,
  ) {
    final day = int.tryParse(d.text.trim());
    final month = int.tryParse(m.text.trim());
    final year = int.tryParse(y.text.trim());
    if (day == null || month == null || year == null) return null;
    if (month < 1 || month > 12) return null;
    if (year < 2000 || year > 2100) return null;
    try {
      final date = DateTime(year, month, day);
      // Проверяем, что дата не "переползла" на другой месяц (напр. 31.02)
      if (date.month != month || date.day != day) return null;
      return date;
    } catch (_) {
      return null;
    }
  }

  void _submit() {
    final from = _parse(_fromDay, _fromMonth, _fromYear);
    final to = _parse(_toDay, _toMonth, _toYear);

    if (from == null || to == null) {
      setState(() => _error = 'Санаро дуруст ворид кунед (Р.М.С)');
      return;
    }
    if (from.isAfter(to)) {
      setState(() => _error = 'Санаи "Аз" бояд пеш аз "То" бошад');
      return;
    }
    if (to.isAfter(widget.maxDate)) {
      setState(() => _error = 'Санаи "То" наметавонад дар оянда бошад');
      return;
    }
    Navigator.pop(context, DateTimeRange(start: from, end: to));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Давраро интихоб кунед'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Санаи оғоз (Аз)',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 6),
            _DateFieldRow(day: _fromDay, month: _fromMonth, year: _fromYear),
            const SizedBox(height: 16),
            const Text(
              'Санаи анҷом (То)',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 6),
            _DateFieldRow(day: _toDay, month: _toMonth, year: _toYear),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
            const SizedBox(height: 4),
            const Text(
              'Формат: рӯз . моҳ . сол',
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Бекор кардан'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4F6EF7),
          ),
          child: const Text('Тасдиқ', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

class _DateFieldRow extends StatelessWidget {
  final TextEditingController day;
  final TextEditingController month;
  final TextEditingController year;

  const _DateFieldRow({
    required this.day,
    required this.month,
    required this.year,
  });

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String hint) => InputDecoration(
      hintText: hint,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: TextField(
            controller: day,
            keyboardType: TextInputType.number,
            maxLength: 2,
            textAlign: TextAlign.center,
            decoration: deco('Рӯз').copyWith(counterText: ''),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextField(
            controller: month,
            keyboardType: TextInputType.number,
            maxLength: 2,
            textAlign: TextAlign.center,
            decoration: deco('Моҳ').copyWith(counterText: ''),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: TextField(
            controller: year,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            decoration: deco('Сол').copyWith(counterText: ''),
          ),
        ),
      ],
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  final String selected;
  final DateTime? customFrom;
  final DateTime? customTo;
  final ValueChanged<String> onChanged;
  final VoidCallback onPickCustomRange;

  const _PeriodSelector({
    required this.selected,
    required this.onChanged,
    required this.onPickCustomRange,
    this.customFrom,
    this.customTo,
  });

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    const periods = {'today': 'Имрӯз', 'week': 'Ҳафта', 'month': 'Моҳ'};
    final isCustom = selected == 'custom';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
            ],
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              ...periods.entries.map((e) {
                final isSelected = e.key == selected;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(e.key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF4F6EF7)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        e.value,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey[600],
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                );
              }),
              Expanded(
                child: GestureDetector(
                  onTap: onPickCustomRange,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isCustom
                          ? const Color(0xFF4F6EF7)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.date_range,
                      size: 18,
                      color: isCustom ? Colors.white : Colors.grey[600],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (isCustom && customFrom != null && customTo != null) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onPickCustomRange,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF4F6EF7).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.event, size: 14, color: Color(0xFF4F6EF7)),
                  const SizedBox(width: 6),
                  Text(
                    '${_fmtDate(customFrom!)} — ${_fmtDate(customTo!)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF4F6EF7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit, size: 12, color: Color(0xFF4F6EF7)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Главная карточка обзора — доход и чистая прибыль владельца сразу видны,
/// без необходимости сравнивать одинаковые плитки между собой.
class _HeroRevenueCard extends StatelessWidget {
  final double revenue;
  final double profit;
  final String salesCount;
  final String periodLabel;

  const _HeroRevenueCard({
    required this.revenue,
    required this.profit,
    required this.salesCount,
    required this.periodLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4F6EF7), Color(0xFF6C8CFF)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F6EF7).withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up, color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              const Text(
                'Фурӯши умумӣ',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                periodLabel,
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${revenue.toStringAsFixed(2)} с.',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _heroStat(
                  'Фоидаи соф',
                  '${profit.toStringAsFixed(2)} с.',
                ),
              ),
              Expanded(
                child: _heroStat('Чекҳо', '$salesCount адад', alignEnd: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String label, String value, {bool alignEnd = false}) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Компактная сводка по всей команде продавцов над списком —
/// чтобы сразу было видно общую картину дня, не складывая цифры в уме.
class _TeamSummaryCard extends StatelessWidget {
  final double totalRevenue;
  final int totalSales;

  const _TeamSummaryCard({
    required this.totalRevenue,
    required this.totalSales,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF27AE60).withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF27AE60).withOpacity(0.15)),
      ),
      child: Row(
        children: [
          const Icon(Icons.groups, color: Color(0xFF27AE60), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${totalRevenue.toStringAsFixed(2)} сомонӣ',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Color(0xFF27AE60),
                  ),
                ),
                Text(
                  'Ҷамъан аз ҳамаи фурӯшандагон · $totalSales чек',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Маленькая подпись-«хлебная крошка» над списком, поясняющая за какой
/// период показаны данные — топ товаров и продавцы не следуют переключателю
/// периода на вкладке «Обзор», поэтому важно не создавать ложное впечатление.
class _ScopeLabel extends StatelessWidget {
  final String text;
  const _ScopeLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: Colors.grey.shade500,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyState({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;
  final IconData icon;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.bottomLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
