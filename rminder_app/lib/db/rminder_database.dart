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
      version: 3,
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
    final id = await db.insert('transactions', txn.toMap());
    await _updateCategorySpent(txn.categoryId, db);
    return id;
  }

  Future<List<models.Transaction>> getTransactions() async {
    final db = await instance.database;
    final result = await db.query('transactions');
    return result.map((map) => models.Transaction.fromMap(map)).toList();
  }

  Future<int> updateTransaction(models.Transaction txn) async {
    final db = await instance.database;
    final result = await db.update(
      'transactions',
      txn.toMap(),
      where: 'id = ?',
      whereArgs: [txn.id],
    );
    await _updateCategorySpent(txn.categoryId, db);
    return result;
  }

  Future<int> deleteTransaction(int id) async {
    final db = await instance.database;
    // Find the transaction to get its categoryId
    final txnList = await db.query('transactions', where: 'id = ?', whereArgs: [id]);
    int? categoryId;
    if (txnList.isNotEmpty) {
      categoryId = txnList.first['categoryId'] as int?;
    }
    final result = await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
    if (categoryId != null) {
      await _updateCategorySpent(categoryId, db);
    }
    return result;
  }

  Future<bool> hasTransactionsForCategory(int categoryId) async {
    final db = await instance.database;
    final result = await db.query('transactions', where: 'categoryId = ?', whereArgs: [categoryId]);
    return result.isNotEmpty;
  }

  Future<void> _updateCategorySpent(int categoryId, Database db) async {
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
  final result = await db.update('liabilities', liability.toMap(), where: 'id = ?', whereArgs: [liability.id]);
  // Keep the linked budget category's budget_limit aligned with planned
  await db.update('categories', {'budget_limit': liability.planned},
    where: 'id = ?', whereArgs: [liability.budgetCategoryId]);
  return result;
  }

  Future<int> deleteLiability(int id) async {
    final db = await instance.database;
    return await db.delete('liabilities', where: 'id = ?', whereArgs: [id]);
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
  Future<void> payLiability(models.Liability liability, double amount) async {
    final db = await instance.database;
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
  await txn.insert('transactions', t.toMap());
      // Update category spent
      final result = await txn.rawQuery(
        'SELECT SUM(amount) as total FROM transactions WHERE categoryId = ?', [liability.budgetCategoryId],
      );
      final total = (result.first['total'] ?? 0) as num;
      await txn.update('categories', {'spent': total}, where: 'id = ?', whereArgs: [liability.budgetCategoryId]);
    });
  }
}
