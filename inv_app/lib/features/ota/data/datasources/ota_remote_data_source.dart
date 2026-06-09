import 'package:dio/dio.dart';

class OtaRemoteDataSource {
  final Dio dio;

  OtaRemoteDataSource(this.dio);

  Future<Response> checkUpdate(String sn) async => dio.get('/ota/check/$sn');

  Future<Response> getFirmwareList({int page = 1, int pageSize = 20}) async =>
      dio.get('/ota/firmwares', queryParameters: {'page': page, 'page_size': pageSize});

  Future<Response> getFirmwareDetail(int id) async => dio.get('/ota/firmwares/$id');

  Future<Response> triggerOTA(String sn, int firmwareId) async =>
      dio.post('/ota/trigger', data: {'sn': sn, 'firmware_id': firmwareId});

  Future<Response> getOTATaskProgress(int taskId) async => dio.get('/ota/tasks/$taskId/progress');

  Future<Response> getDeviceOTAStatus(String sn) async => dio.get('/ota/devices/$sn/status');

  Future<Response> getOTAHistory(String sn, {int page = 1}) async =>
      dio.get('/ota/devices/$sn/history', queryParameters: {'page': page});
}

class OtaRemoteDataSourceImpl extends OtaRemoteDataSource {
  OtaRemoteDataSourceImpl(super.dio);
}
