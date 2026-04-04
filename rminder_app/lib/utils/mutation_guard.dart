import 'package:flutter/material.dart';

import 'logger.dart';
import 'mutation_error_message.dart';

Future<bool> runGuardedMutation({
  required BuildContext context,
  required Future<void> Function() action,
  required String failureMessage,
  Future<void> Function()? onSuccess,
}) async {
  try {
    await action();
    if (!context.mounted) return true;
    if (onSuccess != null) {
      await onSuccess();
    }
    return true;
  } catch (e, st) {
    logError(e, st);
    if (!context.mounted) return false;
    final message = mutationFailureMessage(e, fallback: failureMessage);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
    return false;
  }
}
