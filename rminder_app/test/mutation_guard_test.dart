import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rminder_app/utils/mutation_guard.dart';

void main() {
  testWidgets('runGuardedMutation runs onSuccess when action succeeds', (tester) async {
    late BuildContext context;
    var onSuccessCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              context = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final result = await runGuardedMutation(
      context: context,
      failureMessage: 'Failed action.',
      action: () async {},
      onSuccess: () async {
        onSuccessCalled = true;
      },
    );

    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(onSuccessCalled, isTrue);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('runGuardedMutation shows fallback message for unknown errors', (tester) async {
    late BuildContext context;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              context = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final result = await runGuardedMutation(
      context: context,
      failureMessage: 'Failed to save record.',
      action: () async {
        throw Exception('boom');
      },
    );

    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(find.text('Failed to save record.'), findsOneWidget);
  });

  testWidgets('runGuardedMutation shows timeout-specific message', (tester) async {
    late BuildContext context;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              context = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final result = await runGuardedMutation(
      context: context,
      failureMessage: 'Fallback text.',
      action: () async {
        throw TimeoutException('too slow');
      },
    );

    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(find.text('The operation timed out. Please try again.'), findsOneWidget);
  });
}
