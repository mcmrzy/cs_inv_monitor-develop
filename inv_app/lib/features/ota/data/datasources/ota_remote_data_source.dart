import 'package:dio/dio.dart';

class OtaRemoteDataSource {
  final Dio dio;

  OtaRemoteDataSource(this.dio);

  Future<Response> checkUpdate(String sn) async => dio.get('/ota/check/$sn');

  /// POST /ota/trigger — APP端触发升级，使用 package_id
  Future<Response> triggerOTA(String sn, int packageId) async =>
      dio.post('/ota/trigger', data: {'sn': sn, 'package_id': packageId});

  /// GET /ota/available-packages/:sn — 获取设备可用升级包列表
  Future<Response> getAvailablePackages(String sn) async =>
      dio.get('/ota/available-packages/$sn');

  /// POST /ota/devices/:sn/local-ota-result — 本地OTA结果上报
  Future<Response> reportLocalOTAResult({
    required String sn,
    required String targetChip,
    required String newVersion,
    String? mainVersion,
  }) async =>
      dio.post(
        '/ota/devices/$sn/local-ota-result',
        data: {
          'target_chip': targetChip,
          'new_version': newVersion,
          if (mainVersion != null) 'main_version': mainVersion,
        },
      );

  Future<Response> getDeviceOTAStatus(String sn) async =>
      dio.get('/ota/devices/$sn/status');

  Future<Response> resendUpgradeCommand(String sn) async =>
      dio.post('/ota/resend/$sn');

  Future<Response> listUpgradePackages({String? model}) async {
    final queryParams = <String, dynamic>{};
    if (model != null && model.isNotEmpty) {
      queryParams['model'] = model;
    }
    return dio.get('/ota/app/packages', queryParameters: queryParams);
  }

  Future<Response> installPackage(String sn, int packageId) async => dio.post(
        '/ota/app/packages/install',
        data: {'sn': sn, 'package_id': packageId},
      );
}

class OtaRemoteDataSourceImpl extends OtaRemoteDataSource {
  OtaRemoteDataSourceImpl(super.dio);
}
