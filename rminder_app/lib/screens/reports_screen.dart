import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../db/rminder_database.dart';
import '../models/models.dart' as models;
import '../utils/logger.dart';
import '../widgets/charts.dart';
import '../utils/ui_intents.dart';
import '../utils/currency_input_formatter.dart';
import '../services/period_service.dart';
import '../services/notification_service.dart';
import '../services/alerts_service.dart';
import '../services/overview_input_selector_service.dart';
import '../services/overview_metrics_service.dart';
import '../widgets/compact_cards.dart';
import 'user_guide.dart' show showUserGuide;

class ReportingPage extends StatefulWidget {
  const ReportingPage({super.key});
  @override
  State<ReportingPage> createState() => _ReportingPageState();
}

class _OverviewStat extends StatelessWidget {
  final String title;
  final double amount;
  final Color color;

  const _OverviewStat({
    required this.title,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(title, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          '₹${amount.toStringAsFixed(2)}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _PeriodComparisonTotals {
  final double spending;
  final double debtPaid;
  final double savingsContributed;

  const _PeriodComparisonTotals({
    required this.spending,
    required this.debtPaid,
    required this.savingsContributed,
  });
}

class _PeriodTrendPoint {
  final DateTime periodStart;
  final _PeriodComparisonTotals totals;

  const _PeriodTrendPoint({required this.periodStart, required this.totals});
}

class _PeriodComparisonLineChart extends StatelessWidget {
  final List<_PeriodTrendPoint> points;

  const _PeriodComparisonLineChart({required this.points});

  LineChartBarData _buildSeries({
    required List<_PeriodTrendPoint> points,
    required double Function(_PeriodComparisonTotals totals) valueOf,
    required Color color,
  }) {
    return LineChartBarData(
      spots: [
        for (var i = 0; i < points.length; i++)
          FlSpot(i.toDouble(), valueOf(points[i].totals)),
      ],
      isCurved: true,
      color: color,
      barWidth: 2.5,
      dotData: const FlDotData(show: true),
    );
  }

  String _shortLabel(DateTime d) => '${d.day}/${d.month}';

  String _metricLine(String label, double value) {
    final left = label.padRight(9);
    final amount = '\$${value.toStringAsFixed(2)}'.padLeft(12);
    return '$left: $amount';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (points.isEmpty) {
      return const Text('No period data available yet.');
    }

    final maxY = points
        .expand(
          (p) => [
            p.totals.spending,
            p.totals.debtPaid,
            p.totals.savingsContributed,
          ],
        )
        .fold<double>(0, (m, v) => v > m ? v : m);
    final chartMaxY = maxY <= 0 ? 1.0 : (maxY * 1.2);
    final showEvery = points.length <= 5
        ? 1
        : points.length <= 8
        ? 2
        : 3;

    final spendingColor = theme.colorScheme.error;
    final debtColor = theme.colorScheme.primary;
    final savingsColor = theme.colorScheme.tertiary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 240,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (points.length - 1).toDouble(),
              minY: 0,
              maxY: chartMaxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: chartMaxY / 4,
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(
                  left: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.5),
                  ),
                  bottom: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.5),
                  ),
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (value, meta) => Text(
                      '₹${value.toStringAsFixed(0)}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    reservedSize: 28,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= points.length)
                        return const SizedBox.shrink();
                      final shouldShow =
                          idx == 0 ||
                          idx == points.length - 1 ||
                          idx % showEvery == 0;
                      if (!shouldShow) return const SizedBox.shrink();
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(
                          _shortLabel(points[idx].periodStart),
                          style: theme.textTheme.labelSmall,
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  maxContentWidth: 280,
                  tooltipBorderRadius: BorderRadius.circular(12),
                  tooltipPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  tooltipMargin: 12,
                  getTooltipColor: (_) => const Color(0xFF111827),
                  getTooltipItems: (spots) {
                    final valueStyle =
                        theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                          height: 1.35,
                        ) ??
                        const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                          height: 1.35,
                        );

                    final valuesByIndex = <int, double>{
                      for (final spot in spots) spot.barIndex: spot.y,
                    };

                    return spots.asMap().entries.map((entry) {
                      final rowIndex = entry.key;
                      final spot = entry.value;
                      final idx = spot.x.toInt();
                      if (rowIndex > 0) {
                        return null;
                      }

                      final dateHeader =
                          '${_shortLabel(points[idx].periodStart)}\n';
                      final spending = _metricLine(
                        'Spending',
                        valuesByIndex[0] ?? 0,
                      );
                      final debtPaid = _metricLine(
                        'Debt paid',
                        valuesByIndex[1] ?? 0,
                      );
                      final savings = _metricLine(
                        'Savings',
                        valuesByIndex[2] ?? 0,
                      );

                      return LineTooltipItem(
                        '$dateHeader$spending\n$debtPaid\n$savings',
                        valueStyle,
                        textAlign: TextAlign.left,
                      );
                    }).toList();
                  },
                ),
              ),
              lineBarsData: [
                _buildSeries(
                  points: points,
                  valueOf: (t) => t.spending,
                  color: spendingColor,
                ),
                _buildSeries(
                  points: points,
                  valueOf: (t) => t.debtPaid,
                  color: debtColor,
                ),
                _buildSeries(
                  points: points,
                  valueOf: (t) => t.savingsContributed,
                  color: savingsColor,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _legend(theme, spendingColor, 'Spending'),
            _legend(theme, debtColor, 'Debt paid'),
            _legend(theme, savingsColor, 'Savings'),
          ],
        ),
      ],
    );
  }

  Widget _legend(ThemeData theme, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.labelMedium),
      ],
    );
  }
}

