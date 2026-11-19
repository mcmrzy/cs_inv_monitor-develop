import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// Device health at a glance. The online share uses the same status counts
/// as the offline and fault totals below it.
class DeviceDistributionChart extends StatelessWidget {
  const DeviceDistributionChart({
    super.key,
    required this.onlineCount,
    required this.offlineCount,
    required this.faultCount,
  });

  final int onlineCount;
  final int offlineCount;
  final int faultCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final numbers = NumberFormat.decimalPattern(locale);
    final percent = NumberFormat.percentPattern(locale)
      ..maximumFractionDigits = 1;
    final total = onlineCount + offlineCount + faultCount;
    final text = Theme.of(context).textTheme;
    final primary = AppColor.primary(context);
    final muted = AppColor.textSecondary(context);
    final foreground = AppColor.textPrimary(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: AppColor.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.deviceStatusDistribution,
            style: text.titleSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 14.h),
          if (total == 0)
            Text(
              l10n.noDevicesYet,
              style: text.bodySmall?.copyWith(color: muted),
            )
          else ...[
            Container(
              padding: EdgeInsets.fromLTRB(14.w, 11.h, 14.w, 12.h),
              decoration: BoxDecoration(
                color: AppColor.primarySoft(context),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12.w,
                    runSpacing: 4.h,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: numbers.format(onlineCount),
                              style: text.headlineSmall?.copyWith(
                                color: primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(
                              text:
                                  ' / ${numbers.format(total)} ${l10n.statusOnline}',
                            ),
                          ],
                        ),
                        style: text.bodyMedium?.copyWith(color: muted),
                      ),
                      Text(
                        percent.format(onlineCount / total),
                        style: text.labelLarge?.copyWith(
                          color: primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8.h),
                  ExcludeSemantics(
                    child: LinearProgressIndicator(
                      value: onlineCount / total,
                      minHeight: 5.h,
                      borderRadius: BorderRadius.circular(8.r),
                      color: primary,
                      backgroundColor: primary.withValues(alpha: 0.15),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12.h),
            LayoutBuilder(
              builder: (context, constraints) {
                final entries = [
                  _StatusValue(
                    icon: Icons.cloud_off_outlined,
                    label: l10n.statusOffline,
                    value: numbers.format(offlineCount),
                    accent: muted,
                  ),
                  _StatusValue(
                    icon: Icons.error_outline_rounded,
                    label: l10n.statusFault,
                    value: numbers.format(faultCount),
                    accent: faultCount == 0
                        ? muted
                        : dark
                            ? const Color(0xFFF2A49D)
                            : const Color(0xFFAB524D),
                  ),
                ];
                if (constraints.maxWidth < 250 ||
                    MediaQuery.textScalerOf(context).scale(14) >= 22) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: entries,
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var index = 0; index < entries.length; index++) ...[
                      if (index > 0) SizedBox(width: 10.w),
                      Expanded(child: entries[index]),
                    ],
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusValue extends StatelessWidget {
  const _StatusValue({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 3.w, vertical: 4.h),
      child: Row(
        children: [
          Icon(icon, size: 17.sp, color: accent),
          SizedBox(width: 7.w),
          Expanded(
            child: Text(
              label,
              style: text.bodySmall?.copyWith(
                color: AppColor.textSecondary(context),
              ),
            ),
          ),
          SizedBox(width: 4.w),
          Flexible(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: text.titleMedium?.copyWith(
                  color: AppColor.textPrimary(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
