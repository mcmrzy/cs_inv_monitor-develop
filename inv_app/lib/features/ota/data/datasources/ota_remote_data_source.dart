import 'package:dio/dio.dart';

class OtaRemoteDataSource {
  final Dio dio;

  OtaRemoteDataSource(this.dio);

  Future<Response> checkUpdate(String sn) async => dio.get('/ota/check/$sn');

  Future<Response> triggerOTA(String sn, int firmwareId) async =>
      dio.post('/ota/trigger', data: {'sn': sn, 'firmware_id': firmwareId});

  Future<Response> getDeviceOTAStatus(String sn) async => dio.get('/ota/devices/$sn/status');

  Future<Response> resendUpgradeCommand(String sn) async => dio.post('/ota/resend/$sn');

  Future<Response> listUpgradePackages({String? model}) async {
    final queryParams = <String, dynamic>{};
    if (model != null && model.isNotEmpty) {
      queryParams['model'] = model;
    }
    return dio.get('/ota/app/packages', queryParameters: queryParams);
  }

  Future<Response> installPackage(String sn, int packageId) async =>
      dio.post(
        '/ota/app/packages/install',
        data: {'sn': sn, 'package_id': packageId},
      );
}

class OtaRemoteDataSourceImpl extends OtaRemoteDataSource {
  OtaRemoteDataSourceImpl(super.dio);
}
