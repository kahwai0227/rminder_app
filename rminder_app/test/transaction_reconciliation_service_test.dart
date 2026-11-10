import 'package:flutter_test/flutter_test.dart';
import 'package:rminder_app/models/models.dart' as models;
import 'package:rminder_app/services/transaction_reconciliation_service.dart';

void main() {
  test('parseStatementCsv parses amount and quoted description columns', () {
    const csv = '''
Date,Amount,Description
2026-11-01,12.40,"Coffee, Latte"
2026-11-02,-5.00,Refund
''';

    final records = parseStatementCsv(csv, source: 'bank');

    expect(records, hasLength(2));
    expect(records[0].date, DateTime(2026, 11, 1));
    expect(records[0].amount, 12.40);
    expect(records[0].description, 'Coffee, Latte');
    expect(records[0].source, 'bank');
    expect(records[1].amount, -5.00);
  });

  test('parseStatementCsv supports debit and credit fallback columns', () {
    const csv = '''
Transaction Date,Debit,Credit,Details
01/11/2026,20.50,,Lunch
02/11/2026,,5.25,Cashback
''';

    final records = parseStatementCsv(csv, source: 'ewallet');

    expect(records, hasLength(2));
    expect(records[0].amount, 20.50);
    expect(records[1].amount, -5.25);
    expect(records[1].description, 'Cashback');
  });

  test('reconcileTransactions flags missing statement and app records', () {
    final statementRecords = <StatementRecord>[
      StatementRecord(
        date: DateTime(2026, 11, 1),
        amount: 12.4,
        description: 'Coffee',
        source: 'bank',
      ),
      StatementRecord(
        date: DateTime(2026, 11, 2),
        amount: 9.9,
        description: 'Taxi',
        source: 'bank',
      ),
      StatementRecord(
        date: DateTime(2026, 11, 2),
        amount: 9.9,
        description: 'Taxi duplicate',
        source: 'bank',
      ),
    ];

    final appTransactions = <models.Transaction>[
      models.Transaction(
        categoryId: 1,
        amount: 12.4,
        date: DateTime(2026, 11, 1, 10),
      ),
      models.Transaction(
        categoryId: 1,
        amount: 3.5,
        date: DateTime(2026, 11, 3, 9),
      ),
      models.Transaction(
        categoryId: 1,
        amount: 9.9,
        date: DateTime(2026, 11, 2, 8),
      ),
    ];

    final report = reconcileTransactions(
      statementRecords: statementRecords,
      appTransactions: appTransactions,
    );

    expect(report.missingInApp, hasLength(1));
    expect(report.missingInApp.single.description, 'Taxi duplicate');
    expect(report.missingInStatement, hasLength(1));
    expect(report.missingInStatement.single.amount, 3.5);
  });
}
