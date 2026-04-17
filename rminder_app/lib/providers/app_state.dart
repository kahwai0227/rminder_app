import 'package:flutter/foundation.dart';
import '../db/rminder_database.dart';
import '../models/models.dart' as models;
import '../utils/logger.dart';

/// Global app state managed via Provider.
class AppState extends ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<models.BudgetCategory> categories = [];
  List<models.Transaction> transactions = [];
  List<models.Liability> liabilities = [];
  List<models.SinkingFund> sinkingFunds = [];
  List<models.IncomeSource> incomeSources = [];

  final Map<int, double> _paidLiabilitiesThisMonth = {};
  Map<int, double> get paidLiabilitiesThisMonth => _paidLiabilitiesThisMonth;

  final Map<int, double> _contributedToFundsThisMonth = {};
  Map<int, double> get contributedToFundsThisMonth => _contributedToFundsThisMonth;

  DateTime? activePeriodStart;

  AppState() {
    loadAllData();
  }

  Future<void> loadAllData() async {
    _isLoading = true;
    notifyListeners();

    try {
      // First load active period
      await _loadActivePeriod();
      
      await Future.wait([
        _loadCategories(),
        _loadTransactions(),
        _loadLiabilities(),
        _loadSinkingFunds(),
        _loadIncomeSources(),
      ]);

      _recomputeFundContributionsForActivePeriod();
    } catch (e, st) {
      logError(e, st);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadCategories() async {
    categories = await RMinderDatabase.instance.getCategories();
  }

  Future<void> _loadTransactions() async {
    transactions = await RMinderDatabase.instance.getTransactions();
  }

  Future<void> _loadLiabilities() async {
    liabilities = await RMinderDatabase.instance.getAllLiabilities();
    _paidLiabilitiesThisMonth.clear();
    for (var l in liabilities) {
      if (l.id != null) {
        _paidLiabilitiesThisMonth[l.id!] = await RMinderDatabase.instance.sumPaidForLiabilityInMonth(l.id!, activePeriodStart!);
      }
    }
  }

  Future<void> _loadSinkingFunds() async {
    sinkingFunds = await RMinderDatabase.instance.getSinkingFunds();
  }

  Future<void> _loadIncomeSources() async {
    incomeSources = await RMinderDatabase.instance.getIncomeSources();
  }

  Future<void> _loadActivePeriod() async {
    activePeriodStart = await RMinderDatabase.instance.getActivePeriodStart();  
  }

  DateTime _activePeriodEndExclusive() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  }

  void _recomputeFundContributionsForActivePeriod() {
    _contributedToFundsThisMonth.clear();
    if (sinkingFunds.isEmpty) return;

    final now = DateTime.now();
    final start = activePeriodStart ?? DateTime(now.year, now.month, 1);
    final endExclusive = _activePeriodEndExclusive();

    final contributionByCategory = <int, double>{};
    for (final t in transactions) {
      // Match reports logic: count only positive savings transactions in active period.
      if (t.amount <= 0) continue;
      if (t.date.isBefore(start) || !t.date.isBefore(endExclusive)) continue;
      contributionByCategory[t.categoryId] =
          (contributionByCategory[t.categoryId] ?? 0.0) + t.amount;
    }

    for (final fund in sinkingFunds) {
      final fundId = fund.id;
      final categoryId = fund.budgetCategoryId;
      if (fundId == null || categoryId == null) continue;
      _contributedToFundsThisMonth[fundId] =
          contributionByCategory[categoryId] ?? 0.0;
    }
  }

  // Example of adding a generic refresh method you can call after performing an action
  Future<void> refresh() async {
    await loadAllData();
  }
}
