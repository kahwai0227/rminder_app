import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'screens/budget_screen.dart';
import 'screens/liability_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/transaction_screen.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AppState())],
      child: MaterialApp(
        title: 'RMinder',
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
        home: const MainScreen(),
      ),
    );
  }
}

class TabSwitcher extends InheritedWidget {
  final void Function(int index) switchTo;
  const TabSwitcher({required this.switchTo, required super.child, super.key});
  static TabSwitcher? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<TabSwitcher>();
  @override
  bool updateShouldNotify(covariant TabSwitcher oldWidget) => switchTo != oldWidget.switchTo;
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  late final List<Widget> _pages = const [
    BudgetPage(),
    TransactionsPage(),
    ReportingPage(),
    LiabilitiesPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return TabSwitcher(
      switchTo: (i) => setState(() => _selectedIndex = i.clamp(0, _pages.length - 1)),
      child: Scaffold(
        body: _pages[_selectedIndex],
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (i) => setState(() => _selectedIndex = i),
          selectedItemColor: Colors.deepPurple.shade800,
          unselectedItemColor: Colors.deepPurple.shade800,
          selectedIconTheme: IconThemeData(color: Colors.deepPurple.shade800),
          unselectedIconTheme: IconThemeData(color: Colors.deepPurple.shade800),
          selectedLabelStyle: TextStyle(color: Colors.deepPurple.shade800),
          unselectedLabelStyle: TextStyle(color: Colors.deepPurple.shade800),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'Budget'),
            BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Transactions'),
            BottomNavigationBarItem(icon: Icon(Icons.pie_chart), label: 'Report'),
            BottomNavigationBarItem(icon: Icon(Icons.savings), label: 'Liabilities'),
          ],
        ),
      ),
    );
  }
}
