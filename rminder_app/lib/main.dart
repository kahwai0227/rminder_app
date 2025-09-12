import 'dart:developer' as developer;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'db/rminder_database.dart';
import 'models/models.dart' as models;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RMinder',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);
  @override
  State<MainScreen> createState() => _MainScreenState();
}

// Simple inherited widget to allow switching tabs from nested pages/dialogs
class TabSwitcher extends InheritedWidget {
  final void Function(int index) switchTo;
  const TabSwitcher({required this.switchTo, required Widget child, Key? key}) : super(key: key, child: child);
  static TabSwitcher? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TabSwitcher>();
  @override
  bool updateShouldNotify(covariant TabSwitcher oldWidget) => switchTo != oldWidget.switchTo;
}

// Global UI intents for cross-page actions
class UiIntents {
  static final ValueNotifier<int?> editLiabilityId = ValueNotifier<int?>(null);
}

// Simple DTOs used by Reporting/Charts
class CategoryBreakdown {
  final String name;
  final double spent;
  final double limit;
  final int? categoryId;
  const CategoryBreakdown({required this.name, required this.spent, required this.limit, this.categoryId});
}

class MonthlySummary {
  final double totalSpent;
  final double totalLimit;
  final double totalRemaining;
  final List<CategoryBreakdown> breakdown;
  const MonthlySummary({
    required this.totalSpent,
    required this.totalLimit,
    required this.totalRemaining,
    required this.breakdown,
  });
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  List<Map<String, dynamic>> liabilities = [];
  final GlobalKey<_BudgetPageState> _budgetKey = GlobalKey<_BudgetPageState>();
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      BudgetPage(key: _budgetKey),
      const TransactionsPage(),
      const ReportingPage(),
      LiabilitiesPage(
        liabilities: liabilities,
        onSave: (newLiabilities) => setState(() => liabilities = newLiabilities),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return TabSwitcher(
      switchTo: (i) => setState(() => _selectedIndex = i.clamp(0, 3)),
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

// Pie chart for budget allocation (budget limits per category)
class BudgetAllocationChart extends StatelessWidget {
  final List<CategoryBreakdown> breakdown;
  final ValueChanged<CategoryBreakdown>? onSliceTap;
  // Additional slice to represent income not yet allocated to any category.
  final double unallocatedAmount;
  const BudgetAllocationChart({
    required this.breakdown,
    this.onSliceTap,
    this.unallocatedAmount = 0,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Allow chart to render even if there are no categories, as long as there is
    // a positive unallocated amount to show.
    final categoriesTotal = breakdown.fold<double>(0, (s, c) => s + c.limit);
    final double extraUnallocated = unallocatedAmount > 0 ? unallocatedAmount : 0.0;
    final total = categoriesTotal + extraUnallocated;
    if (total == 0) return const Center(child: Text('No budget allocated'));

    const double labelThreshold = 8.0; // show on-slice labels only when >= 8%

    // Build legend entries in the same order/colors as the chart
    final legendEntries = <_LegendEntry>[];
    for (final entry in breakdown.asMap().entries) {
      final idx = entry.key;
      final cat = entry.value;
      final color = Colors.primaries[idx % Colors.primaries.length];
      final percent = total == 0.0 ? 0.0 : (cat.limit / total) * 100;
      legendEntries.add(_LegendEntry(label: cat.name, color: color, percent: percent));
    }
    if (extraUnallocated > 0) {
      final percent = (extraUnallocated / total) * 100;
      legendEntries.add(_LegendEntry(label: 'Unallocated', color: Colors.blueGrey, percent: percent));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 200,
          child: PieChart(
            PieChartData(
              pieTouchData: PieTouchData(
                touchCallback: (event, pieTouchResponse) {
                  if (!event.isInterestedForInteractions) return;
                  final touched = pieTouchResponse?.touchedSection;
                  if (touched == null) return;
                  final idx = touched.touchedSectionIndex;
                  // Map taps: if within categories call with that category; if it's the
                  // optional Unallocated slice, pass a synthetic breakdown item.
                  if (idx >= 0) {
                    if (idx < breakdown.length) {
                      final data = breakdown[idx];
                      onSliceTap?.call(data);
                    } else if (extraUnallocated > 0 && idx == breakdown.length) {
                      onSliceTap?.call(
                        CategoryBreakdown(name: 'Unallocated', spent: 0, limit: extraUnallocated),
                      );
                    }
                  }
                },
              ),
              sectionsSpace: 4,
              centerSpaceRadius: 40,
              sections: [
                // Category slices
                ...breakdown.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final cat = entry.value;
                  final percent = total == 0.0 ? 0.0 : (cat.limit / total) * 100;
                  return PieChartSectionData(
                    value: cat.limit,
                    // Show only percent on slice (and only if big enough)
                    title: percent >= labelThreshold ? '${percent.toStringAsFixed(0)}%' : '',
                    color: Colors.primaries[idx % Colors.primaries.length],
                    radius: 60,
                    titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  );
                }),
                // Optional Unallocated slice
                if (extraUnallocated > 0)
                  PieChartSectionData(
                    value: extraUnallocated,
                    title: ((extraUnallocated / total) * 100) >= labelThreshold
                        ? '${((extraUnallocated / total) * 100).toStringAsFixed(0)}%'
                        : '',
                    color: Colors.blueGrey,
                    radius: 60,
                    titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _ChartLegend(entries: legendEntries),
      ],
    );
  }
}

// Simple data holder for legend entries
class _LegendEntry {
  final String label;
  final Color color;
  final double percent;
  const _LegendEntry({required this.label, required this.color, required this.percent});
}

// Responsive legend for pie charts: shows colored dot, label and percent
class _ChartLegend extends StatelessWidget {
  final List<_LegendEntry> entries;
  const _ChartLegend({required this.entries, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: entries.map((e) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: e.color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(
                e.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 6),
              Text('${e.percent.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.grey)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// Simple horizontal thermometer-style progress bar
class ThermometerBar extends StatelessWidget {
  final double value; // current value
  final double max; // maximum (budget limit)
  final Color color;
  final double height;
  final BorderRadiusGeometry borderRadius;

  const ThermometerBar({
    required this.value,
    required this.max,
    this.color = Colors.deepPurple,
    this.height = 14,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final clamped = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    final over = value > max;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final fillWidth = width * clamped;
        return Stack(children: [
          Container(
            height: height,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: borderRadius,
            ),
          ),
          Container(
            height: height,
            width: fillWidth,
            decoration: BoxDecoration(
              color: over ? Colors.redAccent : color,
              borderRadius: borderRadius,
            ),
          ),
        ]);
      },
    );
  }
}

class BudgetPage extends StatefulWidget {
  const BudgetPage({Key? key}) : super(key: key);
  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  List<models.BudgetCategory> categories = [];
  List<models.IncomeSource> incomeSources = [];
  List<models.Liability> liabilities = [];
  // Scroll controller for showing a visible scrollbar when content overflows
  final ScrollController _budgetScroll = ScrollController();
  // Debt budgets are static (managed via Liabilities). Always show them, but tag and lock editing.
  double get totalIncome => incomeSources.fold(0.0, (s, i) => s + i.amount);

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadIncomeSources();
    _loadLiabilities();
  }

  @override
  void dispose() {
    _budgetScroll.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await RMinderDatabase.instance.getCategories();
      setState(() => categories = cats);
    } catch (e, st) {
      logError(e, st);
    }
  }

  Future<void> _loadIncomeSources() async {
    try {
      final sources = await RMinderDatabase.instance.getIncomeSources();
      setState(() => incomeSources = sources);
    } catch (e, st) {
      logError(e, st);
    }
  }

  Future<void> _loadLiabilities() async {
    try {
      final list = await RMinderDatabase.instance.getLiabilities();
      setState(() => liabilities = list);
    } catch (e, st) {
      logError(e, st);
    }
  }

  Future<void> _showAddIncomeSourceDialog() async {
    final nameController = TextEditingController();
    final amountController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Income Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatefulBuilder(builder: (context, setState) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Income Name'),
                  maxLength: 15,
                  onChanged: (_) => setState(() {}),
                ),
                if (nameController.text.length >= 15)
                  const Padding(
                    padding: EdgeInsets.only(left: 4.0),
                    child: Text('Maximum characters reached',
                        style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold)),
                  ),
              ]);
            }),
            TextField(
              controller: amountController,
              decoration: const InputDecoration(labelText: 'Amount'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final amount = double.tryParse(amountController.text.trim()) ?? 0;
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name cannot be empty.')));
                return;
              }
              if (amount <= 0) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Amount must be greater than 0.')));
                return;
              }
              await RMinderDatabase.instance.insertIncomeSource(models.IncomeSource(name: name, amount: amount));
              await _loadIncomeSources();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteIncomeSource(int id) async {
    await RMinderDatabase.instance.deleteIncomeSource(id);
    await _loadIncomeSources();
  }

  Future<void> _showAddCategoryDialog() async {
    final nameController = TextEditingController();
    final limitController = TextEditingController(text: '0');
    double sliderValue = 0;
    final allocated = categories.fold<double>(0.0, (s, c) => s + c.budgetLimit);
    final double maxValue = totalIncome > 0 ? ((totalIncome - allocated).clamp(0.0, totalIncome)).toDouble() : 10000.0;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Budget'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatefulBuilder(builder: (context, setState) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: 'Category Name'),
                        maxLength: 15,
                        onChanged: (_) => setState(() {}),
                      ),
                      if (nameController.text.length >= 15)
                        const Padding(
                          padding: EdgeInsets.only(left: 4.0),
                          child: Text(
                            'Maximum characters reached',
                            style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 8,
                              activeTrackColor: Colors.deepPurple[700],
                              inactiveTrackColor: Colors.deepPurple[200],
                              thumbColor: Colors.deepPurple[900],
                              overlayColor: Colors.deepPurple.withValues(alpha: 0.2),
                              valueIndicatorColor: Colors.deepPurple[700],
                            ),
                            child: Slider(
                              value: sliderValue,
                              min: 0,
                              max: maxValue,
                              divisions: maxValue > 0 ? maxValue.toInt() : null,
                              label: '₹${sliderValue.toStringAsFixed(0)}',
                              onChanged: (v) {
                                setState(() {
                                  sliderValue = v;
                                  limitController.text = v.toStringAsFixed(0);
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 100,
                          child: TextField(
                            controller: limitController,
                            decoration: const InputDecoration(labelText: 'Monthly Limit'),
                            keyboardType: TextInputType.number,
                            onChanged: (val) {
                              final parsed = double.tryParse(val) ?? 0;
                              setState(() => sliderValue = parsed.clamp(0.0, maxValue).toDouble());
                            },
                          ),
                        ),
                      ]),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final budgetLimit = double.tryParse(limitController.text.trim()) ?? 0;
              if (name.isNotEmpty && budgetLimit > 0) {
                await RMinderDatabase.instance.insertCategory(
                  models.BudgetCategory(name: name, budgetLimit: budgetLimit, spent: 0),
                );
                await _loadCategories();
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditCategoryDialog(models.BudgetCategory category) async {
    final nameController = TextEditingController(text: category.name);
    double sliderValue = category.budgetLimit;
    final allocatedOthers =
        categories.where((c) => c.id != category.id).fold<double>(0.0, (s, c) => s + c.budgetLimit);
    final double maxValue = totalIncome > 0 ? ((totalIncome - allocatedOthers).clamp(0.0, totalIncome)).toDouble() : 10000.0;
    // Ensure slider starts within the valid [0, maxValue] range to avoid slider assertion errors.
    sliderValue = sliderValue.clamp(0.0, maxValue).toDouble();
    final limitController = TextEditingController(text: sliderValue.toStringAsFixed(0));
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Budget Category'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatefulBuilder(builder: (context, setState) {
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Category Name'),
                    maxLength: 15,
                    onChanged: (_) => setState(() {}),
                  ),
                  if (nameController.text.length >= 15)
                    const Padding(
                      padding: EdgeInsets.only(left: 4.0),
                      child: Text('Maximum characters reached',
                          style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold)),
                    ),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 8,
                          activeTrackColor: Colors.deepPurple[700],
                          inactiveTrackColor: Colors.deepPurple[200],
                          thumbColor: Colors.deepPurple[900],
                          overlayColor: Colors.deepPurple.withValues(alpha: 0.2),
                          valueIndicatorColor: Colors.deepPurple[700],
                        ),
                        child: Slider(
                          value: sliderValue,
                          min: 0,
                          max: maxValue,
                          divisions: maxValue > 0 ? maxValue.toInt() : null,
                          label: '₹${sliderValue.toStringAsFixed(0)}',
                          onChanged: (v) {
                            setState(() {
                              sliderValue = v;
                              limitController.text = v.toStringAsFixed(0);
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: limitController,
                        decoration: const InputDecoration(labelText: 'Monthly Limit'),
                        keyboardType: TextInputType.number,
                        onChanged: (val) {
                          final parsed = double.tryParse(val) ?? 0;
                          setState(() => sliderValue = parsed.clamp(0.0, maxValue).toDouble());
                        },
                      ),
                    ),
                  ]),
                ]);
              }),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final budgetLimit = double.tryParse(limitController.text.trim()) ?? 0;
              if (name.isNotEmpty && budgetLimit > 0) {
                await RMinderDatabase.instance.updateCategory(models.BudgetCategory(
                  id: category.id,
                  name: name,
                  budgetLimit: budgetLimit,
                  spent: category.spent,
                ));
                await _loadCategories();
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteCategory(models.BudgetCategory category) async {
    final hasTransactions = await RMinderDatabase.instance.hasTransactionsForCategory(category.id ?? 0);
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text(
          hasTransactions
              ? 'Warning: This category has active transactions. Deleting it will also delete all related transactions. Do you want to proceed?'
              : 'Are you sure you want to delete this category?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (shouldDelete == true) {
      await RMinderDatabase.instance.deleteTransactionsForCategory(category.id ?? 0);
      await RMinderDatabase.instance.deleteCategory(category.id!);
      if (mounted) setState(() => categories.removeWhere((c) => c.id == category.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Budget')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Scrollbar(
          controller: _budgetScroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _budgetScroll,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Income', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                        onPressed: _showAddIncomeSourceDialog,
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    incomeSources.isEmpty
                        ? const Center(child: Text('No income sources yet.'))
                        : Column(
                            children: incomeSources
                                .map((src) => Card(
                                      child: ListTile(
                                        title: Text(
                                          src.name,
                                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                                        ),
                                        subtitle: Text('Amount: ₹${src.amount.toStringAsFixed(2)}'),
                                        trailing: IconButton(
                                          icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
                                          onPressed: () => _deleteIncomeSource(src.id!),
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Budget', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                        onPressed: () {
                          if (totalIncome == 0) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                content: Text('Please add your income before adding a budget category.')));
                          } else {
                            _showAddCategoryDialog();
                          }
                        },
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    // Expenses section (non-debt categories)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shopping_bag, size: 18, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 6),
                          Text('Expenses', style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...categories
                        .where((c) => !liabilities.any((l) => l.budgetCategoryId == c.id))
                        .map((category) => Card(
                              child: ListTile(
                                key: ValueKey(category.id),
                                title: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      category.name.length > 15
                                          ? '${category.name.substring(0, 15)}...'
                                          : category.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Limit: ₹${category.budgetLimit.toStringAsFixed(2)}',
                                      style: TextStyle(color: Theme.of(context).colorScheme.primary),
                                    ),
                                  ],
                                ),
                                trailing: Wrap(spacing: 4, children: [
                                  IconButton(
                                    icon: Icon(Icons.edit, color: Theme.of(context).colorScheme.primary),
                                    onPressed: () => _showEditCategoryDialog(category),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
                                    onPressed: () => _confirmDeleteCategory(category),
                                  ),
                                ]),
                              ),
                            )),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.savings, size: 18, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 6),
                          Text('Liabilities', style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (liabilities.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6.0),
                        child: Text('No liabilities added yet.'),
                      )
                    else
                      ...liabilities.map((liab) => Card(
                            child: ListTile(
                              key: ValueKey('liab-${liab.id}'),
                              title: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    liab.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Min: ₹${liab.planned.toStringAsFixed(2)}',
                                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                                  ),
                                ],
                              ),
                              trailing: Wrap(spacing: 4, children: [
                                IconButton(
                                  icon: Icon(Icons.edit, color: Theme.of(context).colorScheme.primary),
                                  tooltip: 'Edit in Liabilities',
                                  onPressed: () {
                                    // Switch tab first, then post edit intent on next frame to ensure listener is attached
                                    TabSwitcher.of(context)?.switchTo(3);
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      UiIntents.editLiabilityId.value = liab.id;
                                    });
                                  },
                                ),
                              ]),
                            ),
                          )),
                  ]),
                ),
              ),
              // Liabilities are edited in the Liabilities tab and surfaced here for convenience.
            ],
            ),
          ),
        ),
      ),
    );
  }
}

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({Key? key}) : super(key: key);
  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  List<models.Transaction> transactions = [];
  List<models.BudgetCategory> categories = [];
  List<models.Liability> liabilities = [];
  // Show debt transactions by default; allow optionally hiding them.
  bool _hideDebt = false;
  // Scroll controller for list & scrollbar
  final ScrollController _txScroll = ScrollController();
  models.BudgetCategory? _filterCategory;
  DateTime? _filterSingleDate;
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  DateTime? _filterMonthDate;
  double? _filterMinAmount;
  double? _filterMaxAmount;

  String _formatShortDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final day = d.day;
    final mon = months[d.month - 1];
    final yy = (d.year % 100).toString().padLeft(2, '0');
    return '$day $mon $yy';
  }

  String _formatMonthYear(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final mon = months[d.month - 1];
    final yy = (d.year % 100).toString().padLeft(2, '0');
    return '$mon $yy';
  }

  @override
  void initState() {
    super.initState();
    _loadCategoriesAndTransactions();
  }

  @override
  void dispose() {
    _txScroll.dispose();
    super.dispose();
  }

  Future<void> _loadCategoriesAndTransactions() async {
    try {
      final cats = await RMinderDatabase.instance.getCategories();
      final txns = await RMinderDatabase.instance.getTransactions();
      final liabs = await RMinderDatabase.instance.getLiabilities();
      final validCategoryIds = cats.map((c) => c.id).toSet();
      final orphaned = txns.where((t) => !validCategoryIds.contains(t.categoryId)).toList();
      for (final t in orphaned) {
        await RMinderDatabase.instance.deleteTransaction(t.id!);
        logError('Deleted orphaned transaction with id: ${t.id}, missing category: ${t.categoryId}');
      }
      setState(() {
        categories = cats;
        transactions = txns.where((t) => validCategoryIds.contains(t.categoryId)).toList();
        liabilities = liabs;
      });
    } catch (e, st) {
      logError(e, st);
    }
  }

  List<models.Transaction> get filteredTransactions {
    final debtCategoryIds = liabilities.map((l) => l.budgetCategoryId).toSet();
    return transactions.where((txn) {
      final byCategory = _filterCategory == null || txn.categoryId == _filterCategory!.id;
      // If hiding debt, exclude debt-category transactions; otherwise include all.
      final byDebt = !_hideDebt || !debtCategoryIds.contains(txn.categoryId);
      bool byDate = true;
      if (_filterSingleDate != null) {
        byDate = txn.date.year == _filterSingleDate!.year && txn.date.month == _filterSingleDate!.month && txn.date.day == _filterSingleDate!.day;
      } else if (_filterStartDate != null && _filterEndDate != null) {
        byDate = !txn.date.isBefore(_filterStartDate!) && !txn.date.isAfter(_filterEndDate!);
      } else if (_filterMonthDate != null) {
        byDate = txn.date.year == _filterMonthDate!.year && txn.date.month == _filterMonthDate!.month;
      }
      bool byAmount = true;
      if (_filterMinAmount != null) byAmount = txn.amount >= _filterMinAmount!;
      if (_filterMaxAmount != null) byAmount = byAmount && txn.amount <= _filterMaxAmount!;
      return byCategory && byDebt && byDate && byAmount;
    }).toList();
  }

  Future<void> _showAddTransactionDialog() async {
    models.BudgetCategory? selectedCategory = categories.isNotEmpty ? categories[0] : null;
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Transaction'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            StatefulBuilder(builder: (context, setState) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                DropdownButton<models.BudgetCategory>(
                  value: selectedCategory,
                  isExpanded: true,
                  items: categories
                      .map((cat) => DropdownMenuItem(value: cat, child: Text(cat.name)))
                      .toList(),
                  onChanged: (cat) => setState(() => selectedCategory = cat),
                ),
                TextField(
                  controller: amountController,
                  decoration: const InputDecoration(labelText: 'Amount'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(labelText: 'Note (optional)'),
                  maxLength: 30,
                  onChanged: (_) => setState(() {}),
                ),
                if (noteController.text.length >= 30)
                  const Padding(
                    padding: EdgeInsets.only(left: 4.0),
                    child: Text('Maximum characters reached',
                        style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold)),
                  ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => selectedDate = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_today, size: 18, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Day: ${_formatShortDate(selectedDate)}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ]);
            }),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountController.text.trim()) ?? 0;
              final catId = selectedCategory?.id;
              if (catId == null) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Please select a category.')));
                return;
              }
              if (amount <= 0) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Amount must be greater than 0.')));
                return;
              }
              await RMinderDatabase.instance.insertTransaction(models.Transaction(
                categoryId: catId,
                amount: amount,
                date: selectedDate,
                note: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
              ));
              await _loadCategoriesAndTransactions();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditTransactionDialog(models.Transaction txn) async {
    models.BudgetCategory? selectedCategory =
        categories.firstWhere((c) => c.id == txn.categoryId, orElse: () => categories.isNotEmpty ? categories[0] : models.BudgetCategory(id: -1, name: 'N/A', budgetLimit: 0, spent: 0));
    final amountController = TextEditingController(text: txn.amount.toString());
    final noteController = TextEditingController(text: txn.note ?? '');
    DateTime selectedDate = txn.date;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Transaction'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            StatefulBuilder(builder: (context, setState) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                DropdownButton<models.BudgetCategory>(
                  value: selectedCategory,
                  isExpanded: true,
                  items:
                      categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat.name))).toList(),
                  onChanged: (cat) => setState(() => selectedCategory = cat),
                ),
                TextField(
                  controller: amountController,
                  decoration: const InputDecoration(labelText: 'Amount'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(labelText: 'Note (optional)'),
                  maxLength: 30,
                  onChanged: (_) => setState(() {}),
                ),
                if (noteController.text.length >= 30)
                  const Padding(
                    padding: EdgeInsets.only(left: 4.0),
                    child: Text('Maximum characters reached',
                        style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold)),
                  ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => selectedDate = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_today, size: 18, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Day: ${_formatShortDate(selectedDate)}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ]);
            }),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountController.text.trim()) ?? 0;
              final catId = selectedCategory?.id;
              if (catId == null || catId == -1) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Please select a category.')));
                return;
              }
              if (amount <= 0) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Amount must be greater than 0.')));
                return;
              }
              await RMinderDatabase.instance.updateTransaction(models.Transaction(
                id: txn.id,
                categoryId: catId,
                amount: amount,
                date: selectedDate,
                note: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
              ));
              await _loadCategoriesAndTransactions();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteTransaction(models.Transaction txn) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: const Text('Are you sure you want to delete this transaction?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await RMinderDatabase.instance.deleteTransaction(txn.id!);
      await _loadCategoriesAndTransactions();
    }
  }

  Future<void> _showFilterDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        models.BudgetCategory? tempCategory = _filterCategory;
        DateTime? tempSingleDate = _filterSingleDate;
        DateTime? tempStartDate = _filterStartDate;
        DateTime? tempEndDate = _filterEndDate;
        DateTime? tempMonthDate = _filterMonthDate;
        double? tempMinAmount = _filterMinAmount;
        double? tempMaxAmount = _filterMaxAmount;
        bool tempHideDebt = _hideDebt;
        String dateMode = (tempSingleDate != null)
            ? 'single'
            : (tempStartDate != null || tempEndDate != null)
                ? 'range'
                : (tempMonthDate != null)
                    ? 'month'
                    : 'none';
        // Build last 24 months list for dropdown
        final now = DateTime.now();
        final List<DateTime> monthOptions = List.generate(24, (i) {
          final base = DateTime(now.year, now.month - i, 1);
          return DateTime(base.year, base.month, 1);
        });
        // Pre-compute amount bounds from existing transactions to drive the slider.
        double _amountMinAvailable = 0;
        double _amountMaxAvailable = 1000;
        if (transactions.isNotEmpty) {
          final amts = transactions.map((t) => t.amount).toList();
          _amountMinAvailable = amts.reduce((a, b) => a < b ? a : b);
          _amountMaxAvailable = amts.reduce((a, b) => a > b ? a : b);
          if (_amountMaxAvailable <= _amountMinAvailable) {
            _amountMaxAvailable = _amountMinAvailable + 1;
          }
        }
    double _currentMin = (tempMinAmount ?? _amountMinAvailable).clamp(_amountMinAvailable, _amountMaxAvailable);
    double _currentMax = (tempMaxAmount ?? _amountMaxAvailable).clamp(_currentMin, _amountMaxAvailable);
    RangeValues amountRange = RangeValues(_currentMin, _currentMax);
    final TextEditingController minAmountController =
      TextEditingController(text: amountRange.start.toStringAsFixed(0));
    final TextEditingController maxAmountController =
      TextEditingController(text: amountRange.end.toStringAsFixed(0));

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Customize Filter'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 520,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    DropdownButton<models.BudgetCategory>(
                      value: tempCategory,
                      hint: const Text('Category'),
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All Categories')),
                        ...categories.map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                      ],
                      onChanged: (cat) => setState(() => tempCategory = cat),
                    ),
                    const SizedBox(height: 8),
                    FilterChip(
                      label: const Text('Hide Debt'),
                      selected: tempHideDebt,
                      onSelected: (v) => setState(() => tempHideDebt = v),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      ChoiceChip(
                        label: const Text('Day'),
                        selected: dateMode == 'single',
                        onSelected: (_) {
                          setState(() {
                            dateMode = 'single';
                            tempSingleDate = DateTime.now();
                            tempStartDate = null;
                            tempEndDate = null;
                            tempMonthDate = null;
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Range'),
                        selected: dateMode == 'range',
                        onSelected: (_) {
                          setState(() {
                            dateMode = 'range';
                            tempSingleDate = null;
                            // Default preset: first day of current month to today
                            tempStartDate = DateTime(now.year, now.month, 1);
                            tempEndDate = now;
                            tempMonthDate = null;
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Month'),
                        selected: dateMode == 'month',
                        onSelected: (_) {
                          setState(() {
                            dateMode = 'month';
                            tempSingleDate = null;
                            tempStartDate = null;
                            tempEndDate = null;
                            tempMonthDate = tempMonthDate ?? monthOptions.first;
                          });
                        },
                      ),
                    ]),
                    if (dateMode == 'single')
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: tempSingleDate ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) setState(() => tempSingleDate = picked);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.calendar_today, size: 18, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                tempSingleDate == null
                                    ? 'Pick a day'
                                    : 'Day: ${_formatShortDate(tempSingleDate!)}',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (dateMode == 'range')
                      InkWell(
                        onTap: () async {
                          final start = tempStartDate ?? DateTime(now.year, now.month, 1);
                          final end = tempEndDate ?? now;
                          final pickedRange = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                            initialDateRange: DateTimeRange(start: start, end: end),
                            initialEntryMode: DatePickerEntryMode.calendarOnly,
                          );
                          if (pickedRange != null) {
                            setState(() {
                              tempStartDate = pickedRange.start;
                              tempEndDate = pickedRange.end;
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.date_range, size: 18, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Date Range: '
                                  '${_formatShortDate((tempStartDate ?? DateTime(now.year, now.month, 1)))}'
                                  ' - '
                                  '${_formatShortDate((tempEndDate ?? now))}',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (dateMode == 'month')
                      InkWell(
                        onTap: () async {
                          // Show a simple dialog with a dropdown inside (keeping behavior consistent with prior UX)
                          DateTime localSel = tempMonthDate ?? monthOptions.first;
                          final selected = await showDialog<DateTime>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Select Month'),
                              content: StatefulBuilder(
                                builder: (ctx, setInner) {
                                  return DropdownButton<DateTime>(
                                    value: localSel,
                                    isExpanded: true,
                                    items: monthOptions
                                        .map((dt) => DropdownMenuItem(
                                              value: dt,
                                              child: Text(_formatMonthYear(dt)),
                                            ))
                                        .toList(),
                                    onChanged: (dt) => setInner(() => localSel = dt ?? localSel),
                                  );
                                },
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(ctx, localSel),
                                  child: const Text('Select'),
                                ),
                              ],
                            ),
                          );
                          if (selected != null) setState(() => tempMonthDate = selected);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.calendar_month, size: 18, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                'Month: ${_formatMonthYear(tempMonthDate ?? monthOptions.first)}',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    const Text('Amount Range'),
        Row(children: [
                      Expanded(
                        child: TextField(
          controller: minAmountController,
                          decoration: const InputDecoration(hintText: 'Min'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final parsed = double.tryParse(val);
                            setState(() {
                              if (parsed == null) {
                                tempMinAmount = null;
                              } else {
                                final clamped = parsed.clamp(_amountMinAvailable, _amountMaxAvailable).toDouble();
                                tempMinAmount = clamped;
                                if (amountRange.start != clamped) {
                                  amountRange = RangeValues(clamped, amountRange.end < clamped ? clamped : amountRange.end);
                                  // Reflect any clamp in the text boxes
                                  final newMin = clamped.toStringAsFixed(0);
                                  if (minAmountController.text != newMin) {
                                    minAmountController.text = newMin;
                                  }
                                  if (amountRange.end < clamped) {
                                    final newMax = clamped.toStringAsFixed(0);
                                    if (maxAmountController.text != newMax) {
                                      maxAmountController.text = newMax;
                                    }
                                  }
                                }
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
          controller: maxAmountController,
                          decoration: const InputDecoration(hintText: 'Max'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final parsed = double.tryParse(val);
                            setState(() {
                              if (parsed == null) {
                                tempMaxAmount = null;
                              } else {
                                final clamped = parsed.clamp(_amountMinAvailable, _amountMaxAvailable).toDouble();
                                tempMaxAmount = clamped;
                                if (amountRange.end != clamped) {
                                  amountRange = RangeValues(amountRange.start > clamped ? clamped : amountRange.start, clamped);
                                  // Reflect any clamp in the text boxes
                                  final newMax = clamped.toStringAsFixed(0);
                                  if (maxAmountController.text != newMax) {
                                    maxAmountController.text = newMax;
                                  }
                                  if (amountRange.start > clamped) {
                                    final newMin = clamped.toStringAsFixed(0);
                                    if (minAmountController.text != newMin) {
                                      minAmountController.text = newMin;
                                    }
                                  }
                                }
                              }
                            });
                          },
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
        RangeSlider(
                      values: amountRange,
                      min: _amountMinAvailable,
                      max: _amountMaxAvailable,
                      labels: RangeLabels(
                        amountRange.start.toStringAsFixed(0),
                        amountRange.end.toStringAsFixed(0),
                      ),
                      onChanged: (values) {
                        setState(() {
                          amountRange = values;
                          tempMinAmount = values.start;
                          tempMaxAmount = values.end;
          minAmountController.text = values.start.toStringAsFixed(0);
          maxAmountController.text = values.end.toStringAsFixed(0);
                        });
                      },
                    ),
                  ]),
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('Clear'),
                  onPressed: () {
                    setState(() {
                      tempCategory = null;
                      tempSingleDate = null;
                      tempStartDate = null;
                      tempEndDate = null;
                      tempMonthDate = null;
                      tempMinAmount = null;
                      tempMaxAmount = null;
                      tempHideDebt = false;
                      dateMode = 'none';
                      // Reset slider and text controllers to full available range
                      amountRange = RangeValues(_amountMinAvailable, _amountMaxAvailable);
                      minAmountController.text = _amountMinAvailable.toStringAsFixed(0);
                      maxAmountController.text = _amountMaxAvailable.toStringAsFixed(0);
                    });
                  },
                ),
                ElevatedButton(
                  child: const Text('Apply'),
                  onPressed: () {
                    Navigator.of(context).pop({
                      'category': tempCategory,
                      'singleDate': tempSingleDate,
                      'startDate': tempStartDate,
                      'endDate': tempEndDate,
                      'monthDate': tempMonthDate,
                      'minAmount': tempMinAmount,
                      'maxAmount': tempMaxAmount,
                      'hideDebt': tempHideDebt,
                      'dateMode': dateMode,
                    });
                  },
                ),
              ],
            );
          },
        );
      },
    );
    if (result != null) {
      if (!mounted) return;
      setState(() {
        _filterCategory = result['category'] as models.BudgetCategory?;
        final mode = (result['dateMode'] as String?) ?? 'none';
        if (mode == 'single') {
          _filterSingleDate = result['singleDate'] as DateTime?;
          _filterStartDate = null;
          _filterEndDate = null;
          _filterMonthDate = null;
        } else if (mode == 'range') {
          _filterStartDate = result['startDate'] as DateTime?;
          _filterEndDate = result['endDate'] as DateTime?;
          _filterSingleDate = null;
          _filterMonthDate = null;
        } else if (mode == 'month') {
          _filterMonthDate = result['monthDate'] as DateTime?;
          _filterSingleDate = null;
          _filterStartDate = null;
          _filterEndDate = null;
        } else {
          _filterSingleDate = null;
          _filterStartDate = null;
          _filterEndDate = null;
          _filterMonthDate = null;
        }
        _filterMinAmount = result['minAmount'] as double?;
        _filterMaxAmount = result['maxAmount'] as double?;
        final hideDebtRes = result['hideDebt'];
        if (hideDebtRes is bool) _hideDebt = hideDebtRes;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      return Scaffold(
        appBar: AppBar(title: const Text('Transactions')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.filter_list),
                label: const Text('Filter'),
                onPressed: _showFilterDialog,
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add'),
                onPressed: categories.isEmpty ? null : _showAddTransactionDialog,
              ),
            ]),
            Expanded(
              child: categories.isEmpty
                  ? const Center(child: Text('No categories available. Add a category to begin.'))
                  : filteredTransactions.isEmpty
                      ? const Center(child: Text('No transactions yet.'))
                      : Scrollbar(
                          controller: _txScroll,
                          thumbVisibility: true,
                          child: ListView.builder(
                            controller: _txScroll,
                            itemCount: filteredTransactions.length,
                            itemBuilder: (context, index) {
                            final txn = filteredTransactions[index];
                            final catList = categories.where((c) => c.id == txn.categoryId);
                            if (catList.isEmpty) {
                              logError('Transaction with missing category: ${txn.categoryId}');
                              return const SizedBox.shrink();
                            }
                            final cat = catList.first;
                            final isDebt = liabilities.any((l) => l.budgetCategoryId == txn.categoryId);
                            return Card(
                              child: ListTile(
                                leading: Icon(
                                  isDebt ? Icons.savings : Icons.shopping_bag,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                title: Text('${cat.name} - ₹${txn.amount.toStringAsFixed(2)}'),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      () {
                                        final dateStr = txn.date.toLocal().toString().split(' ')[0];
                                        if (isDebt) return dateStr; // icon already conveys debt, omit debt note
                                        final note = txn.note;
                                        if (note == null || note.trim().isEmpty) return dateStr;
                                        return '$dateStr | $note';
                                      }(),
                                    ),
                                  ],
                                ),
                                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    tooltip: 'Edit',
                                    onPressed: () => _showEditTransactionDialog(txn),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    tooltip: 'Delete',
                                    onPressed: () => _confirmDeleteTransaction(txn),
                                  ),
                                ]),
                              ),
                            );
                          },
                        ),
                      ),
            ),
          ]),
        ),
      );
    } catch (e, st) {
      logError(e, st);
      return const Center(child: Text('An error occurred. Please restart the app.'));
    }
  }
}

