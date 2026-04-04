import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rminder_app/utils/mutation_error_message.dart';

void main() {
  test('returns timeout message for TimeoutException', () {
    final message = mutationFailureMessage(
      TimeoutException('took too long'),
      fallback: 'Fallback message',
    );

    expect(message, 'The operation timed out. Please try again.');
  });

  test('returns fallback for unknown errors', () {
    const fallback = 'Something went wrong.';
    final message = mutationFailureMessage(Exception('unknown'), fallback: fallback);

    expect(message, fallback);
  });
}
