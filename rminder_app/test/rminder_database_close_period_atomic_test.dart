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
    final dbDir = await sqflite.getDatabasesPath();
    final dbPath = p.join(dbDir, 'rminder.db');
    final dbFile = File(dbPath);
    final walFile = File('$dbPath-wal');
    final shmFile = File('$dbPath-shm');

    if (await dbFile.exists()) await dbFile.delete();
    if (await walFile.exists()) await walFile.delete();
    if (await shmFile.exists()) await shmFile.delete();
  });

  tearDown(() async {
    await RMinderDatabase.instance.close();
    final dbDir = await sqflite.getDatabasesPath();
    final dbPath = p.join(dbDir, 'rminder.db');
    final dbFile = File(dbPath);
    final walFile = File('$dbPath-wal');
    final shmFile = File('$dbPath-shm');

    if (await dbFile.exists()) await dbFile.delete();
    if (await walFile.exists()) await walFile.delete();
    if (await shmFile.exists()) await shmFile.delete();
  });

  test('closePeriodAtomic rolls back all writes on forced mid-transaction failure', () async {
    final dbApi = RMinderDatabase.instance;

    final categoryId = await dbApi.insertCategory(
      models.BudgetCategory(name: 'Food', budgetLimit: 300, spent: 0, inBudget: true),
    );

    final previousActiveStart = DateTime(2026, 4, 1, 0, 0, 0);
    await dbApi.setActivePeriodStart(previousActiveStart);

    final periodStart = DateTime(2026, 4, 1);
    final closeAt = DateTime(2026, 4, 30, 22, 0, 0);
    final nextStart = DateTime(2026, 4, 30, 22, 0, 0);

    expect(
      () => dbApi.closePeriodAtomic(
        periodStart: periodStart,
        closeAt: closeAt,
        nextStart: nextStart,
        action: 'payDebt',
        totalLeftover: 120,
        transferCategoryId: null,
        transferNote: 'forced failure test',
        categories: [
          models.BudgetCategory(
            id: categoryId,
            name: 'Food',
            budgetLimit: 300,
            spent: 0,
            inBudget: true,
          ),
        ],
        incomeSources: [models.IncomeSource(name: 'Salary', amount: 1000)],
        liabilities: const [],
        sinkingFunds: const [],
        spentByCategory: {categoryId: 50},
        paidByLiabilityId: const {},
        contributedByFundId: const {},
      ),
      throwsArgumentError,
    );

    final db = await dbApi.database;
    final ps = DateTime(periodStart.year, periodStart.month, periodStart.day).toIso8601String();

    final budgetSnapshots = await db.query('budget_snapshots', where: 'period_start = ?', whereArgs: [ps]);
    final incomeSnapshots = await db.query('income_snapshots', where: 'period_start = ?', whereArgs: [ps]);
    final spendingSnapshots = await db.query('spending_snapshots', where: 'period_start = ?', whereArgs: [ps]);
    final closedMonths = await db.query('closed_months', where: 'month_start = ?', whereArgs: [ps]);

    expect(budgetSnapshots, isEmpty);
    expect(incomeSnapshots, isEmpty);
    expect(spendingSnapshots, isEmpty);
    expect(closedMonths, isEmpty);

    final activeStartAfter = await dbApi.getActivePeriodStart();
    expect(activeStartAfter, previousActiveStart);
  });
}
