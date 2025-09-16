import 'package:flutter/foundation.dart';

/// Global app state (placeholder for now).
///
/// We introduce this as a ChangeNotifier so we can expand later without
/// changing the widget tree. Screens can continue to read directly from the
/// database for now while we migrate incrementally.
class AppState extends ChangeNotifier {
  // Future extension: selected month, theme, cached data, etc.
}
