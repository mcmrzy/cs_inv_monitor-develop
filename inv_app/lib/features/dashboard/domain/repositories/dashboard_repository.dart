import 'package:dartz/dartz.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/features/dashboard/domain/entities/trend_data_point.dart';
import 'package:inv_app/features/dashboard/domain/entities/station_rank_item.dart';

abstract class DashboardRepository {
  /// 获取仪表盘统计数据（Hero 卡片 + 最近告警）
  Future<Either<Failure, Map<String, dynamic>>> getStatistics();

  /// 获取 7 日发电趋势
  Future<Either<Failure, List<TrendDataPoint>>> getTrendData();

  /// 获取设备分布数据
  Future<Either<Failure, Map<String, dynamic>>> getDeviceDistribution();

  /// 获取电站排行
  Future<Either<Failure, List<StationRankItem>>> getStationRanking();
}
