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
