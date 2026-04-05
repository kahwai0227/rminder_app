import 'package:flutter/material.dart';

const EdgeInsets kCompactPagePadding = EdgeInsets.all(12);
const double kCompactSectionGap = 6;

TextStyle compactSectionTitleStyle(BuildContext context) {
  final base = Theme.of(context).textTheme.titleLarge;
  return (base ?? const TextStyle(fontSize: 20)).copyWith(
    fontWeight: FontWeight.w700,
  );
}

TextStyle compactMutedStyle(BuildContext context) {
  final theme = Theme.of(context);
  return (theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12)).copyWith(
    color: theme.colorScheme.onSurfaceVariant,
  );
}

class CompactSectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  const CompactSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.only(left: 10, right: 10, top: 5),
    this.margin = const EdgeInsets.only(bottom: 8),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: margin,
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.28),
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class CompactItemCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry margin;

  const CompactItemCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.only(bottom: 4),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemBg = theme.colorScheme.surfaceContainerLow;
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: itemBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.08),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ListTileTheme.merge(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        minVerticalPadding: 1,
        child: child,
      ),
    );
  }
}
