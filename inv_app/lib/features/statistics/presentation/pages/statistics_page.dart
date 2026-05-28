import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/statistics/presentation/bloc/statistics_bloc.dart';
import 'package:inv_app/core/widgets/styled_refresh_indicator.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  @override
  void initState() {
    super.initState();
    context.read<StatisticsBloc>().add(StatisticsOverviewRequested());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('数据统计')),
      body: BlocBuilder<StatisticsBloc, StatisticsState>(
        builder: (context, state) {
          if (state is StatisticsLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is StatisticsError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48.sp, color: AppColors.textHint),
                  SizedBox(height: 12.h),
                  Text(state.message, style: TextStyle(color: AppColors.textSecondary)),
                  SizedBox(height: 12.h),
                  FilledButton.icon(
                    onPressed: () => context.read<StatisticsBloc>().add(StatisticsOverviewRequested()),
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ),
            );
          }
          if (state is StatisticsOverviewLoaded) {
            final overview = state.overview;
            return StyledRefreshIndicator(
              onRefresh: () async => context.read<StatisticsBloc>().add(StatisticsOverviewRequested()),
              child: ListView(
                padding: EdgeInsets.all(16.w),
                children: [
                  _buildHeaderBanner(context, overview),
                  SizedBox(height: 16.h),
                  _buildGenerationChart(context, overview),
                  SizedBox(height: 16.h),
                  _buildDeviceStatusRing(context, overview),
                  SizedBox(height: 16.h),
                  if (overview['stations'] != null) ...[
                    Text('各电站统计', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    SizedBox(height: 12.h),
                    ...(overview['stations'] as List).map((s) => _buildStationStatsCard(context, s)),
                  ],
                  SizedBox(height: 80.h),
                ],
              ),
            );
          }
          return Center(child: Text('加载中...', style: TextStyle(color: AppColors.textHint)));
        },
      ),
    );
  }

  Widget _buildHeaderBanner(BuildContext context, dynamic overview) {
    final summary = overview['summary'] as Map<String, dynamic>? ?? {};
    final totalEnergy = (summary['total_energy'] ?? 0.0);
    final totalIncome = (summary['total_income'] ?? 0.0);
    final deviceCount = (summary['device_count'] ?? 0);

    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: AppColor.heroCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('累计统计', style: TextStyle(fontSize: 13.sp, color: Colors.white70)),
          SizedBox(height: 16.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _bannerItem('${totalEnergy.toStringAsFixed(0)}', 'kWh', '总发电量'),
              Container(width: 1, height: 40.h, color: Colors.white24),
              _bannerItem('¥${totalIncome.toStringAsFixed(0)}', '', '总收益'),
              Container(width: 1, height: 40.h, color: Colors.white24),
              _bannerItem('$deviceCount', '台', '设备总数'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bannerItem(String value, String unit, String label) {
    return Column(
      children: [
        RichText(
          text: TextSpan(
            children: [
              TextSpan(text: value, style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w800, color: Colors.white)),
              if (unit.isNotEmpty)
                TextSpan(text: ' $unit', style: TextStyle(fontSize: 12.sp, color: Colors.white70)),
            ],
          ),
        ),
        SizedBox(height: 4.h),
        Text(label, style: TextStyle(fontSize: 11.sp, color: Colors.white60)),
      ],
    );
  }

  Widget _buildGenerationChart(BuildContext context, dynamic overview) {
    final summary = overview['summary'] as Map<String, dynamic>? ?? {};
    final totalEnergy = (summary['total_energy'] ?? 0).toDouble();
    final todayEnergy = (summary['today_energy'] ?? 0).toDouble();
    final monthEnergy = (summary['month_energy'] ?? todayEnergy * 30).toDouble();

    final items = [
      {'label': '今日', 'value': todayEnergy, 'color': AppColors.primary},
      {'label': '本月', 'value': monthEnergy, 'color': AppColors.info},
      {'label': '累计', 'value': totalEnergy, 'color': AppColors.purple},
    ];

    final maxValue = items.map((e) => (e['value'] as double)).reduce((a, b) => a > b ? a : b);

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: AppColor.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('发电量统计', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          SizedBox(height: 16.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: items.map((item) {
              final value = item['value'] as double;
              final color = item['color'] as Color;
              final label = item['label'] as String;
              final height = maxValue > 0 ? (value / maxValue * 120.h) : 10.h;
              return Column(
                children: [
                  Text('${value.toStringAsFixed(1)}',
                      style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  Text('kWh', style: TextStyle(fontSize: 9.sp, color: AppColors.textHint)),
                  SizedBox(height: 6.h),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    width: 56.w,
                    height: height.clamp(20.h, 130.h),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color.withValues(alpha: 0.5), color],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(12.r)),
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Text(label, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceStatusRing(BuildContext context, dynamic overview) {
    final summary = overview['summary'] as Map<String, dynamic>? ?? {};
    final onlineCount = (summary['online_count'] ?? 0) as int;
    final faultCount = (summary['fault_count'] ?? 0) as int;
    final offlineCount = ((summary['device_count'] ?? 0) as int) - onlineCount - faultCount;
    final totalCount = onlineCount + offlineCount + faultCount;

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: AppColor.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('设备状态分布', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          SizedBox(height: 16.h),
          Row(
            children: [
              SizedBox(
                width: 100.w,
                height: 100.w,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 100.w, height: 100.w,
                      child: CircularProgressIndicator(
                        value: totalCount > 0 ? (onlineCount + faultCount) / totalCount : 0,
                        strokeWidth: 10.w,
                        backgroundColor: AppColors.offline.withValues(alpha: 0.2),
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.online),
                      ),
                    ),
                    SizedBox(
                      width: 78.w, height: 78.w,
                      child: faultCount > 0
                          ? CircularProgressIndicator(
                              value: totalCount > 0 ? faultCount / totalCount : 0,
                              strokeWidth: 10.w,
                              backgroundColor: Colors.transparent,
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.fault),
                            )
                          : null,
                    ),
                    Text('$totalCount',
                        style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  ],
                ),
              ),
              SizedBox(width: 20.w),
              Expanded(
                child: Column(
                  children: [
                    _legendRow(AppColors.online, '在线', '$onlineCount 台'),
                    SizedBox(height: 10.h),
                    _legendRow(AppColors.offline, '离线', '$offlineCount 台'),
                    SizedBox(height: 10.h),
                    _legendRow(AppColors.fault, '故障', '$faultCount 台'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendRow(Color color, String label, String count) {
    return Row(
      children: [
        Container(width: 10.w, height: 10.w, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        SizedBox(width: 8.w),
        Text(label, style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
        const Spacer(),
        Text(count, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      ],
    );
  }

  Widget _buildStationStatsCard(BuildContext context, dynamic station) {
    final name = station['station_name'] ?? '-';
    final todayEnergy = station['today_energy'] ?? 0;
    final todayIncome = station['today_income'] ?? 0;
    final deviceCount = station['device_count'] ?? 0;

    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      padding: EdgeInsets.all(14.w),
      decoration: AppColor.card(context),
      child: Row(
        children: [
          Container(
            width: 38.w, height: 38.w,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(Icons.solar_power, color: AppColors.primary, size: 20.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                SizedBox(height: 2.h),
                Text('$deviceCount 台设备', style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${todayEnergy.toStringAsFixed(1)} kWh',
                  style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.primary)),
              SizedBox(height: 2.h),
              Text('¥${todayIncome.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 12.sp, color: AppColors.warning)),
            ],
          ),
        ],
      ),
    );
  }
}
