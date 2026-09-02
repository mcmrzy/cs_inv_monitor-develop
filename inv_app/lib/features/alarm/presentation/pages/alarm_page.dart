import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/data/alarm_code_mapping.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
import 'package:inv_app/features/alarm/presentation/bloc/alarm_bloc.dart';
import 'package:inv_app/core/widgets/styled_refresh_indicator.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class AlarmPage extends StatefulWidget {
  const AlarmPage({super.key});

  @override
  State<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends State<AlarmPage> {
  AlarmState? _cachedState;

  Future<void> _refresh() async {
    final bloc = context.read<AlarmBloc>();
    final completed = bloc.stream.firstWhere(
      (state) => state is AlarmListLoaded || state is AlarmError,
    );
    bloc.add(const AlarmListRequested());
    try {
      await completed.timeout(const Duration(seconds: 15));
    } catch (_) {
      // 网络永久悬挂时也要结束下拉刷新动画，允许用户再次尝试。
    }
  }

  @override
  void initState() {
    super.initState();
    context.read<AlarmBloc>().add(const AlarmListRequested());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.alarmList)),
      body: BlocConsumer<AlarmBloc, AlarmState>(
        listener: (context, state) {
          if (state is AlarmError && _cachedState != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.translateError(state.message)),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
        builder: (context, state) {
          if (state is AlarmListLoaded) {
            _cachedState = state;
          }

          if (_cachedState is AlarmListLoaded) {
            final ds = _cachedState as AlarmListLoaded;
            if (ds.alarms.isEmpty) {
              return StyledRefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(height: 120.h),
                    Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.notifications_none,
                            size: 64.sp,
                            color: AppColor.textHint(context),
                          ),
                          SizedBox(height: 16.h),
                          Text(
                            l10n.noAlarms,
                            style: TextStyle(
                              color: AppColor.textHint(context),
                              fontSize: 16.sp,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }
            return Column(
              children: [
                if (ds.isFromCache)
                  OfflineDataBanner(
                    onRetry: () => context
                        .read<AlarmBloc>()
                        .add(const AlarmListRequested()),
                  ),
                Expanded(
                  child: StyledRefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView.builder(
                      padding: EdgeInsets.all(12.w),
                      itemCount: ds.alarms.length,
                      itemBuilder: (context, index) =>
                          _buildAlarmCard(context, ds.alarms[index], l10n),
                    ),
                  ),
                ),
              ],
            );
          }

          if (state is AlarmError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48.sp,
                    color: AppColor.textHint(context),
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    l10n.translateError(state.message),
                    style: TextStyle(color: AppColor.textSecondary(context)),
                  ),
                  SizedBox(height: 12.h),
                  FilledButton.icon(
                    onPressed: () => context
                        .read<AlarmBloc>()
                        .add(const AlarmListRequested()),
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.retry),
                  ),
                ],
              ),
            );
          }

          return _buildSkeletonList();
        },
      ),
    );
  }

  Widget _buildSkeletonList() {
    return ListView.builder(
      padding: EdgeInsets.all(12.w),
      itemCount: 8,
      itemBuilder: (context, index) => const SkeletonListItem(),
    );
  }

  String _levelToSeverity(dynamic level) {
    switch (level) {
      case 3:
        return 'fault';
      case 2:
        return 'warning';
      default:
        return 'info';
    }
  }

  Widget _buildAlarmCard(
    BuildContext context,
    dynamic alarm,
    AppLocalizations l10n,
  ) {
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
    final alarmEntry =
        parsedCode >= 0 ? AlarmCodeMapping.getEntry(parsedCode) : null;
    final severity =
        alarmEntry?.severity ?? _levelToSeverity(alarm['alarm_level']);

    Color levelColor;
    String levelText;
    switch (severity) {
      case 'fault':
        levelColor = AppColors.errorLight;
        levelText = l10n.severe;
        break;
      case 'warning':
        levelColor = AppColors.warning;
        levelText = l10n.warningLevel;
        break;
      case 'info':
        levelColor = AppColors.blue;
        levelText = l10n.infoLevel;
        break;
      case 'normal':
        levelColor = AppColors.success;
        levelText = l10n.normal;
        break;
      default:
        levelColor = AppColor.textHint(context);
        levelText = l10n.general;
    }

    final isRead = alarm['status'] == 1;

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: InkWell(
        onTap: () => context.push('/alarm/${alarm['id']}'),
        borderRadius: BorderRadius.circular(14.r),
        child: Padding(
          padding: EdgeInsets.all(14.w),
          child: Row(
            children: [
              Container(
                width: 32.w,
                height: 32.w,
                decoration: BoxDecoration(
                  color: (isRead ? AppColor.textHint(context) : levelColor)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(
                  isRead
                      ? Icons.notifications_none
                      : Icons.warning_amber_rounded,
                  size: 18.sp,
                  color: isRead ? AppColor.textHint(context) : levelColor,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            alarm['fault_message'] ?? l10n.alarm,
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight:
                                  isRead ? FontWeight.w500 : FontWeight.w600,
                              color: AppColor.textPrimary(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6.w,
                            vertical: 2.h,
                          ),
                          decoration: BoxDecoration(
                            color: levelColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4.r),
                          ),
                          child: Text(
                            levelText,
                            style: TextStyle(
                              fontSize: 10.sp,
                              fontWeight: FontWeight.w600,
                              color: levelColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      '${l10n.deviceLabel}: ${alarm['device_sn'] ?? '-'}  ${l10n.faultCodeLabel}: ${alarm['fault_code'] ?? '-'}',
                      style:
                          TextStyle(fontSize: 12.sp, color: AppColor.textHint(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColor.textHint(context), size: 20.sp),
            ],
          ),
        ),
      ),
    );
  }
}
