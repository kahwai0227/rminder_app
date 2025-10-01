import 'package:flutter/material.dart';
import '../db/rminder_database.dart';
import '../models/models.dart' as models;
import '../utils/logger.dart';
import '../main.dart' show TabSwitcher; // reuse the inherited widget
import '../utils/currency_input_formatter.dart';
import '../main.dart' show buildGlobalAppBarActions;

class BudgetPage extends StatefulWidget {
  const BudgetPage({Key? key}) : super(key: key);
  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  List<models.BudgetCategory> categories = [];
  List<models.IncomeSource> incomeSources = [];
  List<models.Liability> liabilities = [];
  List<models.SinkingFund> sinkingFunds = [];
  final ScrollController _budgetScroll = ScrollController();

  double get totalIncome => incomeSources.fold(0.0, (s, i) => s + i.amount);

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadIncomeSources();
    _loadLiabilities();
    _loadSinkingFunds();
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

  Future<void> _loadSinkingFunds() async {
    try {
      final list = await RMinderDatabase.instance.getSinkingFunds();
      setState(() => sinkingFunds = list);
    } catch (e, st) {
      logError(e, st);
    }
  }

  Future<void> _showAddIncomeSourceDialog() async {
    final nameController = TextEditingController();
    final amountController = TextEditingController(text: '0.00');
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
              keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
              inputFormatters: [
                CurrencyInputFormatter(),
              ],
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
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Income'),
        content: const Text('Are you sure you want to delete this income source?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (shouldDelete == true) {
      await RMinderDatabase.instance.deleteIncomeSource(id);
      await _loadIncomeSources();
    }
  }

  Future<void> _showEditIncomeSourceDialog(models.IncomeSource source) async {
    final nameController = TextEditingController(text: source.name);
    final amountController = TextEditingController(text: source.amount.toStringAsFixed(2));
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Income Source'),
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
              keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
              inputFormatters: [
                CurrencyInputFormatter(),
              ],
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
              await RMinderDatabase.instance.updateIncomeSource(
                models.IncomeSource(id: source.id, name: name, amount: amount),
              );
              await _loadIncomeSources();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddCategoryDialog() async {
    final nameController = TextEditingController();
  final limitController = TextEditingController(text: '0.00');
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
                              divisions: null,
                              label: '₹${sliderValue.toStringAsFixed(2)}',
                              onChanged: (v) {
                                setState(() {
                                  sliderValue = v;
                                  limitController.text = v.toStringAsFixed(2);
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
                            keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
                            inputFormatters: [
                              CurrencyInputFormatter(),
                            ],
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
              final budgetLimit = double.tryParse(limitController.text.trim().replaceAll(',', '')) ?? 0;
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
    sliderValue = sliderValue.clamp(0.0, maxValue).toDouble();
  final limitController = TextEditingController(text: sliderValue.toStringAsFixed(2));
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
                          divisions: null,
                          label: '₹${sliderValue.toStringAsFixed(2)}',
                          onChanged: (v) {
                            setState(() {
                              sliderValue = v;
                              limitController.text = v.toStringAsFixed(2);
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
                        keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
                        inputFormatters: [
                          CurrencyInputFormatter(),
                        ],
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
              final budgetLimit = double.tryParse(limitController.text.trim().replaceAll(',', '')) ?? 0;
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
  appBar: AppBar(title: const Text('Budget'), actions: buildGlobalAppBarActions(context)),
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
                                          trailing: Wrap(spacing: 4, children: [
                                            IconButton(
                                              icon: Icon(Icons.edit, color: Theme.of(context).colorScheme.primary),
                                              onPressed: () => _showEditIncomeSourceDialog(src),
                                            ),
                                            IconButton(
                                              icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
                                              onPressed: () => _deleteIncomeSource(src.id!),
                                            ),
                                          ]),
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
              .where((c) =>
                !liabilities.any((l) => l.budgetCategoryId == c.id) &&
                !sinkingFunds.any((f) => f.budgetCategoryId == c.id))
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
                                      // Liabilities tab index in main.dart: 3
                                      TabSwitcher.of(context)?.switchTo(3);
                                    },
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
                            Icon(Icons.attach_money, size: 18, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 6),
                            Text('Savings', style: Theme.of(context).textTheme.titleMedium),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (sinkingFunds.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6.0),
                          child: Text('No savings funds added yet.'),
                        )
                      else
                        ...sinkingFunds.map((fund) => Card(
                              child: ListTile(
                                key: ValueKey('fund-${fund.id}'),
                                title: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fund.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Monthly: ₹${fund.monthlyContribution.toStringAsFixed(2)}',
                                      style: TextStyle(color: Theme.of(context).colorScheme.primary),
                                    ),
                                  ],
                                ),
                                trailing: Wrap(spacing: 4, children: [
                                  IconButton(
                                    icon: Icon(Icons.edit, color: Theme.of(context).colorScheme.primary),
                                    tooltip: 'Edit in Savings',
                                    onPressed: () {
                                      // Savings tab index in main.dart: 2
                                      TabSwitcher.of(context)?.switchTo(2);
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
