import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rminder_app/db/rminder_database.dart';
import 'package:rminder_app/models/models.dart' as models;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await RMinderDatabase.instance.close();
    final db = await RMinderDatabase.instance.database;
    const tables = <String>[
      'category_carryovers',
      'fund_snapshots',
      'liability_snapshots',
      'spending_snapshots',
      'income_snapshots',
      'budget_snapshots',
      'extra_payments',
      'transactions',
      'sinking_funds',
      'liabilities',
      'income_sources',
      'closed_months',
      'settings',
      'categories',
    ];
    for (final table in tables) {
      await db.delete(table);
    }
    await RMinderDatabase.instance.close();

    final dbDir = await sqflite.getDatabasesPath();
    final backupDir = Directory(p.join(dbDir, 'backups'));
    if (await backupDir.exists()) await backupDir.delete(recursive: true);
  });

  tearDown(() async {
    await RMinderDatabase.instance.close();
  });

  test('carryByCategory creates and applies category carryovers', () async {
    final dbApi = RMinderDatabase.instance;
    final catId = await dbApi.insertCategory(
      models.BudgetCategory(
        name: 'Groceries',
        budgetLimit: 100,
        spent: 0,
        inBudget: true,
      ),
    );

    final periodStart = DateTime(2026, 5, 1);
    final closeAt = DateTime(2026, 5, 30, 20, 0, 0);
    final nextStart = closeAt;
    await dbApi.closePeriodAtomic(
      periodStart: periodStart,
      closeAt: closeAt,
      nextStart: nextStart,
      action: 'carryByCategory',
      totalLeftover: 60,
      categories: [
        models.BudgetCategory(
          id: catId,
          name: 'Groceries',
          budgetLimit: 100,
          spent: 0,
          inBudget: true,
        ),
      ],
      incomeSources: const [],
      liabilities: const [],
      sinkingFunds: const [],
      spentByCategory: {catId: 40},
      paidByLiabilityId: const {},
      contributedByFundId: const {},
    );

    final pending = await dbApi.getCategoryCarryoversForPeriod(
      nextStart,
      onlyPending: true,
    );
    expect(pending.length, 1);
    expect(((pending.first['amount'] ?? 0) as num).toDouble(), 60);

    final applied = await dbApi.applyPendingCategoryCarryoversForPeriod(
      nextStart,
    );
    expect(applied, 1);

    final categories = await dbApi.getCategories();
    final updated = categories.firstWhere((c) => c.id == catId);
    expect(updated.budgetLimit, 160);
  });

  test(
    'applyBudgetTemplateFromPeriod copies template and deactivates missing categories',
    () async {
      final dbApi = RMinderDatabase.instance;
      final catA = await dbApi.insertCategory(
        models.BudgetCategory(
          name: 'Food',
          budgetLimit: 10,
          spent: 0,
          inBudget: true,
        ),
      );
      final catB = await dbApi.insertCategory(
        models.BudgetCategory(
          name: 'Transport',
          budgetLimit: 20,
          spent: 0,
          inBudget: true,
        ),
      );

      final templatePeriod = DateTime(2026, 4, 1);
      await dbApi.saveBudgetSnapshotForPeriod(templatePeriod, [
        models.BudgetCategory(
          id: catA,
          name: 'Food',
          budgetLimit: 99,
          spent: 0,
          inBudget: true,
        ),
        models.BudgetCategory(
          id: 999,
          name: 'New Category',
          budgetLimit: 55,
          spent: 0,
          inBudget: true,
        ),
      ]);

      final touched = await dbApi.applyBudgetTemplateFromPeriod(
        templatePeriodStart: templatePeriod,
        liabilities: const [],
        sinkingFunds: const [],
      );
      expect(touched, 2);

      final categories = await dbApi.getCategories();
      final food = categories.firstWhere((c) => c.id == catA);
      final transport = categories.firstWhere((c) => c.id == catB);
      final created = categories.firstWhere((c) => c.id == 999);

      expect(food.budgetLimit, 99);
      expect(food.inBudget, isTrue);
      expect(transport.inBudget, isFalse);
      expect(created.name, 'New Category');
      expect(created.inBudget, isTrue);
    },
  );

  test(
    'reopenClosedPeriod removes all snapshots and carryover artifacts',
    () async {
      final dbApi = RMinderDatabase.instance;
      final catId = await dbApi.insertCategory(
        models.BudgetCategory(
          name: 'Home',
          budgetLimit: 200,
          spent: 0,
          inBudget: true,
        ),
      );

      final periodStart = DateTime(2026, 6, 1);
      final closeAt = DateTime(2026, 6, 28, 19, 0, 0);
      final nextStart = closeAt;
      await dbApi.closePeriodAtomic(
        periodStart: periodStart,
        closeAt: closeAt,
        nextStart: nextStart,
        action: 'carryIncome',
        totalLeftover: 25,
        categories: [
          models.BudgetCategory(
            id: catId,
            name: 'Home',
            budgetLimit: 200,
            spent: 0,
            inBudget: true,
          ),
        ],
      incomeSources: [
        models.IncomeSource(name: 'Salary', amount: 1000),
      ],
        liabilities: const [],
        sinkingFunds: const [],
        spentByCategory: {catId: 100},
        paidByLiabilityId: const {},
        contributedByFundId: const {},
      );

      final db = await dbApi.database;
      final nextPeriodIso = DateTime(
        nextStart.year,
        nextStart.month,
        nextStart.day,
      ).toIso8601String();
      final carryIncomeKey =
          'carry_income:${nextStart.year.toString().padLeft(4, '0')}-${nextStart.month.toString().padLeft(2, '0')}-${nextStart.day.toString().padLeft(2, '0')}';
      await db.insert('category_carryovers', {
        'period_start': nextPeriodIso,
        'source_period_start': DateTime(
          periodStart.year,
          periodStart.month,
          periodStart.day,
        ).toIso8601String(),
        'category_id': catId,
        'category_name': 'Home',
        'amount': 10,
        'is_applied': 0,
      });

      final reopened = await dbApi.reopenClosedPeriod(periodStart);
      expect(reopened, isTrue);

      final ps = DateTime(
        periodStart.year,
        periodStart.month,
        periodStart.day,
      ).toIso8601String();
      expect(
        await db.query(
          'closed_months',
          where: 'month_start = ?',
          whereArgs: [ps],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          'budget_snapshots',
          where: 'period_start = ?',
          whereArgs: [ps],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          'income_snapshots',
          where: 'period_start = ?',
          whereArgs: [ps],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          'spending_snapshots',
          where: 'period_start = ?',
          whereArgs: [ps],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          'liability_snapshots',
          where: 'period_start = ?',
          whereArgs: [ps],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          'fund_snapshots',
          where: 'period_start = ?',
          whereArgs: [ps],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          'category_carryovers',
          where: 'period_start = ?',
          whereArgs: [nextPeriodIso],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          'settings',
          where: 'key = ?',
          whereArgs: [carryIncomeKey],
        ),
        isEmpty,
      );
    },
  );

  test('local backup export and restore round-trips data', () async {
    final dbApi = RMinderDatabase.instance;
    final catId = await dbApi.insertCategory(
      models.BudgetCategory(
        name: 'Utilities',
        budgetLimit: 300,
        spent: 0,
        inBudget: true,
      ),
    );
    await dbApi.insertIncomeSource(
      models.IncomeSource(name: 'Salary', amount: 5000),
    );
    await dbApi.insertTransaction(
      models.Transaction(
        categoryId: catId,
        amount: 120,
        date: DateTime(2026, 7, 2),
        note: 'Electricity',
      ),
    );

    final backupPath = await dbApi.createLocalBackup();
    expect(await File(backupPath).exists(), isTrue);

    final db = await dbApi.database;
    await db.delete('transactions');
    await db.delete('income_sources');
    await db.delete('categories');

    expect(await dbApi.getCategories(), isEmpty);
    expect(await dbApi.getIncomeSources(), isEmpty);

    await dbApi.restoreFromLocalBackup(backupPath);

    final categories = await dbApi.getCategories();
    final incomes = await dbApi.getIncomeSources();
    final txns = await dbApi.getTransactions();
    expect(categories.any((c) => c.name == 'Utilities'), isTrue);
    expect(incomes.any((i) => i.name == 'Salary'), isTrue);
    expect(txns.any((t) => t.note == 'Electricity'), isTrue);
  });
}
