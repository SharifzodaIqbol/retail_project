import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/cart_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/analytics_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/history_screen.dart';
import 'screens/terminal_screen.dart';
import 'screens/owner_panel_screen.dart';
import 'services/api_service.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => CartProvider())],
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
      navigatorKey: ApiService.navigatorKey,
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

class _Bootstrapper extends StatefulWidget {
  const _Bootstrapper();

  @override
  State<_Bootstrapper> createState() => _BootstrapperState();
}

class _BootstrapperState extends State<_Bootstrapper> {
  bool _checking = true;
  bool _loggedIn = false;
  bool _terminalMode = false;
  String _role = '';
  int _companyId = 0;
  String _companyName = '';

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ?? '';
    final role = prefs.getString('user_role') ?? '';
    final terminalMode = prefs.getBool('terminal_mode') ?? false;
    final companyId = prefs.getInt('company_id') ?? 0;
    final companyName = prefs.getString('company_name') ?? '';

    setState(() {
      _loggedIn = token.isNotEmpty;
      _role = role;
      _terminalMode = terminalMode;
      _companyId = companyId;
      _companyName = companyName;
      _checking = false;
    });
  }

  void _onLogin(String role) async {
    final prefs = await SharedPreferences.getInstance();
    final companyId = prefs.getInt('company_id') ?? 0;
    final companyName = prefs.getString('company_name') ?? '';
    setState(() {
      _loggedIn = true;
      _role = role;
      _companyId = companyId;
      _companyName = companyName;
    });
  }

  void _onEnterTerminal() {
    setState(() => _terminalMode = true);
  }

  /// Продавец нажал "Выйти" — возвращаемся на PIN-экран (терминал остаётся активным)
  void _onSellerLogout() async {
    final prefs = await SharedPreferences.getInstance();
    // Очищаем токен продавца, но terminal_mode и company_id оставляем
    await prefs.remove('jwt_token');
    await prefs.remove('user_role');
    await prefs.remove('username');
    // НЕ трогаем terminal_mode — он остаётся true
    await _checkAuth(); // перечитываем: token пустой → покажем TerminalScreen
  }

  /// Хозяин вышел из терминального режима — очищаем всё и показываем логин
  void _onOwnerExitTerminal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('terminal_mode', false);
    // jwt_token уже сохранён (owner снова авторизован через _OwnerPasswordDialog)
    await _checkAuth();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Терминальный режим активен, но пользователь не вошёл (или вышел продавец)
    if (_terminalMode && !_loggedIn) {
      return TerminalScreen(
        companyId: _companyId,
        companyName: _companyName,
        onSellerLogin: (token, role, username) async {
          // Продавец ввёл PIN и вошёл
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('jwt_token', token);
          await prefs.setString('user_role', role);
          await prefs.setString('username', username);
          await _checkAuth();
        },
        onOwnerExitTerminal: _onOwnerExitTerminal,
      );
    }

    // Не авторизован — показываем логин (только для owner)
    if (!_loggedIn) {
      return LoginScreen(onLogin: _onLogin);
    }

    // Авторизован как owner в терминальном режиме — показываем терминал для выбора продавца
    if (_terminalMode && _role == 'owner') {
      return TerminalScreen(
        companyId: _companyId,
        companyName: _companyName,
        onSellerLogin: (token, role, username) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('jwt_token', token);
          await prefs.setString('user_role', role);
          await prefs.setString('username', username);
          await _checkAuth();
        },
        onOwnerExitTerminal: _onOwnerExitTerminal,
      );
    }

    // Обычный режим — главная оболочка
    return MainShell(
      role: _role,
      onEnterTerminal: _onEnterTerminal,
      onSellerLogout: _terminalMode ? _onSellerLogout : null,
    );
  }
}

class MainShell extends StatefulWidget {
  final String role;
  final VoidCallback onEnterTerminal;
  final VoidCallback? onSellerLogout; // если в терминальном режиме

  const MainShell({
    super.key,
    required this.role,
    required this.onEnterTerminal,
    this.onSellerLogout,
  });

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
        screen: HomeScreen(onSellerLogout: widget.onSellerLogout),
      ),
      _NavItem(icon: Icons.history, label: 'История', screen: HistoryScreen()),
      _NavItem(
        icon: Icons.inventory_2,
        label: 'Склад',
        screen: const InventoryScreen(),
      ),
    ];

    if (widget.role == 'owner') {
      items.add(
        _NavItem(
          icon: Icons.bar_chart,
          label: 'Аналитика',
          screen: const AnalyticsScreen(),
        ),
      );
      items.add(
        _NavItem(
          icon: Icons.manage_accounts,
          label: 'Управление',
          screen: OwnerPanelScreen(onEnterTerminal: widget.onEnterTerminal),
        ),
      );
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
              (e) => NavigationDestination(icon: Icon(e.icon), label: e.label),
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
