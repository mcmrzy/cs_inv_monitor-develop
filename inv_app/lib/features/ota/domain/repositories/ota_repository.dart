import 'package:dartz/dartz.dart';
import 'package:inv_app/core/errors/failures.dart';

abstract class OtaRepository {
  Future<Either<Failure, Map<String, dynamic>>> checkUpdate(String sn);
  Future<Either<Failure, List<dynamic>>> getFirmwareList({int page, int pageSize});
  Future<Either<Failure, Map<String, dynamic>>> getFirmwareDetail(int id);
  Future<Either<Failure, Map<String, dynamic>>> triggerOTA(String sn, int firmwareId);
  Future<Either<Failure, Map<String, dynamic>>> getOTATaskProgress(int taskId);
  Future<Either<Failure, Map<String, dynamic>>> getDeviceOTAStatus(String sn);
  Future<Either<Failure, List<dynamic>>> getOTAHistory(String sn, {int page});
}
