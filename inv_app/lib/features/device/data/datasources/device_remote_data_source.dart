import 'package:dio/dio.dart';

class DeviceRemoteDataSource {
  final Dio dio;

  DeviceRemoteDataSource(this.dio);

  Future<Response> getList({
    int? stationId,
    int? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'page_size': pageSize,
    };
    if (stationId != null) params['station_id'] = stationId;
    if (status != null) params['status'] = status;
    return await dio.get('/devices', queryParameters: params);
  }

  Future<Response> getDetail(String sn) async {
    return await dio.get('/devices/$sn');
  }

  Future<Response> getRealtimeData(String sn) async {
    return await dio.get('/devices/$sn/realtime');
  }

  Future<Response> bind(String sn, int? stationId) async {
    return await dio.post(
      '/devices/bind',
      data: {
        'sn': sn,
        'station_id': stationId,
      },
    );
  }

  Future<Response> unbind(String sn) async {
    return await dio.delete('/devices/$sn/unbind');
  }

  Future<Response> control(
    String sn,
    String cmdType,
    Map<String, dynamic> params,
  ) async {
    return await dio.post(
      '/devices/$sn/control',
      data: {
        'command': cmdType,
        'params': params,
      },
    );
  }

  Future<Response> getStatistics(
    String sn,
    String startDate,
    String endDate,
    String period,
  ) async {
    return await dio.get(
      '/devices/$sn/statistics',
      queryParameters: {
        'start_date': startDate,
        'end_date': endDate,
        'period': period,
      },
    );
  }

  Future<Response> getHistory(
    String sn,
    String startDate,
    String endDate,
    String period,
  ) async {
    return await dio.get(
      '/devices/$sn/history',
      queryParameters: {
        'start_date': startDate,
        'end_date': endDate,
        'period': period,
      },
    );
  }

  Future<Response> getAlarms(
    String sn, {
    int page = 1,
    int pageSize = 20,
  }) async {
    return await dio.get(
      '/devices/$sn/alarms',
      queryParameters: {
        'page': page,
        'page_size': pageSize,
      },
    );
  }

  Future<Response> scanLocal() async {
    return await dio.get('/devices/scan/local');
  }

  Future<Response> getModelFields(int modelId) async {
    return await dio.get('/models/$modelId/fields');
  }

  Future<Response> getModelFieldsByCode(String modelCode) async {
    return await dio.get('/models/by-code/$modelCode/fields');
  }
}

class DeviceRemoteDataSourceImpl extends DeviceRemoteDataSource {
  DeviceRemoteDataSourceImpl(super.dio);
}
