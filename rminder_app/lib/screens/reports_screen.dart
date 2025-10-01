import 'package:flutter/material.dart';
import '../db/rminder_database.dart';
import '../models/models.dart' as models;
import '../utils/logger.dart';
import '../widgets/charts.dart';
import '../utils/ui_intents.dart';

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
  // Periods are anchored by last close; no static reset day.

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadActivePeriod();
    // Listen for global Close Period events (triggered from other pages' menus)
    UiIntents.closePeriodEvent.addListener(_maybeHandleClosePeriodIntent);
  }

  @override
  void dispose() {
    UiIntents.closePeriodEvent.removeListener(_maybeHandleClosePeriodIntent);
    _reportScroll.dispose();
    super.dispose();
  }

  void _maybeHandleClosePeriodIntent() {
    // Debounce by posting to next frame to avoid re-entrancy
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _closeMonthFlow();
    });
  }

  // Period start for a given anchor (truncate to date)
  DateTime _periodStartFor(DateTime anchor) {
    return DateTime(anchor.year, anchor.month, anchor.day);
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isClosedPeriod(DateTime start) {
    return _closedMonths.any((d) => _sameDay(d, start));
  }

  // Upper bound (exclusive) for the selected period: if closed, next start; else, now+1d.
  DateTime _periodUpperBoundExclusive(DateTime start) {
    if (_isClosedPeriod(start)) {
      return DateTime(start.year, start.month + 1, start.day);
    }
    // Active period: include everything up to "now"
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  }

  String _shortMon(int m) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return names[m - 1];
  }

  String _formatDayMon(DateTime d, {bool withYear = false}) {
    final date = DateTime(d.year, d.month, d.day);
    final base = '${date.day} ${_shortMon(date.month)}';
    return withYear ? '$base ${date.year}' : base;
  }

  String _formatPeriodRange(DateTime start) {
    final s = DateTime(start.year, start.month, start.day);
    final endExclusive = _periodUpperBoundExclusive(s);
    final endInclusive = endExclusive.subtract(const Duration(days: 1));
    final withYear = s.year != endInclusive.year;
    return '${_formatDayMon(s, withYear: withYear)} – ${_formatDayMon(endInclusive, withYear: withYear)}';
  }

  Future<void> _loadData() async {
    try {
      final cats = await RMinderDatabase.instance.getCategories();
      final txns = await RMinderDatabase.instance.getTransactions();
      final liabs = await RMinderDatabase.instance.getLiabilities();
      final funds = await RMinderDatabase.instance.getSinkingFunds();
      final incomes = await RMinderDatabase.instance.getIncomeSources();
      final closed = await RMinderDatabase.instance.getClosedMonths();
      if (!mounted) return;
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

  Future<void> _loadActivePeriod() async {
    try {
      final active = await RMinderDatabase.instance.getActivePeriodStart();
      if (!mounted) return;
      setState(() {
        if (active != null) {
          selectedMonth = active;
        } else {
          selectedMonth = DateTime.now();
        }
      });
    } catch (e, st) {
      logError(e, st);
    }
  }

  // Build the list of period anchors (start dates) used for navigation
  List<DateTime> _allowedPeriods() {
    final closedPeriods = _closedMonths.map((d) => DateTime(d.year, d.month, d.day)).toSet();
    final currentAnchor = DateTime(selectedMonth.year, selectedMonth.month, selectedMonth.day);
    final set = {...closedPeriods, currentAnchor};
    final list = set.toList()..sort((a, b) => a.compareTo(b));
    return list;
  }

  MonthlySummary getMonthlySummary() {
    final debtCategoryIds = liabilities.map((l) => l.budgetCategoryId).toSet();
    final fundCategoryIds = sinkingFunds.where((f) => f.budgetCategoryId != null).map((f) => f.budgetCategoryId!).toSet();
    final excludedCategoryIds = {...debtCategoryIds, ...fundCategoryIds};
    final Map<int, double> spentByCategoryThisMonth = {};
    final periodStart = _periodStartFor(selectedMonth);
    final periodEnd = _periodUpperBoundExclusive(periodStart);
    for (final txn in transactions) {
      // Include transactions in [periodStart, periodEnd)
      if (!txn.date.isBefore(periodStart) && txn.date.isBefore(periodEnd)) {
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

  @override
  Widget build(BuildContext context) {
    final summary = getMonthlySummary();
    final periods = _allowedPeriods();
    if (!periods.any((p) => _sameDay(p, selectedMonth))) {
      selectedMonth = periods.isNotEmpty ? periods.last : DateTime.now();
    }
    final int currentIndex = periods.indexWhere((p) => _sameDay(p, selectedMonth));
    final bool canGoPrev = currentIndex > 0;
    final bool canGoNext = currentIndex >= 0 && currentIndex < periods.length - 1;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Previous Period',
              icon: const Icon(Icons.chevron_left),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: canGoPrev
                  ? () => setState(() {
                        selectedMonth = periods[currentIndex - 1];
                        if (!_isClosedPeriod(selectedMonth)) {
                          RMinderDatabase.instance.setActivePeriodStart(selectedMonth);
                        }
                      })
                  : null,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: InkWell(
                onTap: _showJumpToPeriod,
                borderRadius: BorderRadius.circular(6),
                child: Text(
                  _formatPeriodRange(_periodStartFor(selectedMonth)),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Next Period',
              icon: const Icon(Icons.chevron_right),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: canGoNext
                  ? () => setState(() {
                        selectedMonth = periods[currentIndex + 1];
                        if (!_isClosedPeriod(selectedMonth)) {
                          RMinderDatabase.instance.setActivePeriodStart(selectedMonth);
                        }
                      })
                  : null,
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'close',
                child: ListTile(
                  leading: Icon(Icons.task_alt),
                  title: Text('Close period'),
                ),
              ),
            ],
            onSelected: (value) async {
              if (value == 'close') {
                await _closeMonthFlow();
              }
            },
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
                      // Use cents to avoid floating-point rounding issues showing “overbudgeted by 0.00”.
                      final totalIncome = incomeSources.fold<double>(0, (s, i) => s + i.amount);
                      final totalBudgeted = categories.fold<double>(0, (s, c) => s + c.budgetLimit);
                      final int incomeCents = (totalIncome * 100).round();
                      final int budgetCents = (totalBudgeted * 100).round();
                      final int unallocatedCents = incomeCents - budgetCents; // positive => unallocated
                      final hasIncome = incomeCents > 0;
                      final hasBudget = budgetCents > 0;
                      final isNoIncomeButBudgeted = !hasIncome && hasBudget;
                      final isOverBudgeted = hasIncome && budgetCents > incomeCents;

                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Budget Summary', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text('Total Income: ₹${(incomeCents / 100).toStringAsFixed(2)}'),
                        Text('Total Budgeted: ₹${(budgetCents / 100).toStringAsFixed(2)}'),

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
                            'Overbudgeted by ₹${((budgetCents - incomeCents) / 100).toStringAsFixed(2)}',
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
                            'Unallocated: ₹${(unallocatedCents / 100).toStringAsFixed(2)}',
                            style: TextStyle(
                              color: unallocatedCents == 0 ? Colors.green : Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (unallocatedCents != 0)
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
                        final int cents = ((income - budgeted) * 100).round();
                        return cents > 0 ? cents / 100.0 : 0.0;
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
    final start = _periodStartFor(selectedMonth);
    final end = _periodUpperBoundExclusive(start);
    for (final t in transactions) {
      if (t.categoryId == fund.budgetCategoryId && !t.date.isBefore(start) && t.date.isBefore(end)) {
        total += t.amount;
      }
    }
    return total;
  }

  double _paidThisMonthFor(models.Liability liab) {
    double total = 0;
    final start = _periodStartFor(selectedMonth);
    final end = _periodUpperBoundExclusive(start);
    for (final t in transactions) {
      if (t.categoryId == liab.budgetCategoryId && !t.date.isBefore(start) && t.date.isBefore(end)) {
        total += t.amount;
      }
    }
    return total;
  }

  Future<void> _closeMonthFlow() async {
    // User-driven close: allow closing the currently selected period at any time.

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
    final periodStart = _periodStartFor(selectedMonth);
    final periodEnd = DateTime(periodStart.year, periodStart.month + 1, periodStart.day);
    for (final txn in transactions) {
      if (!txn.date.isBefore(periodStart) && txn.date.isBefore(periodEnd)) {
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
        final nextStart = DateTime(periodStart.year, periodStart.month + 1, periodStart.day);
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
          monthStart: periodStart,
          action: 'carryForward',
        );
        await _loadData();
        if (!mounted) return;
        setState(() => selectedMonth = nextStart);
        await RMinderDatabase.instance.setActivePeriodStart(nextStart);
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
        final end = DateTime(periodStart.year, periodStart.month + 1, periodStart.day).subtract(const Duration(days: 1));
        await RMinderDatabase.instance.insertTransaction(models.Transaction(
          categoryId: liab.budgetCategoryId,
          amount: totalLeftover,
          date: end,
          note: 'Month close payment (${_monthName(selectedMonth.month)} ${selectedMonth.year}) - ${liab.name}',
        ));
        await RMinderDatabase.instance.insertClosedMonth(
          monthStart: periodStart,
          action: 'payDebt',
        );
        final nextStart = DateTime(periodStart.year, periodStart.month + 1, periodStart.day);
        await _loadData();
        if (!mounted) return;
        setState(() => selectedMonth = nextStart);
        await RMinderDatabase.instance.setActivePeriodStart(nextStart);
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

  Future<void> _showJumpToPeriod() async {
    try {
      final periods = _allowedPeriods();
      if (periods.isEmpty) return;
      final chosen = await showDialog<DateTime>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Jump to period'),
          content: SizedBox(
            width: 360,
            height: 320,
            child: ListView.builder(
              itemCount: periods.length,
              itemBuilder: (c, i) {
                final p = periods[i];
                return ListTile(
                  title: Text(_formatPeriodRange(_periodStartFor(p))),
                  onTap: () => Navigator.pop(ctx, p),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ],
        ),
      );
      if (chosen != null && mounted) {
        setState(() => selectedMonth = chosen);
        if (!_isClosedPeriod(chosen)) {
          RMinderDatabase.instance.setActivePeriodStart(chosen);
        }
      }
    } catch (e, st) {
      logError(e, st);
    }
  }
}

String _monthName(int m) {
  const names = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  return names[m - 1];
}
