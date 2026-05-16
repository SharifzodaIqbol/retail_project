import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();
  late TabController _tabController;

  String _period = 'today';
  bool _loading = true;

  Map<String, dynamic>? _summary;
  List<dynamic> _topProducts = [];
  List<dynamic> _salesByDay = [];
  List<dynamic> _lowStock = [];
  List<dynamic> _sellers = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _api.getAnalyticsSummary(_period),
      _api.getTopProducts(limit: 10),
      _api.getSalesByDay(days: 7),
      _api.getLowStockProducts(threshold: 10),
      _api.getSellerStats(),
    ]);
    setState(() {
      _summary = results[0] as Map<String, dynamic>?;
      _topProducts = results[1] as List<dynamic>;
      _salesByDay = results[2] as List<dynamic>;
      _lowStock = results[3] as List<dynamic>;
      _sellers = results[4] as List<dynamic>;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'Аналитика',
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
            Tab(text: 'Обзор'),
            Tab(text: 'Топ товары'),
            Tab(text: 'Склад'),
            Tab(text: 'Продавцы'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverview(),
                _buildTopProducts(),
                _buildLowStock(),
                _buildSellers(),
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
                    label: 'Выручка',
                    value: _fmt(_summary!['revenue']),
                    unit: 'сом.',
                    color: const Color(0xFF4F6EF7),
                    icon: Icons.trending_up,
                  ),
                  _MetricCard(
                    label: 'Прибыль',
                    value: _fmt(_summary!['profit']),
                    unit: 'сом.',
                    color: const Color(0xFF27AE60),
                    icon: Icons.account_balance_wallet,
                  ),
                  _MetricCard(
                    label: 'Продаж',
                    value: '${_summary!['sales_count']}',
                    unit: 'чеков',
                    color: const Color(0xFFE67E22),
                    icon: Icons.receipt_long,
                  ),
                  _MetricCard(
                    label: 'Ср. чек',
                    value: _fmt(_summary!['avg_check']),
                    unit: 'сом.',
                    color: const Color(0xFF9B59B6),
                    icon: Icons.calculate,
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),

            // Мини-график выручки по дням
            const Text(
              'Выручка за 7 дней',
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
      return const Center(child: Text('Нет данных'));
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
    if (_topProducts.isEmpty) {
      return const Center(child: Text('Нет данных'));
    }

    final maxQty = _topProducts
        .map((p) => (p['total_qty'] as num).toDouble())
        .fold<double>(0, (a, b) => a > b ? a : b);

    return ListView.separated(
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
                    '${qty.toInt()} шт.',
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
                    'Выручка',
                    _fmt(p['total_revenue']),
                    Colors.blue,
                  ),
                  _statChip(
                    'Прибыль',
                    _fmt(p['total_profit']),
                    Colors.green,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Вкладка: Низкий остаток ─────────────────────────────────
  Widget _buildLowStock() {
    if (_lowStock.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 64),
            SizedBox(height: 12),
            Text('Все товары в норме!', style: TextStyle(fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _lowStock.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final p = _lowStock[i];
        final stock = p['stock'] as int;
        final color = stock <= 3 ? Colors.red : Colors.orange;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.warning_amber, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p['name'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Осталось: $stock шт.',
                      style: TextStyle(color: color, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$stock',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
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
      return const Center(child: Text('Нет данных за сегодня'));
    }

    return ListView.separated(
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
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
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
                      '${s['sales_count']} продаж',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${_fmt(s['total_revenue'])} сом.',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF27AE60),
                ),
              ),
            ],
          ),
        );
      },
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
    if (d >= 1000) {
      return '${(d / 1000).toStringAsFixed(1)}к';
    }
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

  const _PeriodSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const periods = {
      'today': 'Сегодня',
      'week': 'Неделя',
      'month': 'Месяц',
    };

    return Container(
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
      padding: const EdgeInsets.all(4),
      child: Row(
        children: periods.entries.map((e) {
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
        }).toList(),
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