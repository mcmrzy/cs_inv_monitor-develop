import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/styled_refresh_indicator.dart';
import 'package:inv_app/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:inv_app/features/dashboard/presentation/widgets/hero_energy_card.dart';
import 'package:inv_app/features/dashboard/presentation/widgets/quick_stats_row.dart';
import 'package:inv_app/features/dashboard/presentation/widgets/energy_trend_chart.dart';
import 'package:inv_app/features/dashboard/presentation/widgets/device_distribution_chart.dart';
import 'package:inv_app/features/dashboard/presentation/widgets/station_ranking_list.dart';
import 'package:inv_app/features/dashboard/presentation/widgets/recent_alarms_card.dart';
import 'package:inv_app/features/dashboard/presentation/widgets/dashboard_skeleton.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 数据概览页面
class DashboardOverviewPage extends StatefulWidget {
  const DashboardOverviewPage({super.key});

  @override
  State<DashboardOverviewPage> createState() => _DashboardOverviewPageState();
}

class _DashboardOverviewPageState extends State<DashboardOverviewPage> {
  @override
  void initState() {
    super.initState();
    context.read<DashboardBloc>().add(const DashboardLoadRequested());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(50.h),
        child: AppBar(
          title: Text(
            AppLocalizations.of(context)!.dataOverview,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17.sp),
          ),
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
        ),
      ),
      body: BlocConsumer<DashboardBloc, DashboardState>(
        listener: (context, state) {
          // 数据加载成功后自动连接 SSE
          if (state is DashboardLoaded && !state.isSSEConnected) {
            context.read<DashboardBloc>().add(const DashboardSSEConnectRequested());
          }
        },
        builder: (context, state) {
          if (state is DashboardLoading && state is! DashboardLoaded) {
            return const DashboardSkeleton();
          }

          if (state is DashboardError) {
            return _buildError(context, state.message);
          }

          if (state is DashboardLoaded) {
            return _buildContent(context, state);
          }

          return const DashboardSkeleton();
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, DashboardLoaded state) {
    final data = state.data;

    return StyledRefreshIndicator(
      onRefresh: () async {
        context.read<DashboardBloc>().add(const DashboardLoadRequested());
        await context.read<DashboardBloc>().stream.firstWhere(
              (s) => s is! DashboardLoading,
            );
      },
      child: ListView(
        padding: EdgeInsets.symmetric(vertical: 16.h),
        children: [
          // 离线数据提示
          if (data.isFromCache) _buildCacheBanner(),

          // Hero 能量卡片
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: HeroEnergyCard(
              todayEnergy: data.todayEnergy,
              totalEnergy: data.totalEnergy,
              deviceCount: data.deviceTotal,
            ),
          ),
          SizedBox(height: 16.h),

          // 快捷状态行
          QuickStatsRow(
            onlineCount: data.onlineCount,
            offlineCount: data.offlineCount,
            faultCount: data.faultCount,
          ),
          SizedBox(height: 16.h),

          // 能量趋势图
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: EnergyTrendChart(data: data.trendData),
          ),
          SizedBox(height: 16.h),

          // 设备分布图
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: DeviceDistributionChart(
              onlineCount: data.onlineCount,
              offlineCount: data.offlineCount,
              faultCount: data.faultCount,
            ),
          ),
          SizedBox(height: 16.h),

          // 电站排行
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: StationRankingList(items: data.stationRanking),
          ),
          SizedBox(height: 16.h),

          // 最近告警
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: RecentAlarmsCard(alarms: data.recentAlarms),
          ),

          // 底部留白
          SizedBox(height: 100.h),
        ],
      ),
    );
  }

  Widget _buildCacheBanner() {
    return Container(
      margin: EdgeInsets.only(left: 16.w, right: 16.w, bottom: 12.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 16.w, color: AppColors.warning),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              AppLocalizations.of(context)!.offlineDataHint,
              style: TextStyle(fontSize: 12.sp, color: AppColors.warning),
            ),
          ),
          GestureDetector(
            onTap: () {
              context.read<DashboardBloc>().add(const DashboardLoadRequested());
            },
            child: Text(
              AppLocalizations.of(context)!.retry,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, String message) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(40.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 44.sp,
              color: AppColors.textHint,
            ),
            SizedBox(height: 12.h),
            Text(
              l10n.translateError(message),
              style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16.h),
            OutlinedButton(
              onPressed: () {
                context.read<DashboardBloc>().add(const DashboardLoadRequested());
              },
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}
