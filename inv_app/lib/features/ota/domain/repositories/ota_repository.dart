import 'package:dartz/dartz.dart';
import 'package:inv_app/core/errors/failures.dart';

abstract class OtaRepository {
  Future<Either<Failure, Map<String, dynamic>>> checkUpdate(String sn);
  Future<Either<Failure, Map<String, dynamic>>> triggerOTA(String sn, int firmwareId);
  Future<Either<Failure, Map<String, dynamic>>> resendUpgradeCommand(String sn);
  Future<Either<Failure, Map<String, dynamic>>> getDeviceOTAStatus(String sn);
}
