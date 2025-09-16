import 'package:flutter/material.dart';
import '../db/rminder_database.dart';
import '../models/models.dart' as models;
import '../utils/logger.dart';
import '../utils/ui_intents.dart';
import '../utils/currency_input_formatter.dart';

class LiabilitiesPage extends StatefulWidget {
  const LiabilitiesPage({Key? key}) : super(key: key);
  @override
  State<LiabilitiesPage> createState() => _LiabilitiesPageState();
}

class _LiabilitiesPageState extends State<LiabilitiesPage> {
  List<models.Liability> liabilitiesList = [];
  Map<int, double> _paidThisMonth = {};
  bool _dialogOpenGuard = false;
  final ScrollController _liabScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadLiabilities();
    UiIntents.editLiabilityId.addListener(_maybeOpenEditFromIntent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (UiIntents.editLiabilityId.value != null) {
        _maybeOpenEditFromIntent();
      }
    });
  }

  @override
  void dispose() {
    UiIntents.editLiabilityId.removeListener(_maybeOpenEditFromIntent);
    _liabScroll.dispose();
    super.dispose();
  }

  void _maybeOpenEditFromIntent() {
    final id = UiIntents.editLiabilityId.value;
    if (id == null) return;
    final idx = liabilitiesList.indexWhere((l) => l.id == id);
    if (idx == -1) {
      return;
    }
    if (mounted && !_dialogOpenGuard) {
      UiIntents.editLiabilityId.value = null;
      _dialogOpenGuard = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        _addOrEditLiability(index: idx);
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) _dialogOpenGuard = false;
      });
    }
  }

  Future<void> _loadLiabilities() async {
    try {
      final list = await RMinderDatabase.instance.getLiabilities();
      setState(() => liabilitiesList = list);
      await _loadPaidThisMonth();
      _maybeOpenEditFromIntent();
    } catch (e, st) {
      logError(e, st);
    }
  }

  Future<void> _loadPaidThisMonth() async {
    try {
      final now = DateTime.now();
      final Map<int, double> map = {};
      for (final liab in liabilitiesList) {
        if (liab.id == null) continue;
        final paid = await RMinderDatabase.instance.sumPaidForLiabilityInMonth(liab.id!, now);
        map[liab.id!] = paid;
      }
      if (mounted) setState(() => _paidThisMonth = map);
    } catch (e, st) {
      logError(e, st);
    }
  }

  void _addOrEditLiability({int? index}) {
    final nameController = TextEditingController(text: index != null ? liabilitiesList[index].name : '');
  final balanceController = TextEditingController(text: index != null ? liabilitiesList[index].balance.toStringAsFixed(2) : '0.00');
  final plannedController = TextEditingController(text: index != null ? liabilitiesList[index].planned.toStringAsFixed(2) : '0.00');
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
                keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
                inputFormatters: [CurrencyInputFormatter()],
              ),
              TextField(
                controller: plannedController,
                decoration: const InputDecoration(labelText: 'Minimum Payment'),
                keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
                inputFormatters: [CurrencyInputFormatter()],
              ),
            ]);
          }),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              final balance = double.tryParse(balanceController.text.trim().replaceAll(',', '')) ?? 0;
              final planned = double.tryParse(plannedController.text.trim().replaceAll(',', '')) ?? 0;
              if (name.isEmpty || balance < 0 || planned < 0) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter valid values.')));
                return;
              }
              () async {
                if (index == null) {
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
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Liability'),
        content: Text(
          'Deleting "${liab.name}" will also delete its linked budget category and all its transactions. This action cannot be undone. Continue?',
        ),
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
        await RMinderDatabase.instance.deleteLiabilityCascade(liab.id!);
        await _loadLiabilities();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Liability "${liab.name}" and related data deleted.')),
          );
        }
      }
    });
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
                : Scrollbar(
                    controller: _liabScroll,
                    thumbVisibility: true,
                    child: ListView.builder(
                      controller: _liabScroll,
                      itemCount: liabilitiesList.length,
                      itemBuilder: (context, index) {
                        final liab = liabilitiesList[index];
                        return Card(
                          child: ListTile(
                            title: Text(liab.name),
                            subtitle: Text('Balance: ₹${liab.balance.toStringAsFixed(2)} | Min: ₹${liab.planned.toStringAsFixed(2)}'),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                tooltip: 'Make payment',
                                icon: const Icon(Icons.payment),
                                onPressed: () async {
                                  final paid = _paidThisMonth[liab.id!] ?? 0.0;
                                  final remaining = (liab.planned - paid).clamp(0, double.infinity);
                                  if (remaining > 0) {
                                    final controller = TextEditingController(text: remaining.toStringAsFixed(2));
                                    showDialog(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: Text('Pay ${liab.name}') ,
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Remaining planned this month: ₹${remaining.toStringAsFixed(2)}'),
                                            const SizedBox(height: 8),
                                            TextField(
                                              controller: controller,
                                              decoration: const InputDecoration(labelText: 'Amount to pay'),
                                              keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
                                              inputFormatters: [CurrencyInputFormatter()],
                                            ),
                                          ],
                                        ),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                                          ElevatedButton(
                                            onPressed: () async {
                                              final amt = double.tryParse(controller.text.trim().replaceAll(',', '')) ?? 0;
                                              if (amt <= 0) {
                                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount.')));
                                                return;
                                              }
                                              final txId = await RMinderDatabase.instance.payLiability(liab, amt);
                                              final afterPaid = paid + amt;
                                              final extra = afterPaid > liab.planned ? (afterPaid - liab.planned) : 0.0;
                                              if (extra > 0) {
                                                await RMinderDatabase.instance.insertExtraPayment(
                                                  liabilityId: liab.id!,
                                                  amount: extra,
                                                  date: DateTime.now(),
                                                  transactionId: txId,
                                                );
                                              }
                                              await _loadLiabilities();
                                              await _loadPaidThisMonth();
                                              if (mounted) Navigator.pop(context);
                                            },
                                            child: const Text('Confirm'),
                                          ),
                                        ],
                                      ),
                                    );
                                  } else {
                                    final controller = TextEditingController(text: '0.00');
                                    showDialog(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: Text('Extra payment - ${liab.name}'),
                                        content: TextField(
                                          controller: controller,
                                          decoration: const InputDecoration(labelText: 'Extra amount'),
                                          keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
                                          inputFormatters: [CurrencyInputFormatter()],
                                        ),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                                          ElevatedButton(
                                            onPressed: () async {
                                              final extra = double.tryParse(controller.text.trim().replaceAll(',', '')) ?? 0;
                                              if (extra <= 0) {
                                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount.')));
                                                return;
                                              }
                                              final txId = await RMinderDatabase.instance.payLiability(liab, extra);
                                              await RMinderDatabase.instance.insertExtraPayment(
                                                liabilityId: liab.id!,
                                                amount: extra,
                                                date: DateTime.now(),
                                                transactionId: txId,
                                              );
                                              await _loadLiabilities();
                                              await _loadPaidThisMonth();
                                              if (mounted) Navigator.pop(context);
                                            },
                                            child: const Text('Confirm'),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
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
          ),
        ]),
      ),
    );
  }
}
