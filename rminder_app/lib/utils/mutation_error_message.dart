import 'dart:async';

import 'package:sqflite/sqflite.dart';

String mutationFailureMessage(
  Object error, {
  required String fallback,
}) {
  if (error is DatabaseException) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('database is locked')) {
      return 'Database is busy. Please try again.';
    }
    if (raw.contains('unique constraint')) {
      return 'This would create a duplicate record.';
    }
    if (raw.contains('foreign key')) {
      return 'Related data is missing. Refresh and try again.';
    }
    if (raw.contains('not null constraint')) {
      return 'Required data is missing. Please check your input.';
    }
  }

  if (error is TimeoutException) {
    return 'The operation timed out. Please try again.';
  }

  return fallback;
}
