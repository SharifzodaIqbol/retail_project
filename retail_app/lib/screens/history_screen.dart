import 'package:flutter/material.dart';
import '../services/api_service.dart';

class HistoryScreen extends StatefulWidget {
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final ApiService _apiService = ApiService();

  // Какие секции-дни сейчас развёрнуты. По умолчанию открыт только сегодняшний день.
  final Set<String> _expandedDays = {};
  bool _initializedExpansion = false;

  void _showCancelDialog(int saleId) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Отмена чека №$saleId'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Причина отмены'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Назад'),
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
              'ОТМЕНИТЬ',
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
    return 'Без даты';
  }

  String _dayLabel(String dayKey) {
    final now = DateTime.now();
    final today =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
    final yesterdayDt = now.subtract(const Duration(days: 1));
    final yesterday =
        '${yesterdayDt.day.toString().padLeft(2, '0')}.${yesterdayDt.month.toString().padLeft(2, '0')}.${yesterdayDt.year}';

    if (dayKey == today) return 'Сегодня · $dayKey';
    if (dayKey == yesterday) return 'Вчера · $dayKey';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('История продаж')),
      body: FutureBuilder<List<dynamic>>(
        // Каждый раз, когда вызывается setState, FutureBuilder будет срабатывать снова
        future: _apiService.getSalesHistory(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Продаж пока нет'));
          }

          final grouped = _groupByDay(snapshot.data!);
          final dayKeys = grouped.keys.toList();

          // Открываем самый свежий день по умолчанию (только один раз за время жизни экрана).
          if (!_initializedExpansion) {
            _initializedExpansion = true;
            if (dayKeys.isNotEmpty) _expandedDays.add(dayKeys.first);
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: dayKeys.length,
            itemBuilder: (context, dayIndex) {
              final dayKey = dayKeys[dayIndex];
              final daySales = grouped[dayKey]!;
              final dayTotal = _dayTotal(daySales);
              final canceledCount = daySales
                  .where((s) => s['is_canceled'] ?? false)
                  .length;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  initiallyExpanded: _expandedDays.contains(dayKey),
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
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${daySales.length} чек(ов)'
                    '${canceledCount > 0 ? ' · отменено: $canceledCount' : ''}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  trailing: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      '${dayTotal.toStringAsFixed(2)} см.',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF27AE60),
                        fontSize: 15,
                      ),
                    ),
                  ),
                  children: daySales.map<Widget>((sale) {
                    final bool isCanceled = sale['is_canceled'] ?? false;

                    return ListTile(
                      leading: Icon(
                        Icons.receipt_long,
                        color: isCanceled ? Colors.grey : Colors.blue,
                      ),
                      title: Text(
                        'Чек №${sale['id']} — ${sale['total_amount']} Сомони',
                      ),
                      subtitle: Text(
                        isCanceled
                            ? 'ОТМЕНЕН: ${sale['cancel_reason']}'
                            : 'Продавец: ${sale['seller_name'] ?? sale['seller_id']}',
                      ),

                      // КНОПКА ВЫЗОВА ДИАЛОГА
                      trailing: isCanceled
                          ? const Icon(Icons.cancel, color: Colors.red)
                          : IconButton(
                              icon: const Icon(
                                Icons.undo,
                                color: Colors.orange,
                              ),
                              onPressed: () => _showCancelDialog(sale['id']),
                            ),
                    );
                  }).toList(),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
