import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/data/alarm_code_mapping.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/core/widgets/pagination_bar.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/core/widgets/xiaoshuo_state_panel.dart';
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

  /// 级别筛选（与 Web 端 alarmLevel 对齐）：null=全部 1=严重 2=警告 3=提示
  int? _selectedLevel;

  /// 当前页码（1-based），由底部 PaginationBar 驱动
  int _currentPage = 1;
  static const int _pageSize = 20;

  AlarmListRequested _buildRequest() => AlarmListRequested(
        page: _currentPage,
        pageSize: _pageSize,
        alarmLevel: _selectedLevel,
      );

  void _request() {
    context.read<AlarmBloc>().add(_buildRequest());
  }

  Future<void> _refresh() async {
    final bloc = context.read<AlarmBloc>();
    final request = _buildRequest();
    final completed = bloc.stream.firstWhere(
      (state) => state is AlarmListLoaded || state is AlarmError,
    );
    bloc.add(request);
    try {
      await completed.timeout(const Duration(seconds: 15));
    } catch (_) {
      // 网络永久悬挂时也要结束下拉刷新动画，允许用户再次尝试。
    }
  }

  void _onLevelSelected(int? level) {
    if (_selectedLevel == level) return;
    setState(() {
      _selectedLevel = level;
      _currentPage = 1;
      _cachedState = null;
    });
    _request();
  }

  void _onPageChanged(int page) {
    setState(() => _currentPage = page);
    _request();
  }

  @override
  void initState() {
    super.initState();
    _request();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.alarmList)),
      body: BlocConsumer<AlarmBloc, AlarmState>(
        listener: (context, state) {
          if (state is AlarmError && _cachedState != null) {
            AppToast.show(
              context,
              l10n.translateError(state.message),
              type: ToastType.error,
            );
          }
        },
        builder: (context, state) {
          if (state is AlarmListLoaded) {
            _cachedState = state;
          }

          if (_cachedState is AlarmListLoaded) {
            final ds = _cachedState as AlarmListLoaded;
            final totalPages =
                (ds.total / _pageSize).ceil().clamp(1, 1 << 30).toInt();
            if (ds.alarms.isEmpty) {
              return StyledRefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(height: 80.h),
                    XiaoshuoStatePanel(
                      asset: CsergyAssets.xiaoshuoEmpty,
                      title: l10n.noAlarms,
                      size: 176,
                      action: TextButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        label: Text(l10n.retry),
                      ),
                    ),
                    _buildLevelFilterChips(context, l10n),
                  ],
                ),
              );
            }
            return Column(
              children: [
                _buildLevelFilterChips(context, l10n),
                if (ds.isFromCache)
                  OfflineDataBanner(
                    onRetry: _request,
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
                SafeArea(
                  top: false,
                  child: PaginationBar(
                    currentPage: _currentPage,
                    totalPages: totalPages,
                    onPageChanged: _onPageChanged,
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
                    onPressed: _request,
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

  /// 顶部级别筛选 Chip 行：全部 / 严重 / 警告 / 提示
  Widget _buildLevelFilterChips(BuildContext context, AppLocalizations l10n) {
    final entries = <int?, String>{
      null: l10n.all,
      1: l10n.severe,
      2: l10n.warningLevel,
      3: l10n.infoLevel,
    };
    return Container(
      width: double.infinity,
      color: AppColor.surfaceContainer(context),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: entries.entries
              .map(
                (e) => Padding(
                  padding: EdgeInsets.only(right: 8.w),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: _selectedLevel == e.key,
                    onSelected: (_) => _onLevelSelected(e.key),
                    labelStyle: TextStyle(
                      fontSize: 12.sp,
                      color: _selectedLevel == e.key
                          ? Colors.white
                          : AppColor.textSecondary(context),
                    ),
                    selectedColor: AppColors.primary,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(
                      color: _selectedLevel == e.key
                          ? AppColors.primary
                          : AppColor.border(context),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
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
