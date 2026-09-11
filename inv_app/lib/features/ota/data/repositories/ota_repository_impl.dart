import 'package:fpdart/fpdart.dart';
import 'package:dio/dio.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/features/ota/data/datasources/ota_remote_data_source.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';
import 'package:inv_app/features/ota/domain/entities/device_firmware_history.dart';

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

  Either<Failure, List<dynamic>> _parsePackageListResponse(Response response) {
    final data = response.data;
    if (data is Map<String, dynamic>) {
      if (data['status'] == 'ok' || data['code'] == 0) {
        final inner = data['data'];
        if (inner is Map<String, dynamic>) {
          final packages = inner['packages'];
          if (packages is List) {
            return Right(packages);
          }
        }
        if (inner is List) {
          return Right(inner);
        }
        return const Left(
          ServerFailure('Response format error: expected package list data'),
        );
      }
      return Left(ServerFailure(data['message'] ?? 'Request failed'));
    }
    return const Left(ServerFailure('Response format error'));
  }

  Either<Failure, Map<String, dynamic>> _parseStatusOkResponse(
    Response response,
  ) {
    final data = response.data;
    if (data is Map<String, dynamic>) {
      if (data['status'] == 'ok' || data['code'] == 0) {
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
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await remoteDataSource.getDeviceHistory(
        sn,
        page: page,
        pageSize: pageSize,
      );
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
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> triggerOTA(
    String sn,
    int packageId,
  ) async {
    try {
      final response = await remoteDataSource.triggerOTA(sn, packageId);
      return _parseData(response);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<dynamic>>> getAvailablePackages(String sn) async {
    try {
      final response = await remoteDataSource.getAvailablePackages(sn);
      return _parsePackageListResponse(response);
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
    String? mainVersion,
  }) async {
    try {
      final response = await remoteDataSource.reportLocalOTAResult(
        sn: sn,
        targetChip: targetChip,
        newVersion: newVersion,
        mainVersion: mainVersion,
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
    String sn,
    {int? taskId}
  ) async {
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

  @override
  Future<Either<Failure, List<dynamic>>> listUpgradePackages({
    String? model,
  }) async {
    try {
      final response = await remoteDataSource.listUpgradePackages(model: model);
      return _parsePackageListResponse(response);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> installPackage(
    String sn,
    int packageId,
  ) async {
    try {
      final response = await remoteDataSource.installPackage(sn, packageId);
      return _parseStatusOkResponse(response);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }
}
