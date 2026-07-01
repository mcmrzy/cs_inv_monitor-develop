import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/data/alarm_code_mapping.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/utils/timezone_utils.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 最近告警卡片 - 展示 3-5 条最近告警
class RecentAlarmsCard extends StatelessWidget {
  final List<Map<String, dynamic>> alarms;

  const RecentAlarmsCard({super.key, required this.alarms});

  @override
  Widget build(BuildContext context) {
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
          // 标题行
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(Icons.notifications_active_rounded, size: 18.w, color: AppColors.error),
              ),
              SizedBox(width: 10.w),
              Text(
                l10n.recentAlarms,
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.go('/alarms'),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.viewAll,
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(width: 2.w),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 10.w,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          if (alarms.isEmpty)
            _buildEmpty(l10n)
          else
            ...alarms.take(5).map((alarm) => _buildAlarmItem(context, alarm, l10n)),
        ],
      ),
    );
  }

  Widget _buildEmpty(AppLocalizations l10n) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 24.h),
      child: Center(
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_outline_rounded,
                size: 32.w,
                color: AppColors.success,
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              l10n.noAlarms,
              style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlarmItem(BuildContext context, Map<String, dynamic> alarm, AppLocalizations l10n) {
    final level = (alarm['alarm_level'] as num?)?.toInt() ?? 0;
    final faultMessage = alarm['fault_message'] as String? ?? l10n.unknownAlarm;
    final deviceSn = alarm['device_sn'] as String? ?? '';
    final occurredAt = alarm['occurred_at'] as String? ?? '';
    final alarmId = alarm['id'] as int?;

    // 优先使用 fault_code 映射实际严重级别
    final faultCode = alarm['fault_code'];
    int parsedCode = -1;
    if (faultCode is int) {
      parsedCode = faultCode;
    } else if (faultCode != null) {
      final str = faultCode.toString();
      if (str.startsWith('0x') || str.startsWith('0X')) {
        parsedCode = int.tryParse(str.substring(2), radix: 16) ?? -1;
      } else {
        parsedCode = int.tryParse(str) ?? -1;
      }
    }
    final alarmEntry = parsedCode >= 0 ? AlarmCodeMapping.getEntry(parsedCode) : null;
    final severity = alarmEntry?.severity ?? _levelToSeverity(level);

    final levelColor = _getSeverityColor(severity);
    final levelLabel = _getSeverityLabel(severity, l10n);
    final timeAgo = _formatTimeAgo(occurredAt);

    return GestureDetector(
      onTap: alarmId != null ? () => context.push('/alarm/$alarmId') : null,
      child: Container(
        margin: EdgeInsets.only(bottom: 10.h),
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: levelColor.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: levelColor.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            // 状态点
            Container(
              width: 10.w,
              height: 10.w,
              decoration: BoxDecoration(
                color: levelColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: levelColor.withValues(alpha: 0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
            SizedBox(width: 12.w),
            // 内容
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          faultMessage,
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8.w,
                          vertical: 3.h,
                        ),
                        decoration: BoxDecoration(
                          color: levelColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6.r),
                        ),
                        child: Text(
                          levelLabel,
                          style: TextStyle(
                            fontSize: 10.sp,
                            color: levelColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6.h),
                  Row(
                    children: [
                      if (deviceSn.isNotEmpty) ...[
                        Icon(Icons.device_hub_rounded, size: 12.w, color: AppColors.textHint),
                        SizedBox(width: 4.w),
                        Text(
                          deviceSn,
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: AppColors.textHint,
                          ),
                        ),
                        SizedBox(width: 12.w),
                      ],
                      Icon(Icons.access_time_rounded, size: 12.w, color: AppColors.textHint),
                      SizedBox(width: 4.w),
                      Text(
                        timeAgo,
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 箭头
            Icon(
              Icons.arrow_forward_ios,
              size: 14.w,
              color: AppColors.textHint,
            ),
          ],
        ),
      ),
    );
  }

  String _levelToSeverity(int level) {
    switch (level) {
      case 3:
        return 'fault';
      case 2:
        return 'warning';
      case 1:
        return 'info';
      default:
        return 'normal'; // code=0
    }
  }

  Color _getSeverityColor(String severity) {
    switch (severity) {
      case 'fault':
        return AppColors.errorLight;
      case 'warning':
        return AppColors.warning;
      case 'info':
        return AppColors.blue;
      case 'normal':
        return AppColors.success;
      default:
        return AppColors.textHint;
    }
  }

  String _getSeverityLabel(String severity, AppLocalizations l10n) {
    switch (severity) {
      case 'fault':
        return l10n.severe;
      case 'warning':
        return l10n.warningLevel;
      case 'info':
        return l10n.infoLevel;
      case 'normal':
        return '正常';
      default:
        return l10n.general;
    }
  }

  String _formatTimeAgo(String dateTimeStr) {
    return TimezoneUtils.formatRelativeTime(dateTimeStr);
  }
}