class ReportingPage extends StatefulWidget {
  const ReportingPage({Key? key}) : super(key: key);
  @override
  State<ReportingPage> createState() => _ReportingPageState();
}

// Close-month actions
enum CloseAction { carryForward, payDebt }

class _ReportingPageState extends State<ReportingPage> {
  List<models.BudgetCategory> categories = [];
  List<models.Transaction> transactions = [];
  List<models.Liability> liabilities = [];
  List<models.IncomeSource> incomeSources = [];
  DateTime selectedMonth = DateTime.now();
  // Months the user has explicitly closed and saved summaries for
  List<DateTime> _closedMonths = [];
  bool _isDetailsDialogOpen = false; // prevent duplicate dialog opens
  // Scroll controller for outer report scroll
  final ScrollController _reportScroll = ScrollController();
  // Debt transactions are never counted as "spending" in reports; they are listed separately.

  String _shortMonthName(int m) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return names[m - 1];
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _reportScroll.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final cats = await RMinderDatabase.instance.getCategories();
      final txns = await RMinderDatabase.instance.getTransactions();
      final liabs = await RMinderDatabase.instance.getLiabilities();
      final incomes = await RMinderDatabase.instance.getIncomeSources();
      final closed = await RMinderDatabase.instance.getClosedMonths();
      setState(() {
        categories = cats;
        transactions = txns;
        liabilities = liabs;
        incomeSources = incomes;
        _closedMonths = closed;
      });
    } catch (e, st) {
      logError(e, st);
    }
  }

  bool _isSameMonth(DateTime a, DateTime b) => a.year == b.year && a.month == b.month;

  MonthlySummary getMonthlySummary() {
    // Compute per-category spending for the selected month
    final debtCategoryIds = liabilities.map((l) => l.budgetCategoryId).toSet();
    final Map<int, double> spentByCategoryThisMonth = {};
    for (final txn in transactions) {
      if (_isSameMonth(txn.date, selectedMonth)) {
        // Debt payments are not considered spending
        if (debtCategoryIds.contains(txn.categoryId)) continue;
        spentByCategoryThisMonth.update(txn.categoryId, (v) => v + txn.amount, ifAbsent: () => txn.amount);
      }
    }
    double totalSpent = 0;
    double totalLimit = 0;
    List<CategoryBreakdown> breakdown = [];
    for (final cat in categories) {
      // Exclude debt categories from spending breakdown
      if (debtCategoryIds.contains(cat.id)) continue;
      final spent = spentByCategoryThisMonth[cat.id!] ?? 0;
      totalSpent += spent;
      totalLimit += cat.budgetLimit;
      breakdown.add(CategoryBreakdown(name: cat.name, spent: spent, limit: cat.budgetLimit, categoryId: cat.id));
    }
    return MonthlySummary(
      totalSpent: totalSpent,
      totalLimit: totalLimit,
      totalRemaining: totalLimit - totalSpent,
      breakdown: breakdown,
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = getMonthlySummary();
    // Allowed months: all closed months + current month
    final currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final List<DateTime> allowedMonths = ([..._closedMonths, currentMonth]
          ..sort((a, b) => a.compareTo(b)))
        .map((d) => DateTime(d.year, d.month, 1))
        .toList();
    // Ensure selectedMonth is within allowed set
    if (!allowedMonths.any((m) => _isSameMonth(m, selectedMonth))) {
      // default to current month
      selectedMonth = currentMonth;
    }
    final int currentIndex = allowedMonths.indexWhere((m) => _isSameMonth(m, selectedMonth));
    final bool canGoPrev = currentIndex > 0;
    final bool canGoNext = currentIndex >= 0 && currentIndex < allowedMonths.length - 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report'),
        actions: [
          IconButton(
            tooltip: 'Previous Month',
            icon: const Icon(Icons.chevron_left),
            onPressed: canGoPrev
                ? () => setState(() {
                      selectedMonth = allowedMonths[currentIndex - 1];
                    })
                : null,
          ),
          // Fix width so chevrons don't shift when text length changes
          Center(
              child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: SizedBox(
              width: 110,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('${_shortMonthName(selectedMonth.month)} ${selectedMonth.year}'),
              ),
            ),
          )),
          IconButton(
            tooltip: 'Next Month',
            icon: const Icon(Icons.chevron_right),
            onPressed: canGoNext
                ? () => setState(() {
                      selectedMonth = allowedMonths[currentIndex + 1];
                    })
                : null,
          ),
          IconButton(
            tooltip: 'Close Month',
            icon: const Icon(Icons.task_alt),
            onPressed: _closeMonthFlow,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Scrollbar(
          controller: _reportScroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _reportScroll,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Monthly Summary', style: Theme.of(context).textTheme.headlineSmall),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Builder(builder: (_) {
                  final totalIncome = incomeSources.fold<double>(0, (s, i) => s + i.amount);
                  final totalBudgeted = categories.fold<double>(0, (s, c) => s + c.budgetLimit);
                  final unallocated = totalIncome - totalBudgeted;
                  final hasIncome = totalIncome > 0;
                  final hasBudget = totalBudgeted > 0;
                  final isNoIncomeButBudgeted = !hasIncome && hasBudget;
                  final isOverBudgeted = hasIncome && totalBudgeted > totalIncome;

                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Budget Summary', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('Total Income: ₹${totalIncome.toStringAsFixed(2)}'),
                    Text('Total Budgeted: ₹${totalBudgeted.toStringAsFixed(2)}'),

                    // Status line
                    if (isNoIncomeButBudgeted) ...[
                      const SizedBox(height: 4),
                      const Text(
                        'No income declared',
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Tip: Add income sources under Budget.',
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.account_balance_wallet),
                          label: const Text('Go to Budget'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            TabSwitcher.of(context)?.switchTo(0);
                          },
                        ),
                      ),
                    ] else if (isOverBudgeted) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Overbudgeted by ₹${(totalBudgeted - totalIncome).toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Tip: Reduce some category limits until your total budgeted amount is at or below your income.',
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.account_balance_wallet),
                          label: const Text('Go to Budget'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            TabSwitcher.of(context)?.switchTo(0);
                          },
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 4),
                      Text(
                        'Unallocated: ₹${unallocated.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: unallocated == 0 ? Colors.green : Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (unallocated != 0)
                        const Padding(
                          padding: EdgeInsets.only(top: 4.0),
                          child: Text(
                            'Tip: Go to the budget page to give your money a purpose.',
                            style: TextStyle(fontSize: 12, color: Colors.orange),
                          ),
                        ),
                      if (unallocated > 0) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.account_balance_wallet),
                            label: const Text('Go to Budget'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () {
                              TabSwitcher.of(context)?.switchTo(0);
                            },
                          ),
                        ),
                      ],
                    ],
                  ]);
                }),
              ),
            ),
            // Over-budget guidance banner
            Builder(builder: (_) {
              final overBudget = summary.breakdown.where((b) => b.spent > b.limit).toList();
              if (overBudget.isEmpty) return const SizedBox.shrink();
              final totalOver = overBudget.fold<double>(0, (s, b) => s + (b.spent - b.limit));
              return Padding(
                padding: const EdgeInsets.only(top: 10.0),
                child: Card(
                  color: Colors.red.withValues(alpha: 0.06),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.warning, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${overBudget.length} ${overBudget.length == 1 ? 'category is' : 'categories are'} over budget· Over by ₹${totalOver.toStringAsFixed(0)}',
                            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ]),
                      if (overBudget.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: overBudget
                              .map((b) => Chip(
                                    avatar: const Icon(Icons.trending_up, size: 16, color: Colors.red),
                                    label: Text('${b.name}: +₹${(b.spent - b.limit).toStringAsFixed(0)}'),
                                    backgroundColor: Colors.red.withValues(alpha: 0.08),
                                    labelStyle: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                                  ))
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.account_balance_wallet),
                          label: const Text('Go to Budget'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            TabSwitcher.of(context)?.switchTo(0);
                          },
                        ),
                      ),
                    ]),
                  ),
                ),
              );
            }),
            const SizedBox(height: 10),
            Text('Budget Allocation', style: Theme.of(context).textTheme.titleMedium),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: BudgetAllocationChart(
                  // Allocation should include all categories (including debt). Tag debt in names.
                  breakdown: categories.map((c) {
                    return CategoryBreakdown(
                      name: c.name,
                      spent: 0,
                      limit: c.budgetLimit,
                      categoryId: c.id,
                    );
                  }).toList(),
                  unallocatedAmount: (() {
                    final income = incomeSources.fold<double>(0, (s, i) => s + i.amount);
                    final budgeted = categories.fold<double>(0, (s, c) => s + c.budgetLimit);
                    final u = income - budgeted;
                    return u > 0 ? u : 0.0;
                  })(),
                  onSliceTap: (data) => _showCategoryDetails(context, data),
                ),
              ),
            ),
            const SizedBox(height: 10),
            summary.breakdown.isEmpty
                ? const Center(child: Text('No categories available. Add a category to view reports.'))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Spending by Category', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: summary.breakdown.length,
                      itemBuilder: (context, index) {
                        final cat = summary.breakdown[index];
                        final remaining = cat.limit - cat.spent;
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                  Text(
                                    '₹${cat.spent.toStringAsFixed(0)} / ₹${cat.limit.toStringAsFixed(0)}',
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ThermometerBar(
                                value: cat.spent,
                                max: cat.limit <= 0 ? 1 : cat.limit,
                                color: Colors.deepPurple,
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Spent: ₹${cat.spent.toStringAsFixed(2)}'),
                                  Text(
                                    'Remaining: ₹${remaining.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: remaining < 0 ? Colors.red : Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
                  ]),
            const SizedBox(height: 16),
            if (liabilities.isNotEmpty) ...[
              Text('Debt Payments', style: Theme.of(context).textTheme.titleMedium),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: liabilities.length,
                itemBuilder: (context, index) {
                  final liab = liabilities[index];
                  final paid = _paidThisMonthFor(liab);
                  final delta = paid - liab.planned;
                  return Card(
                    child: ListTile(
                      title: Text(liab.name),
                      subtitle: Text('Min: ₹${liab.planned.toStringAsFixed(2)} | Paid: ₹${paid.toStringAsFixed(2)}'),
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Text('Δ vs Plan'),
                        Text(
                          '₹${delta.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: delta >= 0 ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  DateTime _startOfNextMonth(DateTime m) => DateTime(m.year, m.month + 1, 1);
  DateTime _endOfMonth(DateTime m) => DateTime(m.year, m.month + 1, 0);

  Future<void> _closeMonthFlow() async {
    // Preconditions:
    // 1) Date must be at or after the first day of the next month.
    final now = DateTime.now();
    final earliestClose = DateTime(selectedMonth.year, selectedMonth.month + 1, 1);
    if (now.isBefore(earliestClose)) {
      if (!mounted) return;
      final nextName = _monthName(earliestClose.month);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You can only close ${_monthName(selectedMonth.month)} after $nextName 1.')),
      );
      return;
    }

    // 2b) Prevent duplicate closure: if this month already recorded as closed, block
    final alreadyClosed = await RMinderDatabase.instance.isMonthClosed(selectedMonth);
    if (alreadyClosed) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_monthName(selectedMonth.month)} ${selectedMonth.year} is already closed.')),
      );
      return;
    }

    // 2) All liabilities must have at least their minimum payment covered for the selected month.
    final List<Map<String, dynamic>> minShortfalls = [];
    for (final liab in liabilities) {
      final paid = _paidThisMonthFor(liab);
      final remaining = (liab.planned - paid);
      if (remaining > 0.01) {
        minShortfalls.add({'name': liab.name, 'remaining': remaining});
      }
    }
    if (minShortfalls.isNotEmpty) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Minimum payments required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Before closing ${_monthName(selectedMonth.month)} ${selectedMonth.year}, please complete the minimum payments:'),
              const SizedBox(height: 8),
              ...minShortfalls.map((m) => Text('${m['name']}: ₹${(m['remaining'] as double).toStringAsFixed(2)} remaining')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                TabSwitcher.of(context)?.switchTo(3); // Go to Liabilities tab
              },
              child: const Text('Go to Liabilities'),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        ),
      );
      return;
    }

    // Compute unspent per non-debt category for the selected month
    final debtCategoryIds = liabilities.map((l) => l.budgetCategoryId).toSet();
    final Map<int, double> spentByCategoryThisMonth = {};
    for (final txn in transactions) {
      if (_isSameMonth(txn.date, selectedMonth)) {
        if (debtCategoryIds.contains(txn.categoryId)) continue;
        spentByCategoryThisMonth.update(txn.categoryId, (v) => v + txn.amount, ifAbsent: () => txn.amount);
      }
    }
    final List<models.BudgetCategory> regularCats = categories.where((c) => !debtCategoryIds.contains(c.id)).toList();
    final Map<models.BudgetCategory, double> leftoverByCat = {
      for (final c in regularCats)
        c: (c.budgetLimit - (spentByCategoryThisMonth[c.id] ?? 0)).clamp(0, double.infinity)
    };
    final double totalLeftover = leftoverByCat.values.fold(0.0, (s, v) => s + v);
    if (totalLeftover <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No unspent money to close for this month.')));
      return;
    }

    CloseAction mode = CloseAction.carryForward;
    models.Liability? selectedLiab = liabilities.isNotEmpty ? liabilities.first : null;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Close Month'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Month: ${_monthName(selectedMonth.month)} ${selectedMonth.year}'),
              const SizedBox(height: 8),
              Text('Total unspent across categories: ₹${totalLeftover.toStringAsFixed(2)}'),
              const SizedBox(height: 8),
              const Text('Choose what to do with unspent money:'),
              const SizedBox(height: 6),
              RadioListTile<CloseAction>(
                value: CloseAction.carryForward,
                groupValue: mode,
                onChanged: (v) => setLocal(() => mode = v ?? mode),
                title: const Text('Carry forward to next month'),
                subtitle: const Text('Add leftover as extra available amount next month.'),
              ),
              RadioListTile<CloseAction>(
                value: CloseAction.payDebt,
                groupValue: mode,
                onChanged: liabilities.isEmpty ? null : (v) => setLocal(() => mode = v ?? mode),
                title: const Text('Use unspent to pay debt'),
                subtitle: liabilities.isEmpty
                    ? const Text('No liabilities added')
                    : DropdownButton<models.Liability>(
                        value: selectedLiab,
                        isExpanded: true,
                        items: liabilities
                            .map((l) => DropdownMenuItem(value: l, child: Text(l.name)))
                            .toList(),
                        onChanged: (l) => setLocal(() => selectedLiab = l),
                      ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Note: Budget limits persist each month. "Copy budget to next month" is not required.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      if (mode == CloseAction.carryForward) {
        final nextStart = _startOfNextMonth(selectedMonth);
        for (final entry in leftoverByCat.entries) {
          final leftover = entry.value;
          if (leftover <= 0) continue;
          final cat = entry.key;
          await RMinderDatabase.instance.insertTransaction(models.Transaction(
            categoryId: cat.id!,
            amount: -leftover,
            date: nextStart,
            note: 'Carry forward from ${_monthName(selectedMonth.month)} ${selectedMonth.year}',
          ));
        }
        await RMinderDatabase.instance.insertClosedMonth(
          monthStart: DateTime(selectedMonth.year, selectedMonth.month, 1),
          action: 'carryForward',
        );
        await _loadData();
        if (!mounted) return;
        setState(() => selectedMonth = nextStart);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Carried forward unspent to next month.')));
        }
      } else {
        // Pay debt using total leftover
        final liab = selectedLiab;
        if (liab == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add/select a liability.')));
          }
          return;
        }
        final end = _endOfMonth(selectedMonth);
        await RMinderDatabase.instance.insertTransaction(models.Transaction(
          categoryId: liab.budgetCategoryId,
          amount: totalLeftover,
          date: end,
          note: 'Month close payment (${_monthName(selectedMonth.month)} ${selectedMonth.year}) - ${liab.name}',
        ));
        await RMinderDatabase.instance.insertClosedMonth(
          monthStart: DateTime(selectedMonth.year, selectedMonth.month, 1),
          action: 'payDebt',
        );
        final nextStart = _startOfNextMonth(selectedMonth);
        await _loadData();
        if (!mounted) return;
        setState(() => selectedMonth = nextStart);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Debt payment recorded; tracking advanced to next month.')));
        }
      }
    } catch (e, st) {
      logError(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to close month. Please try again.')));
      }
    }
  }

  double _paidThisMonthFor(models.Liability liab) {
    double total = 0;
    for (final t in transactions) {
      if (t.categoryId == liab.budgetCategoryId && _isSameMonth(t.date, selectedMonth)) {
        total += t.amount;
      }
    }
    return total;
  }

  Future<void> _showCategoryDetails(BuildContext context, CategoryBreakdown data) async {
    if (_isDetailsDialogOpen) return;
    _isDetailsDialogOpen = true;
    final remaining = data.limit - data.spent;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(data.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total Budget: ₹${data.limit.toStringAsFixed(2)}'),
            Text('Current Spent: ₹${data.spent.toStringAsFixed(2)}'),
            Text('Balance: ₹${remaining.toStringAsFixed(2)}',
                style: TextStyle(color: remaining < 0 ? Colors.red : Colors.green, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
    _isDetailsDialogOpen = false;
  }
}

String _monthName(int m) {
  const names = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  return names[m - 1];
}

class IncomeDeclarationPage extends StatefulWidget {
  final double income;
  final double assets;
  final double liabilities;
  final Function(double, double, double) onSave;
  const IncomeDeclarationPage({
    required this.income,
    required this.assets,
    required this.liabilities,
    required this.onSave,
    Key? key,
  }) : super(key: key);
  @override
  State<IncomeDeclarationPage> createState() => _IncomeDeclarationPageState();
}

class _IncomeDeclarationPageState extends State<IncomeDeclarationPage> {
  late TextEditingController incomeController;
  late TextEditingController assetsController;
  late TextEditingController liabilitiesController;

  @override
  void initState() {
    super.initState();
    incomeController = TextEditingController(text: widget.income.toString());
    assetsController = TextEditingController(text: widget.assets.toString());
    liabilitiesController = TextEditingController(text: widget.liabilities.toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Declare Income, Assets, Liabilities')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: incomeController,
            decoration: const InputDecoration(labelText: 'Monthly Income'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: assetsController,
            decoration: const InputDecoration(labelText: 'Assets'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: liabilitiesController,
            decoration: const InputDecoration(labelText: 'Liabilities'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () {
              final income = double.tryParse(incomeController.text.trim()) ?? 0;
              final assets = double.tryParse(assetsController.text.trim()) ?? 0;
              final liabilities = double.tryParse(liabilitiesController.text.trim()) ?? 0;
              if (income <= 0) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Income must be greater than 0.')));
                return;
              }
              if (assets < 0) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Assets cannot be negative.')));
                return;
              }
              if (liabilities < 0) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Liabilities cannot be negative.')));
                return;
              }
              widget.onSave(income, assets, liabilities);
              Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ]),
      ),
    );
  }
}

