import 'package:flutter/material.dart';
import '../services/api_service.dart';

class HistoryScreen extends StatefulWidget {
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final ApiService _apiService = ApiService();

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
              // 1. Вызываем метод в API (не забудь добавить его в api_service.dart)
              bool ok = await _apiService.cancelSale(saleId, controller.text);
              if (ok) {
                if (mounted) {
                  Navigator.pop(context);
                  // 2. Обновляем UI, чтобы FutureBuilder заново запросил данные
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

          return ListView.builder(
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) {
              final sale = snapshot.data![index];
              final bool isCanceled = sale['is_canceled'] ?? false;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ListTile(
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
                        : 'Продавец ID: ${sale['seller_id']}',
                  ),

                  // КНОПКА ВЫЗОВА ДИАЛОГА
                  trailing: isCanceled
                      ? const Icon(Icons.cancel, color: Colors.red)
                      : IconButton(
                          icon: const Icon(Icons.undo, color: Colors.orange),
                          onPressed: () => _showCancelDialog(sale['id']),
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
