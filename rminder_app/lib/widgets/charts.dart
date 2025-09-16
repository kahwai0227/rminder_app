import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class CategoryBreakdown {
  final String name;
  final double spent;
  final double limit;
  final int? categoryId;
  const CategoryBreakdown({required this.name, required this.spent, required this.limit, this.categoryId});
}

class MonthlySummary {
  final double totalSpent;
  final double totalLimit;
  final double totalRemaining;
  final List<CategoryBreakdown> breakdown;
  const MonthlySummary({
    required this.totalSpent,
    required this.totalLimit,
    required this.totalRemaining,
    required this.breakdown,
  });
}

class BudgetAllocationChart extends StatelessWidget {
  final List<CategoryBreakdown> breakdown;
  final ValueChanged<CategoryBreakdown>? onSliceTap;
  final double unallocatedAmount;
  final bool compactLegend;
  const BudgetAllocationChart({
    super.key,
    required this.breakdown,
    this.onSliceTap,
    this.unallocatedAmount = 0,
    this.compactLegend = true,
  });

  @override
  Widget build(BuildContext context) {
    final categoriesTotal = breakdown.fold<double>(0, (s, c) => s + c.limit);
    final double extraUnallocated = unallocatedAmount > 0 ? unallocatedAmount : 0.0;
    final total = categoriesTotal + extraUnallocated;
    if (total == 0) return const Center(child: Text('No budget allocated'));

    const double labelThreshold = 8.0;

    final legendEntries = <_LegendEntry>[];
    for (final entry in breakdown.asMap().entries) {
      final idx = entry.key;
      final cat = entry.value;
      final color = Colors.primaries[idx % Colors.primaries.length];
      final percent = total == 0.0 ? 0.0 : (cat.limit / total) * 100;
      legendEntries.add(_LegendEntry(label: cat.name, color: color, percent: percent));
    }
    if (extraUnallocated > 0) {
      final percent = (extraUnallocated / total) * 100;
      legendEntries.add(_LegendEntry(label: 'Unallocated', color: Colors.blueGrey, percent: percent));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 200,
          child: PieChart(
            PieChartData(
              pieTouchData: PieTouchData(
                touchCallback: (event, pieTouchResponse) {
                  if (!event.isInterestedForInteractions) return;
                  final touched = pieTouchResponse?.touchedSection;
                  if (touched == null) return;
                  final idx = touched.touchedSectionIndex;
                  if (idx >= 0) {
                    if (idx < breakdown.length) {
                      final data = breakdown[idx];
                      onSliceTap?.call(data);
                    } else if (extraUnallocated > 0 && idx == breakdown.length) {
                      onSliceTap?.call(
                        const CategoryBreakdown(name: 'Unallocated', spent: 0, limit: 0),
                      );
                    }
                  }
                },
              ),
              sectionsSpace: 4,
              centerSpaceRadius: 40,
              sections: [
                ...breakdown.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final cat = entry.value;
                  final percent = total == 0.0 ? 0.0 : (cat.limit / total) * 100;
                  return PieChartSectionData(
                    value: cat.limit,
                    title: percent >= labelThreshold ? '${percent.toStringAsFixed(0)}%' : '',
                    color: Colors.primaries[idx % Colors.primaries.length],
                    radius: 60,
                    titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  );
                }),
                if (extraUnallocated > 0)
                  PieChartSectionData(
                    value: extraUnallocated,
                    title: ((extraUnallocated / total) * 100) >= labelThreshold
                        ? '${((extraUnallocated / total) * 100).toStringAsFixed(0)}%'
                        : '',
                    color: Colors.blueGrey,
                    radius: 60,
                    titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _ChartLegend(entries: legendEntries, compact: compactLegend),
      ],
    );
  }
}

class _LegendEntry {
  final String label;
  final Color color;
  final double percent;
  const _LegendEntry({required this.label, required this.color, required this.percent});
}

class _ChartLegend extends StatefulWidget {
  final List<_LegendEntry> entries;
  final bool compact;
  const _ChartLegend({required this.entries, this.compact = true});

  @override
  State<_ChartLegend> createState() => _ChartLegendState();
}

class _ChartLegendState extends State<_ChartLegend> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    if (entries.isEmpty) return const SizedBox.shrink();

    // Compact mode: show up to N entries and allow expand
  const maxVisible = 5;
    final showToggle = widget.compact && entries.length > maxVisible;
    final visibleEntries = (widget.compact && !_expanded)
        ? entries.take(maxVisible).toList()
        : entries;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: visibleEntries.map((e) {
            final label = e.label.length > 14 ? '${e.label.substring(0, 14)}…' : e.label;
            final pctStr = e.percent < 0.5 ? '<1%' : '${e.percent.toStringAsFixed(0)}%';
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: e.color, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(width: 4),
                  Text(pctStr, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              ),
            );
          }).toList(),
        ),
        if (showToggle)
          Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: TextButton(
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: const Size(0, 0)),
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? 'Show less' : 'Show all (${entries.length - maxVisible} more)'),
            ),
          ),
      ],
    );
  }
}

class ThermometerBar extends StatelessWidget {
  final double value;
  final double max;
  final Color color;
  final double height;
  final BorderRadiusGeometry borderRadius;

  const ThermometerBar({
    super.key,
    required this.value,
    required this.max,
    this.color = Colors.deepPurple,
    this.height = 14,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  Widget build(BuildContext context) {
    final clamped = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    final over = value > max;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final fillWidth = width * clamped;
        return Stack(children: [
          Container(
            height: height,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: borderRadius,
            ),
          ),
          Container(
            height: height,
            width: fillWidth,
            decoration: BoxDecoration(
              color: over ? Colors.redAccent : color,
              borderRadius: borderRadius,
            ),
          ),
        ]);
      },
    );
  }
}
