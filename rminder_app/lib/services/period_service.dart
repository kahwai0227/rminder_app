import 'package:flutter/material.dart';
import '../db/rminder_database.dart';
import '../models/models.dart' as models;
import '../utils/mutation_error_message.dart';
import 'navigation_service.dart';

enum PeriodCloseAction { none, carryIncome, payDebt, contributeFund }

/// Service to close the active budgeting period from any page without relying
/// on the internal state of `ReportingPage`.
class PeriodService {
  PeriodService._();

  static String _monthName(int m) {
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return names[m - 1];
  }

  static DateTime _truncate(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Close the currently active period. Shows dialogs/snackbars for user choices.
  static Future<void> closeActivePeriod(BuildContext context) async {
    try {
      // Prefer root navigator context to avoid issues when invoked from overlays/menus or other tabs.
      final ctx = NavigationService.instance.navigatorKey.currentContext ?? context;
      final activeStart = await RMinderDatabase.instance.getActivePeriodStart();
      final periodStart = activeStart ?? _truncate(DateTime.now());
      final alreadyClosed = await RMinderDatabase.instance.isMonthClosed(periodStart);
      if (alreadyClosed) {
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(content: Text('${_monthName(periodStart.month)} ${periodStart.year} is already closed.')),
          );
        }
        return;
      }

      // Prevent closing on the very first day of a new active period.
      // Our close logic sets closedAt to "yesterday"; if periodStart is today,
      // closedAt would precede periodStart, yielding an invalid range.
      final todayOnly = _truncate(DateTime.now());
      if (todayOnly.year == periodStart.year && todayOnly.month == periodStart.month && todayOnly.day == periodStart.day) {
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(content: Text('You can\'t close a period on its start day. Try again tomorrow.')),
          );
        }
        return;
      }

      // Load current data required for closing logic.
      final categories = await RMinderDatabase.instance.getCategories();
      final transactions = await RMinderDatabase.instance.getTransactions();
      final liabilities = await RMinderDatabase.instance.getAllLiabilities();
      final sinkingFunds = await RMinderDatabase.instance.getSinkingFunds();
      final incomeSources = await RMinderDatabase.instance.getIncomeSources(); // for snapshot

      // Active (non-archived) liabilities only for minimum payment requirement.
      final activeLiabilities = liabilities.where((l) => !l.isArchived).toList();

      double paidThisMonthFor(models.Liability liab) {
        double total = 0;
        final start = periodStart;
        final today = DateTime.now();
        final endExclusive = _truncate(today).add(const Duration(days: 1));
        for (final t in transactions) {
          if (t.categoryId == liab.budgetCategoryId && !t.date.isBefore(start) && t.date.isBefore(endExclusive)) {
            total += t.amount;
          }
        }
        return total;
      }

      // Check minimum payments.
      final List<Map<String, dynamic>> minShortfalls = [];
      for (final liab in activeLiabilities) {
        final paid = paidThisMonthFor(liab);
        final remaining = liab.planned - paid;
        if (remaining > 0.01) {
          minShortfalls.add({'name': liab.name, 'remaining': remaining});
        }
      }
      if (minShortfalls.isNotEmpty) {
        if (!ctx.mounted) return;
        await showDialog(
          context: ctx,
          builder: (_) => AlertDialog(
            title: const Text('Minimum payments required'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Before closing ${_monthName(periodStart.month)} ${periodStart.year}, please complete the minimum payments:'),
                const SizedBox(height: 8),
                ...minShortfalls.map((m) => Text('${m['name']}: ₹${(m['remaining'] as double).toStringAsFixed(2)} remaining')),
              ],
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
          ),
        );
        return;
      }

      // Compute unspent leftover across non-debt / non-fund categories.
      final debtCategoryIds = liabilities.map((l) => l.budgetCategoryId).toSet();
      final fundCategoryIds = sinkingFunds.where((f) => f.budgetCategoryId != null).map((f) => f.budgetCategoryId!).toSet();
      final excluded = {...debtCategoryIds, ...fundCategoryIds};
      final Map<int, double> spentByCategory = {};
      final today = DateTime.now();
      final periodEndExclusive = _truncate(today).add(const Duration(days: 1));
      for (final txn in transactions) {
        if (!txn.date.isBefore(periodStart) && txn.date.isBefore(periodEndExclusive)) {
          if (excluded.contains(txn.categoryId)) continue;
          spentByCategory.update(txn.categoryId, (v) => v + txn.amount, ifAbsent: () => txn.amount);
        }
      }
      final regularCats = categories.where((c) => c.id != null && !excluded.contains(c.id)).toList();
      final Map<models.BudgetCategory, double> leftoverByCat = {
        for (final c in regularCats)
          c: (c.budgetLimit - (spentByCategory[c.id] ?? 0)).clamp(0, double.infinity)
      };
      final totalLeftover = leftoverByCat.values.fold<double>(0, (s, v) => s + v);

      // Default action: if there's leftover, suggest carrying as income; else just close.
      PeriodCloseAction mode = totalLeftover > 0 ? PeriodCloseAction.carryIncome : PeriodCloseAction.none;
      models.Liability? selectedLiab = activeLiabilities.isNotEmpty ? activeLiabilities.first : null;
      final fundChoices = sinkingFunds.where((f) => f.budgetCategoryId != null).toList();
      models.SinkingFund? selectedFund = fundChoices.isNotEmpty ? fundChoices.first : null;

      if (!ctx.mounted) return;
      final confirmed = await showDialog<bool>(
        context: ctx,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('Close Month'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640, maxHeight: 600),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_monthName(periodStart.month)} ${periodStart.year}'),
                    const SizedBox(height: 8),
                    Text('Unspent: ₹${totalLeftover.toStringAsFixed(2)}'),
                    const SizedBox(height: 12),
                    RadioGroup<PeriodCloseAction>(
                      groupValue: mode,
                      onChanged: (v) {
                        if (v != null) {
                          setLocal(() => mode = v);
                        }
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const RadioListTile<PeriodCloseAction>(
                            value: PeriodCloseAction.none,
                            title: Text('Close only'),
                          ),
                          RadioListTile<PeriodCloseAction>(
                            value: PeriodCloseAction.carryIncome,
                            enabled: totalLeftover > 0,
                            title: const Text('Carry as income'),
                          ),
                          RadioListTile<PeriodCloseAction>(
                            value: PeriodCloseAction.payDebt,
                            enabled: activeLiabilities.isNotEmpty && totalLeftover > 0,
                            title: const Text('Pay debt'),
                            subtitle: activeLiabilities.isEmpty
                                ? null
                                : DropdownButton<models.Liability>(
                                    value: selectedLiab,
                                    isExpanded: true,
                                    items: [
                                      for (final l in activeLiabilities)
                                        DropdownMenuItem(value: l, child: Text(l.name)),
                                    ],
                                    onChanged: (v) => setLocal(() => selectedLiab = v),
                                  ),
                          ),
                          RadioListTile<PeriodCloseAction>(
                            value: PeriodCloseAction.contributeFund,
                            enabled: fundChoices.isNotEmpty && totalLeftover > 0,
                            title: const Text('Contribute to fund'),
                            subtitle: fundChoices.isEmpty
                                ? null
                                : DropdownButton<models.SinkingFund>(
                                    value: selectedFund,
                                    isExpanded: true,
                                    items: [
                                      for (final f in fundChoices)
                                        DropdownMenuItem(value: f, child: Text(f.name)),
                                    ],
                                    onChanged: (v) => setLocal(() => selectedFund = v),
                                  ),
                          ),
                        ],
                      ),
                    ),
              ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
            ],
          ),
        ),
      );
      if (confirmed != true) return;

      // Determine closed period end using the actual close timestamp (with time)
      final closeAt = DateTime.now();
      final endExclusive = closeAt.add(const Duration(microseconds: 1));

      // Snapshot spending per category (positive expenses only) for the closed period
      final Map<int, double> spentAllCats = {};
      for (final t in transactions) {
        if (!t.date.isBefore(periodStart) && t.date.isBefore(endExclusive) && t.amount > 0) {
          spentAllCats.update(t.categoryId, (v) => v + t.amount, ifAbsent: () => t.amount);
        }
      }
      // Snapshot liabilities: planned vs paid (payments are positive amounts against liability category)
      final Map<int, double> paidByLiabilityId = {};
      for (final l in liabilities) {
        if (l.id == null) continue;
        double paid = 0;
        for (final t in transactions) {
          if (t.categoryId == l.budgetCategoryId && !t.date.isBefore(periodStart) && t.date.isBefore(endExclusive) && t.amount > 0) {
            paid += t.amount;
          }
        }
        paidByLiabilityId[l.id!] = paid;
      }
      // Snapshot funds: planned monthly vs contributed (contributions are positive amounts against fund category)
      final Map<int, double> contribByFundId = {};
      for (final f in sinkingFunds) {
        if (f.id == null || f.budgetCategoryId == null) continue;
        double contributed = 0;
        for (final t in transactions) {
          if (t.categoryId == f.budgetCategoryId && !t.date.isBefore(periodStart) && t.date.isBefore(endExclusive) && t.amount > 0) {
            contributed += t.amount;
          }
        }
        contribByFundId[f.id!] = contributed;
      }
      final nextStart = closeAt; // new period begins at the exact close timestamp

      String action = 'closeOnly';
      int? transferCategoryId;
      String? transferNote;

      if (mode == PeriodCloseAction.carryIncome) {
        action = 'carryIncome';
      } else if (mode == PeriodCloseAction.payDebt) {
        final liab = selectedLiab;
        if (liab == null) {
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Please add/select a liability.')));
          }
          return;
        }
        action = 'payDebt';
        transferCategoryId = liab.budgetCategoryId;
        transferNote = 'Period close payment (${_monthName(periodStart.month)} ${periodStart.year}) - ${liab.name}';
      } else if (mode == PeriodCloseAction.contributeFund) {
        final fund = selectedFund;
        if (fund == null || fund.budgetCategoryId == null) {
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Please add/select a valid sinking fund with a category.')));
          }
          return;
        }
        action = 'contributeFund';
        transferCategoryId = fund.budgetCategoryId!;
        transferNote = 'Period close contribution (${_monthName(periodStart.month)} ${periodStart.year}) - ${fund.name}';
      }

      await RMinderDatabase.instance.closePeriodAtomic(
        periodStart: periodStart,
        closeAt: closeAt,
        nextStart: nextStart,
        action: action,
        totalLeftover: totalLeftover,
        transferCategoryId: transferCategoryId,
        transferNote: transferNote,
        categories: categories,
        incomeSources: incomeSources,
        liabilities: liabilities,
        sinkingFunds: sinkingFunds,
        spentByCategory: spentAllCats,
        paidByLiabilityId: paidByLiabilityId,
        contributedByFundId: contribByFundId,
      );

      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Closed ${_monthName(periodStart.month)} ${periodStart.year}')),
        );
      }
    } catch (e, st) {
      // Log & surface failure.
      debugPrint('Failed to close period: $e\n$st');
      final ctx = NavigationService.instance.navigatorKey.currentContext ?? context;
      final userMessage = mutationFailureMessage(e, fallback: 'Failed to close period. Please try again.');
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(userMessage)));
      }
    }
  }
}