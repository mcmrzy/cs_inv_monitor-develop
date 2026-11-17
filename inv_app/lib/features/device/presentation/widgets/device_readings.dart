import 'package:flutter/material.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/device/presentation/widgets/modbus_panel_metrics.dart';

typedef DeviceReadingCategory = (IconData icon, String label);

class DeviceReadings extends StatelessWidget {
  const DeviceReadings({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelect,
    required this.values,
    this.status,
    this.staleLabel,
    this.loading = false,
  });

  final List<DeviceReadingCategory> categories;
  final int selected;
  final ValueChanged<int>? onSelect;
  final List<(String, String)> values;
  final String? status;
  final String? staleLabel;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final (icon, title) = categories[selected];
    final accent = AppColor.primary(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status case final message?)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColor.textSecondary(context),
              ),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (var index = 0; index < categories.length; index++)
              ChoiceChip(
                label: Text(categories[index].$2),
                labelStyle: theme.textTheme.labelLarge?.copyWith(
                  color: selected == index
                      ? accent
                      : AppColor.textPrimary(context),
                  fontWeight: selected == index ? FontWeight.w700 : null,
                ),
                selected: selected == index,
                selectedColor: AppColor.primaryContainer(context),
                disabledColor: selected == index
                    ? AppColor.primaryContainer(context)
                    : AppColor.surfaceContainer(context),
                backgroundColor: AppColor.surfaceContainer(context),
                showCheckmark: false,
                shape: const StadiumBorder(),
                side: BorderSide.none,
                onSelected: onSelect == null
                    ? null
                    : (_) {
                        if (index != selected) onSelect!(index);
                      },
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          decoration: AppColor.card(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, color: accent, size: 20),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (loading) const LinearProgressIndicator(),
              if (values.isNotEmpty)
                ModbusPanelMetrics(
                  values: values,
                  staleLabel: staleLabel,
                  inset: false,
                  emphasizeFirst: true,
                )
              else if (!loading)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(zh ? '暂无参数读数' : 'No readings available'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
