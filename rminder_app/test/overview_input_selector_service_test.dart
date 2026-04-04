import 'package:flutter_test/flutter_test.dart';
import 'package:rminder_app/models/models.dart' as models;
import 'package:rminder_app/services/overview_input_selector_service.dart';

void main() {
  test('selectActiveOverviewSelection filters debt/fund and period-bounds correctly', () {
    final categories = <models.BudgetCategory>[
      models.BudgetCategory(id: 1, name: 'Food', budgetLimit: 300, spent: 0, inBudget: true),
      models.BudgetCategory(id: 2, name: 'Transport', budgetLimit: 150, spent: 0, inBudget: true),
      models.BudgetCategory(id: 3, name: 'Debt', budgetLimit: 200, spent: 0, inBudget: true),
      models.BudgetCategory(id: 4, name: 'Savings', budgetLimit: 100, spent: 0, inBudget: true),
    ];

    final liabilities = <models.Liability>[
      models.Liability(
        id: 11,
        name: 'Credit Card',
        balance: 1200,
        planned: 200,
        budgetCategoryId: 3,
        isArchived: false,
      ),
      models.Liability(
        id: 12,
        name: 'Archived Debt',
        balance: 0,
        planned: 50,
        budgetCategoryId: 99,
        isArchived: true,
      ),
    ];

    final funds = <models.SinkingFund>[
      models.SinkingFund(
        id: 21,
        name: 'Vacation',
        targetAmount: 5000,
        balance: 1000,
        monthlyContribution: 100,
        budgetCategoryId: 4,
      ),
    ];

    final periodStart = DateTime(2026, 4, 1, 10, 0, 0);
    final periodEndExclusive = DateTime(2026, 4, 5, 0, 0, 0);

    final txns = <models.Transaction>[
      models.Transaction(categoryId: 1, amount: 120, date: DateTime(2026, 4, 1, 10, 1, 0)),
      models.Transaction(categoryId: 2, amount: 70, date: DateTime(2026, 4, 3, 8, 0, 0)),
      models.Transaction(categoryId: 2, amount: -15, date: DateTime(2026, 4, 3, 12, 0, 0)),
      models.Transaction(categoryId: 3, amount: 80, date: DateTime(2026, 4, 2, 9, 0, 0)),
      models.Transaction(categoryId: 4, amount: 50, date: DateTime(2026, 4, 2, 11, 0, 0)),
      models.Transaction(categoryId: 1, amount: 25, date: DateTime(2026, 3, 31, 23, 0, 0)),
      models.Transaction(categoryId: 2, amount: 30, date: DateTime(2026, 4, 5, 0, 0, 0)),
    ];

    final selection = selectActiveOverviewSelection(
      categories: categories,
      transactions: txns,
      liabilities: liabilities,
      sinkingFunds: funds,
      periodStart: periodStart,
      periodEndExclusive: periodEndExclusive,
    );

    final selectedIds = selection.categories.map((c) => c.id).toSet();
    expect(selectedIds, {1, 2});

    expect(selection.spentByCategory[1], 120);
    expect(selection.spentByCategory[2], 70);
    expect(selection.spentByCategory.containsKey(3), isFalse);
    expect(selection.spentByCategory.containsKey(4), isFalse);
  });
}
