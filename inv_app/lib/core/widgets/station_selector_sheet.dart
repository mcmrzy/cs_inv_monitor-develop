import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 电站选择面板（从 add_device_page 提取的共享组件）：
/// 可拖拽高度 + 电站列表，选中后回调 (stationId, stationName)。
/// 用于设备绑定/换绑等需要选择目标电站的场景。
class StationSelectorSheet extends StatefulWidget {
  final void Function(int stationId, String stationName) onSelected;
  final VoidCallback onCancel;

  const StationSelectorSheet({
    super.key,
    required this.onSelected,
    required this.onCancel,
  });

  @override
  State<StationSelectorSheet> createState() => _StationSelectorSheetState();
}

class _StationSelectorSheetState extends State<StationSelectorSheet> {
  @override
  void initState() {
    super.initState();
    context.read<StationBloc>().add(StationSummaryRequested());
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollCtl) {
        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 8.h),
              child: Row(
                children: [
                  Container(
                    width: 40.w,
                    height: 4.h,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2.r),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
              child: Row(
                children: [
                  Text(
                    AppLocalizations.of(context)!.selectStation,
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: widget.onCancel,
                    child: const Icon(
                      Icons.close,
                      size: 24,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Text(
                AppLocalizations.of(context)!.selectStationForDevice,
                style: TextStyle(fontSize: 13.sp, color: AppColors.textHint),
              ),
            ),
            SizedBox(height: 12.h),
            Expanded(
              child: BlocBuilder<StationBloc, StationState>(
                builder: (context, state) {
                  if (state is StationLoading || state is StationInitial) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (state is StationError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            AppLocalizations.of(context)!
                                .translateError(state.message),
                            style: TextStyle(
                              fontSize: 14.sp,
                              color: AppColors.errorLight,
                            ),
                          ),
                          SizedBox(height: 12.h),
                          ElevatedButton(
                            onPressed: () => context
                                .read<StationBloc>()
                                .add(StationSummaryRequested()),
                            child: Text(AppLocalizations.of(context)!.retry),
                          ),
                        ],
                      ),
                    );
                  }
                  List<dynamic> stations = [];
                  if (state is StationSummaryLoaded) {
                    stations = state.stations;
                  }
                  if (stations.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.home_work_outlined,
                            size: 48,
                            color: AppColors.textHint,
                          ),
                          SizedBox(height: 12.h),
                          Text(
                            AppLocalizations.of(context)!.noStationsYet,
                            style: TextStyle(
                              fontSize: 15.sp,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          SizedBox(height: 8.h),
                          Text(
                            AppLocalizations.of(context)!.createStationFirst,
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: AppColors.textHint,
                            ),
                          ),
                          SizedBox(height: 16.h),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              context.push('/station/create');
                            },
                            icon: const Icon(Icons.add),
                            label: Text(
                              AppLocalizations.of(context)!.createStation,
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: scrollCtl,
                    padding: EdgeInsets.symmetric(
                      horizontal: 20.w,
                      vertical: 8.h,
                    ),
                    itemCount: stations.length,
                    separatorBuilder: (_, __) => SizedBox(height: 8.h),
                    itemBuilder: (_, i) {
                      final s = stations[i];
                      final id = (s['station_id'] ?? s['id']) as int;
                      final name =
                          (s['station_name'] ?? s['name'] ?? '').toString();
                      final deviceCount =
                          (s['device_count'] as num?)?.toInt() ?? 0;
                      return Material(
                        color: AppColor.surfaceContainer(context),
                        borderRadius: BorderRadius.circular(12.r),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12.r),
                          onTap: () => widget.onSelected(id, name),
                          child: Padding(
                            padding: EdgeInsets.all(16.w),
                            child: Row(
                              children: [
                                Container(
                                  width: 44.w,
                                  height: 44.w,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10.r),
                                  ),
                                  child: const Icon(
                                    Icons.solar_power,
                                    color: AppColors.primary,
                                    size: 22,
                                  ),
                                ),
                                SizedBox(width: 14.w),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: TextStyle(
                                          fontSize: 15.sp,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      SizedBox(height: 2.h),
                                      Text(
                                        AppLocalizations.of(context)!
                                            .nDevices('$deviceCount'),
                                        style: TextStyle(
                                          fontSize: 12.sp,
                                          color: AppColors.textHint,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_forward_ios,
                                  size: 16,
                                  color: AppColors.textHint,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
