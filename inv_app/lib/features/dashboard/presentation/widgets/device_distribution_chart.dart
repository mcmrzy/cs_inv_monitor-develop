import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 设备分布图 - 环形图展示在线/离线/故障占比
class DeviceDistributionChart extends StatelessWidget {
  final int onlineCount;
  final int offlineCount;
  final int faultCount;

  const DeviceDistributionChart({
    super.key,
    required this.onlineCount,
    required this.offlineCount,
    required this.faultCount,
  });

  @override
  Widget build(BuildContext context) {
    final total = onlineCount + offlineCount + faultCount;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(Icons.pie_chart_rounded, size: 18.w, color: AppColors.primary),
              ),
              SizedBox(width: 10.w),
              Text(
                l10n.deviceStatusDistribution,
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          SizedBox(height: 20.h),
          Row(
            children: [
              // 环形图
              SizedBox(
                width: 120.w,
                height: 120.w,
                child: total > 0
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          PieChart(
                            PieChartData(
                              sectionsSpace: 3,
                              centerSpaceRadius: 36.w,
                              sections: _buildSections(),
                              borderData: FlBorderData(show: false),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$total',
                                style: TextStyle(
                                  fontSize: 22.sp,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                '${l10n.unitDevices}${l10n.deviceLabel}',
                                style: TextStyle(
                                  fontSize: 10.sp,
                                  color: AppColors.textHint,
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.devices_rounded, size: 32.w, color: AppColors.textHint),
                            SizedBox(height: 4.h),
                            Text(
                              l10n.noDevicesYet,
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: AppColors.textHint,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              SizedBox(width: 20.w),
              // 图例
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _legendRow(context, AppColors.online, l10n.statusOnline, onlineCount, total, Icons.check_circle_rounded),
                    SizedBox(height: 16.h),
                    _legendRow(context, AppColors.offline, l10n.statusOffline, offlineCount, total, Icons.pause_circle_rounded),
                    SizedBox(height: 16.h),
                    _legendRow(context, AppColors.fault, l10n.statusFault, faultCount, total, Icons.error_rounded),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<PieChartSectionData> _buildSections() {
    final total = onlineCount + offlineCount + faultCount;
    if (total == 0) return [];

    final sections = <PieChartSectionData>[];

    if (onlineCount > 0) {
      sections.add(PieChartSectionData(
        value: onlineCount.toDouble(),
        color: AppColors.online,
        radius: 16.w,
        showTitle: false,
      ),);
    }
    if (offlineCount > 0) {
      sections.add(PieChartSectionData(
        value: offlineCount.toDouble(),
        color: AppColors.offline,
        radius: 16.w,
        showTitle: false,
      ),);
    }
    if (faultCount > 0) {
      sections.add(PieChartSectionData(
        value: faultCount.toDouble(),
        color: AppColors.fault,
        radius: 16.w,
        showTitle: false,
      ),);
    }

    return sections;
  }

  Widget _legendRow(BuildContext context, Color color, String label, int count, int total, IconData icon) {
    final percent = total > 0 ? (count / total * 100).toStringAsFixed(0) : '0';
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(6.w),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Icon(icon, size: 16.w, color: color),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
              ),
              SizedBox(height: 2.h),
              LinearProgressIndicator(
                value: total > 0 ? count / total : 0,
                backgroundColor: color.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(color),
                borderRadius: BorderRadius.circular(2.r),
                minHeight: 4.h,
              ),
            ],
          ),
        ),
        SizedBox(width: 10.w),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$count ${l10n.unitDevices}',
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              '$percent%',
              style: TextStyle(fontSize: 11.sp, color: AppColors.textHint),
            ),
          ],
        ),
      ],
    );
  }
}
