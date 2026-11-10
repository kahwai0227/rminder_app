import '../models/models.dart' as models;

class StatementRecord {
  final DateTime date;
  final double amount;
  final String description;
  final String source;

  const StatementRecord({
    required this.date,
    required this.amount,
    required this.description,
    required this.source,
  });
}

class ReconciliationReport {
  final List<StatementRecord> missingInApp;
  final List<models.Transaction> missingInStatement;

  const ReconciliationReport({
    required this.missingInApp,
    required this.missingInStatement,
  });
}

class StatementParseException implements Exception {
  final String message;

  const StatementParseException(this.message);

  @override
  String toString() => 'StatementParseException: $message';
}

List<StatementRecord> parseStatementCsv(
  String csvContent, {
  String source = 'statement',
}) {
  final lines = csvContent
      .split(RegExp(r'\r?\n'))
      .where((line) => line.trim().isNotEmpty)
      .toList();

  if (lines.length < 2) {
    return const [];
  }

  final header = _parseCsvLine(lines.first)
      .map((value) => value.trim().toLowerCase())
      .toList();

  final dateIndex = _findColumn(header, const ['date', 'transaction date', 'posted date']);
  if (dateIndex == null) {
    throw const StatementParseException('Missing date column.');
  }

  final amountIndex = _findColumn(header, const ['amount', 'amt', 'value']);
  final debitIndex = _findColumn(header, const ['debit', 'withdrawal', 'outflow']);
  final creditIndex = _findColumn(header, const ['credit', 'deposit', 'inflow']);

  if (amountIndex == null && debitIndex == null && creditIndex == null) {
    throw const StatementParseException('Missing amount/debit/credit column.');
  }

  final descriptionIndex = _findColumn(
    header,
    const ['description', 'details', 'merchant', 'note', 'transaction'],
  );

  final result = <StatementRecord>[];
  for (var i = 1; i < lines.length; i++) {
    final row = _parseCsvLine(lines[i]);
    if (row.every((cell) => cell.trim().isEmpty)) {
      continue;
    }

    final dateCell = dateIndex < row.length ? row[dateIndex].trim() : '';
    final parsedDate = _parseFlexibleDate(dateCell);
    if (parsedDate == null) {
      continue;
    }

    double? amount;
    if (amountIndex != null && amountIndex < row.length) {
      amount = _parseAmount(row[amountIndex]);
    } else {
      final debit = (debitIndex != null && debitIndex < row.length)
          ? (_parseAmount(row[debitIndex]) ?? 0)
          : 0;
      final credit = (creditIndex != null && creditIndex < row.length)
          ? (_parseAmount(row[creditIndex]) ?? 0)
          : 0;
      amount = debit - credit;
    }

    if (amount == null) {
      continue;
    }

    final description = (descriptionIndex != null && descriptionIndex < row.length)
        ? row[descriptionIndex].trim()
        : '';

    result.add(
      StatementRecord(
        date: DateTime(parsedDate.year, parsedDate.month, parsedDate.day),
        amount: amount,
        description: description,
        source: source,
      ),
    );
  }

  return result;
}

ReconciliationReport reconcileTransactions({
  required Iterable<StatementRecord> statementRecords,
  required Iterable<models.Transaction> appTransactions,
}) {
  final statementMap = <String, List<StatementRecord>>{};
  for (final record in statementRecords) {
    statementMap.putIfAbsent(_key(record.date, record.amount), () => <StatementRecord>[]).add(record);
  }

  final appMap = <String, List<models.Transaction>>{};
  for (final txn in appTransactions) {
    appMap
        .putIfAbsent(
          _key(txn.date, txn.amount),
          () => <models.Transaction>[],
        )
        .add(txn);
  }

  final missingInApp = <StatementRecord>[];
  final missingInStatement = <models.Transaction>[];

  final allKeys = {...statementMap.keys, ...appMap.keys};
  for (final key in allKeys) {
    final statementList = statementMap[key] ?? const <StatementRecord>[];
    final appList = appMap[key] ?? const <models.Transaction>[];
    if (statementList.length > appList.length) {
      missingInApp.addAll(statementList.skip(appList.length));
    } else if (appList.length > statementList.length) {
      missingInStatement.addAll(appList.skip(statementList.length));
    }
  }

  return ReconciliationReport(
    missingInApp: missingInApp,
    missingInStatement: missingInStatement,
  );
}

String _key(DateTime date, double amount) {
  final d = DateTime(date.year, date.month, date.day).toIso8601String();
  final cents = (amount * 100).round();
  return '$d|$cents';
}

int? _findColumn(List<String> header, List<String> aliases) {
  for (final alias in aliases) {
    final idx = header.indexOf(alias);
    if (idx >= 0) return idx;
  }
  return null;
}

DateTime? _parseFlexibleDate(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;

  final direct = DateTime.tryParse(trimmed);
  if (direct != null) return direct;

  final m = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$').firstMatch(trimmed);
  if (m == null) return null;

  final p1 = int.parse(m.group(1)!);
  final p2 = int.parse(m.group(2)!);
  var year = int.parse(m.group(3)!);
  if (year < 100) year += 2000;

  final monthFirstCandidate = DateTime.tryParse(
    '${year.toString().padLeft(4, '0')}-${p1.toString().padLeft(2, '0')}-${p2.toString().padLeft(2, '0')}',
  );
  final dayFirstCandidate = DateTime.tryParse(
    '${year.toString().padLeft(4, '0')}-${p2.toString().padLeft(2, '0')}-${p1.toString().padLeft(2, '0')}',
  );

  if (monthFirstCandidate != null && p1 > 12) {
    return dayFirstCandidate;
  }
  if (dayFirstCandidate != null && p2 > 12) {
    return monthFirstCandidate;
  }

  return monthFirstCandidate ?? dayFirstCandidate;
}

double? _parseAmount(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;

  var normalized = trimmed
      .replaceAll(RegExp(r'[,\s]'), '')
      .replaceAll(RegExp(r'^[A-Za-z$£€¥RM]+'), '');
  if (normalized.startsWith('(') && normalized.endsWith(')')) {
    normalized = '-${normalized.substring(1, normalized.length - 1)}';
  }
  return double.tryParse(normalized);
}

List<String> _parseCsvLine(String line) {
  final values = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;

  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        buffer.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }
    if (char == ',' && !inQuotes) {
      values.add(buffer.toString());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  values.add(buffer.toString());
  return values;
}
