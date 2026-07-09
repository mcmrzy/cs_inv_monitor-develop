import 'package:dio/dio.dart';

class AlarmRemoteDataSource {
  final Dio dio;

  AlarmRemoteDataSource(this.dio);

  Future<Response> getList({int? stationId, int? status, int page = 1, int pageSize = 20}) async {
    final params = <String, dynamic>{
      'page': page,
      'page_size': pageSize,
    };
    if (stationId != null) params['station_id'] = stationId;
    if (status != null) params['status'] = status;
    return await dio.get('/alarms', queryParameters: params);
  }

  Future<Response> getDetail(int alarmId) async {
    return await dio.get('/alarms/$alarmId');
  }

  Future<Response> markHandled(int alarmId) async {
    return await dio.put('/alarms/$alarmId/handle');
  }

  Future<Response> markRead(List<int> alarmIds) async {
    return await dio.put('/alarms/read', data: {
      'ids': alarmIds,
    },);
  }
}

class AlarmRemoteDataSourceImpl extends AlarmRemoteDataSource {
  AlarmRemoteDataSourceImpl(super.dio);
}
