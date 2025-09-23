import 'package:flutter/material.dart';
import 'dart:async';
import 'package:home_widget/home_widget.dart';
import 'dart:convert';
import 'db/rminder_database.dart';
import 'models/models.dart' as models;
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'screens/budget_screen.dart';
import 'screens/liability_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/transaction_screen.dart';
import 'screens/savings_screen.dart';
import 'screens/onboarding_screen.dart';
// Removed flutter_svg import as the AppBar logo is no longer used

@pragma('vm:entry-point')
FutureOr<void> homeWidgetBackgroundCallback(Uri? data) async {
  // Ensure bindings for platform channels when running in background isolate
  WidgetsFlutterBinding.ensureInitialized();
  // This is invoked from the Android Home Screen Widget via background intent.
  // We support a minimal quick-add flow using query params in the URI.
  // Scheme examples:
  // rminder://add-transaction?amount=12.34&categoryId=1&note=Lunch
  // rminder://widget?action=cat_prev|cat_next|key|clear|backspace|save&value=1|2|3
  if (data == null) return;
  try {
    if (data.host == 'add-transaction') {
      final params = data.queryParameters;
      final amount = double.tryParse(params['amount'] ?? '');
      final categoryId = int.tryParse(params['categoryId'] ?? '');
      final note = params['note'] ?? 'Quick add';
      if (amount != null && categoryId != null && categoryId > 0) {
        // Insert via our DB helper to preserve side-effects (liabilities/sinking funds)
        final txn = models.Transaction(
          categoryId: categoryId,
          amount: amount,
          date: DateTime.now(),
          note: note,
        );
        await RMinderDatabase.instance.insertTransaction(txn);
        // Trigger widget refresh
        await HomeWidget.updateWidget(name: 'QuickAddWidgetProvider');
      }
    } else if (data.host == 'widget') {
      final action = data.queryParameters['action'];
      switch (action) {
        case 'cat_toggle':
          {
            final vis = await HomeWidget.getWidgetData<int>('cat_list_visible') ?? 0;
            final next = vis == 1 ? 0 : 1;
            await HomeWidget.saveWidgetData<int>('cat_list_visible', next);
            if (next == 1) {
              // Reset to first page when opening list
              await HomeWidget.saveWidgetData<int>('cat_list_page', 0);
            }
            await HomeWidget.updateWidget(name: 'QuickAddWidgetProvider');
          }
          break;
        case 'cat_select':
          {
            final idx = int.tryParse(data.queryParameters['index'] ?? '');
            if (idx != null) {
              await HomeWidget.saveWidgetData<int>('cat_index', idx);
            }
            await HomeWidget.saveWidgetData<int>('cat_list_visible', 0);
            await HomeWidget.updateWidget(name: 'QuickAddWidgetProvider');
          }
          break;
        case 'cat_prev':
        case 'cat_next':
          {
            final jsonStr = await HomeWidget.getWidgetData<String>('categories_json');
            final categories = _parseCategories(jsonStr);
            if (categories.isNotEmpty) {
              final current = await HomeWidget.getWidgetData<int>('cat_index') ?? 0;
              final next = action == 'cat_prev'
                  ? (current - 1 + categories.length) % categories.length
                  : (current + 1) % categories.length;
              await HomeWidget.saveWidgetData<int>('cat_index', next);
            }
            await HomeWidget.updateWidget(name: 'QuickAddWidgetProvider');
          }
          break;
        case 'key':
          {
            final v = data.queryParameters['value'] ?? '';
            var digits = await HomeWidget.getWidgetData<String>('amount_digits') ?? '';
            if (v == '00') {
              if (digits.length < 9) {
                final remaining = 9 - digits.length;
                final toAdd = remaining >= 2 ? '00' : '0';
                digits = digits + toAdd;
              }
            } else if (v.length == 1 && v.codeUnitAt(0) >= 48 && v.codeUnitAt(0) <= 57) {
              // Single digit
              if (digits.length < 9) {
                digits = digits + v;
              }
            }
            final display = _formatFromDigits(digits);
            await HomeWidget.saveWidgetData<String>('amount_digits', digits);
            await HomeWidget.saveWidgetData<String>('amount_str', display);
            await HomeWidget.updateWidget(name: 'QuickAddWidgetProvider');
          }
          break;
        case 'clear':
          await HomeWidget.saveWidgetData<String>('amount_str', '');
          await HomeWidget.saveWidgetData<String>('amount_digits', '');
          await HomeWidget.updateWidget(name: 'QuickAddWidgetProvider');
          break;
        case 'backspace':
          {
            var digits = await HomeWidget.getWidgetData<String>('amount_digits') ?? '';
            if (digits.isNotEmpty) {
              digits = digits.substring(0, digits.length - 1);
            }
            final display = _formatFromDigits(digits);
            await HomeWidget.saveWidgetData<String>('amount_digits', digits);
            await HomeWidget.saveWidgetData<String>('amount_str', display);
            await HomeWidget.updateWidget(name: 'QuickAddWidgetProvider');
          }
          break;
        case 'save':
          {
            // Compose values from stored state
            final jsonStr = await HomeWidget.getWidgetData<String>('categories_json');
            final categories = _parseCategories(jsonStr);
            if (categories.isEmpty) {
              await HomeWidget.updateWidget(name: 'QuickAddWidgetProvider');
              break;
            }
            final catIndex = await HomeWidget.getWidgetData<int>('cat_index') ?? 0;
            final cat = categories[catIndex % categories.length];
            final digits = await HomeWidget.getWidgetData<String>('amount_digits') ?? '';
            final amount = _amountFromDigits(digits) ?? 0.0;
            if (amount > 0) {
              final txn = models.Transaction(
                categoryId: cat.id,
                amount: amount,
                date: DateTime.now(),
                note: null,
              );
              await RMinderDatabase.instance.insertTransaction(txn);
              // Reset amount after save
              await HomeWidget.saveWidgetData<String>('amount_str', '');
              await HomeWidget.saveWidgetData<String>('amount_digits', '');
            }
            await HomeWidget.updateWidget(name: 'QuickAddWidgetProvider');
          }
          break;
      }
    }
  } catch (_) {}
}

