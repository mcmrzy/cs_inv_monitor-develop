import 'package:fpdart/fpdart.dart';
import 'package:dio/dio.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/features/ota/data/datasources/ota_remote_data_source.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';
import 'package:inv_app/features/ota/domain/entities/device_firmware_history.dart';
import 'package:inv_app/features/ota/domain/entities/device_firmware_overview.dart';

class OtaRepositoryImpl implements OtaRepository {
  final OtaRemoteDataSource remoteDataSource;

  OtaRepositoryImpl(this.remoteDataSource);

  Failure _mapError(DioException e) {
    final statusCode = e.response?.statusCode;
    final message = e.message ?? e.toString();
    switch (statusCode) {
      case 401:
        return const UnauthorizedFailure('Unauthorized');
      case 403:
        return const ForbiddenFailure('Access denied');
      case 404:
        return const NotFoundFailure('Not found');
      case 410:
        return const ValidationFailure('Endpoint retired');
      case 422:
        return ValidationFailure(message);
      case null:
        return const NetworkFailure('Network error');
      default:
        return ServerFailure('Server error: $statusCode');
    }
  }

  Either<Failure, Map<String, dynamic>> _parseData(Response response) {
    final data = response.data;
    if (data is Map<String, dynamic>) {
      if (data['code'] == 0) {
        final inner = data['data'];
        if (inner is Map<String, dynamic>) {
          return Right(inner);
        }
        return const Right(<String, dynamic>{});
      }
      return Left(ServerFailure(data['message'] ?? 'Request failed'));
    }
    return const Left(ServerFailure('Response format error'));
  }

  Either<Failure, DeviceFirmwareHistoryPage> _parseHistoryPage(
    Response response, {
    required int page,
    required int pageSize,
  }) {
    final parsed = _parseData(response);
    return parsed.flatMap((data) {
      final rawItems = data['items'];
      if (rawItems is! List) {
        return const Left(ServerFailure('Response format error'));
      }
      final items = rawItems
          .whereType<Map>()
          .map((item) => DeviceFirmwareHistory.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList();
      return Right(DeviceFirmwareHistoryPage(
        items: items,
        total: (data['total'] as num?)?.toInt() ?? items.length,
        page: (data['page'] as num?)?.toInt() ?? page,
        pageSize: (data['page_size'] as num?)?.toInt() ?? pageSize,
      ));
    });
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> checkUpdate(String sn) async {
    try {
      final response = await remoteDataSource.checkUpdate(sn);
      return _parseData(response);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, DeviceFirmwareOverview>> getFirmwareOverview(
    String sn,
  ) async {
    try {
      final response = await remoteDataSource.getFirmwareOverview(sn);
      final parsed = _parseData(response);
      return parsed.map(DeviceFirmwareOverview.fromJson);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<FirmwareResource>>> getFirmwareResources(
    String sn, {
    String? targetChip,
  }) async {
    try {
      final response = await remoteDataSource.getFirmwareResources(
        sn,
        targetChip: targetChip,
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        if (data['code'] == 0) {
          final inner = data['data'];
          final rawList = inner is List
              ? inner
              : inner is Map<String, dynamic>
                  ? (inner['items'] ?? inner['firmwares'] ?? inner['list'])
                  : null;
          if (rawList is List) {
            return Right(rawList
                .whereType<Map>()
                .map((e) => FirmwareResource.fromJson(
                      Map<String, dynamic>.from(e),
                    ))
                .toList());
          }
          return const Right(<FirmwareResource>[]);
        }
        return Left(ServerFailure(data['message'] ?? 'Request failed'));
      }
      return const Left(ServerFailure('Response format error'));
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<OtaTriggerTask>>> triggerFirmware(
    String sn,
    List<int> firmwareIds, {
    required String idempotencyKey,
    String? forceReason,
  }) async {
    try {
      final response = await remoteDataSource.triggerFirmware(
        sn,
        firmwareIds,
        idempotencyKey: idempotencyKey,
        forceReason: forceReason,
      );
      final parsed = _parseData(response);
      return parsed.flatMap((data) {
        final rawTasks = data['tasks'];
        if (rawTasks is List) {
          return Right(rawTasks
              .whereType<Map>()
              .map((e) => OtaTriggerTask.fromJson(
                    Map<String, dynamic>.from(e),
                  ))
              .toList());
        }
        // 兼容单任务响应
        if (data['task_id'] != null) {
          return Right([
            OtaTriggerTask.fromJson(data),
          ]);
        }
        return const Right(<OtaTriggerTask>[]);
      });
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> rollbackFirmware(
    String sn,
    int firmwareId, {
    required String idempotencyKey,
    String? forceReason,
  }) async {
    try {
      final response = await remoteDataSource.rollbackFirmware(
        sn,
        firmwareId,
        idempotencyKey: idempotencyKey,
        forceReason: forceReason,
      );
      return _parseData(response);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> getFirmwareInfo(
    int firmwareId,
  ) async {
    try {
      final response = await remoteDataSource.getFirmwareInfo(firmwareId);
      return _parseData(response);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, DeviceFirmwareHistoryPage>> getDeviceHistory(
    String sn, {
    String? targetChip,
    String? status,
    DateTime? startTime,
    DateTime? endTime,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final filter = FirmwareHistoryFilter(
        targetChip: targetChip,
        status: status,
        startTime: startTime,
        endTime: endTime,
        page: page,
        pageSize: pageSize,
      );
      final response = await remoteDataSource.getDeviceHistory(
        sn,
        queryParameters: filter.toQueryParameters()
          ..remove('device_sn'),
      );
      return _parseHistoryPage(response, page: page, pageSize: pageSize);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, DeviceFirmwareHistoryPage>> getHistory({
    String? deviceSn,
    String? targetChip,
    String? status,
    DateTime? startTime,
    DateTime? endTime,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final filter = FirmwareHistoryFilter(
        deviceSn: deviceSn,
        targetChip: targetChip,
        status: status,
        startTime: startTime,
        endTime: endTime,
        page: page,
        pageSize: pageSize,
      );
      final response = await remoteDataSource.getHistory(
        queryParameters: filter.toQueryParameters(),
      );
      return _parseHistoryPage(response, page: page, pageSize: pageSize);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> reportLocalOTAResult({
    required String sn,
    required String targetChip,
    required String newVersion,
  }) async {
    try {
      final response = await remoteDataSource.reportLocalOTAResult(
        sn: sn,
        targetChip: targetChip,
        newVersion: newVersion,
      );
      return _parseData(response);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> getDeviceOTAStatus(
    String sn, {
    int? taskId,
  }) async {
    try {
      final response = await remoteDataSource.getDeviceOTAStatus(
        sn,
        taskId: taskId,
      );
      return _parseData(response);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> resendUpgradeCommand(
    String sn,
  ) async {
    try {
      final response = await remoteDataSource.resendUpgradeCommand(sn);
      return _parseData(response);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }
}
