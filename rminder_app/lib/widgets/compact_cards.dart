import 'package:flutter/material.dart';

const EdgeInsets kCompactPagePadding = EdgeInsets.all(12);
const double kCompactSectionGap = 8;

class CompactSectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  const CompactSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(10),
    this.margin = const EdgeInsets.symmetric(vertical: 4),
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: margin,
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

class CompactItemCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry margin;

  const CompactItemCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.symmetric(vertical: 3),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.25)),
      ),
      child: child,
    );
  }
}
