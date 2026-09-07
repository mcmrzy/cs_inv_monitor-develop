import 'package:fpdart/fpdart.dart';
import 'package:inv_app/core/errors/failures.dart';

abstract class OtaRepository {
  Future<Either<Failure, Map<String, dynamic>>> checkUpdate(String sn);

  /// POST /ota/trigger — APP端触发升级，使用 package_id，返回 task_id
  Future<Either<Failure, Map<String, dynamic>>> triggerOTA(
    String sn,
    int packageId,
  );

  /// GET /ota/available-packages/:sn — 获取设备可用升级包列表
  Future<Either<Failure, List<dynamic>>> getAvailablePackages(String sn);

  /// POST /ota/local-result — 本地OTA结果上报
  Future<Either<Failure, Map<String, dynamic>>> reportLocalOTAResult({
    required String sn,
    required String targetChip,
    required String newVersion,
    String? mainVersion,
  });

  Future<Either<Failure, Map<String, dynamic>>> resendUpgradeCommand(String sn);
  Future<Either<Failure, Map<String, dynamic>>> getDeviceOTAStatus(
    String sn, {
    int? taskId,
  });
  Future<Either<Failure, List<dynamic>>> listUpgradePackages({String? model});
  Future<Either<Failure, Map<String, dynamic>>> installPackage(
    String sn,
    int packageId,
  );

  /// GET /ota/firmware-info/:id — 按固件 ID 获取本地 OTA 所需元数据
  /// （下载 URL/SHA-256/签名/安全版本等），路由无需再携带复杂 query 参数
  Future<Either<Failure, Map<String, dynamic>>> getFirmwareInfo(int firmwareId);
}
