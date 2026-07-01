import 'package:dio/dio.dart';

class OtaRemoteDataSource {
  final Dio dio;

  OtaRemoteDataSource(this.dio);

  Future<Response> checkUpdate(String sn) async => dio.get('/ota/check/$sn');

  Future<Response> triggerOTA(String sn, int firmwareId) async =>
      dio.post('/ota/trigger', data: {'sn': sn, 'firmware_id': firmwareId});

  Future<Response> getDeviceOTAStatus(String sn) async => dio.get('/ota/devices/$sn/status');

  Future<Response> resendUpgradeCommand(String sn) async => dio.post('/ota/resend/$sn');
}

class OtaRemoteDataSourceImpl extends OtaRemoteDataSource {
  OtaRemoteDataSourceImpl(super.dio);
}
