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
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) async {
          if (index != 0) {
            final budgetState = _budgetKey.currentState;
            if (budgetState != null) {
              final totalBudgeted = budgetState.categories.fold(0.0, (s, c) => s + c.budgetLimit);
              final totalIncome = budgetState.totalIncome;
              final remaining = totalIncome - totalBudgeted;
              if (remaining > 0) {
                ScaffoldMessenger.of(context).removeCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('₹${remaining.toStringAsFixed(2)} of income is not allocated to any budget.')),
                );
              }
            }
          }
          setState(() => _selectedIndex = index);
        },
        selectedItemColor: Colors.deepPurple,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'Budget'),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Transactions'),
          BottomNavigationBarItem(icon: Icon(Icons.pie_chart), label: 'Reporting'),
          BottomNavigationBarItem(icon: Icon(Icons.warning), label: 'Liabilities'),
        ],
      ),
    );
  }
}

class MonthlySummary {
  final double totalSpent;
  final double totalLimit;
  final double totalRemaining;
  final List<CategoryBreakdown> breakdown;
  MonthlySummary({
    required this.totalSpent,
    required this.totalLimit,
    required this.totalRemaining,
    required this.breakdown,
  });
}

class CategoryBreakdown {
  final String name;
  final double spent;
  final double limit;
  CategoryBreakdown({required this.name, required this.spent, required this.limit});
}

