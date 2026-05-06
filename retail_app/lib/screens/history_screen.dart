import 'package:flutter/material.dart';
import '../services/api_service.dart';

class HistoryScreen extends StatelessWidget {
  final ApiService _apiService = ApiService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('История продаж')),
      body: FutureBuilder<List<dynamic>>(
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
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ListTile(
                  leading: const Icon(Icons.receipt_long, color: Colors.blue),
                  // Используем total_amount вместо total
                  title: Text(
                    'Чек №${sale['id']} — ${sale['total_amount']} сом',
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Продавец ID: ${sale['seller_id']}'),
                      if (sale['is_canceled'] == true)
                        Text(
                          'ОТМЕНЕН: ${sale['cancel_reason']}',
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                  trailing: sale['is_canceled'] == true
                      ? const Icon(Icons.cancel, color: Colors.red)
                      : const Icon(Icons.check_circle, color: Colors.green),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
