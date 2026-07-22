import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 横向滑动数据卡片 - 今日/本月/本年/累计数据
class ScrollableDataCards extends StatelessWidget {
  final double todayEnergy;
  final double monthEnergy;
  final double yearEnergy;
  final double totalEnergy;
  final String selectedPeriod;
  final ValueChanged<String>? onPeriodChanged;

  const ScrollableDataCards({
    super.key,
    required this.todayEnergy,
    required this.monthEnergy,
    required this.yearEnergy,
    required this.totalEnergy,
    this.selectedPeriod = 'today',
    this.onPeriodChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cards = [
      _DataCard(
        label: l10n.timeToday,
        value: todayEnergy,
        unit: 'kWh',
        wanLabel: l10n.wan,
        isSelected: selectedPeriod == 'today',
        onTap: () => onPeriodChanged?.call('today'),
      ),
      _DataCard(
        label: l10n.timeThisMonth,
        value: monthEnergy,
        unit: 'kWh',
        wanLabel: l10n.wan,
        isSelected: selectedPeriod == 'month',
        onTap: () => onPeriodChanged?.call('month'),
      ),
      _DataCard(
        label: l10n.timeThisYear,
        value: yearEnergy,
        unit: 'kWh',
        wanLabel: l10n.wan,
        isSelected: selectedPeriod == 'year',
        onTap: () => onPeriodChanged?.call('year'),
      ),
      _DataCard(
        label: l10n.timeTotal,
        value: totalEnergy,
        unit: 'kWh',
        wanLabel: l10n.wan,
        isSelected: selectedPeriod == 'total',
        onTap: () => onPeriodChanged?.call('total'),
      ),
    ];

    return SizedBox(
      height: 100.h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (context, index) => SizedBox(width: 12.w),
        itemBuilder: (context, index) => cards[index],
      ),
    );
  }
}

class _DataCard extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final String wanLabel;
  final bool isSelected;
  final VoidCallback? onTap;

  const _DataCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.wanLabel,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100.w,
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.1)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.3)
                : AppColors.divider,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11.sp,
                fontWeight: FontWeight.w500,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatValue(value),
                  style: TextStyle(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w800,
                    color:
                        isSelected ? AppColors.primary : AppColors.textPrimary,
                  ),
                ),
                Text(
                  unit,
                  style: TextStyle(
                    fontSize: 10.sp,
                    color: isSelected ? AppColors.primary : AppColors.textHint,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatValue(double value) {
    if (value >= 10000) {
      return '${(value / 10000).toStringAsFixed(1)}$wanLabel';
    }
    if (value >= 1000) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }
}
