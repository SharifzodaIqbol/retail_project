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
  bool _loading = true;

  Map<String, dynamic>? _summary;
  List<dynamic> _topProducts = [];
  List<dynamic> _salesByDay = [];
  List<dynamic> _lowStock = [];
  List<dynamic> _sellers = [];

  // ── Многомагазинность ───────────────────────────────────────
  // Список магазинов компании (для переключателя) и id выбранного
  // магазина: null означает "Ҳама мағозаҳо" (все магазины вместе).
  List<dynamic> _shops = [];
  int? _selectedShopId;
  List<dynamic> _shopsSummary = [];

  @override
  Stream<void> get refreshStream =>
      DataRefreshService.instance.onAnalyticsChanged;

  @override
  Future<void> loadData() => _loadAll();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _api.getAnalyticsSummary(_period, shopId: _selectedShopId),
      _api.getTopProducts(limit: 10, shopId: _selectedShopId),
      _api.getSalesByDay(days: 7, shopId: _selectedShopId),
      _api.getLowStockProducts(threshold: 10),
      _api.getSellerStats(shopId: _selectedShopId),
      _api.getShops(),
      _api.getShopsSummary(_period),
    ]);
    setState(() {
      _summary = results[0] as Map<String, dynamic>?;
      _topProducts = results[1] as List<dynamic>;
      _salesByDay = results[2] as List<dynamic>;
      _lowStock = results[3] as List<dynamic>;
      _sellers = results[4] as List<dynamic>;
      _shops = results[5] as List<dynamic>;
      _shopsSummary = results[6] as List<dynamic>;
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
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF4F6EF7),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF4F6EF7),
          tabs: const [
            Tab(text: 'Шарҳи умумӣ'),
            Tab(text: 'Маҳсулоти бисёр харида шуда'),
            Tab(text: 'Фурӯшандагон'),
            Tab(text: 'Мағозаҳо'),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverview(),
                _buildTopProducts(),
                _buildSellers(),
                _buildShopsComparison(),
              ],
            ),
    );
  }

  // ── Вкладка: Обзор ──────────────────────────────────────────
  Widget _buildOverview() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Выбор периода
            _PeriodSelector(
              selected: _period,
              onChanged: (p) {
                setState(() => _period = p);
                _loadAll();
              },
            ),

            // Переключатель магазинов — показывается только если у
            // компании больше одного магазина.
            if (_shops.length > 1) ...[
              const SizedBox(height: 12),
              _ShopSwitcher(
                shops: _shops,
                selectedShopId: _selectedShopId,
                onChanged: (id) {
                  setState(() => _selectedShopId = id);
                  _loadAll();
                },
              ),
            ],
            const SizedBox(height: 16),

            // Карточки-метрики
            if (_summary != null) ...[
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.6,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _MetricCard(
                    label: 'Фурӯш',
                    value: _fmt(_summary!['revenue']),
                    unit: 'Сомонӣ',
                    color: const Color(0xFF4F6EF7),
                    icon: Icons.trending_up,
                  ),
                  _MetricCard(
                    label: 'Фоида',
                    value: _fmt(_summary!['profit']),
                    unit: 'Сомонӣ',
                    color: const Color(0xFF27AE60),
                    icon: Icons.account_balance_wallet,
                  ),
                  _MetricCard(
                    label: 'Миқдори харид',
                    value: '${_summary!['sales_count']}',
                    unit: 'чек',
                    color: const Color(0xFFE67E22),
                    icon: Icons.receipt_long,
                  ),
                  _MetricCard(
                    label: 'Ба ҳисоби миёна чек',
                    value: _fmt(_summary!['avg_check']),
                    unit: 'Сомонӣ',
                    color: const Color(0xFF9B59B6),
                    icon: Icons.calculate,
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),

            // Мини-график выручки по дням
            const Text(
              'Фоида 7 рӯза',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
      return const Center(child: Text('Маълумот нест'));
    }

    final maxRevenue = _salesByDay
        .map((d) => (d['revenue'] as num).toDouble())
        .fold<double>(0, (a, b) => a > b ? a : b);

    return Container(
      height: 180,
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
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: _salesByDay.map((day) {
          final revenue = (day['revenue'] as num).toDouble();
          final ratio = maxRevenue > 0 ? revenue / maxRevenue : 0.0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    revenue > 0 ? _fmtShort(revenue) : '',
                    style: const TextStyle(fontSize: 9, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: (120 * ratio).clamp(4.0, 120.0),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          const Color(0xFF4F6EF7),
                          const Color(0xFF82A3FF),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    day['date'] ?? '',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
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
    final switcher = _shops.length > 1
        ? Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _ShopSwitcher(
              shops: _shops,
              selectedShopId: _selectedShopId,
              onChanged: (id) {
                setState(() => _selectedShopId = id);
                _loadAll();
              },
            ),
          )
        : null;

    if (_topProducts.isEmpty) {
      return Column(
        children: [
          if (switcher != null) switcher,
          const Expanded(child: Center(child: Text('Маълумот нест'))),
        ],
      );
    }

    final maxQty = _topProducts
        .map((p) => (p['total_qty'] as num).toDouble())
        .fold<double>(0, (a, b) => a > b ? a : b);

    return Column(
      children: [
        if (switcher != null) switcher,
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _topProducts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final p = _topProducts[i];
              final qty = (p['total_qty'] as num).toDouble();
              final ratio = maxQty > 0 ? qty / maxQty : 0.0;

              return Container(
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
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: _rankColor(i).withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                color: _rankColor(i),
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
                          ),
                        ),
                        Text(
                          '${qty.toInt()} дона.',
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
                        valueColor: AlwaysStoppedAnimation(_rankColor(i)),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _statChip(
                          'Фурӯш',
                          _fmt(p['total_revenue']),
                          Colors.blue,
                        ),
                        _statChip(
                          'Фоида',
                          _fmt(p['total_profit']),
                          Colors.green,
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Вкладка: Продавцы ───────────────────────────────────────
  Widget _buildSellers() {
    final switcher = _shops.length > 1
        ? Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _ShopSwitcher(
              shops: _shops,
              selectedShopId: _selectedShopId,
              onChanged: (id) {
                setState(() => _selectedShopId = id);
                _loadAll();
              },
            ),
          )
        : null;

    if (_sellers.isEmpty) {
      return Column(
        children: [
          if (switcher != null) switcher,
          const Expanded(
            child: Center(child: Text('Маълумот нест барои имрӯз')),
          ),
        ],
      );
    }

    return Column(
      children: [
        if (switcher != null) switcher,
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _sellers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final s = _sellers[i];
              return Container(
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
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFF4F6EF7).withOpacity(0.1),
                      child: Text(
                        (s['username'] as String? ?? '?')[0].toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF4F6EF7),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s['username'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${s['sales_count']} фурӯш',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${_fmt(s['total_revenue'])} Сомонӣ',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF27AE60),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Вкладка: Все магазины (сравнение) ───────────────────────
  Widget _buildShopsComparison() {
    if (_shopsSummary.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(32),
          children: const [
            SizedBox(height: 80),
            Icon(Icons.storefront_outlined, size: 56, color: Colors.grey),
            SizedBox(height: 16),
            Center(
              child: Text(
                'Ҳанӯз ягон мағоза илова карда нашудааст.\nМағозаҳоро дар "Панели соҳиб" илова кунед.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      );
    }

    final maxRevenue = _shopsSummary
        .map((s) => (s['revenue'] as num).toDouble())
        .fold<double>(0, (a, b) => a > b ? a : b);

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _shopsSummary.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Муқоисаи мағозаҳо',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey[900],
                      ),
                    ),
                  ),
                  _PeriodSelector(
                    compact: true,
                    selected: _period,
                    onChanged: (p) {
                      setState(() => _period = p);
                      _loadAll();
                    },
                  ),
                ],
              ),
            );
          }

          final s = _shopsSummary[i - 1];
          final revenue = (s['revenue'] as num).toDouble();
          final profit = (s['profit'] as num).toDouble();
          final salesCount = s['sales_count'] ?? 0;
          final avgCheck = (s['avg_check'] as num?)?.toDouble() ?? 0;
          final ratio = maxRevenue > 0 ? revenue / maxRevenue : 0.0;
          final isBest = i == 1 && revenue > 0 && s['shop_id'] != null;
          final unassigned = s['shop_id'] == null;

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: isBest
                  ? Border.all(color: const Color(0xFF27AE60), width: 1.4)
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                            (unassigned ? Colors.grey : const Color(0xFF4F6EF7))
                                .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        unassigned ? Icons.help_outline : Icons.storefront,
                        color: unassigned
                            ? Colors.grey[600]
                            : const Color(0xFF4F6EF7),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s['shop_name'] ?? '—',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isBest)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF27AE60).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.emoji_events,
                              size: 13,
                              color: Color(0xFF27AE60),
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Беҳтарин',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF27AE60),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    backgroundColor: Colors.grey[100],
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF4F6EF7)),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _shopStat(
                        'Фурӯш',
                        '${_fmt(revenue)} Сомонӣ',
                        const Color(0xFF4F6EF7),
                      ),
                    ),
                    Expanded(
                      child: _shopStat(
                        'Фоида',
                        '${_fmt(profit)} Сомонӣ',
                        const Color(0xFF27AE60),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _shopStat(
                        'Чек',
                        '$salesCount',
                        const Color(0xFFE67E22),
                      ),
                    ),
                    Expanded(
                      child: _shopStat(
                        'Миёнаи чек',
                        '${_fmt(avgCheck)} Сомонӣ',
                        const Color(0xFF9B59B6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _shopStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[500],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  // ── Вспомогательные ─────────────────────────────────────────

  Widget _statChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Color _rankColor(int i) {
    switch (i) {
      case 0:
        return const Color(0xFFFFD700); // Золото
      case 1:
        return const Color(0xFFC0C0C0); // Серебро
      case 2:
        return const Color(0xFFCD7F32); // Бронза
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
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(0)}к';
    return value.toStringAsFixed(0);
  }
}

// ── Вспомогательные виджеты ──────────────────────────────────

class _PeriodSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  final bool compact;

  const _PeriodSelector({
    required this.selected,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    const periods = {'today': 'Имӯз', 'week': 'Ҳафта', 'month': 'Моҳ'};

    final row = Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: periods.entries.map((e) {
        final isSelected = e.key == selected;
        final chip = GestureDetector(
          onTap: () => onChanged(e.key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(
              vertical: compact ? 6 : 10,
              horizontal: compact ? 10 : 0,
            ),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF4F6EF7) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              e.value,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[600],
                fontWeight: FontWeight.w600,
                fontSize: compact ? 12 : 13,
              ),
            ),
          ),
        );
        return compact ? chip : Expanded(child: chip);
      }).toList(),
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: row,
    );
  }
}

// ── Переключатель магазинов ──────────────────────────────────
// Горизонтальная лента чипов: "Ҳама мағозаҳо" + по одному чипу на каждый
// магазин компании. Позволяет владельцу переключаться между магазинами
// прямо на вкладках "Обзор", "Топ товары" и "Продавцы".
class _ShopSwitcher extends StatelessWidget {
  final List<dynamic> shops;
  final int? selectedShopId;
  final ValueChanged<int?> onChanged;

  const _ShopSwitcher({
    required this.shops,
    required this.selectedShopId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip(
            label: 'Ҳама мағозаҳо',
            icon: Icons.apps,
            selected: selectedShopId == null,
            onTap: () => onChanged(null),
          ),
          ...shops.map((shop) {
            final id = shop['id'] as int;
            return _chip(
              label: shop['name'] ?? 'Мағоза',
              icon: Icons.storefront,
              selected: selectedShopId == id,
              onTap: () => onChanged(id),
            );
          }),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF4F6EF7) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? const Color(0xFF4F6EF7)
                  : Colors.grey.withOpacity(0.25),
            ),
            boxShadow: selected
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 6,
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? Colors.white : Colors.grey[600],
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.grey[700],
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const Spacer(),
            ],
          ),
          const Spacer(),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
