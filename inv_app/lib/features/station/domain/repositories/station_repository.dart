import 'package:dartz/dartz.dart';
import 'package:inv_app/core/errors/failures.dart';

abstract class StationRepository {
  Future<Either<Failure, Map<String, dynamic>>> getSummary();
  Future<Either<Failure, Map<String, dynamic>>> getList({int page, int pageSize});
  Future<Either<Failure, Map<String, dynamic>>> getDetail(int stationId);
  Future<Either<Failure, void>> create(Map<String, dynamic> data);
  Future<Either<Failure, void>> update(int stationId, Map<String, dynamic> data);
  Future<Either<Failure, void>> delete(int stationId);
  Future<Either<Failure, List<dynamic>>> getStatistics(int stationId, String startDate, String endDate, String period);
}
