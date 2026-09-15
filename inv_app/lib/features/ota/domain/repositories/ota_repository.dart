import 'package:fpdart/fpdart.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/features/ota/domain/entities/device_firmware_history.dart';
import 'package:inv_app/features/ota/domain/entities/device_firmware_overview.dart';

abstract class OtaRepository {
  Future<Either<Failure, Map<String, dynamic>>> checkUpdate(String sn);

  /// GET /ota/devices/{sn}/firmware-overview — 四模块固件总览
  Future<Either<Failure, DeviceFirmwareOverview>> getFirmwareOverview(
    String sn,
  );

  /// GET /ota/devices/{sn}/firmware-resources?target_chip= — 已发布固件列表
  Future<Either<Failure, List<FirmwareResource>>> getFirmwareResources(
    String sn, {
    String? targetChip,
  });

  /// POST /ota/trigger — 按 firmware_ids 批量触发升级
  Future<Either<Failure, List<OtaTriggerTask>>> triggerFirmware(
    String sn,
    List<int> firmwareIds, {
    required String idempotencyKey,
    String? forceReason,
  });

  /// POST /ota/firmware/rollback — 按 firmware_id 回滚
  Future<Either<Failure, Map<String, dynamic>>> rollbackFirmware(
    String sn,
    int firmwareId, {
    required String idempotencyKey,
    String? forceReason,
  });

  /// POST /ota/local-result — 本地OTA结果上报（仅 target/new_version）
  Future<Either<Failure, Map<String, dynamic>>> reportLocalOTAResult({
    required String sn,
    required String targetChip,
    required String newVersion,
  });

  Future<Either<Failure, Map<String, dynamic>>> resendUpgradeCommand(String sn);
  Future<Either<Failure, Map<String, dynamic>>> getDeviceOTAStatus(
    String sn, {
    int? taskId,
  });

  /// GET /ota/firmware-info/:id — 按固件 ID 获取本地 OTA 所需元数据
  /// （下载 URL/SHA-256/签名/安全版本等），路由无需再携带复杂 query 参数
  Future<Either<Failure, Map<String, dynamic>>> getFirmwareInfo(int firmwareId);

  /// GET /ota/devices/{sn}/history — 设备升级历史（支持四类筛选）
  Future<Either<Failure, DeviceFirmwareHistoryPage>> getDeviceHistory(
    String sn, {
    String? targetChip,
    String? status,
    DateTime? startTime,
    DateTime? endTime,
    int page = 1,
    int pageSize = 20,
  });

  /// GET /ota/history — 全量升级历史（支持四类筛选）
  Future<Either<Failure, DeviceFirmwareHistoryPage>> getHistory({
    String? deviceSn,
    String? targetChip,
    String? status,
    DateTime? startTime,
    DateTime? endTime,
    int page = 1,
    int pageSize = 20,
  });
}
