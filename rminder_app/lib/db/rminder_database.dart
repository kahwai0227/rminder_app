import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/models.dart' as models;

class RMinderDatabase {
  static final RMinderDatabase instance = RMinderDatabase._init();
  static Database? _database;

  RMinderDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('rminder.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbDir = await getDatabasesPath();
    final fullPath = join(dbDir, fileName);
    return await openDatabase(
      fullPath,
      version: 7,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            budget_limit REAL NOT NULL,
            spent REAL NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            categoryId INTEGER NOT NULL,
            amount REAL NOT NULL,
            date TEXT NOT NULL,
            note TEXT,
            FOREIGN KEY (categoryId) REFERENCES categories (id)
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS income_sources (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            amount REAL NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS liabilities (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            balance REAL NOT NULL,
            planned REAL NOT NULL,
            budgetCategoryId INTEGER NOT NULL,
            FOREIGN KEY (budgetCategoryId) REFERENCES categories (id)
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS extra_payments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            liabilityId INTEGER NOT NULL,
            amount REAL NOT NULL,
            date TEXT NOT NULL,
            transactionId INTEGER,
            FOREIGN KEY (liabilityId) REFERENCES liabilities (id),
            FOREIGN KEY (transactionId) REFERENCES transactions (id)
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS closed_months (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            month_start TEXT NOT NULL UNIQUE,
            closed_at TEXT NOT NULL,
            action TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS sinking_funds (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            target_amount REAL NOT NULL,
            balance REAL NOT NULL,
            monthly_contribution REAL NOT NULL,
            budgetCategoryId INTEGER,
            FOREIGN KEY (budgetCategoryId) REFERENCES categories (id)
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS income_sources (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              amount REAL NOT NULL
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS liabilities (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              balance REAL NOT NULL,
              planned REAL NOT NULL,
              budgetCategoryId INTEGER NOT NULL,
              FOREIGN KEY (budgetCategoryId) REFERENCES categories (id)
            )
          ''');
        }
        if (oldVersion < 4) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS extra_payments (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              liabilityId INTEGER NOT NULL,
              amount REAL NOT NULL,
              date TEXT NOT NULL,
              transactionId INTEGER,
              FOREIGN KEY (liabilityId) REFERENCES liabilities (id),
              FOREIGN KEY (transactionId) REFERENCES transactions (id)
            )
          ''');
        }
        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS closed_months (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              month_start TEXT NOT NULL UNIQUE,
              closed_at TEXT NOT NULL,
              action TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 6) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS sinking_funds (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              target_amount REAL NOT NULL,
              balance REAL NOT NULL,
              monthly_contribution REAL NOT NULL,
              budgetCategoryId INTEGER,
              FOREIGN KEY (budgetCategoryId) REFERENCES categories (id)
            )
          ''');
        }
        if (oldVersion < 7) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
        }
      },
    );
  }

  // CRUD for BudgetCategory
  Future<int> insertCategory(models.BudgetCategory category) async {
    final db = await instance.database;
    return await db.insert('categories', category.toMap());
  }

  Future<List<models.BudgetCategory>> getCategories() async {
    final db = await instance.database;
    final result = await db.query('categories');
    return result.map((map) => models.BudgetCategory.fromMap(map)).toList();
  }

  Future<int> updateCategory(models.BudgetCategory category) async {
    final db = await instance.database;
    return await db.update(
      'categories',
      category.toMap(),
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  Future<int> deleteCategory(int id) async {
    final db = await instance.database;
    return await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  // CRUD for Transaction
  Future<int> insertTransaction(models.Transaction txn) async {
    final db = await instance.database;
    int insertedId = -1;
    await db.transaction((txnDb) async {
      insertedId = await txnDb.insert('transactions', txn.toMap());
      // If this category is linked to a liability, reduce its balance by txn.amount
      await _adjustLiabilityBalanceForCategory(txnDb, txn.categoryId, -txn.amount);
      // If this category is linked to a sinking fund, increase its balance by txn.amount
      await _adjustSinkingFundBalanceForCategory(txnDb, txn.categoryId, txn.amount);
      await _updateCategorySpent(txn.categoryId, txnDb);
    });
    return insertedId;
  }

  Future<List<models.Transaction>> getTransactions() async {
    final db = await instance.database;
    final result = await db.query('transactions');
    return result.map((map) => models.Transaction.fromMap(map)).toList();
  }

  Future<int> updateTransaction(models.Transaction txn) async {
    final db = await instance.database;
    int rows = 0;
    await db.transaction((txnDb) async {
      // Load the existing transaction to compute adjustments
      final prevList = await txnDb.query('transactions', where: 'id = ?', whereArgs: [txn.id]);
      Map<String, Object?>? prev;
      if (prevList.isNotEmpty) prev = prevList.first;

      rows = await txnDb.update(
        'transactions',
        txn.toMap(),
        where: 'id = ?',
        whereArgs: [txn.id],
      );

      if (prev != null) {
        final prevCategoryId = prev['categoryId'] as int;
        final prevAmount = (prev['amount'] as num).toDouble();

        if (prevCategoryId == txn.categoryId) {
          // Same category; net change is new - old
          final delta = txn.amount - prevAmount; // positive means increased spend
          await _adjustLiabilityBalanceForCategory(txnDb, txn.categoryId, -delta);
          await _adjustSinkingFundBalanceForCategory(txnDb, txn.categoryId, delta);
          await _updateCategorySpent(txn.categoryId, txnDb);
        } else {
          // Different categories; revert old, apply new
          await _adjustLiabilityBalanceForCategory(txnDb, prevCategoryId, prevAmount);
          await _adjustSinkingFundBalanceForCategory(txnDb, prevCategoryId, -prevAmount);
          await _updateCategorySpent(prevCategoryId, txnDb);

          await _adjustLiabilityBalanceForCategory(txnDb, txn.categoryId, -txn.amount);
          await _adjustSinkingFundBalanceForCategory(txnDb, txn.categoryId, txn.amount);
          await _updateCategorySpent(txn.categoryId, txnDb);
        }
      } else {
        // No previous? Just update spent on target category
        await _updateCategorySpent(txn.categoryId, txnDb);
      }
    });
    return rows;
  }

  Future<int> deleteTransaction(int id) async {
    final db = await instance.database;
    int rows = 0;
    await db.transaction((txnDb) async {
      // Find the transaction to get its details
      final txnList = await txnDb.query('transactions', where: 'id = ?', whereArgs: [id]);
      int? categoryId;
      double? amount;
      if (txnList.isNotEmpty) {
        final t = txnList.first;
        categoryId = t['categoryId'] as int?;
        amount = (t['amount'] as num).toDouble();
      }
      rows = await txnDb.delete('transactions', where: 'id = ?', whereArgs: [id]);
      if (categoryId != null && amount != null) {
        // Deleting a transaction should add back to liability balance if it was a payment
  await _adjustLiabilityBalanceForCategory(txnDb, categoryId, amount);
        // And subtract from sinking fund balance if it was a contribution
        await _adjustSinkingFundBalanceForCategory(txnDb, categoryId, -amount);
        await _updateCategorySpent(categoryId, txnDb);
      }
    });
    return rows;
  }

  Future<bool> hasTransactionsForCategory(int categoryId) async {
    final db = await instance.database;
    final result = await db.query('transactions', where: 'categoryId = ?', whereArgs: [categoryId]);
    return result.isNotEmpty;
  }

  Future<void> _updateCategorySpent(int categoryId, DatabaseExecutor db) async {
    // Sum all transactions for this category
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM transactions WHERE categoryId = ?', [categoryId],
    );
    final total = (result.first['total'] ?? 0) as num;
    await db.update(
      'categories',
      {'spent': total},
      where: 'id = ?',
      whereArgs: [categoryId],
    );
  }

  // Helper: Adjust liability balance by delta for a category if it maps to a liability.
  // delta < 0 reduces balance (payment). delta > 0 increases balance (undo payment).
  Future<void> _adjustLiabilityBalanceForCategory(DatabaseExecutor db, int categoryId, double delta) async {
    // Find the liability linked to this category
    final liabs = await db.query('liabilities', where: 'budgetCategoryId = ?', whereArgs: [categoryId]);
    Map<String, Object?>? liab;
    if (liabs.isNotEmpty) {
      liab = liabs.first;
    } else {
      // Fallback: try to auto-link by name if a liability with the same name as the category exists
      final cats = await db.query('categories', columns: ['name'], where: 'id = ?', whereArgs: [categoryId]);
      if (cats.isNotEmpty) {
        final catName = cats.first['name'] as String;
        final byName = await db.query('liabilities', where: 'name = ?', whereArgs: [catName]);
        if (byName.length == 1) {
          liab = byName.first;
          // Link this liability to the category for future operations
          await db.update('liabilities', {'budgetCategoryId': categoryId}, where: 'id = ?', whereArgs: [liab['id']]);
        }
      }
    }
    if (liab == null) return;
    final current = (liab['balance'] as num).toDouble();
    double next = current + delta;
    if (next < 0) next = 0;
    await db.update('liabilities', {'balance': next}, where: 'id = ?', whereArgs: [liab['id']]);
  }

  // Helper: Adjust sinking fund balance by delta for a category if it maps to a sinking fund.
  // delta > 0 increases balance (contribution). delta < 0 decreases balance (undo).
  Future<void> _adjustSinkingFundBalanceForCategory(DatabaseExecutor db, int categoryId, double delta) async {
    // Find the sinking fund linked to this category
    final funds = await db.query('sinking_funds', where: 'budgetCategoryId = ?', whereArgs: [categoryId]);
    Map<String, Object?>? fund;
    if (funds.isNotEmpty) {
      fund = funds.first;
    } else {
      // Fallback: try to auto-link by same name as category
      final cats = await db.query('categories', columns: ['name'], where: 'id = ?', whereArgs: [categoryId]);
      if (cats.isNotEmpty) {
        final catName = cats.first['name'] as String;
        final byName = await db.query('sinking_funds', where: 'name = ?', whereArgs: [catName]);
        if (byName.length == 1) {
          fund = byName.first;
          await db.update('sinking_funds', {'budgetCategoryId': categoryId}, where: 'id = ?', whereArgs: [fund['id']]);
        }
      }
    }
    if (fund == null) return;
    final current = (fund['balance'] as num).toDouble();
    final target = (fund['target_amount'] as num).toDouble();
    double next = current + delta;
    if (next < 0) next = 0;
    if (next > target) next = target;
    await db.update('sinking_funds', {'balance': next}, where: 'id = ?', whereArgs: [fund['id']]);
  }

  Future<void> deleteTransactionsForCategory(int categoryId) async {
    final db = await instance.database;
    await db.delete('transactions', where: 'categoryId = ?', whereArgs: [categoryId]);
  }

  // CRUD for IncomeSource
  Future<int> insertIncomeSource(models.IncomeSource income) async {
    final db = await instance.database;
    return await db.insert('income_sources', income.toMap());
  }

  Future<List<models.IncomeSource>> getIncomeSources() async {
    final db = await instance.database;
    final result = await db.query('income_sources');
    return result.map((map) => models.IncomeSource.fromMap(map)).toList();
  }

  Future<int> updateIncomeSource(models.IncomeSource income) async {
    final db = await instance.database;
    if (income.id == null) return 0;
    return await db.update(
      'income_sources',
      income.toMap(),
      where: 'id = ?',
      whereArgs: [income.id],
    );
  }

  Future<int> deleteIncomeSource(int id) async {
    final db = await instance.database;
    return await db.delete('income_sources', where: 'id = ?', whereArgs: [id]);
  }

  Future close() async {
    final db = _database;
    if (db != null) {
      await db.close();
    }
  }

  // CRUD for Liability
  Future<int> insertLiability(models.Liability liability) async {
    final db = await instance.database;
    return await db.insert('liabilities', liability.toMap());
  }

  Future<List<models.Liability>> getLiabilities() async {
    final db = await instance.database;
    final result = await db.query('liabilities');
    return result.map((m) => models.Liability.fromMap(m)).toList();
  }

  Future<int> updateLiability(models.Liability liability) async {
  final db = await instance.database;
  return await db.transaction((txn) async {
    final result = await txn.update('liabilities', liability.toMap(), where: 'id = ?', whereArgs: [liability.id]);
    // Keep the linked budget category aligned with the liability:
    // - name updated to match liability name (so Transactions filter shows new name)
    // - budget_limit updated to liability.planned
    await txn.update(
      'categories',
      {
        'name': liability.name,
        'budget_limit': liability.planned,
      },
      where: 'id = ?',
      whereArgs: [liability.budgetCategoryId],
    );
    return result;
  });
  }

  Future<int> deleteLiability(int id) async {
    final db = await instance.database;
    return await db.delete('liabilities', where: 'id = ?', whereArgs: [id]);
  }

  // Delete liability and cascade: remove all transactions under its linked category,
  // delete the linked budget category, and finally the liability itself.
  Future<void> deleteLiabilityCascade(int liabilityId) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      final liabs = await txn.query('liabilities', where: 'id = ?', whereArgs: [liabilityId]);
      if (liabs.isEmpty) return; // nothing to do
      final liab = liabs.first;
      final categoryId = liab['budgetCategoryId'] as int;
      // Delete transactions for the category
      await txn.delete('transactions', where: 'categoryId = ?', whereArgs: [categoryId]);
      // Delete the category
      await txn.delete('categories', where: 'id = ?', whereArgs: [categoryId]);
      // Delete the liability
      await txn.delete('liabilities', where: 'id = ?', whereArgs: [liabilityId]);
    });
  }

  // Ensure a debt budget category exists for this liability name, returns category id
  Future<int> ensureDebtCategory(String liabilityName, {double planned = 0}) async {
    final db = await instance.database;
    // Try find existing category with same name (or a prefixed naming convention)
    final existing = await db.query('categories', where: 'name = ?', whereArgs: [liabilityName]);
    if (existing.isNotEmpty) {
      return existing.first['id'] as int;
    }
    final id = await db.insert('categories', {
      'name': liabilityName,
      'budget_limit': planned,
      'spent': 0,
    });
    return id;
  }

  // Pay liability: deduct balance, log transaction in linked budget category, and update spent
  // Returns the created transaction id.
  Future<int> payLiability(models.Liability liability, double amount) async {
    final db = await instance.database;
    int txId = -1;
    await db.transaction((txn) async {
      final newBalance = (liability.balance - amount) < 0 ? 0 : (liability.balance - amount);
      // Update liability balance
      await txn.update('liabilities', {'balance': newBalance}, where: 'id = ?', whereArgs: [liability.id]);
      // Log transaction
      final t = models.Transaction(
        categoryId: liability.budgetCategoryId,
        amount: amount,
        date: DateTime.now(),
        note: 'Debt payment: ${liability.name}',
      );
      txId = await txn.insert('transactions', t.toMap());
      // Update category spent
      final result = await txn.rawQuery(
        'SELECT SUM(amount) as total FROM transactions WHERE categoryId = ?', [liability.budgetCategoryId],
      );
      final total = (result.first['total'] ?? 0) as num;
      await txn.update('categories', {'spent': total}, where: 'id = ?', whereArgs: [liability.budgetCategoryId]);
    });
    return txId;
  }

  // CRUD for SinkingFund
  Future<int> insertSinkingFund(models.SinkingFund fund) async {
    final db = await instance.database;
    return await db.insert('sinking_funds', fund.toMap());
  }

  Future<List<models.SinkingFund>> getSinkingFunds() async {
    final db = await instance.database;
    final rows = await db.query('sinking_funds');
    return rows.map((m) => models.SinkingFund.fromMap(m)).toList();
  }

  Future<int> updateSinkingFund(models.SinkingFund fund) async {
    final db = await instance.database;
    // Perform updates in a single transaction to keep entities consistent
    return await db.transaction((txn) async {
      final result = await txn.update('sinking_funds', fund.toMap(), where: 'id = ?', whereArgs: [fund.id]);
      // Keep the linked budget category aligned:
      // - name matches the fund name (so filters show updated name)
      // - budget_limit matches monthly contribution
      if (fund.budgetCategoryId != null) {
        await txn.update(
          'categories',
          {
            'name': fund.name,
            'budget_limit': fund.monthlyContribution,
          },
          where: 'id = ?',
          whereArgs: [fund.budgetCategoryId],
        );
      }
      return result;
    });
  }

  Future<void> deleteSinkingFundCascade(int fundId) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      final funds = await txn.query('sinking_funds', where: 'id = ?', whereArgs: [fundId]);
      if (funds.isEmpty) return;
      final fund = funds.first;
      final categoryId = fund['budgetCategoryId'] as int?;
      if (categoryId != null) {
        await txn.delete('transactions', where: 'categoryId = ?', whereArgs: [categoryId]);
        await txn.delete('categories', where: 'id = ?', whereArgs: [categoryId]);
      }
      await txn.delete('sinking_funds', where: 'id = ?', whereArgs: [fundId]);
    });
  }

  // Ensure a savings budget category exists for this fund name, returns category id
  Future<int> ensureSavingsCategory(String fundName, {double monthly = 0}) async {
    final db = await instance.database;
    final existing = await db.query('categories', where: 'name = ?', whereArgs: [fundName]);
    if (existing.isNotEmpty) {
      return existing.first['id'] as int;
    }
    final id = await db.insert('categories', {
      'name': fundName,
      'budget_limit': monthly,
      'spent': 0,
    });
    return id;
  }

  // Contribute to a sinking fund: increase balance, log transaction in linked budget category, and update spent.
  Future<int> contributeToFund(models.SinkingFund fund, double amount) async {
    final db = await instance.database;
    int txId = -1;
    await db.transaction((txn) async {
      final newBalance = (fund.balance + amount);
      // Update fund balance (clamped to target)
      final target = fund.targetAmount;
      final clamped = newBalance > target ? target : (newBalance < 0 ? 0 : newBalance);
      await txn.update('sinking_funds', {'balance': clamped}, where: 'id = ?', whereArgs: [fund.id]);
      // Log transaction
      if (fund.budgetCategoryId != null) {
        final t = models.Transaction(
          categoryId: fund.budgetCategoryId!,
          amount: amount,
          date: DateTime.now(),
        );
        txId = await txn.insert('transactions', t.toMap());
        // Update category spent
        final result = await txn.rawQuery(
          'SELECT SUM(amount) as total FROM transactions WHERE categoryId = ?', [fund.budgetCategoryId],
        );
        final total = (result.first['total'] ?? 0) as num;
        await txn.update('categories', {'spent': total}, where: 'id = ?', whereArgs: [fund.budgetCategoryId]);
      }
    });
    return txId;
  }

  // Spend from a sinking fund: decrease balance, log a negative transaction in the linked budget category, and update spent.
  // Returns the created transaction id (or -1 if no transaction written).
  Future<int> spendFromFund(models.SinkingFund fund, double amount, {String? note}) async {
    final db = await instance.database;
    int txId = -1;
    await db.transaction((txn) async {
      // Clamp withdrawal to available balance
  final withdraw = (amount < 0 ? 0 : amount).toDouble();
      final newBalance = fund.balance - withdraw;
      final clamped = newBalance < 0 ? 0 : newBalance;
      await txn.update('sinking_funds', {'balance': clamped}, where: 'id = ?', whereArgs: [fund.id]);
      // Log transaction (negative amount) in linked category if present
      if (fund.budgetCategoryId != null) {
        final t = models.Transaction(
          categoryId: fund.budgetCategoryId!,
          amount: -withdraw,
          date: DateTime.now(),
          note: note ?? 'Fund withdrawal: ${fund.name}',
        );
        txId = await txn.insert('transactions', t.toMap());
        // Update category spent to reflect new sum
        final result = await txn.rawQuery(
          'SELECT SUM(amount) as total FROM transactions WHERE categoryId = ?', [fund.budgetCategoryId],
        );
        final total = (result.first['total'] ?? 0) as num;
        await txn.update('categories', {'spent': total}, where: 'id = ?', whereArgs: [fund.budgetCategoryId]);
      }
    });
    return txId;
  }

  // Sum contributions recorded for a fund for a given month
  Future<double> sumContributedForFundInMonth(int fundId, DateTime month) async {
    final db = await instance.database;
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final funds = await db.query('sinking_funds', columns: ['budgetCategoryId'], where: 'id = ?', whereArgs: [fundId]);
    if (funds.isEmpty) return 0;
    final catId = funds.first['budgetCategoryId'] as int?;
    if (catId == null) return 0;
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM transactions WHERE categoryId = ? AND date >= ? AND date < ?',
      [catId, start.toIso8601String(), end.toIso8601String()],
    );
    final total = (result.first['total'] ?? 0) as num;
    return total.toDouble();
  }

  // Record an extra payment line (meta) linked to a liability (and optionally a transaction)
  Future<int> insertExtraPayment({
    required int liabilityId,
    required double amount,
    required DateTime date,
    int? transactionId,
  }) async {
    final db = await instance.database;
    return await db.insert('extra_payments', {
      'liabilityId': liabilityId,
      'amount': amount,
      'date': date.toIso8601String(),
      'transactionId': transactionId,
    });
  }

  // Sum of paid transactions for a liability for a given month
  Future<double> sumPaidForLiabilityInMonth(int liabilityId, DateTime month) async {
    final db = await instance.database;
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    // Look up categoryId
    final liabs = await db.query('liabilities', columns: ['budgetCategoryId'], where: 'id = ?', whereArgs: [liabilityId]);
    if (liabs.isEmpty) return 0;
    final catId = liabs.first['budgetCategoryId'] as int;
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM transactions WHERE categoryId = ? AND date >= ? AND date < ?',
      [catId, start.toIso8601String(), end.toIso8601String()],
    );
    final total = (result.first['total'] ?? 0) as num;
    return total.toDouble();
  }

  // Sum of extra payments recorded for a liability in a given month
  Future<double> sumExtraForLiabilityInMonth(int liabilityId, DateTime month) async {
    final db = await instance.database;
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM extra_payments WHERE liabilityId = ? AND date >= ? AND date < ?',
      [liabilityId, start.toIso8601String(), end.toIso8601String()],
    );
    final total = (result.first['total'] ?? 0) as num;
    return total.toDouble();
  }

  // Record that a month has been closed
  Future<int> insertClosedMonth({required DateTime monthStart, required String action}) async {
    final db = await instance.database;
    // Store the provided period start day (respect user-defined reset day)
    final ms = DateTime(monthStart.year, monthStart.month, monthStart.day).toIso8601String();
    final now = DateTime.now().toIso8601String();
    return await db.insert(
      'closed_months',
      {
        'month_start': ms,
        'closed_at': now,
        'action': action,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<bool> isMonthClosed(DateTime monthStart) async {
    final db = await instance.database;
    final ms = DateTime(monthStart.year, monthStart.month, monthStart.day).toIso8601String();
    final rows = await db.query('closed_months', where: 'month_start = ?', whereArgs: [ms], limit: 1);
    return rows.isNotEmpty;
  }

  Future<List<DateTime>> getClosedMonths() async {
    final db = await instance.database;
    final rows = await db.query('closed_months', columns: ['month_start']);
    return rows
        .map((r) => DateTime.parse((r['month_start'] as String)))
        .toSet()
        .toList()
      ..sort((a, b) => a.compareTo(b));
  }

  static const String _activePeriodStartKey = 'active_period_start';

  Future<DateTime?> getActivePeriodStart() async {
    final s = await getSetting(_activePeriodStartKey);
    if (s == null) return null;
    try {
      final d = DateTime.parse(s);
      return d;
    } catch (_) {
      return null;
    }
  }

  Future<void> setActivePeriodStart(DateTime start) async {
    await setSetting(_activePeriodStartKey, start.toIso8601String());
  }

  // Settings helpers
  Future<void> setSetting(String key, String value) async {
    final db = await instance.database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await instance.database;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  static const String _resetDayKey = 'reset_day';

  Future<void> setResetDay(int day) async {
    final clamped = day.clamp(1, 28);
    await setSetting(_resetDayKey, clamped.toString());
  }

  Future<int> getResetDay() async {
    final v = await getSetting(_resetDayKey);
    if (v == null) return 1;
    final parsed = int.tryParse(v);
    if (parsed == null) return 1;
    if (parsed < 1 || parsed > 28) return 1;
    return parsed;
  }
}
