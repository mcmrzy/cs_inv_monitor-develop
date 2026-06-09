import 'package:dartz/dartz.dart';
import 'package:inv_app/core/errors/failures.dart';

abstract class AlarmRepository {
  Future<Either<Failure, Map<String, dynamic>>> getList({int? stationId, int? status, int page, int pageSize});
  Future<Either<Failure, Map<String, dynamic>>> getDetail(int alarmId);
  Future<Either<Failure, void>> markHandled(int alarmId);
  Future<Either<Failure, void>> markRead(List<int> alarmIds);
}
