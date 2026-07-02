import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/features/ota/data/datasources/ota_remote_data_source.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';

class OtaRepositoryImpl implements OtaRepository {
  final OtaRemoteDataSource remoteDataSource;

  OtaRepositoryImpl(this.remoteDataSource);

  Failure _mapError(DioException e) {
    final statusCode = e.response?.statusCode;
    final message = e.message ?? e.toString();
    switch (statusCode) {
      case 401:
        return UnauthorizedFailure('Unauthorized');
      case 403:
        return ForbiddenFailure('Access denied');
      case 404:
        return NotFoundFailure('Not found');
      case 422:
        return ValidationFailure(message);
      case null:
        return NetworkFailure('Network error');
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
        return Right(<String, dynamic>{});
      }
      return Left(ServerFailure(data['message'] ?? 'Request failed'));
    }
    return Left(ServerFailure('Response format error'));
  }

  Either<Failure, List<dynamic>> _parseListData(Response response) {
    final data = response.data;
    if (data is Map<String, dynamic>) {
      if (data['code'] == 0) {
        final inner = data['data'];
        if (inner is List) {
          return Right(inner);
        }
        if (inner is Map<String, dynamic>) {
          final list = inner['items'] ?? inner['list'];
          if (list is List) {
            return Right(list);
          }
        }
        return Right([]);
      }
      return Left(ServerFailure(data['message'] ?? 'Request failed'));
    }
    return Left(ServerFailure('Response format error'));
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
        return Right([]);
      }
      return Left(ServerFailure(data['message'] ?? 'Request failed'));
    }
    return Left(ServerFailure('Response format error'));
  }

  Either<Failure, Map<String, dynamic>> _parseStatusOkResponse(Response response) {
    final data = response.data;
    if (data is Map<String, dynamic>) {
      if (data['status'] == 'ok' || data['code'] == 0) {
        final inner = data['data'];
        if (inner is Map<String, dynamic>) {
          return Right(inner);
        }
        return Right(<String, dynamic>{});
      }
      return Left(ServerFailure(data['message'] ?? 'Request failed'));
    }
    return Left(ServerFailure('Response format error'));
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
  Future<Either<Failure, Map<String, dynamic>>> triggerOTA(String sn, int firmwareId) async {
    try {
      final response = await remoteDataSource.triggerOTA(sn, firmwareId);
      return _parseData(response);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> getDeviceOTAStatus(String sn) async {
    try {
      final response = await remoteDataSource.getDeviceOTAStatus(sn);
      return _parseData(response);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> resendUpgradeCommand(String sn) async {
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
  Future<Either<Failure, List<dynamic>>> listUpgradePackages({String? model}) async {
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
  Future<Either<Failure, Map<String, dynamic>>> installPackage(String sn, int packageId) async {
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
