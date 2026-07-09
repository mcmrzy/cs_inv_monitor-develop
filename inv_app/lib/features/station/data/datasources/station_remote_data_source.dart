import 'package:dio/dio.dart';

class StationRemoteDataSource {
  final Dio dio;

  StationRemoteDataSource(this.dio);

  Future<Response> getSummary() async {
    return await dio.get('/stations/summary');
  }

  Future<Response> getList({int page = 1, int pageSize = 20}) async {
    return await dio.get('/stations', queryParameters: {
      'page': page,
      'page_size': pageSize,
    },);
  }

  Future<Response> getDetail(int stationId) async {
    return await dio.get('/stations/$stationId');
  }

  Future<Response> create(Map<String, dynamic> data) async {
    return await dio.post('/stations', data: data);
  }

  Future<Response> update(int stationId, Map<String, dynamic> data) async {
    return await dio.put('/stations/$stationId', data: data);
  }

  Future<Response> delete(int stationId) async {
    return await dio.delete('/stations/$stationId');
  }

  Future<Response> getStatistics(int stationId, String startDate, String endDate, String period) async {
    return await dio.get('/stations/$stationId/statistics', queryParameters: {
      'start_date': startDate,
      'end_date': endDate,
      'period': period,
    },);
  }
}

class StationRemoteDataSourceImpl extends StationRemoteDataSource {
  StationRemoteDataSourceImpl(super.dio);
}