// Legacy CloseAction and local close flow have been removed in favor of PeriodService

class _ReportingPageState extends State<ReportingPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  AppState get _appState => Provider.of<AppState>(context, listen: false);
  List<models.BudgetCategory> get categories =>
      _appState.categories.where((c) => c.inBudget).toList();
  List<models.Transaction> get transactions => _appState.transactions;
  List<models.Liability> get liabilities => _appState.liabilities;
  List<models.SinkingFund> get sinkingFunds => _appState.sinkingFunds;
  List<models.IncomeSource> get incomeSources => _appState.incomeSources;
  DateTime? get _activePeriodStart => _appState.activePeriodStart;

  DateTime selectedMonth = DateTime.now();
  double _activeCarryIncome =
      0.0; // One-time carry-forward income for active period
  List<DateTime> _closedMonths = [];
  // Map of period start date -> actual closed-at date (both truncated to date)
  final Map<DateTime, DateTime> _closedAtByStart = {};
  // Snapshots of budgets per closed period: periodStart -> (categoryId -> snapshot)
  final Map<DateTime, Map<int, models.BudgetSnapshot>> _snapshotsByPeriod = {};
  // Sum of income snapshots per closed period (periodStart -> total income)
  final Map<DateTime, double> _incomeSumByPeriod = {};
  // Spending snapshots per closed period: periodStart -> (categoryId -> spent)
  final Map<DateTime, Map<int, double>> _spendingByPeriod = {};
  // Liability snapshots per closed period
  final Map<DateTime, List<models.LiabilitySnapshot>> _liabSnapsByPeriod = {};
  // Fund snapshots per closed period
  final Map<DateTime, List<models.FundSnapshot>> _fundSnapsByPeriod = {};
  bool _isDetailsDialogOpen = false;
  final ScrollController _reportScroll = ScrollController();
  // Periods are anchored by last close; no static reset day.

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadActivePeriod();
    _maybeBackfillSnapshots();
    _maybeBackfillIncomeSnapshots();
    // Listen for global Close Period events (triggered from other pages' menus)
    UiIntents.closePeriodEvent.addListener(_maybeHandleClosePeriodIntent);
  }

  @override
  void dispose() {
    UiIntents.closePeriodEvent.removeListener(_maybeHandleClosePeriodIntent);
    _reportScroll.dispose();
    super.dispose();
  }

  void _maybeHandleClosePeriodIntent() {
    // Debounce by posting to next frame to avoid re-entrancy
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Use the global close flow so behavior matches other pages
      await PeriodService.closeActivePeriod(context);
      // Refresh local data after closing
      await _loadData();
      await _loadActivePeriod();
    });
  }

  // Period start for a given anchor (truncate to date)
  DateTime _periodStartFor(DateTime anchor) {
    // For the active period, keep the exact start timestamp (may include time of day)
    if (!_isClosedPeriod(anchor) &&
        _activePeriodStart != null &&
        _sameDay(anchor, _activePeriodStart!)) {
      return _activePeriodStart!;
    }
    return DateTime(anchor.year, anchor.month, anchor.day);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isClosedPeriod(DateTime start) {
    return _closedMonths.any((d) => _sameDay(d, start));
  }

  List<_PeriodTrendPoint> _periodComparisonHistory({
    required DateTime selectedStart,
    int maxPeriods = 10,
  }) {
    final allowed = _allowedPeriods(); // newest first
    if (allowed.isEmpty) return const [];

    final idx = allowed.indexWhere((d) => _sameDay(d, selectedStart));
    final windowNewestFirst = idx == -1
        ? allowed.take(maxPeriods).toList()
        : allowed.skip(idx).take(maxPeriods).toList();

    return windowNewestFirst
        .map((anchor) {
          final start = _periodStartFor(anchor);
          return _PeriodTrendPoint(
            periodStart: start,
            totals: _totalsForPeriod(start),
          );
        })
        .toList()
        .reversed
        .toList();
  }

  _PeriodComparisonTotals _totalsForPeriod(DateTime periodStart) {
    final periodKey = DateTime(
      periodStart.year,
      periodStart.month,
      periodStart.day,
    );
    final isClosed = _isClosedPeriod(periodStart);

    if (isClosed) {
      final snapshots =
          _snapshotsByPeriod[periodKey] ?? const <int, models.BudgetSnapshot>{};
      final spendingMap = _spendingByPeriod[periodKey] ?? const <int, double>{};
      final debtCategoryIds =
          (_liabSnapsByPeriod[periodKey] ?? const <models.LiabilitySnapshot>[])
              .map((s) => s.categoryId)
              .toSet();
      final fundCategoryIds =
          (_fundSnapsByPeriod[periodKey] ?? const <models.FundSnapshot>[])
              .where((s) => s.categoryId != null)
              .map((s) => s.categoryId!)
              .toSet();

      double spending = 0;
      for (final s in snapshots.values) {
        if (debtCategoryIds.contains(s.categoryId) ||
            fundCategoryIds.contains(s.categoryId)) {
          continue;
        }
        spending += spendingMap[s.categoryId] ?? 0;
      }

      final debtPaid =
          (_liabSnapsByPeriod[periodKey] ?? const <models.LiabilitySnapshot>[])
              .fold<double>(0, (sum, s) => sum + s.paid);
      final savingsContributed =
          (_fundSnapsByPeriod[periodKey] ?? const <models.FundSnapshot>[])
              .fold<double>(0, (sum, s) => sum + s.contributed);

      return _PeriodComparisonTotals(
        spending: spending,
        debtPaid: debtPaid,
        savingsContributed: savingsContributed,
      );
    }

    final periodEndExclusive = _periodUpperBoundExclusive(periodStart);
    final periodLiabs = _liabilitiesForPeriod();
    final debtCategoryIds = periodLiabs.map((l) => l.budgetCategoryId).toSet();
    final fundCategoryIds = sinkingFunds
        .where((f) => f.budgetCategoryId != null)
        .map((f) => f.budgetCategoryId!)
        .toSet();

    final selection = selectActiveOverviewSelection(
      categories: categories,
      transactions: transactions,
      liabilities: periodLiabs,
      sinkingFunds: sinkingFunds,
      periodStart: periodStart,
      periodEndExclusive: periodEndExclusive,
    );

    final spending = selection.spentByCategory.values.fold<double>(
      0,
      (sum, v) => sum + v,
    );

    double debtPaid = 0;
    double savingsContributed = 0;
    for (final t in transactions) {
      final inPeriod =
          !t.date.isBefore(periodStart) && t.date.isBefore(periodEndExclusive);
      if (!inPeriod) continue;
      if (debtCategoryIds.contains(t.categoryId)) {
        debtPaid += t.amount;
      }
      if (fundCategoryIds.contains(t.categoryId) && t.amount > 0) {
        savingsContributed += t.amount;
      }
    }

    return _PeriodComparisonTotals(
      spending: spending,
      debtPaid: debtPaid,
      savingsContributed: savingsContributed,
    );
  }

  // Upper bound (exclusive) for the selected period using actual close date for closed periods.
  DateTime _periodUpperBoundExclusive(DateTime start) {
    if (_isClosedPeriod(start)) {
      final key = DateTime(start.year, start.month, start.day);
      final ca = _closedAtByStart[key];
      if (ca != null) {
        // Use the actual close timestamp as the exclusive upper bound to split transactions precisely.
        return ca;
      }
      return DateTime(start.year, start.month + 1, start.day);
    }
    // Active period: include everything up to "now"
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  }

  String _shortMon(int m) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[m - 1];
  }

  String _formatDayMon(DateTime d, {bool withYear = false}) {
    final date = DateTime(d.year, d.month, d.day);
    final base = '${date.day} ${_shortMon(date.month)}';
    return withYear ? '$base ${date.year}' : base;
  }

  String _formatPeriodRange(DateTime start) {
    final s = DateTime(start.year, start.month, start.day);
    final endExclusive = _periodUpperBoundExclusive(s);
    // For closed periods, endExclusive is the exact timestamp when closed.
    // For display, we want the date portion of that timestamp.
    // For active periods, endExclusive is midnight of (today+1), so we subtract 1 day.
    DateTime endInclusive;
    if (_isClosedPeriod(s)) {
      // Use the date of the close timestamp (e.g., Oct 16 7pm -> Oct 16)
      endInclusive = DateTime(
        endExclusive.year,
        endExclusive.month,
        endExclusive.day,
      );
    } else {
      // Active period: endExclusive is tomorrow's midnight, so subtract 1 day to get today
      endInclusive = endExclusive.subtract(const Duration(days: 1));
    }
    final withYear = s.year != endInclusive.year;
    return '${_formatDayMon(s, withYear: withYear)} – ${_formatDayMon(endInclusive, withYear: withYear)}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final appState = Provider.of<AppState>(context);
    if (appState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final ps = _periodStartFor(selectedMonth);
    final isClosed = _isClosedPeriod(ps);
    final snaps = isClosed
        ? _snapshotsByPeriod[DateTime(ps.year, ps.month, ps.day)]
        : null;
    final useSnaps = snaps != null && snaps.isNotEmpty;
    final snapshotValues = snaps?.values ?? const <models.BudgetSnapshot>[];

    // Income for this period: snapshot sum for closed, else current income sources (+carry-forward for active period)
    final double periodIncome = isClosed
        ? (_incomeSumByPeriod[DateTime(ps.year, ps.month, ps.day)] ?? 0.0)
        : incomeSources.fold<double>(0, (s, i) => s + i.amount) +
              ((_activePeriodStart != null && _sameDay(ps, _activePeriodStart!))
                  ? _activeCarryIncome
                  : 0.0);

    // Determine debt/fund category ids
    final periodLiabs = _liabilitiesForPeriod();
    Set<int> debtCatIds = periodLiabs.map((l) => l.budgetCategoryId).toSet();
    Set<int> fundCatIds = sinkingFunds
        .where((f) => f.budgetCategoryId != null)
        .map((f) => f.budgetCategoryId!)
        .toSet();
    if (isClosed) {
      final key = DateTime(ps.year, ps.month, ps.day);
      final ls = _liabSnapsByPeriod[key] ?? const [];
      final fs = _fundSnapsByPeriod[key] ?? const [];
      debtCatIds = ls.map((s) => s.categoryId).toSet();
      fundCatIds = fs
          .where((s) => s.categoryId != null)
          .map((s) => s.categoryId!)
          .toSet();
    }

    // Base category budgets (excluding debt and fund categories)
    final double baseCategoryBudget = useSnaps
        ? snapshotValues
              .where(
                (x) =>
                    !debtCatIds.contains(x.categoryId) &&
                    !fundCatIds.contains(x.categoryId),
              )
              .fold<double>(0, (s, x) => s + x.budgetLimit)
        : categories
              .where(
                (c) =>
                    c.id != null &&
                    !debtCatIds.contains(c.id!) &&
                    !fundCatIds.contains(c.id!),
              )
              .fold<double>(0, (s, c) => s + c.budgetLimit);

    // Planned debt payments: use snapshots for closed periods
    double plannedDebt = 0;
    if (isClosed) {
      final key = DateTime(ps.year, ps.month, ps.day);
      for (final s in (_liabSnapsByPeriod[key] ?? const [])) {
        plannedDebt += s.planned;
      }
    } else {
      for (final liab in periodLiabs) {
        plannedDebt += liab.planned;
      }
    }

    // Planned fund contributions
    double plannedFunds = 0;
    if (isClosed) {
      final key = DateTime(ps.year, ps.month, ps.day);
      for (final s in (_fundSnapsByPeriod[key] ?? const [])) {
        plannedFunds += s.monthlyContribution;
      }
    } else {
      for (final fund in sinkingFunds) {
        plannedFunds += fund.monthlyContribution;
      }
    }

    // Actual extras beyond plan (sum positive per-item deltas)
    double extraDebt = 0;
    double extraFunds = 0;
    if (isClosed) {
      final key = DateTime(ps.year, ps.month, ps.day);
      for (final s in (_liabSnapsByPeriod[key] ?? const [])) {
        final over = s.paid - s.planned;
        if (over > 0) extraDebt += over;
      }
      for (final s in (_fundSnapsByPeriod[key] ?? const [])) {
        final over = s.contributed - s.monthlyContribution;
        if (over > 0) extraFunds += over;
      }
    } else {
      for (final liab in periodLiabs) {
        final paid = _paidThisMonthFor(liab);
        final over = paid - liab.planned;
        if (over > 0) extraDebt += over;
      }
      for (final fund in sinkingFunds) {
        final contrib = _contributedThisMonthFor(fund);
        final over = contrib - fund.monthlyContribution;
        if (over > 0) extraFunds += over;
      }
    }

    // Totals per formula
    final double totalBudget = baseCategoryBudget + plannedDebt + plannedFunds;
    final double unallocated =
        periodIncome - totalBudget - extraDebt - extraFunds;

    // Removed: Unspent amount (redundant)

    // Build breakdown list for chart
    final breakdownList = useSnaps
        ? snapshotValues
              .map(
                (s) => CategoryBreakdown(
                  name: s.categoryName,
                  spent: 0,
                  limit: s.budgetLimit,
                  categoryId: s.categoryId,
                ),
              )
              .toList()
        : categories
              .map(
                (c) => CategoryBreakdown(
                  name: c.name,
                  spent: 0,
                  limit: c.budgetLimit,
                  categoryId: c.id,
                ),
              )
              .toList();

    // Spending by category for the selected period (exclude debt and funds categories)
    final start = _periodStartFor(selectedMonth);
    final end = _periodUpperBoundExclusive(start);
    final spendingList =
        isClosed
              ? snapshotValues
                    .where(
                      (x) =>
                          !debtCatIds.contains(x.categoryId) &&
                          !fundCatIds.contains(x.categoryId),
                    )
                    .map(
                      (s) => CategoryBreakdown(
                        name: s.categoryName,
                        spent:
                            (_spendingByPeriod[DateTime(
                                  ps.year,
                                  ps.month,
                                  ps.day,
                                )] ??
                                const {})[s.categoryId] ??
                            0.0,
                        limit: s.budgetLimit,
                        categoryId: s.categoryId,
                      ),
                    )
                    .toList()
              : (() {
                  final selection = selectActiveOverviewSelection(
                    categories: categories,
                    transactions: transactions,
                    liabilities: periodLiabs,
                    sinkingFunds: sinkingFunds,
                    periodStart: start,
                    periodEndExclusive: end,
                  );

                  return selection.categories
                      .map(
                        (c) => CategoryBreakdown(
                          name: c.name,
                          spent: selection.spentByCategory[c.id!] ?? 0.0,
                          limit: c.budgetLimit,
                          categoryId: c.id,
                        ),
                      )
                      .toList();
                })()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );

    final overviewMetrics = calculateOverviewMetrics(
      spendingList.map(
        (c) => OverviewMetricItem(planned: c.limit, spent: c.spent),
      ),
    );
    final comparisonHistory = _periodComparisonHistory(
      selectedStart: ps,
      maxPeriods: 10,
    );
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Report'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'close',
                child: ListTile(
                  leading: Icon(Icons.task_alt),
                  title: Text('Close period'),
                ),
              ),
              const PopupMenuItem(
                value: 'notif_enable',
                child: ListTile(
                  leading: Icon(Icons.notification_important),
                  title: Text('Enable notifications'),
                ),
              ),
              if (isClosed)
                const PopupMenuItem(
                  value: 'edit_budget',
                  child: ListTile(
                    leading: Icon(Icons.tune),
                    title: Text('Edit period budget'),
                  ),
                ),
              if (isClosed)
                const PopupMenuItem(
                  value: 'edit_income',
                  child: ListTile(
                    leading: Icon(Icons.payments),
                    title: Text('Edit period income'),
                  ),
                ),
              if (isClosed)
                const PopupMenuItem(
                  value: 'reopen',
                  child: ListTile(
                    leading: Icon(Icons.lock_open),
                    title: Text('Reopen period'),
                  ),
                ),
              const PopupMenuItem(
                value: 'guide',
                child: ListTile(
                  leading: Icon(Icons.help_outline),
                  title: Text('User guide'),
                ),
              ),
            ],
            onSelected: (value) async {
              switch (value) {
                case 'close':
                  await PeriodService.closeActivePeriod(context);
                  break;
                case 'notif_enable':
                  await NotificationService.instance.init();
                  final ok = await NotificationService.instance
                      .requestPermissions();
                  if (!context.mounted) return;
                  if (!ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'Permission denied. Open system settings to enable notifications.',
                        ),
                        action: SnackBarAction(
                          label: 'Open',
                          onPressed: () =>
                              NotificationService.instance.openSystemSettings(),
                        ),
                      ),
                    );
                  } else {
                    await AlertsService.setEnabled(true);
                    await AlertsService.checkAndNotify();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Notifications enabled. You will be reminded about pending spending, debt, or savings actions.',
                        ),
                      ),
                    );
                  }
                  break;
                case 'edit_budget':
                  await _editBudgetForPeriodFlow();
                  break;
                case 'edit_income':
                  await _editIncomeForPeriodFlow();
                  break;
                case 'reopen':
                  await _reopenPeriodFlow();
                  break;
                case 'guide':
                  await showUserGuide(context);
                  break;
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: kCompactPagePadding,
        child: Scrollbar(
          controller: _reportScroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _reportScroll,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Period header and actions (responsive, avoids horizontal overflow)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Previous period',
                          icon: const Icon(Icons.chevron_left),
                          onPressed: _goToPreviousPeriod,
                        ),
                        Expanded(
                          child: Text(
                            _formatPeriodRange(ps),
                            style: theme.textTheme.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next period',
                          icon: const Icon(Icons.chevron_right),
                          onPressed: _goToNextPeriod,
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _showJumpToPeriod,
                          icon: const Icon(Icons.calendar_today),
                          label: const Text('Jump'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
                const SizedBox(height: kCompactSectionGap),

                // Overview dashboard (mirrors Budget screen style)
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primaryContainer.withValues(
                            alpha: 0.7,
                          ),
                          theme.colorScheme.surface,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Overview',
                                  style: compactSectionTitleStyle(context),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Income: ₹${periodIncome.toStringAsFixed(2)}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: overviewMetrics.isOverBudget
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.primary,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                overviewMetrics.isOverBudget
                                    ? 'Over Budget'
                                    : 'On Track',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _OverviewStat(
                              title: 'Planned',
                              amount: overviewMetrics.planned,
                              color: theme.colorScheme.primary,
                            ),
                            _OverviewStat(
                              title: 'Spent',
                              amount: overviewMetrics.spent,
                              color: theme.colorScheme.error,
                            ),
                            _OverviewStat(
                              title: 'Remaining',
                              amount: overviewMetrics.remaining,
                              color: theme.colorScheme.tertiary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: overviewMetrics.progress,
                            minHeight: 10,
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              overviewMetrics.isOverBudget
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: kCompactSectionGap),

                // Spending by Category
                if (spendingList.isEmpty)
                  const Center(
                    child: Text(
                      'No categories available. Add a category to view reports.',
                    ),
                  )
                else ...[
                  Text(
                    'Spending by Category',
                    style: compactSectionTitleStyle(context),
                  ),
                  const SizedBox(height: 6),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: spendingList.length,
                    itemBuilder: (context, index) {
                      final cat = spendingList[index];
                      final remaining = cat.limit - cat.spent;
                      return CompactItemCard(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 2,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      cat.name,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  Text(
                                    '₹${cat.spent.toStringAsFixed(0)} / ₹${cat.limit.toStringAsFixed(0)}',
                                    style: compactMutedStyle(context),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ThermometerBar(
                                value: cat.spent,
                                max: cat.limit <= 0 ? 1 : cat.limit,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Spent: ₹${cat.spent.toStringAsFixed(2)}',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  Text(
                                    'Remaining: ₹${remaining.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: remaining < 0
                                          ? theme.colorScheme.error
                                          : theme.colorScheme.tertiary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                ],

                // Savings contributions
                if (sinkingFunds.isNotEmpty) ...[
                  Text(
                    'Savings Contributions',
                    style: compactSectionTitleStyle(context),
                  ),
                  const SizedBox(height: 6),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: sinkingFunds.length,
                    itemBuilder: (context, index) {
                      final fund = sinkingFunds[index];
                      final contributed = _contributedThisMonthFor(fund);
                      final delta = contributed - fund.monthlyContribution;
                      final progress = fund.targetAmount <= 0
                          ? 0.0
                          : (fund.balance / fund.targetAmount).clamp(0.0, 1.0);
                      return CompactItemCard(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 2,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      fund.name,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'Δ vs Plan',
                                        style: compactMutedStyle(context),
                                      ),
                                      Text(
                                        '₹${delta.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          color: delta >= 0
                                              ? theme.colorScheme.tertiary
                                              : theme.colorScheme.error,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Monthly: ₹${fund.monthlyContribution.toStringAsFixed(2)} | Contributed: ₹${contributed.toStringAsFixed(2)}',
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Progress: ₹${fund.balance.toStringAsFixed(2)} / ₹${fund.targetAmount.toStringAsFixed(2)}',
                                style: compactMutedStyle(context),
                              ),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(value: progress),
                              const SizedBox(height: 6),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                ],

                // Debt payments
                Builder(
                  builder: (_) {
                    final periodLiabilities = _liabilitiesForPeriod();
                    if (periodLiabilities.isEmpty)
                      return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Debt Payments',
                          style: compactSectionTitleStyle(context),
                        ),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: periodLiabilities.length,
                          itemBuilder: (context, index) {
                            final liab = periodLiabilities[index];
                            final paid = _paidThisMonthFor(liab);
                            final delta = paid - liab.planned;
                            return CompactItemCard(
                              child: ListTile(
                                title: Text(
                                  liab.name,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  'Min: ₹${liab.planned.toStringAsFixed(2)} | Paid: ₹${paid.toStringAsFixed(2)}',
                                  style: theme.textTheme.bodyMedium,
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Δ vs Plan',
                                      style: compactMutedStyle(context),
                                    ),
                                    Text(
                                      '₹${delta.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        color: delta >= 0
                                            ? theme.colorScheme.tertiary
                                            : theme.colorScheme.error,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: kCompactSectionGap),

                // Budget allocation
                Text(
                  'Budget Allocation',
                  style: compactSectionTitleStyle(context),
                ),
                CompactItemCard(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                    child: BudgetAllocationChart(
                      breakdown: breakdownList,
                      unallocatedAmount: unallocated > 0 ? unallocated : 0.0,
                      onSliceTap: (data) => _showCategoryDetails(context, data),
                    ),
                  ),
                ),

                const SizedBox(height: kCompactSectionGap),

                // Period comparison
                Text(
                  'Period Comparison',
                  style: compactSectionTitleStyle(context),
                ),
                const SizedBox(height: 6),
                CompactItemCard(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (comparisonHistory.length < 2)
                          const Text(
                            'Close more periods to unlock historical line trends.',
                          )
                        else
                          _PeriodComparisonLineChart(points: comparisonHistory),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadData() async {
    try {
      final closed = await RMinderDatabase.instance.getClosedMonths();
      final closedWith = await RMinderDatabase.instance
          .getClosedMonthsWithClosedAt();
      // Preload snapshots for all closed periods
      final Map<DateTime, Map<int, models.BudgetSnapshot>> snaps = {};
      final Map<DateTime, double> incomeSums = {};
      for (final p in closed) {
        final m = await RMinderDatabase.instance.getBudgetSnapshotMapFor(p);
        snaps[DateTime(p.year, p.month, p.day)] = m;
        // Also load income snapshot sum for this closed period
        final totalInc = await RMinderDatabase.instance.getIncomeSnapshotSumFor(
          p,
        );
        incomeSums[DateTime(p.year, p.month, p.day)] = totalInc;
        // Load additional snapshots
        final spendMap = await RMinderDatabase.instance
            .getSpendingSnapshotMapFor(p);
        _spendingByPeriod[DateTime(p.year, p.month, p.day)] = spendMap;
        final liabSnaps = await RMinderDatabase.instance
            .getLiabilitySnapshotsFor(p);
        _liabSnapsByPeriod[DateTime(p.year, p.month, p.day)] = liabSnaps;
        final fundSnaps = await RMinderDatabase.instance.getFundSnapshotsFor(p);
        _fundSnapsByPeriod[DateTime(p.year, p.month, p.day)] = fundSnaps;
      }
      if (!mounted) return;
      setState(() {
        _closedMonths = closed;
        _snapshotsByPeriod
          ..clear()
          ..addAll(snaps);
        _incomeSumByPeriod
          ..clear()
          ..addAll(incomeSums);
        _closedAtByStart
          ..clear()
          ..addEntries(
            closedWith.map((m) {
              final s = m['start']!;
              final c = m['closedAt']!;
              // Preserve the exact closed-at timestamp for accurate period boundaries
              return MapEntry(DateTime(s.year, s.month, s.day), c);
            }),
          );
      });
    } catch (e, st) {
      logError(e, st);
    }
  }

  Future<void> _loadActivePeriod() async {
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final active = appState.activePeriodStart;
      if (!mounted) return;

      final actualStart = active ?? DateTime.now();
      setState(() {
        final now = DateTime.now();
        final isDefaultValue =
            selectedMonth.year == now.year &&
            selectedMonth.month == now.month &&
            selectedMonth.day == now.day;
        if (isDefaultValue) {
          selectedMonth = actualStart;
        }
      });
      // Load one-time carry-forward income for the active period (if any)
      try {
        final key = 'carry_income:--';
        final str = await RMinderDatabase.instance.getSetting(key);
        final val = double.tryParse(str ?? '0') ?? 0.0;
        if (mounted) {
          setState(() => _activeCarryIncome = val);
        }
      } catch (_) {}
    } catch (e, st) {
      logError(e, st);
    }
  }

  Future<void> _maybeBackfillSnapshots() async {
    try {
      // One-time backfill for existing closed periods: snapshot current budgets as baseline
      final flag = await RMinderDatabase.instance.getSetting(
        'snapshots_backfilled',
      );
      if (flag == 'true') return; // already done
      await RMinderDatabase.instance.backfillBudgetSnapshots();
      await RMinderDatabase.instance.setSetting('snapshots_backfilled', 'true');
      // Reload snapshots after backfill
      if (mounted) {
        await _loadData();
      }
    } catch (e, st) {
      logError(e, st);
    }
  }

  Future<void> _maybeBackfillIncomeSnapshots() async {
    try {
      final flag = await RMinderDatabase.instance.getSetting(
        'income_snapshots_backfilled',
      );
      if (flag == 'true') return;
      await RMinderDatabase.instance.backfillIncomeSnapshots();
      await RMinderDatabase.instance.setSetting(
        'income_snapshots_backfilled',
        'true',
      );
      // reload not strictly necessary here
    } catch (e, st) {
      logError(e, st);
    }
  }

  // Build the list of period anchors (start dates) used for navigation
  List<DateTime> _allowedPeriods() {
    // Include all closed period starts and the current active period start
    final set = _closedMonths
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet();
    if (_activePeriodStart != null) {
      set.add(
        DateTime(
          _activePeriodStart!.year,
          _activePeriodStart!.month,
          _activePeriodStart!.day,
        ),
      );
    }
    final list = set.toList();
    list.sort((a, b) => b.compareTo(a)); // newest first
    return list;
  }

  Future<void> _editBudgetForPeriodFlow() async {
    final periodStart = _periodStartFor(selectedMonth);
    if (!_isClosedPeriod(periodStart)) return;

    // Load snapshots for this period
    List<models.BudgetSnapshot> snaps = [];
    try {
      snaps = await RMinderDatabase.instance.getBudgetSnapshotsFor(periodStart);
    } catch (e, st) {
      logError(e, st);
    }
    if (snaps.isEmpty) {
      // No snapshots? Fallback to current categories as a starting point
      snaps = [
        for (final c in categories.where((c) => c.id != null))
          models.BudgetSnapshot(
            periodStart: DateTime(
              periodStart.year,
              periodStart.month,
              periodStart.day,
            ),
            categoryId: c.id!,
            categoryName: c.name,
            budgetLimit: c.budgetLimit,
          ),
      ];
    }
    // Sort by name for stable UI
    snaps.sort(
      (a, b) =>
          a.categoryName.toLowerCase().compareTo(b.categoryName.toLowerCase()),
    );

    // Controllers for editing amounts; names are read-only in this quick edit
    final amtCtrls = <int, TextEditingController>{};
    for (final s in snaps) {
      amtCtrls[s.categoryId] = TextEditingController(
        text: s.budgetLimit.toStringAsFixed(2),
      );
    }

    if (!mounted) return;

    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit period budget'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SizedBox(
            width: 640,
            height: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatPeriodRange(periodStart),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: snaps.length,
                    itemBuilder: (c, i) {
                      final s = snaps[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(
                                s.categoryName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 120,
                              child: TextField(
                                controller: amtCtrls[s.categoryId],
                                decoration: const InputDecoration(
                                  labelText: 'Limit',
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: false,
                                      signed: false,
                                    ),
                                inputFormatters: [CurrencyInputFormatter()],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Build pseudo categories from edits and save snapshots
    final editedCats = <models.BudgetCategory>[];
    for (final s in snaps) {
      final txt = amtCtrls[s.categoryId]?.text.trim() ?? '0';
      final limit = double.tryParse(txt) ?? 0.0;
      editedCats.add(
        models.BudgetCategory(
          id: s.categoryId,
          name: s.categoryName,
          budgetLimit: limit,
          spent: 0,
        ),
      );
    }

    try {
      await RMinderDatabase.instance.saveBudgetSnapshotForPeriod(
        periodStart,
        editedCats,
      );
      // Reload snapshots for this period and update cache
      final updated = await RMinderDatabase.instance.getBudgetSnapshotMapFor(
        periodStart,
      );
      if (!mounted) return;
      setState(() {
        _snapshotsByPeriod[DateTime(
              periodStart.year,
              periodStart.month,
              periodStart.day,
            )] =
            updated;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved period budget.')));
    } catch (e, st) {
      logError(e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save budget for period.')),
      );
    }
  }

  Future<void> _editIncomeForPeriodFlow() async {
    final periodStart = _periodStartFor(selectedMonth);
    if (!_isClosedPeriod(periodStart)) return;

    // Load existing snapshot rows or fall back to current incomes
    List<Map<String, dynamic>> rows = [];
    try {
      rows = await RMinderDatabase.instance.getIncomeSnapshotsFor(periodStart);
    } catch (e, st) {
      logError(e, st);
    }
    if (rows.isEmpty) {
      rows = [
        for (final s in incomeSources)
          {'source_name': s.name, 'amount': s.amount},
      ];
    }

    // Local editable copy
    final nameCtrls = <TextEditingController>[];
    final amtCtrls = <TextEditingController>[];
    for (final r in rows) {
      nameCtrls.add(
        TextEditingController(text: (r['source_name'] ?? '').toString()),
      );
      final amt = ((r['amount'] ?? 0) as num).toDouble();
      amtCtrls.add(TextEditingController(text: amt.toStringAsFixed(2)));
    }

    if (!mounted) return;

    // Add-row logic is handled inline in the setLocal() call below.

    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('Edit period income'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SizedBox(
                width: 520,
                height: 360,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatPeriodRange(periodStart),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: nameCtrls.length,
                        itemBuilder: (c, i) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: nameCtrls[i],
                                    decoration: const InputDecoration(
                                      labelText: 'Source name',
                                    ),
                                    maxLength: 24,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: amtCtrls[i],
                                    decoration: const InputDecoration(
                                      labelText: 'Amount',
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: false,
                                          signed: false,
                                        ),
                                    inputFormatters: [CurrencyInputFormatter()],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Remove',
                                  onPressed: () => setLocal(() {
                                    nameCtrls.removeAt(i);
                                    amtCtrls.removeAt(i);
                                  }),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setLocal(() {
                          nameCtrls.add(TextEditingController());
                          amtCtrls.add(TextEditingController(text: '0.00'));
                        }),
                        icon: const Icon(Icons.add),
                        label: const Text('Add income source'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true) return;

    // Validate and save
    final edits = <models.IncomeSource>[];
    for (var i = 0; i < nameCtrls.length; i++) {
      final name = nameCtrls[i].text.trim();
      final amount = double.tryParse(amtCtrls[i].text.trim()) ?? 0;
      if (name.isEmpty) continue; // skip empties
      if (amount < 0) continue; // ignore negative
      edits.add(models.IncomeSource(name: name, amount: amount));
    }
    try {
      await RMinderDatabase.instance.saveIncomeSnapshotForPeriod(
        periodStart,
        edits,
      );
      // Update local sum cache and refresh UI
      final sum = edits.fold<double>(0, (s, e) => s + e.amount);
      if (!mounted) return;
      setState(() {
        _incomeSumByPeriod[DateTime(
              periodStart.year,
              periodStart.month,
              periodStart.day,
            )] =
            sum;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved period income.')));
    } catch (e, st) {
      logError(e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save income for period.')),
      );
    }
  }

  double _contributedThisMonthFor(models.SinkingFund fund) {
    if (fund.budgetCategoryId == null) return 0;
    double total = 0;
    final start = _periodStartFor(selectedMonth);
    final end = _periodUpperBoundExclusive(start);
    for (final t in transactions) {
      if (t.categoryId == fund.budgetCategoryId &&
          !t.date.isBefore(start) &&
          t.date.isBefore(end)) {
        // Only count positive amounts (contributions), ignore withdrawals (negative amounts)
        if (t.amount > 0) {
          total += t.amount;
        }
      }
    }
    return total;
  }

  double _paidThisMonthFor(models.Liability liab) {
    double total = 0;
    final start = _periodStartFor(selectedMonth);
    final end = _periodUpperBoundExclusive(start);
    for (final t in transactions) {
      if (t.categoryId == liab.budgetCategoryId &&
          !t.date.isBefore(start) &&
          t.date.isBefore(end)) {
        total += t.amount;
      }
    }
    return total;
  }

  // Legacy local close flow removed; global close is handled by PeriodService via AppBar action

  Future<void> _showCategoryDetails(
    BuildContext context,
    CategoryBreakdown data,
  ) async {
    if (_isDetailsDialogOpen) return;
    _isDetailsDialogOpen = true;
    final remaining = data.limit - data.spent;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(data.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total Budget: ₹${data.limit.toStringAsFixed(2)}'),
            Text('Current Spent: ₹${data.spent.toStringAsFixed(2)}'),
            Text(
              'Balance: ₹${remaining.toStringAsFixed(2)}',
              style: TextStyle(
                color: remaining < 0 ? Colors.red : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    _isDetailsDialogOpen = false;
  }

  Future<void> _showJumpToPeriod() async {
    try {
      final periods = _allowedPeriods();
      if (periods.isEmpty) return;
      final chosen = await showDialog<DateTime>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Jump to period'),
          content: SizedBox(
            width: 360,
            height: 320,
            child: ListView.builder(
              itemCount: periods.length,
              itemBuilder: (c, i) {
                final p = periods[i];
                return ListTile(
                  title: Text(_formatPeriodRange(_periodStartFor(p))),
                  onTap: () => Navigator.pop(ctx, p),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      if (chosen != null && mounted) {
        setState(() => selectedMonth = chosen);
      }
    } catch (e, st) {
      logError(e, st);
    }
  }

  Future<void> _reopenPeriodFlow() async {
    final periodStart = _periodStartFor(selectedMonth);

    // Confirm with user
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reopen Period?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reopen ${_formatPeriodRange(periodStart)}?'),
            const SizedBox(height: 12),
            const Text(
              'This will:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text('• Remove the closed status'),
            const Text('• Delete budget snapshots (will use current budgets)'),
            const Text(
              '• Keep all transactions (carry-forward, debt payments, etc.)',
            ),
            const SizedBox(height: 12),
            const Text(
              'You can edit transactions and close the period again.',
              style: TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reopen'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final success = await RMinderDatabase.instance.reopenClosedPeriod(
        periodStart,
      );
      if (!success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Period was not closed.')),
          );
        }
        return;
      }

      // Reload data to reflect the reopened period
      await _loadData();

      // Set this period as the active period
      await RMinderDatabase.instance.setActivePeriodStart(periodStart);

      if (!mounted) return;
      setState(() {
        selectedMonth = periodStart;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reopened ${_formatPeriodRange(periodStart)}')),
      );
    } catch (e, st) {
      logError(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to reopen period. Please try again.'),
          ),
        );
      }
    }
  }

  // Liabilities to consider for the selected period (use active/non-archived)
  List<models.Liability> _liabilitiesForPeriod() {
    return liabilities.where((l) => !l.isArchived).toList();
  }

  void _goToPreviousPeriod() {
    final allowed = _allowedPeriods();
    final s = _periodStartFor(selectedMonth);
    final idx = allowed.indexWhere((d) => _sameDay(d, s));
    if (idx != -1 && idx < allowed.length - 1) {
      setState(() => selectedMonth = allowed[idx + 1]);
    }
  }

  void _goToNextPeriod() {
    final allowed = _allowedPeriods();
    final s = _periodStartFor(selectedMonth);
    final idx = allowed.indexWhere((d) => _sameDay(d, s));
    if (idx > 0) {
      setState(() => selectedMonth = allowed[idx - 1]);
    }
  }
}
