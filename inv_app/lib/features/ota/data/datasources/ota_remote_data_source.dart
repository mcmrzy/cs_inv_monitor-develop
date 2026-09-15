import 'package:dio/dio.dart';

class OtaRemoteDataSource {
  final Dio dio;

  OtaRemoteDataSource(this.dio);

  Future<Response> checkUpdate(String sn) async => dio.get('/ota/check/$sn');

  /// GET /ota/devices/{sn}/firmware-overview
  Future<Response> getFirmwareOverview(String sn) async =>
      dio.get('/ota/devices/$sn/firmware-overview');

  /// GET /ota/devices/{sn}/firmware-resources?target_chip=
  Future<Response> getFirmwareResources(
    String sn, {
    String? targetChip,
  }) async =>
          dio.get(
            '/ota/devices/$sn/firmware-resources',
            queryParameters: {
              if (targetChip != null && targetChip.isNotEmpty)
                'target_chip': targetChip,
            },
          );

  /// POST /ota/trigger — 按 firmware_ids 批量触发
  Future<Response> triggerFirmware(
    String sn,
    List<int> firmwareIds, {
    required String idempotencyKey,
    String? forceReason,
  }) async =>
      dio.post(
        '/ota/trigger',
        data: {
          'device_sn': sn,
          'firmware_ids': firmwareIds,
          'idempotency_key': idempotencyKey,
          if (forceReason != null && forceReason.isNotEmpty)
            'force_reason': forceReason,
        },
      );

  /// POST /ota/firmware/rollback — 按 firmware_id 回滚
  Future<Response> rollbackFirmware(
    String sn,
    int firmwareId, {
    required String idempotencyKey,
    String? forceReason,
  }) async =>
      dio.post(
        '/ota/firmware/rollback',
        data: {
          'device_sn': sn,
          'firmware_id': firmwareId,
          'idempotency_key': idempotencyKey,
          if (forceReason != null && forceReason.isNotEmpty)
            'force_reason': forceReason,
        },
      );

  /// POST /ota/devices/:sn/local-ota-result — 本地OTA结果上报（仅 target/new_version）
  Future<Response> reportLocalOTAResult({
    required String sn,
    required String targetChip,
    required String newVersion,
  }) async =>
      dio.post(
        '/ota/devices/$sn/local-ota-result',
        data: {
          'target_chip': targetChip,
          'new_version': newVersion,
        },
      );

  Future<Response> getDeviceOTAStatus(String sn, {int? taskId}) async => dio.get(
        '/ota/devices/$sn/status',
        queryParameters: {
          if (taskId != null && taskId > 0) 'task_id': taskId,
        },
      );

  Future<Response> resendUpgradeCommand(String sn) async =>
      dio.post('/ota/resend/$sn');

  /// GET /ota/firmware-info/:id — 按固件 ID 获取本地 OTA 元数据
  Future<Response> getFirmwareInfo(int firmwareId) async =>
      dio.get('/ota/firmware-info/$firmwareId');

  /// GET /ota/devices/{sn}/history — 设备升级历史
  Future<Response> getDeviceHistory(
    String sn, {
    Map<String, dynamic> queryParameters = const {},
  }) =>
      dio.get(
        '/ota/devices/$sn/history',
        queryParameters: queryParameters,
      );

  /// GET /ota/history — 全量升级历史
  Future<Response> getHistory({
    Map<String, dynamic> queryParameters = const {},
  }) =>
      dio.get('/ota/history', queryParameters: queryParameters);
}

class OtaRemoteDataSourceImpl extends OtaRemoteDataSource {
  OtaRemoteDataSourceImpl(super.dio);
}
