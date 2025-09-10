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

  Future<Database> _initDB(String filePath) async {
    return await openDatabase(
      filePath,
      version: 2,
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
}
