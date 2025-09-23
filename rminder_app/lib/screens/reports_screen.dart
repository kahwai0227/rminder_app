import 'package:flutter/material.dart';
import '../db/rminder_database.dart';
import '../models/models.dart' as models;
import '../utils/logger.dart';
import '../widgets/charts.dart';
import 'tips_screen.dart';

class ReportingPage extends StatefulWidget {
  const ReportingPage({Key? key}) : super(key: key);
  @override
  State<ReportingPage> createState() => _ReportingPageState();
}

enum CloseAction { carryForward, payDebt }

class _ReportingPageState extends State<ReportingPage> {
  List<models.BudgetCategory> categories = [];
  List<models.Transaction> transactions = [];
  List<models.Liability> liabilities = [];
  List<models.SinkingFund> sinkingFunds = [];
  List<models.IncomeSource> incomeSources = [];
  DateTime selectedMonth = DateTime.now();
  List<DateTime> _closedMonths = [];
  bool _isDetailsDialogOpen = false;
  final ScrollController _reportScroll = ScrollController();

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

  bool _isSameMonth(DateTime a, DateTime b) => a.year == b.year && a.month == b.month;

  Future<void> _loadData() async {
    try {
      final cats = await RMinderDatabase.instance.getCategories();
      final txns = await RMinderDatabase.instance.getTransactions();
      final liabs = await RMinderDatabase.instance.getLiabilities();
      final funds = await RMinderDatabase.instance.getSinkingFunds();
      final incomes = await RMinderDatabase.instance.getIncomeSources();
      final closed = await RMinderDatabase.instance.getClosedMonths();
      setState(() {
        categories = cats;
        transactions = txns;
        liabilities = liabs;
        sinkingFunds = funds;
        incomeSources = incomes;
        _closedMonths = closed;
      });
    } catch (e, st) {
      logError(e, st);
    }
  }

  String _shortMonthName(int m) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return names[m - 1];
  }

  MonthlySummary getMonthlySummary() {
    final debtCategoryIds = liabilities.map((l) => l.budgetCategoryId).toSet();
    final fundCategoryIds = sinkingFunds.where((f) => f.budgetCategoryId != null).map((f) => f.budgetCategoryId!).toSet();
    final excludedCategoryIds = {...debtCategoryIds, ...fundCategoryIds};
    final Map<int, double> spentByCategoryThisMonth = {};
    for (final txn in transactions) {
      if (_isSameMonth(txn.date, selectedMonth)) {
        if (excludedCategoryIds.contains(txn.categoryId)) continue;
        spentByCategoryThisMonth.update(txn.categoryId, (v) => v + txn.amount, ifAbsent: () => txn.amount);
      }
    }
    double totalSpent = 0;
    double totalLimit = 0;
    List<CategoryBreakdown> breakdown = [];
    for (final cat in categories) {
      if (cat.id == null) continue;
      if (excludedCategoryIds.contains(cat.id)) continue;
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

  DateTime _startOfNextMonth(DateTime m) => DateTime(m.year, m.month + 1, 1);
  DateTime _endOfMonth(DateTime m) => DateTime(m.year, m.month + 1, 0);

  @override
  Widget build(BuildContext context) {
    final summary = getMonthlySummary();
    final currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final List<DateTime> allowedMonths = ([..._closedMonths, currentMonth]
          ..sort((a, b) => a.compareTo(b)))
        .map((d) => DateTime(d.year, d.month, 1))
        .toList();
    if (!allowedMonths.any((m) => _isSameMonth(m, selectedMonth))) {
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
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const TipsScreen()),
            ),
            tooltip: 'Tips & Help',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
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
                        ],
                      ]);
                    }),
                  ),
                ),
                const SizedBox(height: 10),
                Text('Budget Allocation', style: Theme.of(context).textTheme.titleMedium),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: BudgetAllocationChart(
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
                if (summary.breakdown.isEmpty)
                  const Center(child: Text('No categories available. Add a category to view reports.'))
                else ...[
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
                ],
                const SizedBox(height: 16),
                if (sinkingFunds.isNotEmpty) ...[
                  Text('Savings Contributions', style: Theme.of(context).textTheme.titleMedium),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: sinkingFunds.length,
                    itemBuilder: (context, index) {
                      final fund = sinkingFunds[index];
                      final contributed = _contributedThisMonthFor(fund);
                      final delta = contributed - fund.monthlyContribution;
                      final progress = fund.targetAmount <= 0
                          ? 0.0
                          : (fund.balance / fund.targetAmount).clamp(0.0, 1.0);
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(fund.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      const Text('Δ vs Plan', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                      Text(
                                        '₹${delta.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          color: delta >= 0 ? Colors.green : Colors.red,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text('Monthly: ₹${fund.monthlyContribution.toStringAsFixed(2)} | Contributed: ₹${contributed.toStringAsFixed(2)}'),
                              const SizedBox(height: 6),
                              Text('Progress: ₹${fund.balance.toStringAsFixed(2)} / ₹${fund.targetAmount.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(value: progress),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
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
    );
  }

  double _contributedThisMonthFor(models.SinkingFund fund) {
    if (fund.budgetCategoryId == null) return 0;
    double total = 0;
    for (final t in transactions) {
      if (t.categoryId == fund.budgetCategoryId && _isSameMonth(t.date, selectedMonth)) {
        total += t.amount;
      }
    }
    return total;
  }

  Future<void> _closeMonthFlow() async {
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

    final alreadyClosed = await RMinderDatabase.instance.isMonthClosed(selectedMonth);
    if (alreadyClosed) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_monthName(selectedMonth.month)} ${selectedMonth.year} is already closed.')),
      );
      return;
    }

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
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        ),
      );
      return;
    }

    final debtCategoryIds = liabilities.map((l) => l.budgetCategoryId).toSet();
    final fundCategoryIds = sinkingFunds.where((f) => f.budgetCategoryId != null).map((f) => f.budgetCategoryId!).toSet();
    final excludedCategoryIds = {...debtCategoryIds, ...fundCategoryIds};
    final Map<int, double> spentByCategoryThisMonth = {};
    for (final txn in transactions) {
      if (_isSameMonth(txn.date, selectedMonth)) {
        if (excludedCategoryIds.contains(txn.categoryId)) continue;
        spentByCategoryThisMonth.update(txn.categoryId, (v) => v + txn.amount, ifAbsent: () => txn.amount);
      }
    }
    final List<models.BudgetCategory> regularCats = categories
        .where((c) => c.id != null && !excludedCategoryIds.contains(c.id))
        .toList();
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
