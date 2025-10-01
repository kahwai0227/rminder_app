import 'package:flutter/foundation.dart';

class UiIntents {
  static final ValueNotifier<int?> editLiabilityId = ValueNotifier<int?>(null);
  // Fire-and-forget event counter: increment to request a Close Period flow.
  static final ValueNotifier<int> closePeriodEvent = ValueNotifier<int>(0);
  // Fire-and-forget event counter: increment when categories are added/renamed/deleted
  // so listeners (e.g., Transactions page) can refresh their category lists.
  static final ValueNotifier<int> categoriesChangedEvent = ValueNotifier<int>(0);
}
