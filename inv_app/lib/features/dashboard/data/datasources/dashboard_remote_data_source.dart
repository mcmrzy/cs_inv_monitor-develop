import 'package:dio/dio.dart';

class DashboardRemoteDataSource {
  final Dio dio;

  DashboardRemoteDataSource(this.dio);

  /// 获取仪表盘统计数据（Hero 卡片 + 最近告警）
  Future<Response> getStatistics() async {
    return await dio.get('/dashboard/statistics');
  }

  /// 获取 7 日发电趋势
  Future<Response> getTrendData() async {
    return await dio.get('/dashboard/trend', queryParameters: {'type': 'day'});
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
