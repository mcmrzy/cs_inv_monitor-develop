import 'package:dartz/dartz.dart';
import 'package:inv_app/core/errors/failures.dart';

abstract class OtaRepository {
  Future<Either<Failure, Map<String, dynamic>>> checkUpdate(String sn);

  /// POST /ota/trigger — APP端触发升级，使用 package_id，返回 task_id
  Future<Either<Failure, Map<String, dynamic>>> triggerOTA(
    String sn,
    int packageId,
  );

  /// GET /ota/packages/available/:sn — 获取设备可用升级包列表
  Future<Either<Failure, List<dynamic>>> getAvailablePackages(String sn);

  /// POST /ota/local-result — 本地OTA结果上报
  Future<Either<Failure, Map<String, dynamic>>> reportLocalOTAResult({
    required String sn,
    required String targetChip,
    required String newVersion,
    String? mainVersion,
  });

  Future<Either<Failure, Map<String, dynamic>>> resendUpgradeCommand(String sn);
  Future<Either<Failure, Map<String, dynamic>>> getDeviceOTAStatus(String sn);
  Future<Either<Failure, List<dynamic>>> listUpgradePackages({String? model});
  Future<Either<Failure, Map<String, dynamic>>> installPackage(
    String sn,
    int packageId,
  );
}
