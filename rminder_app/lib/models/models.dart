class SinkingFund {
  final int? id;
  final String name;
  final double targetAmount;
  final double balance;
  final double monthlyContribution;
  final int? budgetCategoryId; // optional: link to a category for contributions

  SinkingFund({
    this.id,
    required this.name,
    required this.targetAmount,
    required this.balance,
    required this.monthlyContribution,
    this.budgetCategoryId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'target_amount': targetAmount,
      'balance': balance,
      'monthly_contribution': monthlyContribution,
      'budgetCategoryId': budgetCategoryId,
    };
  }

  factory SinkingFund.fromMap(Map<String, dynamic> map) {
    return SinkingFund(
      id: map['id'] as int?,
      name: map['name'] as String,
      targetAmount: (map['target_amount'] as num).toDouble(),
      balance: (map['balance'] as num).toDouble(),
      monthlyContribution: (map['monthly_contribution'] as num).toDouble(),
      budgetCategoryId: map['budgetCategoryId'] as int?,
    );
  }
}
class BudgetCategory {
  final int? id;
  final String name;
  final double budgetLimit;
  final double spent;

  BudgetCategory({this.id, required this.name, required this.budgetLimit, required this.spent});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'budget_limit': budgetLimit,
      'spent': spent,
    };
  }

  factory BudgetCategory.fromMap(Map<String, dynamic> map) {
    return BudgetCategory(
      id: map['id'],
      name: map['name'],
      budgetLimit: map['budget_limit'],
      spent: map['spent'],
    );
  }
}

class Transaction {
  final int? id;
  final int categoryId;
  final double amount;
  final DateTime date;
  final String? note;

  Transaction({this.id, required this.categoryId, required this.amount, required this.date, this.note});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'categoryId': categoryId,
      'amount': amount,
      'date': date.toIso8601String(),
      'note': note,
    };
  }

  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      id: map['id'],
      categoryId: map['categoryId'],
      amount: map['amount'],
      date: DateTime.parse(map['date']),
      note: map['note'],
    );
  }
}

class IncomeSource {
  final int? id;
  final String name;
  final double amount;

  IncomeSource({this.id, required this.name, required this.amount});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'amount': amount,
    };
  }

  factory IncomeSource.fromMap(Map<String, dynamic> map) {
    return IncomeSource(
      id: map['id'],
      name: map['name'],
      amount: map['amount'],
    );
  }
}

class Liability {
  final int? id;
  final String name;
  final double balance;
  final double planned; // planned monthly payment
  final int budgetCategoryId; // links to a BudgetCategory used for payments
  final bool isArchived; // true when paid off and hidden from active period

  Liability({
    this.id,
    required this.name,
    required this.balance,
    required this.planned,
    required this.budgetCategoryId,
    this.isArchived = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'balance': balance,
      'planned': planned,
      'budgetCategoryId': budgetCategoryId,
      'is_archived': isArchived ? 1 : 0,
    };
  }

  factory Liability.fromMap(Map<String, dynamic> map) {
    return Liability(
      id: map['id'] as int?,
      name: map['name'] as String,
      balance: (map['balance'] as num).toDouble(),
      planned: (map['planned'] as num).toDouble(),
      budgetCategoryId: map['budgetCategoryId'] as int,
      isArchived: (map['is_archived'] as int?) == 1,
    );
  }
}

class BudgetSnapshot {
  final int? id;
  final DateTime periodStart; // date-only anchor for the period
  final int categoryId;
  final String categoryName; // name at time of snapshot (for stability)
  final double budgetLimit;

  BudgetSnapshot({
    this.id,
    required this.periodStart,
    required this.categoryId,
    required this.categoryName,
    required this.budgetLimit,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'period_start': DateTime(periodStart.year, periodStart.month, periodStart.day).toIso8601String(),
      'category_id': categoryId,
      'category_name': categoryName,
      'budget_limit': budgetLimit,
    };
  }

  factory BudgetSnapshot.fromMap(Map<String, dynamic> map) {
    final ps = DateTime.parse(map['period_start'] as String);
    final p = DateTime(ps.year, ps.month, ps.day);
    return BudgetSnapshot(
      id: map['id'] as int?,
      periodStart: p,
      categoryId: map['category_id'] as int,
      categoryName: map['category_name'] as String,
      budgetLimit: (map['budget_limit'] as num).toDouble(),
    );
  }
}
