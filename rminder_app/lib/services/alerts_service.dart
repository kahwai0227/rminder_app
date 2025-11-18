import 'package:flutter/material.dart';
import '../db/rminder_database.dart';
import 'notification_service.dart';

class AlertsService {
  AlertsService._();

  static const _nearThreshold = 0.9; // 90%
  static const _settingsEnabledKey = 'notifications_enabled';
  static const _lastAlertsRunKey = 'notif_last_run_day';

  // Public entry point: check current active period and notify
  static Future<void> checkAndNotify() async {
    final enabled = await _isEnabled();
    if (!enabled) return;

    final db = RMinderDatabase.instance;
    final start = await db.getActivePeriodStart() ?? _today();
    final startDay = DateTime(start.year, start.month, start.day);
    final endExclusive = _today().add(const Duration(days: 1));

    final categories = await db.getCategories();
    final transactions = await db.getTransactions();
    final liabilities = await db.getAllLiabilities(); // include archived
    final funds = await db.getSinkingFunds();

    final debtCatIds = liabilities.map((l) => l.budgetCategoryId).toSet();
    final fundCatIds = funds.where((f) => f.budgetCategoryId != null).map((f) => f.budgetCategoryId!).toSet();

    // Compute per-category spend in active period (positive amounts only)
    final Map<int, double> periodSpent = {};
    for (final t in transactions) {
      if (!t.date.isBefore(startDay) && t.date.isBefore(endExclusive) && t.amount > 0) {
        periodSpent.update(t.categoryId, (v) => v + t.amount, ifAbsent: () => t.amount);
      }
    }

    // Gate: once per day to avoid spamming
    final todayStr = _isoDate(_today());
    final lastRun = await db.getSetting(_lastAlertsRunKey);
    final alreadyRanToday = lastRun == todayStr;

    // Alerts
    if (!alreadyRanToday) {
      for (final c in categories) {
        if (c.id == null) continue;
        if (c.budgetLimit <= 0) continue;
        if (debtCatIds.contains(c.id!) || fundCatIds.contains(c.id!)) continue; // skip debts/funds
        final spent = periodSpent[c.id!] ?? 0.0;
        if (spent > c.budgetLimit + 0.001) {
          await NotificationService.instance.show(
            id: 2000 + c.id!,
            title: 'Over budget: ${c.name}',
            body: 'Spent ₹${spent.toStringAsFixed(2)} (limit ₹${c.budgetLimit.toStringAsFixed(2)}).',
          );
        } else if (spent >= (_nearThreshold * c.budgetLimit)) {
          await NotificationService.instance.show(
            id: 1000 + c.id!,
            title: 'Almost there: ${c.name}',
            body: 'You\'ve used ₹${spent.toStringAsFixed(2)} of ₹${c.budgetLimit.toStringAsFixed(2)}.',
          );
        }
      }
      await db.setSetting(_lastAlertsRunKey, todayStr);
    }

    // Remind to record spending if there were no transactions in last 3 days
    final threeDaysAgo = _today().subtract(const Duration(days: 3));
    final hadRecent = transactions.any((t) => t.amount > 0 && !t.date.isBefore(threeDaysAgo));
    if (!hadRecent) {
      await NotificationService.instance.show(
        id: 3001,
        title: 'Record your spending',
        body: 'No recent activity detected. Add your latest expenses now.',
      );
    }
  }

  static Future<void> scheduleDailyRecordReminder() async {
    final enabled = await _isEnabled();
    if (!enabled) return;
    await NotificationService.instance.scheduleDailyReminder(
      id: 3000,
      time: const TimeOfDay(hour: 20, minute: 0),
      title: 'Daily spending check',
      body: 'Take a moment to log your spending for today.',
    );
  }

  static Future<bool> _isEnabled() async {
    final v = await RMinderDatabase.instance.getSetting(_settingsEnabledKey);
    if (v == null) return true; // default ON
    return v == '1' || v.toLowerCase() == 'true';
  }

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static String _isoDate(DateTime d) => DateTime(d.year, d.month, d.day).toIso8601String();
}
