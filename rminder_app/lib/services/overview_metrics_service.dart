class OverviewMetricItem {
  final double planned;
  final double spent;

  const OverviewMetricItem({
    required this.planned,
    required this.spent,
  });
}

class OverviewMetrics {
  final double planned;
  final double spent;
  final double remaining;
  final double progress;
  final bool isOverBudget;

  const OverviewMetrics({
    required this.planned,
    required this.spent,
    required this.remaining,
    required this.progress,
    required this.isOverBudget,
  });
}

class ZeroBasedBudgetSummary {
  final double income;
  final double baseCategoryBudget;
  final double plannedDebt;
  final double plannedFunds;
  final double extraDebt;
  final double extraFunds;
  final double plannedTotal;
  final double unallocated;

  const ZeroBasedBudgetSummary({
    required this.income,
    required this.baseCategoryBudget,
    required this.plannedDebt,
    required this.plannedFunds,
    required this.extraDebt,
    required this.extraFunds,
    required this.plannedTotal,
    required this.unallocated,
  });

  bool get isBalanced => unallocated.abs() <= 0.01;
  bool get isUnderAllocated => unallocated > 0.01;
  bool get isOverAllocated => unallocated < -0.01;
}

ZeroBasedBudgetSummary calculateZeroBasedBudgetSummary({
  required double income,
  required double baseCategoryBudget,
  required double plannedDebt,
  required double plannedFunds,
  required double extraDebt,
  required double extraFunds,
}) {
  final plannedTotal =
      baseCategoryBudget + plannedDebt + plannedFunds + extraDebt + extraFunds;
  final unallocated = income - plannedTotal;
  return ZeroBasedBudgetSummary(
    income: income,
    baseCategoryBudget: baseCategoryBudget,
    plannedDebt: plannedDebt,
    plannedFunds: plannedFunds,
    extraDebt: extraDebt,
    extraFunds: extraFunds,
    plannedTotal: plannedTotal,
    unallocated: unallocated,
  );
}

bool requiresExplicitUnallocatedAcknowledgement({
  required double unallocated,
  required bool closeOnlySelected,
}) {
  return closeOnlySelected && unallocated > 0.01;
}

OverviewMetrics calculateOverviewMetrics(Iterable<OverviewMetricItem> items) {
  final planned = items.fold<double>(0.0, (sum, item) => sum + item.planned);
  final spent = items.fold<double>(0.0, (sum, item) => sum + item.spent);
  final remaining = (planned - spent).clamp(0.0, double.infinity);
  final isOverBudget = spent > planned && planned > 0;
  final progress = planned > 0 ? (spent / planned).clamp(0.0, 1.0) : 0.0;

  return OverviewMetrics(
    planned: planned,
    spent: spent,
    remaining: remaining,
    progress: progress,
    isOverBudget: isOverBudget,
  );
}