class LiabilitiesPage extends StatefulWidget {
  final List<Map<String, dynamic>> liabilities;
  final Function(List<Map<String, dynamic>>) onSave;
  const LiabilitiesPage({required this.liabilities, required this.onSave, Key? key}) : super(key: key);
  @override
  State<LiabilitiesPage> createState() => _LiabilitiesPageState();
}

class _LiabilitiesPageState extends State<LiabilitiesPage> {
  List<models.Liability> liabilitiesList = [];
  Map<int, double> _paidThisMonth = {};
  bool _dialogOpenGuard = false;
  // Scroll controller for liabilities list
  final ScrollController _liabScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadLiabilities();
    // Listen for cross-page edit intents
    UiIntents.editLiabilityId.addListener(_maybeOpenEditFromIntent);
    // If an intent was set before listener attached, handle it after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (UiIntents.editLiabilityId.value != null) {
        _maybeOpenEditFromIntent();
      }
    });
  }

  @override
  void dispose() {
    UiIntents.editLiabilityId.removeListener(_maybeOpenEditFromIntent);
    _liabScroll.dispose();
    super.dispose();
  }

  void _maybeOpenEditFromIntent() {
    final id = UiIntents.editLiabilityId.value;
    if (id == null) return;
    final idx = liabilitiesList.indexWhere((l) => l.id == id);
    if (idx == -1) {
      // Liabilities may not be loaded yet; _loadLiabilities will try again
      return;
    }
    if (mounted && !_dialogOpenGuard) {
      // Clear the intent now that we're about to handle it
      UiIntents.editLiabilityId.value = null;
      _dialogOpenGuard = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        _addOrEditLiability(index: idx);
        // Release guard after a brief delay to prevent rapid double-opens
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) _dialogOpenGuard = false;
      });
    }
  }

  Future<void> _loadLiabilities() async {
    try {
      final list = await RMinderDatabase.instance.getLiabilities();
      setState(() => liabilitiesList = list);
      await _loadPaidThisMonth();
      // After data loads, try to process any pending edit intent
      _maybeOpenEditFromIntent();
    } catch (e, st) {
      logError(e, st);
    }
  }

  Future<void> _loadPaidThisMonth() async {
    try {
      final now = DateTime.now();
      final Map<int, double> map = {};
      for (final liab in liabilitiesList) {
        if (liab.id == null) continue;
        final paid = await RMinderDatabase.instance.sumPaidForLiabilityInMonth(liab.id!, now);
        map[liab.id!] = paid;
      }
      if (mounted) setState(() => _paidThisMonth = map);
    } catch (e, st) {
      logError(e, st);
    }
  }

  // (helper removed; integrated into pay flows)

  void _addOrEditLiability({int? index}) {
    final nameController = TextEditingController(text: index != null ? liabilitiesList[index].name : '');
    final balanceController = TextEditingController(text: index != null ? liabilitiesList[index].balance.toStringAsFixed(0) : '');
    final plannedController = TextEditingController(text: index != null ? liabilitiesList[index].planned.toStringAsFixed(0) : '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(index == null ? 'Add Liability' : 'Edit Liability'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          StatefulBuilder(builder: (context, setState) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Liability Name'),
                maxLength: 20,
              ),
              TextField(
                controller: balanceController,
                decoration: const InputDecoration(labelText: 'Current Balance'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: plannedController,
                decoration: const InputDecoration(labelText: 'Minimum Payment'),
                keyboardType: TextInputType.number,
              ),
            ]);
          }),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              final balance = double.tryParse(balanceController.text.trim()) ?? 0;
              final planned = double.tryParse(plannedController.text.trim()) ?? 0;
              if (name.isEmpty || balance < 0 || planned < 0) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter valid values.')));
                return;
              }
              () async {
                if (index == null) {
                  // ensure a budget category exists and set planned as its budget limit
                  final catId = await RMinderDatabase.instance.ensureDebtCategory(name, planned: planned);
                  await RMinderDatabase.instance.insertLiability(
                    models.Liability(name: name, balance: balance, planned: planned, budgetCategoryId: catId),
                  );
                } else {
                  final liab = liabilitiesList[index];
                  await RMinderDatabase.instance.updateLiability(
                    models.Liability(
                      id: liab.id,
                      name: name,
                      balance: balance,
                      planned: planned,
                      budgetCategoryId: liab.budgetCategoryId,
                    ),
                  );
                }
                await _loadLiabilities();
                if (mounted) Navigator.of(context).pop();
              }();
            },
            child: Text(index == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );
  }

  void _removeLiability(int index) {
    final liab = liabilitiesList[index];
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Liability'),
        content: Text(
          'Deleting "${liab.name}" will also delete its linked budget category and all its transactions. This action cannot be undone. Continue?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ).then((confirmed) async {
      if (confirmed == true) {
        await RMinderDatabase.instance.deleteLiabilityCascade(liab.id!);
        await _loadLiabilities();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Liability "${liab.name}" and related data deleted.')),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Liabilities')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add Liability'),
            onPressed: () => _addOrEditLiability(),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: liabilitiesList.isEmpty
                ? const Center(child: Text('No liabilities added yet.'))
                : Scrollbar(
                    controller: _liabScroll,
                    thumbVisibility: true,
                    child: ListView.builder(
                      controller: _liabScroll,
                      itemCount: liabilitiesList.length,
                      itemBuilder: (context, index) {
                      final liab = liabilitiesList[index];
                      return Card(
                        child: ListTile(
                          title: Text(liab.name),
                          subtitle: Text('Balance: ₹${liab.balance.toStringAsFixed(2)} | Min: ₹${liab.planned.toStringAsFixed(2)}'),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            // Single payment icon with conditional workflow
                            IconButton(
                              tooltip: 'Make payment',
                              icon: const Icon(Icons.payment),
                              onPressed: () async {
                                final paid = _paidThisMonth[liab.id!] ?? 0.0;
                                final remaining = (liab.planned - paid).clamp(0, double.infinity);
                                if (remaining > 0) {
                                  // Not fully paid this month: allow paying remaining (default) or more
                                  final controller = TextEditingController(text: remaining.toStringAsFixed(0));
                                  showDialog(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      title: Text('Pay ${liab.name}') ,
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Remaining planned this month: ₹${remaining.toStringAsFixed(2)}'),
                                          const SizedBox(height: 8),
                                          TextField(
                                            controller: controller,
                                            decoration: const InputDecoration(labelText: 'Amount to pay'),
                                            keyboardType: TextInputType.number,
                                          ),
                                        ],
                                      ),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                                        ElevatedButton(
                                          onPressed: () async {
                                            final amt = double.tryParse(controller.text.trim()) ?? 0;
                                            if (amt <= 0) {
                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount.')));
                                              return;
                                            }
                                            final txId = await RMinderDatabase.instance.payLiability(liab, amt);
                                            final afterPaid = paid + amt;
                                            final extra = afterPaid > liab.planned ? (afterPaid - liab.planned) : 0.0;
                                            if (extra > 0) {
                                              await RMinderDatabase.instance.insertExtraPayment(
                                                liabilityId: liab.id!,
                                                amount: extra,
                                                date: DateTime.now(),
                                                transactionId: txId,
                                              );
                                            }
                                            await _loadLiabilities();
                                            await _loadPaidThisMonth();
                                            if (mounted) Navigator.pop(context);
                                          },
                                          child: const Text('Confirm'),
                                        ),
                                      ],
                                    ),
                                  );
                                } else {
                                  // Already paid planned for this month: offer extra payment only
                                  final controller = TextEditingController(text: '0');
                                  showDialog(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      title: Text('Extra payment - ${liab.name}'),
                                      content: TextField(
                                        controller: controller,
                                        decoration: const InputDecoration(labelText: 'Extra amount'),
                                        keyboardType: TextInputType.number,
                                      ),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                                        ElevatedButton(
                                          onPressed: () async {
                                            final extra = double.tryParse(controller.text.trim()) ?? 0;
                                            if (extra <= 0) {
                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount.')));
                                              return;
                                            }
                                            final txId = await RMinderDatabase.instance.payLiability(liab, extra);
                                            await RMinderDatabase.instance.insertExtraPayment(
                                              liabilityId: liab.id!,
                                              amount: extra,
                                              date: DateTime.now(),
                                              transactionId: txId,
                                            );
                                            await _loadLiabilities();
                                            await _loadPaidThisMonth();
                                            if (mounted) Navigator.pop(context);
                                          },
                                          child: const Text('Confirm'),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              tooltip: 'Edit',
                              onPressed: () => _addOrEditLiability(index: index),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Delete',
                              onPressed: () => _removeLiability(index),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
              ),
        ]),
      ),
    );
  }
}

// Add this helper for error logging
void logError(Object error, [StackTrace? stackTrace]) {
  developer.log('ERROR: $error', name: 'RMinderApp');
  if (stackTrace != null) developer.log(stackTrace.toString(), name: 'RMinderApp');
}
