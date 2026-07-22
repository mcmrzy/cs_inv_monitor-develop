import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/dashboard/domain/entities/station_rank_item.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 电站排行列表 - Top5 水平条形图
class StationRankingList extends StatelessWidget {
  final List<StationRankItem> items;

  const StationRankingList({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final maxEnergy = items.isNotEmpty
        ? items.map((e) => e.energy).reduce((a, b) => a > b ? a : b)
        : 1.0;
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
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(
                  Icons.leaderboard_rounded,
                  size: 18.w,
                  color: AppColors.warning,
                ),
              ),
              SizedBox(width: 10.w),
              Text(
                l10n.stationGenerationRanking,
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          ...items.take(5).toList().asMap().entries.map((entry) {
            final index = entry.key;
            final station = entry.value;
            final ratio = maxEnergy > 0 ? station.energy / maxEnergy : 0.0;

            final colors = [
              const Color(0xFFFFD700), // 金色
              const Color(0xFFC0C0C0), // 银色
              const Color(0xFFCD7F32), // 铜色
              AppColors.primary,
              AppColors.textHint,
            ];
            final color = colors[index % colors.length];

            return Padding(
              padding: EdgeInsets.only(bottom: 12.h),
              child: Row(
                children: [
                  // 排名
                  Container(
                    width: 28.w,
                    height: 28.w,
                    decoration: BoxDecoration(
                      gradient: index < 3
                          ? LinearGradient(
                              colors: [color, color.withValues(alpha: 0.7)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: index >= 3 ? color.withValues(alpha: 0.1) : null,
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w700,
                          color: index < 3 ? Colors.white : color,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  // 电站名
                  Expanded(
                    flex: 3,
                    child: Text(
                      station.stationName,
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  SizedBox(width: 8.w),
                  // 进度条
                  Expanded(
                    flex: 4,
                    child: Container(
                      height: 8.h,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: ratio,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [color, color.withValues(alpha: 0.6)],
                            ),
                            borderRadius: BorderRadius.circular(4.r),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  // 数值
                  SizedBox(
                    width: 60.w,
                    child: Text(
                      _formatEnergy(station.energy, l10n.wan),
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String _formatEnergy(double value, String wanLabel) {
    if (value >= 10000) {
      return '${(value / 10000).toStringAsFixed(1)}$wanLabel';
    }
    return '${value.toStringAsFixed(1)} kWh';
  }
}
