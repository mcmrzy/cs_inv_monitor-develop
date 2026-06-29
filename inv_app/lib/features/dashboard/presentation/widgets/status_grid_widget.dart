import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 状态卡片网格 - 2列网格显示在线/离线/故障/告警状态
class StatusGridWidget extends StatelessWidget {
  final int onlineCount;
  final int offlineCount;
  final int faultCount;
  final int alarmCount;
  final int? previousOnlineCount;
  final int? previousOfflineCount;
  final int? previousFaultCount;
  final int? previousAlarmCount;
  final VoidCallback? onOnlineTap;
  final VoidCallback? onOfflineTap;
  final VoidCallback? onFaultTap;
  final VoidCallback? onAlarmTap;

  const StatusGridWidget({
    super.key,
    required this.onlineCount,
    required this.offlineCount,
    required this.faultCount,
    required this.alarmCount,
    this.previousOnlineCount,
    this.previousOfflineCount,
    this.previousFaultCount,
    this.previousAlarmCount,
    this.onOnlineTap,
    this.onOfflineTap,
    this.onFaultTap,
    this.onAlarmTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12.h,
      crossAxisSpacing: 12.w,
      childAspectRatio: 1.8,
      children: [
        _StatusCard(
          icon: Icons.check_circle_rounded,
          label: l10n.statusOnline,
          count: onlineCount,
          color: AppColors.online,
          previousCount: previousOnlineCount,
          onTap: onOnlineTap,
          isOnline: true,
        ),
        _StatusCard(
          icon: Icons.pause_circle_rounded,
          label: l10n.statusOffline,
          count: offlineCount,
          color: AppColors.offline,
          previousCount: previousOfflineCount,
          onTap: onOfflineTap,
        ),
        _StatusCard(
          icon: Icons.error_rounded,
          label: l10n.statusFault,
          count: faultCount,
          color: AppColors.fault,
          previousCount: previousFaultCount,
          onTap: onFaultTap,
        ),
        _StatusCard(
          icon: Icons.notifications_active_rounded,
          label: l10n.statusAlarm,
          count: alarmCount,
          color: AppColors.warning,
          previousCount: previousAlarmCount,
          onTap: onAlarmTap,
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;
  final int? previousCount;
  final VoidCallback? onTap;
  final bool isOnline;

  const _StatusCard({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    this.previousCount,
    this.onTap,
    this.isOnline = false,
  });

  @override
  Widget build(BuildContext context) {
    final change = previousCount != null ? count - previousCount! : 0;
    final isPositive = change > 0;
    final isNeutral = change == 0;

    Color changeColor;
    IconData changeIcon;

    if (isNeutral) {
      changeColor = AppColors.textHint;
      changeIcon = Icons.remove;
    } else if (isPositive) {
      // 对于在线数量，增加是好事；对于离线/故障/告警，增加是坏事
      final isGood = label == '在线';
      changeColor = isGood ? AppColors.success : AppColors.error;
      changeIcon = Icons.arrow_upward;
    } else {
      // 对于在线数量，减少是坏事；对于离线/故障/告警，减少是好事
      final isGood = label != '在线';
      changeColor = isGood ? AppColors.success : AppColors.error;
      changeIcon = Icons.arrow_downward;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: color.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, size: 24.w, color: color),
                const Spacer(),
                if (previousCount != null)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 6.w,
                      vertical: 2.h,
                    ),
                    decoration: BoxDecoration(
                      color: changeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(changeIcon, size: 10.w, color: changeColor),
                        SizedBox(width: 2.w),
                        Text(
                          '${isPositive ? '+' : ''}$change',
                          style: TextStyle(
                            fontSize: 10.sp,
                            fontWeight: FontWeight.w600,
                            color: changeColor,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 24.sp,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
