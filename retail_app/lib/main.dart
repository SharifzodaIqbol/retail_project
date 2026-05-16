import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/cart_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/analytics_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/users_screen.dart';
import 'screens/history_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CartProvider()),
      ],
      child: const RetailApp(),
    ),
  );
}

class RetailApp extends StatelessWidget {
  const RetailApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Retail POS',
      theme: ThemeData(
        primaryColor: const Color(0xFF4F6EF7),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4F6EF7),
          brightness: Brightness.light,
        ),
        fontFamily: 'Inter',
        useMaterial3: true,
      ),
      home: const _Bootstrapper(),
    );
  }
}

// Проверяем, авторизован ли пользователь при запуске
class _Bootstrapper extends StatefulWidget {
  const _Bootstrapper();

  @override
  State<_Bootstrapper> createState() => _BootstrapperState();
}

class _BootstrapperState extends State<_Bootstrapper> {
  bool _checking = true;
  bool _loggedIn = false;
  String _role = '';

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ?? '';
    final role = prefs.getString('user_role') ?? '';
    setState(() {
      _loggedIn = token.isNotEmpty;
      _role = role;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_loggedIn) {
      return LoginScreen(
        onLogin: (role) {
          setState(() {
            _loggedIn = true;
            _role = role;
          });
        },
      );
    }
    return MainShell(role: _role);
  }
}

// Главная оболочка с навигацией по роли
class MainShell extends StatefulWidget {
  final String role;
  const MainShell({super.key, required this.role});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  List<_NavItem> get _navItems {
    final items = [
      _NavItem(
        icon: Icons.point_of_sale,
        label: 'Касса',
        screen: const HomeScreen(),
      ),
      _NavItem(
        icon: Icons.history,
        label: 'История',
        screen: HistoryScreen(),
      ),
      _NavItem(
        icon: Icons.inventory_2,
        label: 'Склад',
        screen: const InventoryScreen(),
      ),
    ];

    if (widget.role == 'owner') {
      items.add(_NavItem(
        icon: Icons.bar_chart,
        label: 'Аналитика',
        screen: const AnalyticsScreen(),
      ));
      items.add(_NavItem(
        icon: Icons.people,
        label: 'Сотрудники',
        screen: const UsersScreen(),
      ));
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _navItems;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: items.map((e) => e.screen).toList(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        backgroundColor: Colors.white,
        elevation: 8,
        destinations: items
            .map(
              (e) => NavigationDestination(
                icon: Icon(e.icon),
                label: e.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final Widget screen;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.screen,
  });
}
