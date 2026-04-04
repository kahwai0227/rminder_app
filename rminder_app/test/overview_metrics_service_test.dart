import 'package:flutter_test/flutter_test.dart';
import 'package:rminder_app/models/models.dart' as models;
import 'package:rminder_app/services/overview_input_selector_service.dart';
import 'package:rminder_app/services/overview_metrics_service.dart';

void main() {
  test('calculateOverviewMetrics computes planned spent remaining and progress', () {
    final metrics = calculateOverviewMetrics(const [
      OverviewMetricItem(planned: 100, spent: 40),
      OverviewMetricItem(planned: 50, spent: 10),
    ]);

    expect(metrics.planned, 150);
    expect(metrics.spent, 50);
    expect(metrics.remaining, 100);
    expect(metrics.progress, closeTo(50 / 150, 0.0001));
    expect(metrics.isOverBudget, isFalse);
  });

  test('calculateOverviewMetrics clamps remaining and progress when overspent', () {
    final metrics = calculateOverviewMetrics(const [
      OverviewMetricItem(planned: 100, spent: 140),
    ]);

    expect(metrics.planned, 100);
    expect(metrics.spent, 140);
    expect(metrics.remaining, 0);
    expect(metrics.progress, 1);
    expect(metrics.isOverBudget, isTrue);
  });

  test('budget and report overview pipelines stay in parity for active period', () {
    final categories = <models.BudgetCategory>[
      models.BudgetCategory(id: 1, name: 'Groceries', budgetLimit: 300, spent: 0, inBudget: true),
      models.BudgetCategory(id: 2, name: 'Transport', budgetLimit: 150, spent: 0, inBudget: true),
      models.BudgetCategory(id: 3, name: 'Debt', budgetLimit: 200, spent: 0, inBudget: true),
      models.BudgetCategory(id: 4, name: 'Vacation Fund', budgetLimit: 100, spent: 0, inBudget: true),
    ];

    final liabilities = <models.Liability>[
      models.Liability(
        id: 11,
        name: 'Credit Card',
        balance: 1200,
        planned: 200,
        budgetCategoryId: 3,
      ),
      models.Liability(
        id: 12,
        name: 'Archived Loan',
        balance: 0,
        planned: 100,
        budgetCategoryId: 5,
        isArchived: true,
      ),
    ];

    final sinkingFunds = <models.SinkingFund>[
      models.SinkingFund(
        id: 21,
        name: 'Vacation',
        targetAmount: 5000,
        balance: 1000,
        monthlyContribution: 100,
        budgetCategoryId: 4,
      ),
    ];

    final periodStart = DateTime(2026, 4, 1, 13, 0, 0);
    final periodEndExclusive = DateTime(2026, 4, 5, 0, 0, 0);

    final transactions = <models.Transaction>[
      models.Transaction(categoryId: 1, amount: 120, date: DateTime(2026, 4, 1, 14, 0, 0)),
      models.Transaction(categoryId: 1, amount: 30, date: DateTime(2026, 4, 2, 9, 0, 0)),
      models.Transaction(categoryId: 2, amount: 70, date: DateTime(2026, 4, 3, 8, 0, 0)),
      models.Transaction(categoryId: 2, amount: -20, date: DateTime(2026, 4, 3, 12, 0, 0)),
      models.Transaction(categoryId: 3, amount: 80, date: DateTime(2026, 4, 2, 10, 0, 0)),
      models.Transaction(categoryId: 4, amount: 50, date: DateTime(2026, 4, 2, 11, 0, 0)),
      models.Transaction(categoryId: 1, amount: 40, date: DateTime(2026, 3, 31, 20, 0, 0)),
      models.Transaction(categoryId: 2, amount: 25, date: DateTime(2026, 4, 5, 0, 0, 0)),
    ];

    // Budget page path: app state liabilities (includes archived items).
    final budgetSelection = selectActiveOverviewSelection(
      categories: categories,
      transactions: transactions,
      liabilities: liabilities,
      sinkingFunds: sinkingFunds,
      periodStart: periodStart,
      periodEndExclusive: periodEndExclusive,
    );

    final budgetOverview = calculateOverviewMetrics(
      budgetSelection.categories.map(
        (c) => OverviewMetricItem(
          planned: c.budgetLimit,
          spent: budgetSelection.spentByCategory[c.id!] ?? 0,
        ),
      ),
    );

    // Report page path: period liabilities (already filtered to non-archived).
    final periodLiabilities = liabilities.where((l) => !l.isArchived).toList();
    final reportSelection = selectActiveOverviewSelection(
      categories: categories,
      transactions: transactions,
      liabilities: periodLiabilities,
      sinkingFunds: sinkingFunds,
      periodStart: periodStart,
      periodEndExclusive: periodEndExclusive,
    );

    final reportOverview = calculateOverviewMetrics(
      reportSelection.categories.map(
        (c) => OverviewMetricItem(
          planned: c.budgetLimit,
          spent: reportSelection.spentByCategory[c.id!] ?? 0,
        ),
      ),
    );

    expect(budgetOverview.planned, reportOverview.planned);
    expect(budgetOverview.spent, reportOverview.spent);
    expect(budgetOverview.remaining, reportOverview.remaining);
    expect(budgetOverview.progress, reportOverview.progress);
    expect(budgetOverview.isOverBudget, reportOverview.isOverBudget);

    expect(budgetOverview.planned, 450);
    expect(budgetOverview.spent, 220);
    expect(budgetOverview.remaining, 230);
  });
}
