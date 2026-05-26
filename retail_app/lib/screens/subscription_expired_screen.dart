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
              'Подписка истекла',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Доступ к системе заблокирован. Пробный период или оплаченный тариф подошел к концу. Пожалуйста, свяжитесь с администратором или оплатите подписку в личном кабинете.',
              textAlign: TextAlign
                  .center, // <-- ИСПРАВЛЕНО: Вместо Center используем TextAlign.center
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(
                Icons.refresh,
              ), // <-- ИСПРАВЛЕНО: Проверьте явное указание именованных аргументов
              label: const Text('Проверить оплату снова'),
              onPressed: () {
                // Перезапускаем приложение (Bootstrapper проверит статус заново)
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
              child: const Text('Выйти из аккаунта'),
            ),
          ],
        ),
      ),
    );
  }
}
