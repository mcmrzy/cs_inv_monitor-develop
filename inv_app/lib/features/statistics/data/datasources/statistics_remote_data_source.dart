import 'package:dio/dio.dart';

class StatisticsRemoteDataSource {
  final Dio dio;

  StatisticsRemoteDataSource(this.dio);

  Future<Response> getOverview() async {
    return await dio.get('/stations/summary');
  }

  Future<Response> getStationStatistics(int stationId, String startDate, String endDate, String period) async {
    return await dio.get('/stations/$stationId/statistics', queryParameters: {
      'start_date': startDate,
      'end_date': endDate,
      'period': period,
    });
  }

  Future<Response> getDeviceStatistics(String sn, String startDate, String endDate, String period) async {
    return await dio.get('/devices/$sn/statistics', queryParameters: {
      'start_date': startDate,
      'end_date': endDate,
      'period': period,
    });
  }
}

class StatisticsRemoteDataSourceImpl extends StatisticsRemoteDataSource {
  StatisticsRemoteDataSourceImpl(super.dio);
}
