import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cart_provider.dart';
import '../services/api_service.dart';
import 'history_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ApiService _apiService = ApiService();

  void _searchProduct(BuildContext context) async {
    final barcode = _searchController.text.trim();
    if (barcode.isEmpty) return;

    final product = await _apiService.getProductByBarcode(barcode);

    if (product != null) {
      Provider.of<CartProvider>(context, listen: false).addProduct(product);
      _searchController.clear();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Товар не найден')));
    }
  }

  void _checkout(BuildContext context) async {
    final cart = Provider.of<CartProvider>(context, listen: false);

    final items = cart.items.values
        .map(
          (item) => {
            'product_id': item.product.id,
            'quantity': item.quantity,
            'price': item.product.sellPrice,
          },
        )
        .toList();

    final success = await _apiService.createSale(items, cart.totalAmount);

    if (success) {
      cart.clearCart();
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('✅ Успех'),
          content: const Text('Продажа успешно оформлена!'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Ошибка при оформлении продажи')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Касса: Продажа'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => HistoryScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () => cart.clearCart(),
          ),
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('jwt_token'); // Стираем токен
              Navigator.pushReplacementNamed(context, '/'); // Возврат на логин
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Введите штрихкод...',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _searchProduct(context),
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _searchProduct(context),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: cart.items.length,
              itemBuilder: (context, index) {
                var item = cart.items.values.toList()[index];
                return ListTile(
                  title: Text(item.product.name),
                  subtitle: Text(
                    '${item.product.sellPrice} сом x ${item.quantity}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: () => cart.removeOneItem(item.product.id),
                      ),
                      Text(
                        '${item.quantity}',
                        style: const TextStyle(fontSize: 18),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () => cart.addProduct(item.product),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.blueGrey[50],
              boxShadow: const [
                BoxShadow(blurRadius: 5, color: Colors.black26),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ИТОГО: ${cart.totalAmount.toStringAsFixed(2)} сом',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ElevatedButton(
                  onPressed: cart.items.isEmpty
                      ? null
                      : () => _checkout(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('ОПЛАТИТЬ'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
