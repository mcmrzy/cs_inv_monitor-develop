import 'package:dio/dio.dart';

class DashboardRemoteDataSource {
  final Dio dio;

  DashboardRemoteDataSource(this.dio);

  /// 获取仪表盘统计数据（Hero 卡片 + 最近告警）
  Future<Response> getStatistics() async {
    return await dio.get('/dashboard/statistics');
  }

  /// 获取发电趋势数据
  /// [type] 时间范围类型：'day'(7日)、'week'(28日)、'month'(12个月)
  Future<Response> getTrendData({String type = 'day'}) async {
    return await dio.get('/dashboard/trend', queryParameters: {'type': type});
  }

  /// 获取设备分布数据
  Future<Response> getDeviceDistribution() async {
    return await dio.get('/dashboard/device-distribution');
  }

  /// 获取电站排行
  Future<Response> getStationRanking({int limit = 5}) async {
    return await dio.get('/dashboard/station-ranking', queryParameters: {
      'period': 'today',
      'limit': limit,
    });
  }
}

class DashboardRemoteDataSourceImpl extends DashboardRemoteDataSource {
  DashboardRemoteDataSourceImpl(super.dio);
}
