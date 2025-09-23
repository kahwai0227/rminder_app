import 'package:flutter/material.dart';
import '../db/rminder_database.dart';
import '../models/models.dart' as models;
import '../utils/logger.dart';
import '../utils/currency_input_formatter.dart';
import 'tips_screen.dart';

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({Key? key}) : super(key: key);
  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  List<models.Transaction> transactions = [];
  List<models.BudgetCategory> categories = [];
  List<models.Liability> liabilities = [];
  List<models.SinkingFund> _sinkingFunds = [];
  bool _hideDebt = false;
  final ScrollController _txScroll = ScrollController();
  models.BudgetCategory? _filterCategory;
  DateTime? _filterSingleDate;
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  DateTime? _filterMonthDate;
  double? _filterMinAmount;
  double? _filterMaxAmount;

  String _formatIsoDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final da = d.day.toString().padLeft(2, '0');
    return '$y-$m-$da';
  }

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
      final funds = await RMinderDatabase.instance.getSinkingFunds();
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
        _sinkingFunds = funds;
      });
    } catch (e, st) {
      logError(e, st);
    }
  }

  List<models.Transaction> get filteredTransactions {
    final debtCategoryIds = liabilities.map((l) => l.budgetCategoryId).toSet();
    return transactions.where((txn) {
      final byCategory = _filterCategory == null || txn.categoryId == _filterCategory!.id;
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

  bool _isSinkingFundCategory(int categoryId) =>
      _sinkingFunds.any((f) => f.budgetCategoryId == categoryId);

  (String display, bool isPositive) _signedAmountForDisplay(models.Transaction t) {
    // Convention:
    // - For non-sinking categories, show as expense (-) regardless of stored sign.
    // - For sinking funds, show + for contributions (>=0), - for withdrawals (<0).
    const symbol = '₹';
    if (_isSinkingFundCategory(t.categoryId)) {
      final isPos = t.amount >= 0;
      final v = t.amount.abs().toStringAsFixed(2);
      return ('${isPos ? '+' : '-'}$symbol$v', isPos);
    }
    final v = t.amount.abs().toStringAsFixed(2);
    return ('-$symbol$v', false);
  }

  List<Widget> _buildGroupedTransactionWidgets(BuildContext context) {
    final txns = List<models.Transaction>.from(filteredTransactions);
    // Sort by date (desc), then by id desc to keep recent first
    txns.sort((a, b) {
      final d = b.date.compareTo(a.date);
      if (d != 0) return d;
      // Null-safe id compare
      final aid = a.id ?? -1;
      final bid = b.id ?? -1;
      return bid.compareTo(aid);
    });

    final List<Widget> children = [];
    DateTime? currentDate;

    for (final t in txns) {
      final dateOnly = DateTime(t.date.year, t.date.month, t.date.day);
      final cat = categories.firstWhere((c) => c.id == t.categoryId,
          orElse: () => models.BudgetCategory(id: -1, name: 'Unknown', budgetLimit: 0, spent: 0));

      if (currentDate == null || dateOnly != currentDate) {
        // Close previous group with a divider (if any)
        if (currentDate != null) {
          children.add(const Divider(height: 24));
        }
        currentDate = dateOnly;
        children.add(Text(
          _formatIsoDate(dateOnly),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ));
        children.add(const Divider());
      }

      final (displayAmount, isPositive) = _signedAmountForDisplay(t);
      final amountColor = isPositive ? Colors.green : Colors.red;
      final isDebt = liabilities.any((l) => l.budgetCategoryId == t.categoryId);
      final isSaving = _isSinkingFundCategory(t.categoryId);
      IconData leadingIcon = Icons.shopping_bag;
      if (isDebt) {
        leadingIcon = Icons.savings;
      } else if (isSaving) {
        leadingIcon = Icons.attach_money;
      }

      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: Icon(
                    leadingIcon,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                Expanded(
                  child: Text(
                    cat.name,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                Text(
                  displayAmount,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: amountColor, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () => _showEditTransactionDialog(t),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _confirmDeleteTransaction(t),
                ),
              ],
            ),
            if (t.note != null && t.note!.trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'note: ${t.note!}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
              ),
            ],
          ],
        ),
      ));
    }

    if (children.isNotEmpty) {
      children.add(const Divider(height: 24));
    }

    return children;
  }

  Future<void> _showAddTransactionDialog() async {
    models.BudgetCategory? selectedCategory = categories.isNotEmpty ? categories[0] : null;
  final amountController = TextEditingController(text: '0.00');
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
                  keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
                  inputFormatters: [CurrencyInputFormatter()],
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
              final amount = double.tryParse(amountController.text.trim().replaceAll(',', '')) ?? 0;
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
  final amountController = TextEditingController(text: txn.amount.toStringAsFixed(2));
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
                  keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
                  inputFormatters: [CurrencyInputFormatter()],
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
              final amount = double.tryParse(amountController.text.trim().replaceAll(',', '')) ?? 0;
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

        final now = DateTime.now();
        final List<DateTime> monthOptions = List.generate(24, (i) {
          final base = DateTime(now.year, now.month - i, 1);
          return DateTime(base.year, base.month, 1);
        });

        double minAvail = 0;
        double maxAvail = 1000;
        if (transactions.isNotEmpty) {
          final amts = transactions.map((t) => t.amount).toList();
          minAvail = amts.reduce((a, b) => a < b ? a : b);
          maxAvail = amts.reduce((a, b) => a > b ? a : b);
          if (maxAvail <= minAvail) maxAvail = minAvail + 1;
        }
        double currentMin = (tempMinAmount ?? minAvail).clamp(minAvail, maxAvail);
        double currentMax = (tempMaxAmount ?? maxAvail).clamp(currentMin, maxAvail);
        RangeValues amountRange = RangeValues(currentMin, currentMax);
        final TextEditingController minAmountController =
            TextEditingController(text: amountRange.start.toStringAsFixed(0));
        final TextEditingController maxAmountController =
            TextEditingController(text: amountRange.end.toStringAsFixed(0));

        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
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
                              ElevatedButton(onPressed: () => Navigator.pop(ctx, localSel), child: const Text('Select')),
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
                              final clamped = parsed.clamp(minAvail, maxAvail).toDouble();
                              tempMinAmount = clamped;
                              if (amountRange.start != clamped) {
                                amountRange = RangeValues(clamped, amountRange.end < clamped ? clamped : amountRange.end);
                                final newMin = clamped.toStringAsFixed(0);
                                if (minAmountController.text != newMin) minAmountController.text = newMin;
                                if (amountRange.end < clamped) {
                                  final newMax = clamped.toStringAsFixed(0);
                                  if (maxAmountController.text != newMax) maxAmountController.text = newMax;
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
                              final clamped = parsed.clamp(minAvail, maxAvail).toDouble();
                              tempMaxAmount = clamped;
                              if (amountRange.end != clamped) {
                                amountRange = RangeValues(amountRange.start > clamped ? clamped : amountRange.start, clamped);
                                final newMax = clamped.toStringAsFixed(0);
                                if (maxAmountController.text != newMax) maxAmountController.text = newMax;
                                if (amountRange.start > clamped) {
                                  final newMin = clamped.toStringAsFixed(0);
                                  if (minAmountController.text != newMin) minAmountController.text = newMin;
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
                    min: minAvail,
                    max: maxAvail,
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
                    amountRange = RangeValues(minAvail, maxAvail);
                    minAmountController.text = minAvail.toStringAsFixed(0);
                    maxAmountController.text = maxAvail.toStringAsFixed(0);
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
          ),
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
        appBar: AppBar(
          title: const Text('Transactions'),
          actions: [
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
                          child: ListView(
                            controller: _txScroll,
                            children: _buildGroupedTransactionWidgets(context),
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
