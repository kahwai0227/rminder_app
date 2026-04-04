import '../models/models.dart' as models;

class ActiveOverviewSelection {
  final List<models.BudgetCategory> categories;
  final Map<int, double> spentByCategory;

  const ActiveOverviewSelection({
    required this.categories,
    required this.spentByCategory,
  });
}

ActiveOverviewSelection selectActiveOverviewSelection({
  required Iterable<models.BudgetCategory> categories,
  required Iterable<models.Transaction> transactions,
  required Iterable<models.Liability> liabilities,
  required Iterable<models.SinkingFund> sinkingFunds,
  required DateTime? periodStart,
  required DateTime periodEndExclusive,
}) {
  final debtCategoryIds = liabilities
      .where((l) => !l.isArchived)
      .map((l) => l.budgetCategoryId)
      .toSet();
  final fundCategoryIds = sinkingFunds
      .where((f) => f.budgetCategoryId != null)
      .map((f) => f.budgetCategoryId!)
      .toSet();

  final selectedCategories = categories
      .where((c) => c.id != null)
      .where((c) => !debtCategoryIds.contains(c.id))
      .where((c) => !fundCategoryIds.contains(c.id))
      .toList();

  final selectedCategoryIds = selectedCategories.map((c) => c.id!).toSet();
  final spentByCategory = <int, double>{};

  for (final tx in transactions) {
    if (tx.amount <= 0 || !selectedCategoryIds.contains(tx.categoryId)) {
      continue;
    }

    if (periodStart != null &&
        (tx.date.isBefore(periodStart) || !tx.date.isBefore(periodEndExclusive))) {
      continue;
    }

    spentByCategory.update(tx.categoryId, (v) => v + tx.amount, ifAbsent: () => tx.amount);
  }

  return ActiveOverviewSelection(
    categories: selectedCategories,
    spentByCategory: spentByCategory,
  );
}
