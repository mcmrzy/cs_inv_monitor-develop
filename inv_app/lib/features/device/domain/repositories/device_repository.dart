import 'package:dartz/dartz.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/core/entities/inverter_data.dart';

abstract class DeviceRepository {
  Future<Either<Failure, Map<String, dynamic>>> getList({
    int? stationId,
    int? status,
    int page,
    int pageSize,
  });
  Future<Either<Failure, Map<String, dynamic>>> getDetail(String sn);
  Future<Either<Failure, Map<String, dynamic>>> getRealtimeData(String sn);
  Future<Either<Failure, void>> bind(String sn, int? stationId);
  Future<Either<Failure, void>> unbind(String sn);
  Future<Either<Failure, void>> control(
    String sn,
    String cmdType,
    Map<String, dynamic> params,
  );
  Future<Either<Failure, void>> sendCommand({
    required String sn,
    required String command,
    required Map<String, dynamic> params,
  });
  Future<Either<Failure, List<dynamic>>> getHistory(
    String sn,
    String startDate,
    String endDate,
    String period,
  );
  Future<Either<Failure, Map<String, dynamic>>> getStatistics(
    String sn,
    String startDate,
    String endDate,
    String period,
  );
  Future<Either<Failure, List<dynamic>>> scanLocal();
  Future<Either<Failure, List<Map<String, dynamic>>>> getModelFieldsByCode(
    String modelCode,
  );
  InverterRealtime? parseRealtimeData(dynamic raw);
}
