import 'package:flutter/material.dart';

class ModbusPanelMetrics extends StatelessWidget {
  const ModbusPanelMetrics({
    super.key,
    required this.values,
    this.staleLabel,
  });

  final List<(String, String)> values;
  final String? staleLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final width = constraints.maxWidth;
        final columns =
            width >= 288 && MediaQuery.textScalerOf(context).scale(16) <= 24
                ? 2
                : 1;
        final tileWidth = (width - (columns - 1) * gap) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (label, rawValue) in values)
              SizedBox(
                width: tileWidth,
                child: _Metric(
                  label: label,
                  value: rawValue,
                  staleLabel: staleLabel,
                  colors: colors,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.staleLabel,
    required this.colors,
  });

  final String label;
  final String value;
  final String? staleLabel;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final taggedStale = value.endsWith('*');
    final reading = taggedStale ? value.substring(0, value.length - 1) : value;
    final missing = reading.isEmpty || reading == '--' || reading == '—';
    final historical = taggedStale && !missing ? staleLabel : null;
    final theme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.labelMedium),
            const SizedBox(height: 4),
            Text(
              missing ? '—' : reading,
              style: theme.titleMedium?.copyWith(
                color: historical != null || missing
                    ? colors.onSurfaceVariant
                    : colors.onSurface,
              ),
            ),
            if (historical != null)
              Text(
                historical,
                style: theme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
