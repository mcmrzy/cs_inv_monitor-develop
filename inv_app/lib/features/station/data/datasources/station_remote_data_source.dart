import 'package:dio/dio.dart';

class StationRemoteDataSource {
  final Dio dio;

  StationRemoteDataSource(this.dio);

  Future<Response> getSummary() async {
    return await dio.get('/stations/summary');
  }

  Future<Response> getList({int page = 1, int pageSize = 20}) async {
    return await dio.get(
      '/stations',
      queryParameters: {
        'page': page,
        'page_size': pageSize,
      },
    );
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

  Future<Response> unbindDevice(String sn) async {
    // 后端 :sn 通配路由统一挂在 /devices/by-sn/ 前缀下（Gin 通配符冲突规避）
    return await dio.post('/devices/by-sn/$sn/unbind');
  }

  /// 换绑：直接更新设备所属电站（add-to-station 语义为 UPDATE station_id，天然支持换绑）
  Future<Response> rebindDevice(String sn, int newStationId) async {
    return await dio.post('/devices/add-to-station', data: {'sn': sn, 'station_id': newStationId});
  }

  /// 绑定电站：设备已归属当前用户，仅需分配电站（非所有权绑定）
  Future<Response> bindDevice(String sn, int stationId) async {
    return await dio.post('/devices/add-to-station', data: {'sn': sn, 'station_id': stationId});
  }

  Future<Response> deleteDevice(String sn) async {
    return await dio.delete('/devices/by-sn/$sn');
  }

  Future<Response> reorderDevices(int stationId, List<String> deviceOrder) async {
    return await dio.put('/stations/$stationId/devices/reorder', data: {'device_order': deviceOrder});
  }

  /// 电站列表拖动排序持久化（后端注册为 POST，规避 PUT 路由通配符冲突）
  Future<Response> reorderStations(List<int> stationOrder) async {
    return await dio.post('/stations/reorder', data: {'station_order': stationOrder});
  }

  Future<Response> getStatistics(
    int stationId,
    String startDate,
    String endDate,
    String period,
  ) async {
    return await dio.get(
      '/stations/$stationId/statistics',
      queryParameters: {
        'start_date': startDate,
        'end_date': endDate,
        'period': period,
      },
    );
  }
}

class StationRemoteDataSourceImpl extends StationRemoteDataSource {
  StationRemoteDataSourceImpl(super.dio);
}
