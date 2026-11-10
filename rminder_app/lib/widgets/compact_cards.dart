import 'package:flutter/material.dart';

const EdgeInsets kCompactPagePadding = EdgeInsets.all(14);
const double kCompactSectionGap = 10;

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
    this.padding = const EdgeInsets.fromLTRB(12, 10, 12, 10),
    this.margin = const EdgeInsets.only(bottom: 10),
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
    this.margin = const EdgeInsets.only(bottom: 6),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        minVerticalPadding: 4,
        child: child,
      ),
    );
  }
}

class CompactSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const CompactSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: compactSectionTitleStyle(context)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: compactMutedStyle(context)),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class CompactEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  const CompactEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                style: compactMutedStyle(context),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[const SizedBox(height: 10), action!],
          ],
        ),
      ),
    );
  }
}

class CompactStateBanner extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color? color;

  const CompactStateBanner({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bannerColor = color ?? theme.colorScheme.secondary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bannerColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: bannerColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: bannerColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: bannerColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
