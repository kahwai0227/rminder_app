import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../db/rminder_database.dart';
import '../models/models.dart' as models;
import '../utils/logger.dart';
import '../utils/mutation_guard.dart';
import '../services/overview_input_selector_service.dart';
import '../services/overview_metrics_service.dart';
import '../widgets/compact_cards.dart';
import '../main.dart' show TabSwitcher; // reuse the inherited widget
import '../utils/currency_input_formatter.dart';
import '../main.dart' show buildGlobalAppBarActions;

class BudgetPage extends StatefulWidget {
  const BudgetPage({super.key});
  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  final ScrollController _budgetScroll = ScrollController();
  double _carryIncome = 0.0; // one-time income for the active period

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshBudgetData();
    });
  }

  @override
  void dispose() {
    _budgetScroll.dispose();
    super.dispose();
  }

  Future<void> _loadCarryIncome() async {
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      // Wait for the next tick to prevent markNeedsBuild during build errors
      await Future.delayed(Duration.zero);
      // Ensure data is loaded
      if (appState.activePeriodStart == null) {
        await appState.loadAllData();
      }
      final d = appState.activePeriodStart;
      if (d != null) {
        final key =
            'carry_income:${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        final str = await RMinderDatabase.instance.getSetting(key);
        final val = double.tryParse(str ?? '0') ?? 0.0;
        if (mounted) setState(() => _carryIncome = val);
      }
    } catch (e, st) {
      logError(e, st);
    }
  }

  Future<void> _refreshBudgetData() async {
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      await appState.refresh();
      if (!mounted) return;
      await _loadCarryIncome();
    } catch (e, st) {
      logError(e, st);
    }
  }

  double totalIncome(AppState state) =>
      state.incomeSources.fold(0.0, (s, i) => s + i.amount) + _carryIncome;

  DateTime _activePeriodEndExclusive() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  }

  double _extraDebtPaymentsForActivePeriod(AppState state) {
    if (state.activePeriodStart == null) return 0.0;
    final ps = DateTime(
      state.activePeriodStart!.year,
      state.activePeriodStart!.month,
      state.activePeriodStart!.day,
    );
    final pe = _activePeriodEndExclusive();

    final paidByCategory = <int, double>{};
    for (final t in state.transactions) {
      if (!t.date.isBefore(ps) && t.date.isBefore(pe)) {
        paidByCategory[t.categoryId] =
            (paidByCategory[t.categoryId] ?? 0.0) + t.amount;
      }
    }

    double extraDebt = 0.0;
    for (final liab in state.liabilities.where((l) => !l.isArchived)) {
      final paid = paidByCategory[liab.budgetCategoryId] ?? 0.0;
      final over = paid - liab.planned;
      if (over > 0) {
        extraDebt += over;
      }
    }
    return extraDebt;
  }

  double _extraFundContributionsForActivePeriod(AppState state) {
    double extraFunds = 0.0;
    for (final fund in state.sinkingFunds) {
      final fundId = fund.id;
      if (fundId == null) continue;
      final contributed = state.contributedToFundsThisMonth[fundId] ?? 0.0;
      final over = contributed - fund.monthlyContribution;
      if (over > 0) {
        extraFunds += over;
      }
    }
    return extraFunds;
  }

  // Compute extras beyond plan for debts and funds within the active period
  double _extrasBeyondPlanForActivePeriod(AppState state) {
    final extraDebt = _extraDebtPaymentsForActivePeriod(state);
    final extraFunds = _extraFundContributionsForActivePeriod(state);
    final extras = extraDebt + extraFunds;
    return extras > 0 ? extras : 0.0;
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
            StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Income Name',
                      ),
                      maxLength: 15,
                      onChanged: (_) => setState(() {}),
                    ),
                    if (nameController.text.length >= 15)
                      const Padding(
                        padding: EdgeInsets.only(left: 4.0),
                        child: Text(
                          'Maximum characters reached',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            TextField(
              controller: amountController,
              decoration: const InputDecoration(labelText: 'Amount'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: false,
                signed: false,
              ),
              inputFormatters: [CurrencyInputFormatter()],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final amount = double.tryParse(amountController.text.trim()) ?? 0;
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Name cannot be empty.')),
                );
                return;
              }
              if (amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Amount must be greater than 0.'),
                  ),
                );
                return;
              }
              await runGuardedMutation(
                context: context,
                failureMessage: 'Failed to add income source.',
                action: () async {
                  await RMinderDatabase.instance.insertIncomeSource(
                    models.IncomeSource(name: name, amount: amount),
                  );
                },
                onSuccess: () async {
                  await Provider.of<AppState>(context, listen: false).refresh();
                  if (context.mounted) Navigator.pop(context);
                },
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditCarryIncomeDialog() async {
    final state = Provider.of<AppState>(context, listen: false);
    if (state.activePeriodStart == null) return;
    final controller = TextEditingController(
      text: _carryIncome.toStringAsFixed(2),
    );
    final period = state.activePeriodStart!;
    final key =
        'carry_income:${period.year.toString().padLeft(4, '0')}-${period.month.toString().padLeft(2, '0')}-${period.day.toString().padLeft(2, '0')}';
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Carry-forward Income'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Amount'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: false,
                signed: false,
              ),
              inputFormatters: [CurrencyInputFormatter()],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(controller.text.trim()) ?? 0.0;
              await runGuardedMutation(
                context: context,
                failureMessage: 'Failed to save carry-forward income.',
                action: () async {
                  await RMinderDatabase.instance.setSetting(
                    key,
                    amount.toStringAsFixed(2),
                  );
                },
                onSuccess: () async {
                  if (!mounted) return;
                  setState(() => _carryIncome = amount);
                  if (context.mounted) Navigator.pop(context);
                },
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCarryIncome() async {
    final state = Provider.of<AppState>(context, listen: false);
    if (state.activePeriodStart == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete carry-forward?'),
        content: const Text(
          'This removes the one-time carry-forward amount for this active period.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final period = state.activePeriodStart!;
    final key =
        'carry_income:${period.year.toString().padLeft(4, '0')}-${period.month.toString().padLeft(2, '0')}-${period.day.toString().padLeft(2, '0')}';
    await runGuardedMutation(
      context: context,
      failureMessage: 'Failed to delete carry-forward income.',
      action: () async {
        await RMinderDatabase.instance.deleteSetting(key);
      },
      onSuccess: () async {
        if (!mounted) return;
        setState(() => _carryIncome = 0.0);
      },
    );
  }

  Future<void> _deleteIncomeSource(int id) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Income'),
        content: const Text(
          'Are you sure you want to delete this income source?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete == true && mounted) {
      await runGuardedMutation(
        context: context,
        failureMessage: 'Failed to delete income source.',
        action: () async {
          await RMinderDatabase.instance.deleteIncomeSource(id);
        },
        onSuccess: () async {
          await Provider.of<AppState>(context, listen: false).refresh();
        },
      );
    }
  }

  Future<void> _showEditIncomeSourceDialog(models.IncomeSource source) async {
    final nameController = TextEditingController(text: source.name);
    final amountController = TextEditingController(
      text: source.amount.toStringAsFixed(2),
    );
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Income Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Income Name',
                      ),
                      maxLength: 15,
                      onChanged: (_) => setState(() {}),
                    ),
                    if (nameController.text.length >= 15)
                      const Padding(
                        padding: EdgeInsets.only(left: 4.0),
                        child: Text(
                          'Maximum characters reached',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            TextField(
              controller: amountController,
              decoration: const InputDecoration(labelText: 'Amount'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: false,
                signed: false,
              ),
              inputFormatters: [CurrencyInputFormatter()],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final amount = double.tryParse(amountController.text.trim()) ?? 0;
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Name cannot be empty.')),
                );
                return;
              }
              if (amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Amount must be greater than 0.'),
                  ),
                );
                return;
              }
              await runGuardedMutation(
                context: context,
                failureMessage: 'Failed to update income source.',
                action: () async {
                  await RMinderDatabase.instance.updateIncomeSource(
                    models.IncomeSource(
                      id: source.id,
                      name: name,
                      amount: amount,
                    ),
                  );
                },
                onSuccess: () async {
                  await Provider.of<AppState>(context, listen: false).refresh();
                  if (context.mounted) Navigator.pop(context);
                },
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddCategoryDialog() async {
    final state = Provider.of<AppState>(context, listen: false);
    final unbudgeted = state.categories.where((c) => !c.inBudget).toList();
    String selectedCatId = unbudgeted.isNotEmpty
        ? unbudgeted.first.id.toString()
        : 'new';

    final nameController = TextEditingController();
    final limitController = TextEditingController(text: '0.00');
    double sliderValue = 0;
    final allocated = state.categories
        .where((c) => c.inBudget)
        .fold<double>(0.0, (s, c) => s + c.budgetLimit);
    final extras = _extrasBeyondPlanForActivePeriod(state);
    final available = totalIncome(state) - allocated - extras;
    final double maxValue = totalIncome(state) > 0
        ? (available.clamp(0.0, totalIncome(state))).toDouble()
        : 10000.0;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Budget Category'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (unbudgeted.isNotEmpty) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedCatId,
                              decoration: const InputDecoration(
                                labelText: 'Select Category',
                              ),
                              items: [
                                ...unbudgeted.map(
                                  (c) => DropdownMenuItem(
                                    value: c.id.toString(),
                                    child: Text(c.name),
                                  ),
                                ),
                                const DropdownMenuItem(
                                  value: 'new',
                                  child: Text('+ Create New Category'),
                                ),
                              ],
                              onChanged: (val) {
                                setState(() {
                                  selectedCatId = val!;
                                });
                              },
                            ),
                          ),
                          if (selectedCatId != 'new')
                            IconButton(
                              icon: const Icon(
                                Icons.delete_forever,
                                color: Colors.red,
                              ),
                              tooltip: 'Permanently Delete Category',
                              onPressed: () async {
                                final cat = unbudgeted.firstWhere(
                                  (c) => c.id.toString() == selectedCatId,
                                );
                                final hasTransactions = await RMinderDatabase
                                    .instance
                                    .hasTransactionsForCategory(cat.id ?? 0);
                                if (!context.mounted) return;
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text(
                                      'Completely Delete Category?!',
                                    ),
                                    content: Text(
                                      hasTransactions
                                          ? 'WARNING: This inactive category has past transactions. Deleting it completely will PERMANENTLY delete all associated past transactions too! Do you want to proceed?'
                                          : 'Are you sure you want to permanently delete this inactive category?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                        ),
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Delete Permanently'),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm != true || !context.mounted) return;
                                await runGuardedMutation(
                                  context: context,
                                  failureMessage: 'Failed to delete category.',
                                  action: () async {
                                    await RMinderDatabase.instance
                                        .deleteCategoryCascade(cat.id!);
                                  },
                                  onSuccess: () async {
                                    await Provider.of<AppState>(
                                      context,
                                      listen: false,
                                    ).refresh();
                                    if (!context.mounted) return;
                                    Navigator.pop(
                                      context,
                                    ); // close the Add Budget dialog
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Category completely deleted.',
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (selectedCatId == 'new') ...[
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'New Category Name',
                        ),
                        maxLength: 15,
                        onChanged: (_) => setState(() {}),
                      ),
                      if (nameController.text.length >= 15)
                        const Padding(
                          padding: EdgeInsets.only(left: 4.0),
                          child: Text(
                            'Maximum characters reached',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Monthly Limit',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SliderTheme(
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
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: 140,
                        child: TextField(
                          controller: limitController,
                          decoration: const InputDecoration(
                            labelText: 'Amount',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: false,
                            signed: false,
                          ),
                          inputFormatters: [CurrencyInputFormatter()],
                          onChanged: (val) {
                            final parsed = double.tryParse(val) ?? 0;
                            setState(
                              () => sliderValue = parsed
                                  .clamp(0.0, maxValue)
                                  .toDouble(),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final budgetLimit =
                  double.tryParse(
                    limitController.text.trim().replaceAll(',', ''),
                  ) ??
                  0;
              if (budgetLimit > 0) {
                if (selectedCatId == 'new') {
                  final name = nameController.text.trim();
                  if (name.isNotEmpty) {
                    await runGuardedMutation(
                      context: context,
                      failureMessage: 'Failed to add budget category.',
                      action: () async {
                        await RMinderDatabase.instance.insertCategory(
                          models.BudgetCategory(
                            name: name,
                            budgetLimit: budgetLimit,
                            spent: 0,
                            inBudget: true,
                          ),
                        );
                      },
                      onSuccess: () async {
                        await Provider.of<AppState>(
                          context,
                          listen: false,
                        ).refresh();
                        if (context.mounted) Navigator.pop(context);
                      },
                    );
                  }
                } else {
                  final cat = unbudgeted.firstWhere(
                    (c) => c.id.toString() == selectedCatId,
                  );
                  await runGuardedMutation(
                    context: context,
                    failureMessage: 'Failed to add category to budget.',
                    action: () async {
                      await RMinderDatabase.instance.updateCategory(
                        models.BudgetCategory(
                          id: cat.id,
                          name: cat.name,
                          budgetLimit: budgetLimit,
                          spent: cat.spent,
                          inBudget: true,
                        ),
                      );
                    },
                    onSuccess: () async {
                      await Provider.of<AppState>(
                        context,
                        listen: false,
                      ).refresh();
                      if (context.mounted) Navigator.pop(context);
                    },
                  );
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditCategoryDialog(models.BudgetCategory category) async {
    final state = Provider.of<AppState>(context, listen: false);
    final nameController = TextEditingController(text: category.name);
    double sliderValue = category.budgetLimit;
    final allocatedOthers = state.categories
        .where((c) => c.id != category.id)
        .fold<double>(0.0, (s, c) => s + c.budgetLimit);
    final extras = _extrasBeyondPlanForActivePeriod(state);
    final totalInc = totalIncome(state);
    final available = totalInc - allocatedOthers - extras;
    final double maxValue = totalInc > 0
        ? (available.clamp(0.0, totalInc)).toDouble()
        : 10000.0;
    sliderValue = sliderValue.clamp(0.0, maxValue).toDouble();
    final limitController = TextEditingController(
      text: sliderValue.toStringAsFixed(2),
    );
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Budget Category'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatefulBuilder(
                builder: (context, setState) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Category Name',
                        ),
                        maxLength: 15,
                        onChanged: (_) => setState(() {}),
                      ),
                      if (nameController.text.length >= 15)
                        const Padding(
                          padding: EdgeInsets.only(left: 4.0),
                          child: Text(
                            'Maximum characters reached',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Text(
                        'Monthly Limit',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 8,
                          activeTrackColor: Colors.deepPurple[700],
                          inactiveTrackColor: Colors.deepPurple[200],
                          thumbColor: Colors.deepPurple[900],
                          overlayColor: Colors.deepPurple.withValues(
                            alpha: 0.2,
                          ),
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
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: SizedBox(
                          width: 140,
                          child: TextField(
                            controller: limitController,
                            decoration: const InputDecoration(
                              labelText: 'Amount',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: false,
                              signed: false,
                            ),
                            inputFormatters: [CurrencyInputFormatter()],
                            onChanged: (val) {
                              final parsed = double.tryParse(val) ?? 0;
                              setState(
                                () => sliderValue = parsed
                                    .clamp(0.0, maxValue)
                                    .toDouble(),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final budgetLimit =
                  double.tryParse(
                    limitController.text.trim().replaceAll(',', ''),
                  ) ??
                  0;
              if (name.isNotEmpty && budgetLimit > 0) {
                await runGuardedMutation(
                  context: context,
                  failureMessage: 'Failed to update category.',
                  action: () async {
                    await RMinderDatabase.instance.updateCategory(
                      models.BudgetCategory(
                        id: category.id,
                        name: name,
                        budgetLimit: budgetLimit,
                        spent: category.spent,
                      ),
                    );
                  },
                  onSuccess: () async {
                    await Provider.of<AppState>(
                      context,
                      listen: false,
                    ).refresh();
                    if (context.mounted) Navigator.pop(context);
                  },
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _removeFromBudget(models.BudgetCategory category) async {
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from Budget?'),
        content: const Text(
          'This will remove the category from the active budget, but keep your past transactions safe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (shouldRemove == true && mounted) {
      await runGuardedMutation(
        context: context,
        failureMessage: 'Failed to remove category from budget.',
        action: () async {
          await RMinderDatabase.instance.updateCategory(
            models.BudgetCategory(
              id: category.id,
              name: category.name,
              budgetLimit: category.budgetLimit,
              spent: category.spent,
              inBudget: false,
            ),
          );
        },
        onSuccess: () async {
          await Provider.of<AppState>(context, listen: false).refresh();
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Budget'),
        actions: buildGlobalAppBarActions(context),
      ),
      body: Consumer<AppState>(
        builder: (context, appState, child) {
          if (appState.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final totalInc = totalIncome(appState);
          final categories = appState.categories
              .where((c) => c.inBudget)
              .toList();
          final incomeSources = appState.incomeSources;
          final sinkingFunds = appState.sinkingFunds;
          final liabilities = appState.liabilities;
          final theme = Theme.of(context);

          return Column(
            children: [
              _buildSummaryDashboard(context, totalInc, categories, appState),
              Expanded(
                child: Padding(
                  padding: kCompactPagePadding,
                  child: Scrollbar(
                    controller: _budgetScroll,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _budgetScroll,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CompactSectionCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Income',
                                      style: compactSectionTitleStyle(context),
                                    ),
                                    Row(
                                      children: [
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.add),
                                          label: const Text('Add'),
                                          onPressed: _showAddIncomeSourceDialog,
                                          style: ElevatedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                if (_carryIncome > 0)
                                  CompactItemCard(
                                    child: ListTile(
                                      title: Text(
                                        'Carry-forward',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      subtitle: Text(
                                        'Amount: ₹${_carryIncome.toStringAsFixed(2)}',
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                      trailing: Wrap(
                                        spacing: 4,
                                        children: [
                                          IconButton(
                                            icon: Icon(
                                              Icons.edit,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                            ),
                                            onPressed:
                                                _showEditCarryIncomeDialog,
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              Icons.delete_forever,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.error,
                                            ),
                                            tooltip: 'Delete',
                                            onPressed: _deleteCarryIncome,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                incomeSources.isEmpty
                                    ? const Center(
                                        child: Text('No income sources yet.'),
                                      )
                                    : Column(
                                        children: incomeSources
                                            .map(
                                              (src) => CompactItemCard(
                                                child: ListTile(
                                                  title: Text(
                                                    src.name,
                                                    style: theme
                                                        .textTheme
                                                        .titleMedium
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                  ),
                                                  subtitle: Text(
                                                    'Amount: ₹${src.amount.toStringAsFixed(2)}',
                                                    style: theme
                                                        .textTheme
                                                        .bodyMedium,
                                                  ),
                                                  trailing: Wrap(
                                                    spacing: 4,
                                                    children: [
                                                      IconButton(
                                                        icon: Icon(
                                                          Icons.edit,
                                                          color: Theme.of(
                                                            context,
                                                          ).colorScheme.primary,
                                                        ),
                                                        onPressed: () =>
                                                            _showEditIncomeSourceDialog(
                                                              src,
                                                            ),
                                                      ),
                                                      IconButton(
                                                        icon: Icon(
                                                          Icons.delete,
                                                          color: Theme.of(
                                                            context,
                                                          ).colorScheme.error,
                                                        ),
                                                        onPressed: () =>
                                                            _deleteIncomeSource(
                                                              src.id!,
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                      ),
                              ],
                            ),
                          ),
                          const SizedBox(height: kCompactSectionGap),
                          CompactSectionCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Budget',
                                      style: compactSectionTitleStyle(context),
                                    ),
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.add),
                                      label: const Text('Add'),
                                      onPressed: () {
                                        if (totalInc == 0) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Please add your income before adding a budget category.',
                                              ),
                                            ),
                                          );
                                        } else {
                                          _showAddCategoryDialog();
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.shopping_bag,
                                        size: 18,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Expenses',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                ...categories
                                    .where(
                                      (c) =>
                                          !liabilities.any(
                                            (l) => l.budgetCategoryId == c.id,
                                          ) &&
                                          !sinkingFunds.any(
                                            (f) => f.budgetCategoryId == c.id,
                                          ),
                                    )
                                    .map(
                                      (category) => CompactItemCard(
                                        child: ListTile(
                                          key: ValueKey(category.id),
                                          title: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                category.name.length > 15
                                                    ? '${category.name.substring(0, 15)}...'
                                                    : category.name,
                                                style: theme
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Limit: ₹${category.budgetLimit.toStringAsFixed(2)}',
                                                style:
                                                    theme.textTheme.bodyMedium,
                                              ),
                                            ],
                                          ),
                                          trailing: Wrap(
                                            spacing: 4,
                                            children: [
                                              IconButton(
                                                icon: Icon(
                                                  Icons.edit,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                                ),
                                                onPressed: () =>
                                                    _showEditCategoryDialog(
                                                      category,
                                                    ),
                                              ),
                                              IconButton(
                                                icon: Icon(
                                                  Icons.delete,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.error,
                                                ),
                                                onPressed: () =>
                                                    _removeFromBudget(category),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.savings,
                                        size: 18,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Liabilities',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                if (liabilities.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(
                                      vertical: 6.0,
                                    ),
                                    child: Text('No liabilities added yet.'),
                                  )
                                else
                                  ...liabilities.map(
                                    (liab) => CompactItemCard(
                                      child: ListTile(
                                        key: ValueKey('liab-${liab.id}'),
                                        title: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              liab.name,
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Min: ₹${liab.planned.toStringAsFixed(2)}',
                                              style: theme.textTheme.bodyMedium,
                                            ),
                                          ],
                                        ),
                                        trailing: Wrap(
                                          spacing: 4,
                                          children: [
                                            IconButton(
                                              icon: Icon(
                                                Icons.edit,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                              ),
                                              tooltip: 'Edit in Liabilities',
                                              onPressed: () {
                                                TabSwitcher.of(
                                                  context,
                                                )?.switchTo(3);
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.attach_money,
                                        size: 18,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Savings',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                if (sinkingFunds.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(
                                      vertical: 6.0,
                                    ),
                                    child: Text('No savings funds added yet.'),
                                  )
                                else
                                  ...sinkingFunds.map(
                                    (fund) => CompactItemCard(
                                      child: ListTile(
                                        key: ValueKey('fund-${fund.id}'),
                                        title: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              fund.name,
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Monthly: ₹${fund.monthlyContribution.toStringAsFixed(2)}',
                                              style: compactMutedStyle(context),
                                            ),
                                          ],
                                        ),
                                        trailing: Wrap(
                                          spacing: 4,
                                          children: [
                                            IconButton(
                                              icon: Icon(
                                                Icons.edit,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                              ),
                                              tooltip: 'Edit in Savings',
                                              onPressed: () {
                                                TabSwitcher.of(
                                                  context,
                                                )?.switchTo(2);
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryDashboard(
    BuildContext context,
    double totalInc,
    List<models.BudgetCategory> categories,
    AppState appState,
  ) {
    final theme = Theme.of(context);
    final selection = selectActiveOverviewSelection(
      categories: categories,
      transactions: appState.transactions,
      liabilities: appState.liabilities,
      sinkingFunds: appState.sinkingFunds,
      periodStart: appState.activePeriodStart,
      periodEndExclusive: _activePeriodEndExclusive(),
    );

    final metrics = calculateOverviewMetrics(
      selection.categories.map(
        (c) => OverviewMetricItem(
          planned: c.budgetLimit,
          spent: selection.spentByCategory[c.id!] ?? 0.0,
        ),
      ),
    );
    final spendingCategoryBudget = metrics.planned;
    final plannedDebt = appState.liabilities
        .where((l) => !l.isArchived)
        .fold<double>(0.0, (sum, l) => sum + l.planned);
    final plannedFunds = appState.sinkingFunds.fold<double>(
      0.0,
      (sum, f) => sum + f.monthlyContribution,
    );

    final extraDebtPayments = _extraDebtPaymentsForActivePeriod(appState);
    final extraFundContributions = _extraFundContributionsForActivePeriod(
      appState,
    );

    final plannedAmount =
        spendingCategoryBudget +
        plannedDebt +
        plannedFunds +
        extraDebtPayments +
        extraFundContributions;
    final unplannedAmount = totalInc - plannedAmount;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
                theme.colorScheme.surface,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Overview',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Income: ₹${totalInc.toStringAsFixed(2)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: metrics.isOverBudget
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      metrics.isOverBudget ? 'Over Budget' : 'On Track',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _SummaryStat(
                      title: 'Planned',
                      amount: plannedAmount,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Expanded(
                    child: _SummaryStat(
                      title: 'Unplanned',
                      amount: unplannedAmount,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                  Expanded(
                    child: _SummaryStat(
                      title: 'Spent',
                      amount: metrics.spent,
                      color: theme.colorScheme.error,
                    ),
                  ),
                  Expanded(
                    child: _SummaryStat(
                      title: 'Remaining',
                      amount: spendingCategoryBudget,
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: metrics.progress,
                  minHeight: 10,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    metrics.isOverBudget
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String title;
  final double amount;
  final Color color;

  const _SummaryStat({
    required this.title,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(title, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          '₹${amount.toStringAsFixed(2)}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
