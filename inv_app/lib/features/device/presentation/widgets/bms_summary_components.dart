import 'package:flutter/material.dart';
import 'package:inv_app/core/theme/app_theme.dart';

const bmsGreen = Color(0xFF19795E);
const bmsAmber = Color(0xFFAD7819);
const bmsRed = Color(0xFFBC4141);
const bmsBlue = Color(0xFF5C90C8);

class BmsMetric extends StatelessWidget {
  final String label, value;
  final String? detail;
  final bool compact;
  final Widget? trailing;

  const BmsMetric({
    super.key,
    required this.label,
    required this.value,
    this.detail,
    this.compact = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColor.textSecondary(context),
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 6),
          // Fixed type sizes; only long numbers shrink to fit their metric track.
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: compact ? 21 : 27,
                  fontWeight: FontWeight.w600,
                  color: AppColor.textPrimary(context),
                ),
              ),
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(
              detail!,
              style: TextStyle(
                fontSize: 11,
                color: AppColor.textSecondary(context),
              ),
            ),
          ],
        ],
      );
}

class BmsMetricGrid extends StatelessWidget {
  final List<Widget> children;
  final int columns;
  const BmsMetricGrid({super.key, required this.children, this.columns = 3});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final count = scale > 1.4 && columns == 3 ? 2 : columns;
          final width = (constraints.maxWidth - (count - 1) * 16) / count;
          return Wrap(
            spacing: 16,
            runSpacing: 20,
            children: [
              for (final child in children)
                SizedBox(width: width, child: child),
            ],
          );
        },
      );
}

class BmsReadout extends StatelessWidget {
  final String label, value;
  final Color? color;
  const BmsReadout({
    super.key,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final labelWidget = Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppColor.textSecondary(context),
              ),
            );
            final valueWidget = Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: color ?? AppColor.textPrimary(context),
              ),
            );
          if (constraints.maxWidth < 300 ||
                MediaQuery.textScalerOf(context).scale(14) > 20) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  labelWidget,
                  const SizedBox(height: 4),
                  valueWidget,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: labelWidget),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: valueWidget,
                  ),
                ),
              ],
            );
          },
        ),
      );
}

class BmsSection extends StatelessWidget {
  final String title;
  final String? detail;
  final List<Widget> children;
  const BmsSection({
    super.key,
    required this.title,
    required this.children,
    this.detail,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 6,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColor.textPrimary(context),
                  ),
                ),
                if (detail != null)
                  Text(
                    detail!,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColor.textSecondary(context),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      );
}
