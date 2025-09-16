import 'package:flutter/material.dart';
import '../db/rminder_database.dart';
import '../models/models.dart' as models;
import '../utils/currency_input_formatter.dart';

class SavingsScreen extends StatefulWidget {
  const SavingsScreen({Key? key}) : super(key: key);

  @override
  State<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends State<SavingsScreen> {
  final ScrollController _scroll = ScrollController();
  List<models.SinkingFund> _funds = [];
  Map<int, double> _contribThisMonth = {};

  @override
  void initState() {
    super.initState();
    _loadFunds();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadFunds() async {
    final list = await RMinderDatabase.instance.getSinkingFunds();
    if (!mounted) return;
    setState(() => _funds = list);
    await _loadContribThisMonth();
  }

  Future<void> _loadContribThisMonth() async {
    final now = DateTime.now();
    final map = <int, double>{};
    for (final f in _funds) {
      if (f.id == null) continue;
      final sum = await RMinderDatabase.instance.sumContributedForFundInMonth(f.id!, now);
      map[f.id!] = sum;
    }
    if (!mounted) return;
    setState(() => _contribThisMonth = map);
  }

  void _addOrEditFund({int? index}) {
    final isEdit = index != null;
  final fund = isEdit ? _funds[index] : null;
    final nameCtrl = TextEditingController(text: fund?.name ?? '');
    final targetCtrl = TextEditingController(text: (fund?.targetAmount ?? 0).toStringAsFixed(2));
    final balanceCtrl = TextEditingController(text: (fund?.balance ?? 0).toStringAsFixed(2));
    final monthlyCtrl = TextEditingController(text: (fund?.monthlyContribution ?? 0).toStringAsFixed(2));

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
              TextField(
                controller: targetCtrl,
                decoration: const InputDecoration(labelText: 'Target Amount'),
                keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
                inputFormatters: [CurrencyInputFormatter()],
              ),
              TextField(
                controller: balanceCtrl,
                decoration: const InputDecoration(labelText: 'Current Balance'),
                keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
                inputFormatters: [CurrencyInputFormatter()],
              ),
              TextField(
                controller: monthlyCtrl,
                decoration: const InputDecoration(labelText: 'Monthly Contribution'),
                keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
                inputFormatters: [CurrencyInputFormatter()],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final target = double.tryParse(targetCtrl.text.trim().replaceAll(',', '')) ?? 0;
              final bal = double.tryParse(balanceCtrl.text.trim().replaceAll(',', '')) ?? 0;
              final monthly = double.tryParse(monthlyCtrl.text.trim().replaceAll(',', '')) ?? 0;
              if (name.isEmpty || target <= 0 || bal < 0 || monthly < 0) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter valid values.')));
                return;
              }
              if (!isEdit) {
                final catId = await RMinderDatabase.instance.ensureSavingsCategory(name, monthly: monthly);
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
                final existing = _funds[index];
                await RMinderDatabase.instance.updateSinkingFund(
                  models.SinkingFund(
                    id: existing.id,
                    name: name,
                    targetAmount: target,
                    balance: bal > target ? target : bal,
                    monthlyContribution: monthly,
                    budgetCategoryId: existing.budgetCategoryId,
                  ),
                );
              }
              await _loadFunds();
              if (mounted) Navigator.pop(context);
            },
            child: Text(isEdit ? 'Save' : 'Add'),
          ),
        ],
      ),
    );
  }

  void _deleteFund(int index) {
    final fund = _funds[index];
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Fund'),
        content: Text('Delete "${fund.name}" and its linked category and transactions? This cannot be undone.'),
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
        await RMinderDatabase.instance.deleteSinkingFundCascade(fund.id!);
        await _loadFunds();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fund "${fund.name}" deleted.')));
      }
    });
  }

  void _contribute(int index) async {
    final fund = _funds[index];
    final contributed = _contribThisMonth[fund.id!] ?? 0.0;
    final remainingPlan = (fund.monthlyContribution - contributed).clamp(0, double.infinity);
    final ctrl = TextEditingController(text: remainingPlan.toStringAsFixed(2));
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Contribute to ${fund.name}') ,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Remaining planned this month: \u20b9${remainingPlan.toStringAsFixed(2)}'),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(labelText: 'Amount to contribute'),
              keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
              inputFormatters: [CurrencyInputFormatter()],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final amt = double.tryParse(ctrl.text.trim().replaceAll(',', '')) ?? 0;
              if (amt <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount.')));
                return;
              }
              await RMinderDatabase.instance.contributeToFund(fund, amt);
              await _loadFunds();
              await _loadContribThisMonth();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Savings')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Fund'),
              onPressed: () => _addOrEditFund(),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _funds.isEmpty
                  ? const Center(child: Text('No funds yet.'))
                  : Scrollbar(
                      controller: _scroll,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _scroll,
                        itemCount: _funds.length,
                        itemBuilder: (context, index) {
                          final f = _funds[index];
                          final progress = f.targetAmount <= 0 ? 0.0 : (f.balance / f.targetAmount).clamp(0.0, 1.0);
                          final contributed = _contribThisMonth[f.id ?? -1] ?? 0.0;
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          f.name,
                                          style: Theme.of(context).textTheme.titleMedium,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Contribute',
                                        icon: const Icon(Icons.add_card),
                                        onPressed: () => _contribute(index),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit, color: Colors.blue),
                                        tooltip: 'Edit',
                                        onPressed: () => _addOrEditFund(index: index),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.red),
                                        tooltip: 'Delete',
                                        onPressed: () => _deleteFund(index),
                                      ),
                                    ],
                                  ),
                                  Text('Balance: \u20b9${f.balance.toStringAsFixed(2)} / Target: \u20b9${f.targetAmount.toStringAsFixed(2)}'),
                                  const SizedBox(height: 6),
                                  LinearProgressIndicator(value: progress),
                                  const SizedBox(height: 6),
                                  Text('Monthly: \u20b9${f.monthlyContribution.toStringAsFixed(2)} | Contributed: \u20b9${contributed.toStringAsFixed(2)}'),
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
