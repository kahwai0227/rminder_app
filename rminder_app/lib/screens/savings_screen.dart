import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../db/rminder_database.dart';
import '../models/models.dart' as models;
import '../utils/currency_input_formatter.dart';
import '../utils/mutation_guard.dart';
import '../widgets/compact_cards.dart';
import '../main.dart' show buildGlobalAppBarActions;
import '../main.dart' as app;
import '../utils/ui_intents.dart';

class SavingsScreen extends StatefulWidget {
  const SavingsScreen({super.key});

  @override
  State<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends State<SavingsScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadFunds() async {
    if (!mounted) return;
    await Provider.of<AppState>(context, listen: false).loadAllData();
  }

  void _addOrEditFund(List<models.SinkingFund> funds, {int? index}) {
    final isEdit = index != null;
    final fund = isEdit ? funds[index] : null;
    final nameCtrl = TextEditingController(text: fund?.name ?? '');
    final targetCtrl = TextEditingController(
      text: (fund?.targetAmount ?? 0).toStringAsFixed(2),
    );
    final balanceCtrl = TextEditingController(
      text: (fund?.balance ?? 0).toStringAsFixed(2),
    );
    final monthlyCtrl = TextEditingController(
      text: (fund?.monthlyContribution ?? 0).toStringAsFixed(2),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEdit ? 'Edit Fund' : 'Add Fund'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Fund Name'),
                maxLength: 20,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: targetCtrl,
                decoration: const InputDecoration(labelText: 'Target Amount'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: false,
                  signed: false,
                ),
                inputFormatters: [CurrencyInputFormatter()],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: balanceCtrl,
                decoration: const InputDecoration(labelText: 'Current Balance'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: false,
                  signed: false,
                ),
                inputFormatters: [CurrencyInputFormatter()],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: monthlyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Monthly Contribution',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: false,
                  signed: false,
                ),
                inputFormatters: [CurrencyInputFormatter()],
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
              final name = nameCtrl.text.trim();
              final target =
                  double.tryParse(targetCtrl.text.trim().replaceAll(',', '')) ??
                  0;
              final bal =
                  double.tryParse(
                    balanceCtrl.text.trim().replaceAll(',', ''),
                  ) ??
                  0;
              final monthly =
                  double.tryParse(
                    monthlyCtrl.text.trim().replaceAll(',', ''),
                  ) ??
                  0;
              if (name.isEmpty || target <= 0 || bal < 0 || monthly < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter valid values.')),
                );
                return;
              }
              await runGuardedMutation(
                context: context,
                failureMessage: isEdit
                    ? 'Failed to update fund.'
                    : 'Failed to add fund.',
                action: () async {
                  if (!isEdit) {
                    final catId = await RMinderDatabase.instance
                        .ensureSavingsCategory(name, monthly: monthly);
                    await RMinderDatabase.instance.insertSinkingFund(
                      models.SinkingFund(
                        name: name,
                        targetAmount: target,
                        balance: bal > target ? target : bal,
                        monthlyContribution: monthly,
                        budgetCategoryId: catId,
                      ),
                    );
                  } else {
                    final existing = funds[index];
                    // If fund has no linked category yet (legacy records), ensure one exists now
                    int? catId = existing.budgetCategoryId;
                    catId ??= await RMinderDatabase.instance
                        .ensureSavingsCategory(name, monthly: monthly);
                    await RMinderDatabase.instance.updateSinkingFund(
                      models.SinkingFund(
                        id: existing.id,
                        name: name,
                        targetAmount: target,
                        balance: bal > target ? target : bal,
                        monthlyContribution: monthly,
                        budgetCategoryId: catId,
                      ),
                    );
                  }
                  await _loadFunds();
                  await app.syncWidgetCategories();
                  UiIntents.categoriesChangedEvent.value++;
                },
                onSuccess: () async {
                  if (context.mounted) Navigator.pop(context);
                },
              );
            },
            child: Text(isEdit ? 'Save' : 'Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFund(List<models.SinkingFund> funds, int index) async {
    final fund = funds[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Fund'),
        content: Text(
          'Delete "${fund.name}" and its linked category and transactions? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await runGuardedMutation(
      context: context,
      failureMessage: 'Failed to delete fund.',
      action: () async {
        await RMinderDatabase.instance.deleteSinkingFundCascade(fund.id!);
        await _loadFunds();
      },
      onSuccess: () async {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fund "${fund.name}" deleted.')));
      },
    );
  }

  Future<void> _contribute(
    List<models.SinkingFund> funds,
    Map<int, double> contribThisMonth,
    int index,
  ) async {
    final fund = funds[index];
    final contributed = contribThisMonth[fund.id!] ?? 0.0;
    final appState = Provider.of<AppState>(context, listen: false);
    final remainingPlan = (fund.monthlyContribution - contributed).clamp(
      0,
      double.infinity,
    );
    final ctrl = TextEditingController(text: remainingPlan.toStringAsFixed(2));
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Contribute to ${fund.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Remaining planned this month: \u20b9${remainingPlan.toStringAsFixed(2)}',
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Amount to contribute',
              ),
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
              final amt =
                  double.tryParse(ctrl.text.trim().replaceAll(',', '')) ?? 0;
              if (amt <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter a valid amount.')),
                );
                return;
              }
              await runGuardedMutation(
                context: context,
                failureMessage: 'Failed to contribute to fund.',
                action: () async {
                  await RMinderDatabase.instance.contributeToFund(fund, amt);
                  await appState.loadAllData();
                },
                onSuccess: () async {
                  if (context.mounted) Navigator.pop(context);
                },
              );
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _withdraw(List<models.SinkingFund> funds, int index) async {
    final fund = funds[index];
    final appState = Provider.of<AppState>(context, listen: false);
    final ctrl = TextEditingController(text: '0.00');
    final noteCtrl = TextEditingController(text: '');
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Spend from ${fund.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Available: \u20b9${fund.balance.toStringAsFixed(2)}'),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(labelText: 'Amount to spend'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: false,
                signed: false,
              ),
              inputFormatters: [CurrencyInputFormatter()],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
              maxLength: 40,
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
              final amt =
                  double.tryParse(ctrl.text.trim().replaceAll(',', '')) ?? 0;
              if (amt <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter a valid amount.')),
                );
                return;
              }
              if (amt > fund.balance) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Amount exceeds available balance.'),
                  ),
                );
                return;
              }
              await runGuardedMutation(
                context: context,
                failureMessage: 'Failed to spend from fund.',
                action: () async {
                  await RMinderDatabase.instance.spendFromFund(
                    fund,
                    amt,
                    note: noteCtrl.text.trim().isEmpty
                        ? null
                        : noteCtrl.text.trim(),
                  );
                  await appState.loadAllData();
                },
                onSuccess: () async {
                  if (context.mounted) Navigator.pop(context);
                },
              );
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final funds = appState.sinkingFunds;
    final contribThisMonth = appState.contributedToFundsThisMonth;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Savings'),
        actions: buildGlobalAppBarActions(context),
      ),
      body: Padding(
        padding: kCompactPagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Savings Funds', style: compactSectionTitleStyle(context)),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add Fund'),
                  onPressed: () => _addOrEditFund(funds),
                ),
              ],
            ),
            const SizedBox(height: kCompactSectionGap),
            Expanded(
              child: funds.isEmpty
                  ? const Center(child: Text('No funds yet.'))
                  : Scrollbar(
                      controller: _scroll,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _scroll,
                        itemCount: funds.length,
                        itemBuilder: (context, index) {
                          final f = funds[index];
                          final progress = f.targetAmount <= 0
                              ? 0.0
                              : (f.balance / f.targetAmount).clamp(0.0, 1.0);
                          final contributed =
                              contribThisMonth[f.id ?? -1] ?? 0.0;
                          return CompactItemCard(
                            margin: const EdgeInsets.only(bottom: 2),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 2,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          f.name,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Contribute',
                                        icon: Icon(
                                          Icons.add_card,
                                          color: theme.colorScheme.primary,
                                        ),
                                        onPressed: () => _contribute(
                                          funds,
                                          contribThisMonth,
                                          index,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Spend',
                                        icon: Icon(
                                          Icons.remove_circle_outline,
                                          color: theme.colorScheme.tertiary,
                                        ),
                                        onPressed: () =>
                                            _withdraw(funds, index),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          Icons.edit,
                                          color: theme.colorScheme.primary,
                                        ),
                                        tooltip: 'Edit',
                                        onPressed: () =>
                                            _addOrEditFund(funds, index: index),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          Icons.delete,
                                          color: theme.colorScheme.error,
                                        ),
                                        tooltip: 'Delete',
                                        onPressed: () =>
                                            _deleteFund(funds, index),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    'Balance: ₹${f.balance.toStringAsFixed(2)} / Target: ₹${f.targetAmount.toStringAsFixed(2)}',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  LinearProgressIndicator(value: progress),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Monthly: ₹${f.monthlyContribution.toStringAsFixed(2)} | Contributed: ₹${contributed.toStringAsFixed(2)}',
                                    style: compactMutedStyle(context),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
