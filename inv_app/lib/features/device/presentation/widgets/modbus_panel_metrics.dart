import 'package:flutter/material.dart';
import 'package:inv_app/core/theme/app_theme.dart';

class ModbusPanelMetrics extends StatelessWidget {
  const ModbusPanelMetrics({
    super.key,
    required this.values,
    this.staleLabel,
    this.inset = true,
    this.emphasizeFirst = false,
  });

  final List<(String, String)> values;
  final String? staleLabel;
  final bool inset;
  final bool emphasizeFirst;

  @override
  Widget build(BuildContext context) {
    final rows = emphasizeFirst
        ? LayoutBuilder(
            builder: (context, constraints) => _buildRows(
              context,
              values.length >= 4 &&
                  constraints.maxWidth >= 280 &&
                  MediaQuery.textScalerOf(context).scale(14) < 22,
            ),
          )
        : _buildRows(context, false);
    if (!inset) return rows;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: AppColor.card(context),
      child: rows,
    );
  }

  Widget _buildRows(BuildContext context, bool prominent) => Column(
        children: [
          if (prominent)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildHighlight(context, values[0])),
                    const SizedBox(width: 10),
                    Expanded(child: _buildHighlight(context, values[1])),
                  ],
                ),
              ),
            ),
          for (var index = prominent ? 2 : 0;
              index < values.length;
              index++) ...[
            if (index > 0 || !inset)
              Divider(height: 1, color: AppColor.divider(context)),
            _buildRow(context, values[index].$1, values[index].$2),
          ],
        ],
      );

  Widget _buildRow(BuildContext context, String label, String value) {
    final (reading, missing, historical) = _reading(value);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: text.bodySmall?.copyWith(
                color: AppColor.textSecondary(context),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  reading,
                  textAlign: TextAlign.end,
                  style: text.bodyMedium?.copyWith(
                    color: missing || historical != null
                        ? AppColor.textSecondary(context)
                        : AppColor.textPrimary(context),
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (historical != null)
                  Text(
                    historical,
                    textAlign: TextAlign.end,
                    style: text.labelSmall?.copyWith(
                      color: AppColor.textSecondary(context),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (String, bool, String?) _reading(String value) {
    final stale = value.endsWith('*');
    final reading = stale ? value.substring(0, value.length - 1) : value;
    final missing = reading.isEmpty || reading == '--' || reading == '—';
    final historical = stale && !missing ? staleLabel : null;
    return (missing ? '—' : reading, missing, historical);
  }

  Widget _buildHighlight(BuildContext context, (String, String) entry) {
    final (label, value) = entry;
    final (reading, missing, historical) = _reading(value);
    final text = Theme.of(context).textTheme;
    final muted = AppColor.textSecondary(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColor.surfaceHover(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: text.bodySmall?.copyWith(
              color: muted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            reading,
            style: text.titleLarge?.copyWith(
              color: missing || historical != null
                  ? muted
                  : AppColor.textPrimary(context),
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (historical != null)
            Text(
              historical,
              style: text.labelSmall?.copyWith(
                color: muted,
              ),
            ),
        ],
      ),
    );
  }
}
