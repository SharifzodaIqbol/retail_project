import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class SubscriptionExpiredScreen extends StatelessWidget {
  const SubscriptionExpiredScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.all(24),
        color: Colors.white,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.credit_card_off,
              size: 80,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 24),
            const Text(
              'Обуна ба охир расид',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Дастрасӣ ба система баста шудааст. Давраи озмоишӣ ё тарофаи пардохтшуда ба охир расид. Лутфан бо администратор тамос гиред. Telegram: @sharifzoda.is',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('Пардохтро дубора тафтиш кунед'),
              onPressed: () {
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/', (route) => false);
              },
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () async {
                await AuthService().logout();
                if (context.mounted) {
                  Navigator.of(
                    context,
                  ).pushNamedAndRemoveUntil('/', (route) => false);
                }
              },
              child: const Text('Аз аккаунт хориҷ шудан'),
            ),
          ],
        ),
      ),
    );
  }
}