class CategorySpendingChart extends StatelessWidget {
  final List<CategoryBreakdown> breakdown;
  const CategorySpendingChart({required this.breakdown, Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    if (breakdown.isEmpty) return const Center(child: Text('No data for chart'));
    final totalSpent = breakdown.fold(0.0, (s, c) => s + c.spent);
    return SizedBox(
      height: 200,
      child: PieChart(
        PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: 40,
          sections: breakdown.asMap().entries.map((entry) {
            final idx = entry.key;
            final cat = entry.value;
            final percent = totalSpent == 0 ? 0 : (cat.spent / totalSpent) * 100;
            return PieChartSectionData(
              value: cat.spent,
              title: '${cat.name}\n${percent.toStringAsFixed(1)}%',
              color: Colors.primaries[idx % Colors.primaries.length],
              radius: 60,
              titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
            );
          }).toList(),
        ),
      ),
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
  double get totalIncome => incomeSources.fold(0.0, (s, i) => s + i.amount);

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadIncomeSources();
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
                          divisions: maxValue > 0 ? maxValue.toInt() : 100,
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
    final limitController = TextEditingController(text: category.budgetLimit.toStringAsFixed(0));
    double sliderValue = category.budgetLimit;
    final allocatedOthers =
        categories.where((c) => c.id != category.id).fold<double>(0.0, (s, c) => s + c.budgetLimit);
    final double maxValue = totalIncome > 0 ? ((totalIncome - allocatedOthers).clamp(0.0, totalIncome)).toDouble() : 10000.0;
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
                          divisions: maxValue > 0 ? maxValue.toInt() : 100,
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
        child: SingleChildScrollView(
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
                                        title: Text(src.name),
                                        subtitle: Text('Amount: ₹${src.amount.toStringAsFixed(2)}'),
                                        trailing: IconButton(
                                          icon: const Icon(Icons.delete, color: Colors.red),
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
                    categories.isEmpty
                        ? const Center(child: Text('No budget categories yet.'))
                        : Column(
                            children: categories
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
                                              style: const TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(height: 4),
                                            Text('Limit: ₹${category.budgetLimit.toStringAsFixed(2)}',
                                                style: const TextStyle(color: Colors.blue)),
                                          ],
                                        ),
                                        trailing: Wrap(spacing: 4, children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit, color: Colors.blue),
                                            onPressed: () => _showEditCategoryDialog(category),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete, color: Colors.red),
                                            onPressed: () => _confirmDeleteCategory(category),
                                          ),
                                        ]),
                                      ),
                                    ))
                                .toList(),
                          ),
                  ]),
                ),
              ),
            ],
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

  Future<void> _loadCategoriesAndTransactions() async {
    try {
      final cats = await RMinderDatabase.instance.getCategories();
      final txns = await RMinderDatabase.instance.getTransactions();
      final validCategoryIds = cats.map((c) => c.id).toSet();
      final orphaned = txns.where((t) => !validCategoryIds.contains(t.categoryId)).toList();
      for (final t in orphaned) {
        await RMinderDatabase.instance.deleteTransaction(t.id!);
        logError('Deleted orphaned transaction with id: ${t.id}, missing category: ${t.categoryId}');
      }
      setState(() {
        categories = cats;
        transactions = txns.where((t) => validCategoryIds.contains(t.categoryId)).toList();
      });
    } catch (e, st) {
      logError(e, st);
    }
  }

  List<models.Transaction> get filteredTransactions {
    return transactions.where((txn) {
      final byCategory = _filterCategory == null || txn.categoryId == _filterCategory!.id;
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
      return byCategory && byDate && byAmount;
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
                Row(children: [
                  Text('Date: ${selectedDate.toLocal().toString().split(' ')[0]}'),
                  TextButton(
                    child: const Text('Pick'),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => selectedDate = picked);
                    },
                  ),
                ]),
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
                Row(children: [
                  Text('Date: ${selectedDate.toLocal().toString().split(' ')[0]}'),
                  TextButton(
                    child: const Text('Pick'),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => selectedDate = picked);
                    },
                  ),
                ]),
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
              Text('Transactions', style: Theme.of(context).textTheme.titleLarge),
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add'),
                onPressed: categories.isEmpty ? null : _showAddTransactionDialog,
              ),
            ]),
            Row(children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.filter_list),
                label: const Text('Filter'),
                onPressed: _showFilterDialog,
              ),
            ]),
            Expanded(
              child: categories.isEmpty
                  ? const Center(child: Text('No categories available. Add a category to begin.'))
                  : filteredTransactions.isEmpty
                      ? const Center(child: Text('No transactions yet.'))
                      : ListView.builder(
                          itemCount: filteredTransactions.length,
                          itemBuilder: (context, index) {
                            final txn = filteredTransactions[index];
                            final catList = categories.where((c) => c.id == txn.categoryId);
                            if (catList.isEmpty) {
                              logError('Transaction with missing category: ${txn.categoryId}');
                              return const SizedBox.shrink();
                            }
                            final cat = catList.first;
                            return Card(
                              child: ListTile(
                                title: Text('${cat.name} - ₹${txn.amount.toStringAsFixed(2)}'),
                                subtitle: Text(
                                    '${txn.date.toLocal().toString().split(' ')[0]}${txn.note != null && txn.note!.isNotEmpty ? ' | ${txn.note}' : ''}'),
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

class _ReportingPageState extends State<ReportingPage> {
  List<models.BudgetCategory> categories = [];
  List<models.Transaction> transactions = [];
  List<models.Liability> liabilities = [];
  DateTime selectedMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final cats = await RMinderDatabase.instance.getCategories();
      final txns = await RMinderDatabase.instance.getTransactions();
      final liabs = await RMinderDatabase.instance.getLiabilities();
      setState(() {
        categories = cats;
        transactions = txns;
        liabilities = liabs;
      });
    } catch (e, st) {
      logError(e, st);
    }
  }

  bool _isSameMonth(DateTime a, DateTime b) => a.year == b.year && a.month == b.month;

  MonthlySummary getMonthlySummary() {
    // Compute per-category spending for the selected month
    final Map<int, double> spentByCategoryThisMonth = {};
    for (final txn in transactions) {
      if (_isSameMonth(txn.date, selectedMonth)) {
        spentByCategoryThisMonth.update(txn.categoryId, (v) => v + txn.amount, ifAbsent: () => txn.amount);
      }
    }
    double totalSpent = 0;
    double totalLimit = 0;
    List<CategoryBreakdown> breakdown = [];
    for (final cat in categories) {
      final spent = spentByCategoryThisMonth[cat.id!] ?? 0;
      totalSpent += spent;
      totalLimit += cat.budgetLimit;
      breakdown.add(CategoryBreakdown(name: cat.name, spent: spent, limit: cat.budgetLimit));
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
    final monthLabel = '${_monthName(selectedMonth.month)} ${selectedMonth.year}';
    return Scaffold(
      appBar: AppBar(title: const Text('Reporting')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Monthly Summary ($monthLabel)', style: Theme.of(context).textTheme.headlineSmall),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Total Spent: ₹${summary.totalSpent.toStringAsFixed(2)}'),
                  Text('Total Limit: ₹${summary.totalLimit.toStringAsFixed(2)}'),
                  Text('Total Remaining: ₹${summary.totalRemaining.toStringAsFixed(2)}'),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            summary.breakdown.isEmpty
                ? const Center(child: Text('No categories available. Add a category to view reports.'))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Spending by Category (Pie Chart)', style: Theme.of(context).textTheme.titleMedium),
                    CategorySpendingChart(breakdown: summary.breakdown),
                    const SizedBox(height: 10),
                    Text('Breakdown by Category', style: Theme.of(context).textTheme.titleMedium),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: summary.breakdown.length,
                      itemBuilder: (context, index) {
                        final cat = summary.breakdown[index];
                        final remaining = cat.limit - cat.spent;
                        return Card(
                          child: ListTile(
                            title: Text(cat.name),
                            subtitle: Text(
                                'Limit: ₹${cat.limit.toStringAsFixed(2)} | Spent: ₹${cat.spent.toStringAsFixed(2)}'),
                            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              const Text('Remaining'),
                              Text('₹${remaining.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    color: remaining < 0 ? Colors.red : Colors.green,
                                    fontWeight: FontWeight.bold,
                                  )),
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
                      subtitle: Text('Planned: ₹${liab.planned.toStringAsFixed(2)} | Paid: ₹${paid.toStringAsFixed(2)}'),
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
    );
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

  @override
  void initState() {
    super.initState();
    _loadLiabilities();
  }

  Future<void> _loadLiabilities() async {
    try {
      final list = await RMinderDatabase.instance.getLiabilities();
      setState(() => liabilitiesList = list);
    } catch (e, st) {
      logError(e, st);
    }
  }

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
                decoration: const InputDecoration(labelText: 'Planned Monthly Payment'),
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
    () async {
      await RMinderDatabase.instance.deleteLiability(liab.id!);
      await _loadLiabilities();
    }();
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
                : ListView.builder(
                    itemCount: liabilitiesList.length,
                    itemBuilder: (context, index) {
                      final liab = liabilitiesList[index];
                      return Card(
                        child: ListTile(
                          title: Text(liab.name),
                          subtitle: Text('Balance: ₹${liab.balance.toStringAsFixed(2)} | Planned: ₹${liab.planned.toStringAsFixed(2)}'),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            TextButton.icon(
                              icon: const Icon(Icons.payment),
                              label: const Text('Pay'),
                              onPressed: () {
                                final controller = TextEditingController(text: liab.planned.toStringAsFixed(0));
                                showDialog(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: Text('Pay ${liab.name}'),
                                    content: TextField(
                                      controller: controller,
                                      decoration: const InputDecoration(labelText: 'Amount'),
                                      keyboardType: TextInputType.number,
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                                      ElevatedButton(
                                        onPressed: () {
                                          final amt = double.tryParse(controller.text.trim()) ?? 0;
                                          if (amt <= 0) {
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount.')));
                                            return;
                                          }
                                          () async {
                                            await RMinderDatabase.instance.payLiability(liab, amt);
                                            await _loadLiabilities();
                                            if (mounted) Navigator.pop(context);
                                          }();
                                        },
                                        child: const Text('Confirm'),
                                      ),
                                    ],
                                  ),
                                );
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
