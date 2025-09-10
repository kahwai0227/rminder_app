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
