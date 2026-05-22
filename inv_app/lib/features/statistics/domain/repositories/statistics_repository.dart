import 'package:dartz/dartz.dart';
import 'package:inv_app/core/errors/failures.dart';

abstract class StatisticsRepository {
  Future<Either<Failure, Map<String, dynamic>>> getOverview();
  Future<Either<Failure, Map<String, dynamic>>> getStationStatistics(int stationId, String startDate, String endDate, String period);
  Future<Either<Failure, Map<String, dynamic>>> getDeviceStatistics(String sn, String startDate, String endDate, String period);
}
