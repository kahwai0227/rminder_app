import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'db/rminder_database.dart';
import 'models/models.dart' as models;
import 'dart:developer' as developer;


void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RMinder',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
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
  final List<Widget> _pages = [];

  @override
  void initState() {
    super.initState();
    _pages.add(BudgetPage());
    _pages.add(TransactionsPage());
    _pages.add(ReportingPage());
    _pages.add(LiabilitiesPage(
      liabilities: liabilities,
      onSave: (newLiabilities) {
        setState(() {
          liabilities = newLiabilities;
        });
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        selectedItemColor: Colors.deepPurple,
        unselectedItemColor: Colors.grey,
        backgroundColor: Colors.white,
        showUnselectedLabels: true,
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
    if (breakdown.isEmpty) {
      return Center(child: Text('No data for chart'));
    }
    final totalSpent = breakdown.fold(0.0, (sum, cat) => sum + cat.spent);
    return SizedBox(
      height: 200,
      child: PieChart(
        PieChartData(
          sections: breakdown.map((cat) {
            final percent = totalSpent == 0 ? 0 : (cat.spent / totalSpent) * 100;
            return PieChartSectionData(
              value: cat.spent,
              title: '${cat.name}\n${percent.toStringAsFixed(1)}%',
              color: Colors.primaries[breakdown.indexOf(cat) % Colors.primaries.length],
              radius: 60,
              titleStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
            );
          }).toList(),
          sectionsSpace: 2,
          centerSpaceRadius: 40,
        ),
      ),
    );
  }
}

class BudgetPage extends StatefulWidget {
  @override
  State<BudgetPage> createState() => _BudgetPageState();
}
class _BudgetPageState extends State<BudgetPage> {
  List<models.BudgetCategory> categories = [];
  double income = 0;
  Map<int, double> incomeAllocation = {};
  List<models.IncomeSource> incomeSources = [];
  double get totalIncome => incomeSources.fold(0, (sum, src) => sum + src.amount);

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadIncomeSources();
  }

  Future<void> _loadCategories() async {
    final cats = await RMinderDatabase.instance.getCategories();
    setState(() {
      categories = cats;
      // Initialize allocation for each category if not present
      for (var cat in cats) {
        incomeAllocation.putIfAbsent(cat.id ?? 0, () => 0);
      }
    });
  }

  Future<void> _loadIncomeSources() async {
    final sources = await RMinderDatabase.instance.getIncomeSources();
    setState(() {
      incomeSources = sources;
    });
  }

  void _showIncomeDialog() async {
    final incomeController = TextEditingController(text: income.toString());
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Declare Income'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: incomeController,
                  decoration: InputDecoration(labelText: 'Monthly Income'),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  income = double.tryParse(incomeController.text.trim()) ?? 0;
                });
                Navigator.of(context).pop();
              },
              child: Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showIncomeAllocationDialog() async {
    final allocationControllers = {
      for (var cat in categories) cat.id ?? 0: TextEditingController(text: incomeAllocation[cat.id ?? 0]?.toString() ?? '0')
    };
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Allocate Income'),
          content: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.8,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...categories.map((cat) => Row(
                    children: [
                      Expanded(child: Text(cat.name)),
                      SizedBox(width: 10),
                      Flexible(
                        child: SizedBox(
                          width: 80,
                          child: TextField(
                            controller: allocationControllers[cat.id ?? 0],
                            decoration: InputDecoration(labelText: '₹'),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ),
                    ],
                  ))
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                double totalAllocated = 0;
                setState(() {
                  for (var cat in categories) {
                    final val = double.tryParse(allocationControllers[cat.id ?? 0]?.text ?? '0') ?? 0;
                    incomeAllocation[cat.id ?? 0] = val;
                    totalAllocated += val;
                  }
                });
                if (totalAllocated != income) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Total allocated (₹${totalAllocated.toStringAsFixed(2)}) must equal income (₹${income.toStringAsFixed(2)})')),
                  );
                } else {
                  Navigator.of(context).pop();
                }
              },
              child: Text('Save Allocation'),
            ),
          ],
        );
      },
    );
  }


  Future<void> _showAddCategoryDialog() async {
    final nameController = TextEditingController();
    final limitController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Add Budget Category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(labelText: 'Category Name'),
              ),
              TextField(
                controller: limitController,
                decoration: InputDecoration(labelText: 'Monthly Limit'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final budgetLimit = double.tryParse(limitController.text.trim()) ?? 0;
                if (name.isNotEmpty && budgetLimit > 0) {
                  await RMinderDatabase.instance.insertCategory(
                    models.BudgetCategory(name: name, budgetLimit: budgetLimit, spent: 0),
                  );
                  await _loadCategories();
                  Navigator.of(context).pop();
                }
              },
              child: Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showEditCategoryDialog(models.BudgetCategory category) async {
    final nameController = TextEditingController(text: category.name);
    final limitController = TextEditingController(text: category.budgetLimit.toString());
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit Budget Category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(labelText: 'Category Name'),
              ),
              TextField(
                controller: limitController,
                decoration: InputDecoration(labelText: 'Monthly Limit'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final budgetLimit = double.tryParse(limitController.text.trim()) ?? 0;
                if (name.isNotEmpty && budgetLimit > 0) {
                  await RMinderDatabase.instance.updateCategory(
                    models.BudgetCategory(
                      id: category.id,
                      name: name,
                      budgetLimit: budgetLimit,
                      spent: category.spent,
                    ),
                  );
                  await _loadCategories();
                  Navigator.of(context).pop();
                }
              },
              child: Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDeleteCategory(models.BudgetCategory category) async {
    final hasTransactions = await RMinderDatabase.instance.hasTransactionsForCategory(category.id ?? 0);
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Category'),
        content: Text(hasTransactions
            ? 'This category has active transactions. Delete anyway? All related transactions will be deleted.'
            : 'Are you sure you want to delete this category?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text('Delete')),
        ],
      ),
    );

    if (shouldDelete == true) {
      await RMinderDatabase.instance.deleteTransactionsForCategory(category.id ?? 0);
      await RMinderDatabase.instance.deleteCategory(category.id!);
      if (mounted) {
        setState(() {
          categories.removeWhere((c) => c.id == category.id);
        });
      }
    }
  }

  Future<void> _showAddIncomeSourceDialog() async {
    final nameController = TextEditingController();
    final amountController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Add Income Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(labelText: 'Income Name'),
              ),
              TextField(
                controller: amountController,
                decoration: InputDecoration(labelText: 'Amount'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final amount = double.tryParse(amountController.text.trim()) ?? 0;
                if (name.isNotEmpty && amount > 0) {
                  await RMinderDatabase.instance.insertIncomeSource(models.IncomeSource(name: name, amount: amount));
                  await _loadIncomeSources();
                  Navigator.of(context).pop();
                }
              },
              child: Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteIncomeSource(int id) async {
    await RMinderDatabase.instance.deleteIncomeSource(id);
    await _loadIncomeSources();
  }

  @override
  Widget build(BuildContext context) {
    try {
      return Scaffold(
        appBar: AppBar(title: Text('Budget')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Income Section
                // Income Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Income', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            ElevatedButton.icon(
                              icon: Icon(Icons.add),
                              label: Text('Add'),
                              onPressed: _showAddIncomeSourceDialog,
                              style: ElevatedButton.styleFrom(
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                textStyle: TextStyle(fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 10),
                        incomeSources.isEmpty
                            ? Center(child: Text('No income sources yet.'))
                            : Column(
                                children: incomeSources.map((src) {
                                  return Card(
                                    child: ListTile(
                                      title: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(src.name),
                                          Text('₹${src.amount.toStringAsFixed(2)}', style: TextStyle(color: Colors.blue)),
                                        ],
                                      ),
                                      trailing: IconButton(
                                        icon: Icon(Icons.delete, color: Colors.red),
                                        tooltip: 'Delete',
                                        onPressed: () => _deleteIncomeSource(src.id!),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                        SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Text('Total Income: ₹${totalIncome.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 10),
                // Budget Categories Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Budget Categories', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            ElevatedButton.icon(
                              icon: Icon(Icons.add),
                              label: Text('Add'),
                              onPressed: _showAddCategoryDialog,
                              style: ElevatedButton.styleFrom(
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                textStyle: TextStyle(fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 10),
                        categories.isEmpty
                            ? Center(child: Text('No budget categories yet.'))
                            : Column(
                                children: categories.map((category) {
                                  return Card(
                                    child: ListTile(
                                      key: ValueKey(category.id),
                                      title: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(category.name),
                                          Text('₹${category.budgetLimit.toStringAsFixed(2)}', style: TextStyle(color: Colors.blue)),
                                        ],
                                      ),
                                      trailing: Wrap(
                                        spacing: 4,
                                        children: [
                                          IconButton(
                                            icon: Icon(Icons.edit, color: Colors.blue),
                                            onPressed: () => _showEditCategoryDialog(category),
                                          ),
                                          IconButton(
                                            icon: Icon(Icons.delete, color: Colors.red),
                                            onPressed: () async {
                                              try {
                                                final hasTransactions = await RMinderDatabase.instance.hasTransactionsForCategory(category.id ?? 0);
                                                if (hasTransactions) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text('Cannot delete category with active transactions.')),
                                                  );
                                                  return;
                                                }
                                                await _confirmDeleteCategory(category);
                                                setState(() {});
                                              } catch (e, st) {
                                                logError(e, st);
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                      ],
                    ),
                  ),
                ),
// ...existing code...
              ],
            ),
          ),
        ),
      );
    } catch (e, st) {
      logError(e, st);
      return Center(child: Text('An error occurred. Please restart the app.'));
    }
  }
}

class TransactionsPage extends StatefulWidget {
  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}
class _TransactionsPageState extends State<TransactionsPage> {
  List<models.Transaction> transactions = [];
  List<models.BudgetCategory> categories = [];
  models.BudgetCategory? filterCategory;
  DateTime? filterDate;

  @override
  void initState() {
    super.initState();
    _loadCategoriesAndTransactions();
  }

  Future<void> _loadCategoriesAndTransactions() async {
    final cats = await RMinderDatabase.instance.getCategories();
    final txns = await RMinderDatabase.instance.getTransactions();
    setState(() {
      categories = cats;
      transactions = txns;
    });
  }

  List<models.Transaction> get filteredTransactions {
    return transactions.where((txn) {
      final matchesCategory = filterCategory == null || txn.categoryId == filterCategory!.id;
      final matchesDate = filterDate == null || txn.date.year == filterDate!.year && txn.date.month == filterDate!.month && txn.date.day == filterDate!.day;
      return matchesCategory && matchesDate;
    }).toList();
  }

  Future<void> _showAddTransactionDialog() async {
    models.BudgetCategory? selectedCategory = categories.isNotEmpty ? categories[0] : null;
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Add Transaction'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<models.BudgetCategory>(
                  value: selectedCategory,
                  isExpanded: true,
                  items: categories.map((cat) {
                    return DropdownMenuItem(
                      value: cat,
                      child: Text(cat.name),
                    );
                  }).toList(),
                  onChanged: (cat) {
                    setState(() {
                      selectedCategory = cat;
                    });
                  },
                ),
                TextField(
                  controller: amountController,
                  decoration: InputDecoration(labelText: 'Amount'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: noteController,
                  decoration: InputDecoration(labelText: 'Note (optional)'),
                ),
                SizedBox(height: 10),
                Row(
                  children: [
                    Text('Date: ${selectedDate.toLocal().toString().split(' ')[0]}'),
                    TextButton(
                      child: Text('Pick'),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() {
                            selectedDate = picked;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (mounted) Navigator.of(context).pop();
              },
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text.trim()) ?? 0;
                if (selectedCategory != null && amount > 0) {
                  await RMinderDatabase.instance.insertTransaction(
                    models.Transaction(
                      categoryId: selectedCategory!.id!,
                      amount: amount,
                      date: selectedDate,
                      note: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
                    ),
                  );
                  await _loadCategoriesAndTransactions();
                  if (mounted) Navigator.of(context).pop();
                }
              },
              child: Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showEditTransactionDialog(models.Transaction txn) async {
    models.BudgetCategory? selectedCategory = categories.firstWhere((c) => c.id == txn.categoryId, orElse: () => categories[0]);
    final amountController = TextEditingController(text: txn.amount.toString());
    final noteController = TextEditingController(text: txn.note ?? '');
    DateTime selectedDate = txn.date;
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit Transaction'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<models.BudgetCategory>(
                  value: selectedCategory,
                  isExpanded: true,
                  items: categories.map((cat) {
                    return DropdownMenuItem(
                      value: cat,
                      child: Text(cat.name),
                    );
                  }).toList(),
                  onChanged: (cat) {
                    setState(() {
                      selectedCategory = cat;
                    });
                  },
                ),
                TextField(
                  controller: amountController,
                  decoration: InputDecoration(labelText: 'Amount'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: noteController,
                  decoration: InputDecoration(labelText: 'Note (optional)'),
                ),
                SizedBox(height: 10),
                Row(
                  children: [
                    Text('Date: ${selectedDate.toLocal().toString().split(' ')[0]}'),
                    TextButton(
                      child: Text('Pick'),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() {
                            selectedDate = picked;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (mounted) Navigator.of(context).pop();
              },
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text.trim()) ?? 0;
                if (selectedCategory != null && amount > 0) {
                  await RMinderDatabase.instance.updateTransaction(
                    models.Transaction(
                      id: txn.id,
                      categoryId: selectedCategory!.id!,
                      amount: amount,
                      date: selectedDate,
                      note: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
                    ),
                  );
                  await _loadCategoriesAndTransactions();
                  if (mounted) Navigator.of(context).pop();
                }
              },
              child: Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDeleteTransaction(models.Transaction txn) async {
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Delete Transaction'),
          content: Text('Are you sure you want to delete this transaction?'),
          actions: [
            TextButton(
              onPressed: () {
                if (mounted) Navigator.of(context).pop();
              },
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                await RMinderDatabase.instance.deleteTransaction(txn.id!);
                await _loadCategoriesAndTransactions();
                if (mounted) Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    try {
      return Scaffold(
        appBar: AppBar(title: Text('Transactions')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Transactions', style: Theme.of(context).textTheme.titleLarge),
                  ElevatedButton.icon(
                    icon: Icon(Icons.add),
                    label: Text('Add'),
                    onPressed: categories.isEmpty ? null : _showAddTransactionDialog,
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<models.BudgetCategory>(
                      value: categories.isEmpty ? null : filterCategory,
                      hint: Text(categories.isEmpty ? 'No categories available' : 'Filter by Category'),
                      isExpanded: true,
                      items: categories.isEmpty
                          ? [const DropdownMenuItem(value: null, child: Text('No categories available'))]
                          : [
                              const DropdownMenuItem(value: null, child: Text('All Categories')),
                              ...categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat.name)))
                            ],
                      onChanged: categories.isEmpty
                          ? null
                          : (cat) {
                              setState(() {
                                filterCategory = cat;
                              });
                            },
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: TextButton(
                      child: Text(filterDate == null
                          ? 'Filter by Date'
                          : 'Date: ${filterDate!.toLocal().toString().split(' ')[0]}'),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: filterDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        setState(() {
                          filterDate = picked;
                        });
                      },
                    ),
                  ),
                  if (filterCategory != null || filterDate != null)
                    IconButton(
                      icon: Icon(Icons.clear),
                      tooltip: 'Clear Filters',
                      onPressed: () {
                        setState(() {
                          filterCategory = null;
                          filterDate = null;
                        });
                      },
                    ),
                ],
              ),
              Expanded(
                child: categories.isEmpty
                    ? Center(child: Text('No categories available. Add a category to begin.'))
                    : filteredTransactions.isEmpty
                        ? Center(child: Text('No transactions yet.'))
                        : ListView.builder(
                            itemCount: filteredTransactions.length,
                            itemBuilder: (context, index) {
                              try {
                                final txn = filteredTransactions[index];
                                final catList = categories.where((c) => c.id == txn.categoryId);
                                if (catList.isEmpty) {
                                  logError('Transaction with missing category: ${txn.categoryId}');
                                  return SizedBox.shrink();
                                }
                                final cat = catList.first;
                                return Card(
                                  child: ListTile(
                                    title: Text('${cat.name} - ₹${txn.amount.toStringAsFixed(2)}'),
                                    subtitle: Text('${txn.date.toLocal().toString().split(' ')[0]}${txn.note != null && txn.note!.isNotEmpty ? ' | ${txn.note}' : ''}'),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: Icon(Icons.edit, color: Colors.blue),
                                          tooltip: 'Edit',
                                          onPressed: () => _showEditTransactionDialog(txn),
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.delete, color: Colors.red),
                                          tooltip: 'Delete',
                                          onPressed: () => _confirmDeleteTransaction(txn),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              } catch (e, st) {
                                logError(e, st);
                                return Center(child: Text('Error loading transaction.'));
                              }
                            },
                          ),
              ),
            ],
          ),
        ),
      );
    } catch (e, st) {
      logError(e, st);
      return Center(child: Text('An error occurred. Please restart the app.'));
    }
  }
}

class ReportingPage extends StatefulWidget {
  @override
  State<ReportingPage> createState() => _ReportingPageState();
}
class _ReportingPageState extends State<ReportingPage> {
  List<models.BudgetCategory> categories = [];
  List<models.Transaction> transactions = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final cats = await RMinderDatabase.instance.getCategories();
    final txns = await RMinderDatabase.instance.getTransactions();
    setState(() {
      categories = cats;
      transactions = txns;
    });
  }

  MonthlySummary getMonthlySummary() {
    double totalSpent = 0;
    double totalLimit = 0;
    List<CategoryBreakdown> breakdown = [];
    for (final cat in categories) {
      totalSpent += cat.spent;
      totalLimit += cat.budgetLimit;
      breakdown.add(CategoryBreakdown(name: cat.name, spent: cat.spent, limit: cat.budgetLimit));
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
    try {
      final summary = getMonthlySummary();
      return Scaffold(
        appBar: AppBar(title: Text('Reporting')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Monthly Summary', style: Theme.of(context).textTheme.headlineSmall),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total Spent: ₹${summary.totalSpent.toStringAsFixed(2)}'),
                        Text('Total Limit: ₹${summary.totalLimit.toStringAsFixed(2)}'),
                        Text('Total Remaining: ₹${summary.totalRemaining.toStringAsFixed(2)}'),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 10),
                summary.breakdown.isEmpty
                    ? Center(child: Text('No categories available. Add a category to view reports.'))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Spending by Category (Pie Chart)', style: Theme.of(context).textTheme.titleMedium),
                          CategorySpendingChart(breakdown: summary.breakdown),
                          SizedBox(height: 10),
                          Text('Breakdown by Category', style: Theme.of(context).textTheme.titleMedium),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: NeverScrollableScrollPhysics(),
                            itemCount: summary.breakdown.length,
                            itemBuilder: (context, index) {
                              try {
                                final cat = summary.breakdown[index];
                                final remaining = cat.limit - cat.spent;
                                return Card(
                                  child: ListTile(
                                    title: Text(cat.name),
                                    subtitle: Text('Limit: ₹${cat.limit.toStringAsFixed(2)} | Spent: ₹${cat.spent.toStringAsFixed(2)}'),
                                    trailing: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text('Remaining'),
                                        Text('₹${remaining.toStringAsFixed(2)}', style: TextStyle(
                                          color: remaining < 0 ? Colors.red : Colors.green,
                                          fontWeight: FontWeight.bold,
                                        )),
                                      ],
                                    ),
                                  ),
                                );
                              } catch (e, st) {
                                logError(e, st);
                                return Center(child: Text('Error loading category breakdown.'));
                              }
                            },
                          ),
                        ],
                      ),
              ],
            ),
          ),
        ),
      );
    } catch (e, st) {
      logError(e, st);
      return Center(child: Text('An error occurred. Please restart the app.'));
    }
  }
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
      appBar: AppBar(title: Text('Declare Income, Assets, Liabilities')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: incomeController,
              decoration: InputDecoration(labelText: 'Monthly Income'),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 16),
            TextField(
              controller: assetsController,
              decoration: InputDecoration(labelText: 'Assets'),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 16),
            TextField(
              controller: liabilitiesController,
              decoration: InputDecoration(labelText: 'Liabilities'),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                final income = double.tryParse(incomeController.text.trim()) ?? 0;
                final assets = double.tryParse(assetsController.text.trim()) ?? 0;
                final liabilities = double.tryParse(liabilitiesController.text.trim()) ?? 0;
                widget.onSave(income, assets, liabilities);
                Navigator.of(context).pop();
              },
              child: Text('Save'),
            ),
          ],
        ),
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
  late List<Map<String, dynamic>> liabilitiesList;
  int? editingIndex;

  @override
  void initState() {
    super.initState();
    liabilitiesList = List<Map<String, dynamic>>.from(widget.liabilities);
  }

  void _addOrEditLiability({int? index}) {
    final nameController = TextEditingController(text: index != null ? liabilitiesList[index]['name'] : '');
    final amountController = TextEditingController(text: index != null ? liabilitiesList[index]['amount'].toString() : '');
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(index == null ? 'Add Liability' : 'Edit Liability'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(labelText: 'Liability Name'),
              ),
              TextField(
                controller: amountController,
                decoration: InputDecoration(labelText: 'Amount'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                final amount = double.tryParse(amountController.text.trim()) ?? 0;
                if (name.isNotEmpty && amount > 0) {
                  setState(() {
                    if (index == null) {
                      liabilitiesList.add({'name': name, 'amount': amount});
                    } else {
                      liabilitiesList[index] = {'name': name, 'amount': amount};
                    }
                  });
                  Navigator.of(context).pop();
                }
              },
              child: Text(index == null ? 'Add' : 'Save'),
            ),
          ],
        );
      },
    );
  }

  void _removeLiability(int index) {
    setState(() {
      liabilitiesList.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Liabilities')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton.icon(
              icon: Icon(Icons.add),
              label: Text('Add Liability'),
              onPressed: () => _addOrEditLiability(),
            ),
            SizedBox(height: 10),
            Expanded(
              child: liabilitiesList.isEmpty
                  ? Center(child: Text('No liabilities added yet.'))
                  : ListView.builder(
                      itemCount: liabilitiesList.length,
                      itemBuilder: (context, index) {
                        final item = liabilitiesList[index];
                        return Card(
                          child: ListTile(
                            title: Text(item['name']),
                            subtitle: Text('Amount: ₹${item['amount'].toStringAsFixed(2)}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.edit, color: Colors.blue),
                                  tooltip: 'Edit',
                                  onPressed: () => _addOrEditLiability(index: index),
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete, color: Colors.red),
                                  tooltip: 'Delete',
                                  onPressed: () => _removeLiability(index),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// Add this helper for error logging
void logError(Object error, [StackTrace? stackTrace]) {
  developer.log('ERROR: $error', name: 'RMinderApp');
  if (stackTrace != null) developer.log(stackTrace.toString(), name: 'RMinderApp');
}
