import 'package:inv_app/features/dashboard/domain/entities/trend_data_point.dart';
import 'package:inv_app/features/dashboard/domain/entities/station_rank_item.dart';

/// 仪表盘组合数据 - 包含所有仪表盘区域的数据
class DashboardData {
  final double todayEnergy; // 今日发电量 (kWh)
  final double totalEnergy; // 累计发电量 (kWh)
  final int deviceTotal; // 设备总数
  final int onlineCount; // 在线设备数
  final int offlineCount; // 离线设备数
  final int faultCount; // 故障设备数
  final List<TrendDataPoint> trendData; // 7 日发电趋势
  final List<StationRankItem> stationRanking; // 电站排行
  final List<Map<String, dynamic>> recentAlarms; // 最近告警
  final bool isFromCache; // 是否来自缓存

  const DashboardData({
    required this.todayEnergy,
    required this.totalEnergy,
    required this.deviceTotal,
    required this.onlineCount,
    required this.offlineCount,
    required this.faultCount,
    required this.trendData,
    required this.stationRanking,
    required this.recentAlarms,
    this.isFromCache = false,
  });

  DashboardData copyWith({
    double? todayEnergy,
    double? totalEnergy,
    int? deviceTotal,
    int? onlineCount,
    int? offlineCount,
    int? faultCount,
    List<TrendDataPoint>? trendData,
    List<StationRankItem>? stationRanking,
    List<Map<String, dynamic>>? recentAlarms,
    bool? isFromCache,
  }) {
    return DashboardData(
      todayEnergy: todayEnergy ?? this.todayEnergy,
      totalEnergy: totalEnergy ?? this.totalEnergy,
      deviceTotal: deviceTotal ?? this.deviceTotal,
      onlineCount: onlineCount ?? this.onlineCount,
      offlineCount: offlineCount ?? this.offlineCount,
      faultCount: faultCount ?? this.faultCount,
      trendData: trendData ?? this.trendData,
      stationRanking: stationRanking ?? this.stationRanking,
      recentAlarms: recentAlarms ?? this.recentAlarms,
      isFromCache: isFromCache ?? this.isFromCache,
    );
  }
}
