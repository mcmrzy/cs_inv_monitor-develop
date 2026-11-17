import 'package:flutter/material.dart';
import 'package:inv_app/core/theme/app_theme.dart';

/// Readback and proposed values share the same presentation on both links.
class DeviceSettingChange extends StatelessWidget {
  const DeviceSettingChange({
    super.key,
    required this.current,
    this.target,
    this.label,
  });

  final String current;
  final String? target;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final currentValue = _value(
      context,
      zh ? '当前值' : 'Current value',
      current,
    );
    final proposed = target;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColor.primarySoft(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label case final name?) ...[
            Text(name, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
          ],
          if (proposed == null)
            currentValue
          else
            _comparison(
              context,
              currentValue,
              _value(
                context,
                zh ? '目标值' : 'Target value',
                proposed,
                highlighted: true,
              ),
            ),
        ],
      ),
    );
  }

  Widget _comparison(BuildContext context, Widget current, Widget target) {
    if (MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(16) > 23) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [current, const Divider(), target],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: current),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Icon(
            Icons.arrow_forward_rounded,
            size: 18,
            color: AppColor.textSecondary(context),
          ),
        ),
        Expanded(child: target),
      ],
    );
  }

  Widget _value(BuildContext context, String caption, String value,
      {bool highlighted = false}) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: '$caption $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(caption,
              style: text.labelMedium?.copyWith(
                color: AppColor.textSecondary(context),
              )),
          const SizedBox(height: 4),
          Text(value,
              style: text.titleLarge?.copyWith(
                color: highlighted
                    ? AppColor.primary(context)
                    : AppColor.textPrimary(context),
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }
}
