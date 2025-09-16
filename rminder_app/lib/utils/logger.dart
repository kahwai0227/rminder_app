import 'dart:developer' as developer;

void logError(Object error, [StackTrace? stackTrace]) {
  developer.log('ERROR: $error', name: 'RMinderApp');
  if (stackTrace != null) developer.log(stackTrace.toString(), name: 'RMinderApp');
}