void main() {
  // Ensure bindings before using platform channels (HomeWidget)
  WidgetsFlutterBinding.ensureInitialized();
  // Register background callback for HomeWidget interactive actions after first frame
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _registerHomeWidgetCallbackWithRetry();
  });
  runApp(const MyApp());
  // Sync categories for widget once app is up
  // Don't block startup; schedule async sync
  Future.microtask(syncWidgetCategories);
}

Future<void> _registerHomeWidgetCallbackWithRetry({int attempts = 3}) async {
  for (int i = 0; i < attempts; i++) {
    try {
      await HomeWidget.registerInteractivityCallback(homeWidgetBackgroundCallback);
      return;
    } catch (e) {
      // MissingPluginException can happen very early; retry a couple times.
      if (i == attempts - 1) {
        // Give up silently; widget still functions for launch intents.
        // You can add logging here if desired.
        return;
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }
}

class _WidgetCategoryDto {
  final int id;
  final String name;
  _WidgetCategoryDto(this.id, this.name);
}

List<_WidgetCategoryDto> _parseCategories(String? jsonStr) {
  if (jsonStr == null || jsonStr.isEmpty) return [];
  try {
    final List list = json.decode(jsonStr) as List;
    return list
        .map((e) => _WidgetCategoryDto(e['id'] as int, e['name'] as String))
        .toList();
  } catch (_) {
    return [];
  }
}

// Format display string from raw digit-only cents string.
// Example: digits "" -> "" (widget shows 0.00); "1" -> "0.01"; "123" -> "1.23"
String _formatFromDigits(String digits) {
  if (digits.isEmpty) return '';
  final n = int.tryParse(digits) ?? 0;
  final d = (n / 100).toStringAsFixed(2);
  return d;
}

// Convert raw digits to amount double.
double? _amountFromDigits(String digits) {
  if (digits.isEmpty) return null;
  final n = int.tryParse(digits);
  if (n == null) return null;
  return n / 100.0;
}

Future<void> syncWidgetCategories() async {
  try {
    final db = RMinderDatabase.instance;
    final categories = await db.getCategories();
  final mapped = categories
    .map((c) => {'id': c.id, 'name': c.name})
        .toList();
    final jsonStr = json.encode(mapped);
    await HomeWidget.saveWidgetData<String>('categories_json', jsonStr);
    await HomeWidget.saveWidgetData<int>('cat_list_visible', 0);
    // Initialize index if absent
    final idx = await HomeWidget.getWidgetData<int>('cat_index');
    if (idx == null) {
      await HomeWidget.saveWidgetData<int>('cat_index', 0);
    }
    await HomeWidget.updateWidget(name: 'QuickAddWidgetProvider');
  } catch (_) {}
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AppState())],
      child: MaterialApp(
        title: 'RMinder',
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
        home: const AppInitializer(),
        routes: {
          '/': (context) => const MainScreen(),
          '/onboarding': (context) => const OnboardingScreen(),
        },
      ),
    );
  }
}

class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final appState = Provider.of<AppState>(context, listen: false);
    await appState.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        if (!appState.isInitialized) {
          // Show loading screen while initializing
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (!appState.isOnboardingCompleted) {
          return const OnboardingScreen();
        }

        return const MainScreen();
      },
    );
  }
}

// Optional helper: call this from a settings screen to wire the widget to a default category
Future<void> setQuickAddCategory({required int categoryId}) async {
  await HomeWidget.saveWidgetData<int>('quick_add_category_id', categoryId);
  await HomeWidget.updateWidget(name: 'QuickAddWidgetProvider');
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
    SavingsScreen(),
    LiabilitiesPage(),
    ReportingPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return TabSwitcher(
      switchTo: (i) => setState(() => _selectedIndex = i.clamp(0, _pages.length - 1)),
      child: Scaffold(
  body: SafeArea(child: _pages[_selectedIndex]),
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
            BottomNavigationBarItem(icon: Icon(Icons.attach_money), label: 'Savings'),
            BottomNavigationBarItem(icon: Icon(Icons.savings), label: 'Liabilities'),
            BottomNavigationBarItem(icon: Icon(Icons.pie_chart), label: 'Report'),
          ],
        ),
      ),
    );
  }
}
