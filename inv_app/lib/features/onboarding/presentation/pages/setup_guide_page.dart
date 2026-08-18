import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/features/onboarding/data/setup_guide_storage.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 首启快速设置向导（登录后无电站时触发）
///
/// 一步步带用户点击操作的三屏向导：创建电站 → 添加设备 → 配网（可选）。
/// 每屏含图标、说明与可点击的子步骤清单，「去完成」直达对应页面；
/// 返回后根据 StationBloc / DeviceBloc 实时数据判断完成并自动进入下一步。
/// 跳过或完成置位后不再弹出。
class SetupGuidePage extends StatefulWidget {
  const SetupGuidePage({super.key});

  @override
  State<SetupGuidePage> createState() => _SetupGuidePageState();
}

class _SetupGuidePageState extends State<SetupGuidePage> {
  final _guideStorage = SetupGuideStorage();
  final _pageController = PageController();

  /// 当前步骤下标（0 创建电站 / 1 添加设备 / 2 配网）
  int _step = 0;

  static const int _totalSteps = 3;

  @override
  void initState() {
    super.initState();
    // 刷新完成状态所需的数据
    context.read<StationBloc>().add(StationSummaryRequested());
    context.read<DeviceBloc>().add(const DeviceListRequested(pageSize: 200));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finishAndPop() async {
    await _guideStorage.markDone();
    if (!mounted) return;
    context.pop();
  }

  void _goTo(int step) {
    final target = step.clamp(0, _totalSteps - 1);
    if (target == _step) return;
    setState(() => _step = target);
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  /// 当前步骤是否已完成（第 3 步配网可选，无完成判据）
  bool _stepDone(int step, StationState stationState, DeviceState deviceState) {
    return switch (step) {
      0 => stationState is StationSummaryLoaded && stationState.stations.isNotEmpty,
      1 => deviceState is DeviceListLoaded && deviceState.devices.isNotEmpty,
      _ => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return MultiBlocListener(
      listeners: [
        // 完成电站创建 → 自动进入下一步
        BlocListener<StationBloc, StationState>(
          listener: (context, state) {
            if (_step == 0 && _stepDone(0, state, context.read<DeviceBloc>().state)) {
              _goTo(1);
            }
          },
        ),
        // 完成设备绑定 → 自动进入配网步骤
        BlocListener<DeviceBloc, DeviceState>(
          listener: (context, state) {
            if (_step == 1 && _stepDone(1, context.read<StationBloc>().state, state)) {
              _goTo(2);
            }
          },
        ),
      ],
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.str('setup_guide_title')),
          actions: [
            TextButton(
              onPressed: _finishAndPop,
              child: Text(l10n.skip),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // 顶部进度：第 X / 3 步 + 进度条
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.str(
                        'setup_guide_step_of',
                        {'current': '${_step + 1}', 'total': '$_totalSteps'},
                      ),
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4.r),
                      child: LinearProgressIndicator(
                        value: (_step + 1) / _totalSteps,
                        minHeight: 6.h,
                        backgroundColor: AppColor.surfaceHover(context),
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              // 三步内容
              Expanded(
                child: BlocBuilder<StationBloc, StationState>(
                  builder: (context, stationState) {
                    return BlocBuilder<DeviceBloc, DeviceState>(
                      builder: (context, deviceState) {
                        return PageView(
                          controller: _pageController,
                          onPageChanged: (index) => setState(() => _step = index),
                          children: [
                            _buildStepPage(
                              l10n: l10n,
                              step: 0,
                              icon: Icons.home_work_rounded,
                              title: l10n.createStation,
                              desc: l10n.str('setup_guide_step1_desc'),
                              items: [
                                l10n.str('setup_guide_s1_item1'),
                                l10n.str('setup_guide_s1_item2'),
                                l10n.str('setup_guide_s1_item3'),
                              ],
                              route: '/station/create',
                              done: _stepDone(0, stationState, deviceState),
                            ),
                            _buildStepPage(
                              l10n: l10n,
                              step: 1,
                              icon: Icons.qr_code_scanner_rounded,
                              title: l10n.addDevice,
                              desc: l10n.str('setup_guide_step2_desc'),
                              items: [
                                l10n.str('setup_guide_s2_item1'),
                                l10n.str('setup_guide_s2_item2'),
                                l10n.str('setup_guide_s2_item3'),
                              ],
                              route: '/add-device',
                              done: _stepDone(1, stationState, deviceState),
                            ),
                            _buildStepPage(
                              l10n: l10n,
                              step: 2,
                              icon: Icons.wifi_rounded,
                              title: l10n.wifiConfig,
                              desc: l10n.str('setup_guide_step3_desc'),
                              items: [
                                l10n.str('setup_guide_s3_item1'),
                                l10n.str('setup_guide_s3_item2'),
                                l10n.str('setup_guide_s3_item3'),
                              ],
                              route: '/wifi-config',
                              done: false,
                              optional: true,
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              // 底部操作区
              _buildBottomBar(l10n),
            ],
          ),
        ),
      ),
    );
  }

  /// 单步页面：图标 + 标题 + 说明 + 子步骤清单 + 「去完成」按钮
  Widget _buildStepPage({
    required AppLocalizations l10n,
    required int step,
    required IconData icon,
    required String title,
    required String desc,
    required List<String> items,
    required String route,
    required bool done,
    bool optional = false,
  }) {
    final accent = done ? AppColors.success : AppColors.primary;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 图标
          Container(
            width: 72.w,
            height: 72.w,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: done
                ? Icon(Icons.check_rounded, size: 36.sp, color: accent)
                : Icon(icon, size: 34.sp, color: accent),
          ),
          SizedBox(height: 14.h),
          // 标题（可选步骤带徽标）
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColor.textPrimary(context),
                ),
              ),
              if (optional) ...[
                SizedBox(width: 8.w),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                  decoration: BoxDecoration(
                    color: AppColor.surfaceHover(context),
                    borderRadius: BorderRadius.circular(6.r),
                  ),
                  child: Text(
                    l10n.str('setup_guide_step_optional'),
                    style: TextStyle(
                      fontSize: 10.sp,
                      color: AppColor.textHint(context),
                    ),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: 6.h),
          Text(
            desc,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.sp,
              color: AppColor.textHint(context),
            ),
          ),
          SizedBox(height: 20.h),
          // 操作步骤清单
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: AppColor.surfaceContainer(context),
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(
                color: done
                    ? AppColors.success.withValues(alpha: 0.35)
                    : AppColor.divider(context),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) SizedBox(height: 14.h),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22.w,
                        height: 22.w,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(top: 2.h),
                          child: Text(
                            items[i],
                            style: TextStyle(
                              fontSize: 13.sp,
                              height: 1.5,
                              color: AppColor.textSecondary(context),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: 20.h),
          // 「去完成」直达按钮
          SizedBox(
            width: double.infinity,
            height: 46.h,
            child: done
                ? OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.success,
                      side: BorderSide(color: AppColors.success.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    onPressed: _step < _totalSteps - 1 ? () => _goTo(_step + 1) : null,
                    icon: Icon(Icons.check_circle_rounded, size: 18.sp),
                    label: Text(
                      _step < _totalSteps - 1
                          ? l10n.str('setup_guide_next')
                          : l10n.str('setup_guide_step_done'),
                      style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                    ),
                  )
                : FilledButton.icon(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    onPressed: () => context.push(route),
                    icon: Icon(Icons.arrow_forward_rounded, size: 18.sp),
                    label: Text(
                      l10n.str('setup_guide_go'),
                      style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// 底部操作区：上一步 / 跳过此步（可选步骤）/ 完成
  Widget _buildBottomBar(AppLocalizations l10n) {
    final isLast = _step == _totalSteps - 1;
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
      child: Row(
        children: [
          if (_step > 0) ...[
            Expanded(
              child: SizedBox(
                height: 48.h,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                  onPressed: () => _goTo(_step - 1),
                  child: Text(
                    l10n.str('setup_guide_back'),
                    style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            SizedBox(width: 12.w),
          ],
          Expanded(
            flex: _step > 0 ? 2 : 1,
            child: SizedBox(
              height: 48.h,
              child: FilledButton(
                onPressed: isLast ? _finishAndPop : () => _goTo(_step + 1),
                child: Text(
                  isLast
                      ? l10n.str('setup_guide_finish')
                      : l10n.str('setup_guide_next'),
                  style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
