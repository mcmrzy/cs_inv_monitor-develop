import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/features/station/data/datasources/station_remote_data_source.dart';
import 'package:inv_app/features/station/domain/repositories/station_repository.dart';

class StationRepositoryImpl implements StationRepository {
  final StationRemoteDataSource remoteDataSource;

  StationRepositoryImpl(this.remoteDataSource);

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

  Either<Failure, List<dynamic>> _parseList(Response response) {
    final data = response.data;
    if (data is Map<String, dynamic>) {
      if (data['code'] == 0) {
        final inner = data['data'];
        if (inner is List) {
          return Right(inner);
        }
        return Right(<dynamic>[]);
      }
      return Left(ServerFailure(data['message'] ?? 'Request failed'));
    }
    return Left(ServerFailure('Response format error'));
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> getSummary() async {
    try {
      final response = await remoteDataSource.getSummary();
      return _parseData(response);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> getList({int page = 1, int pageSize = 20}) async {
    try {
      final response = await remoteDataSource.getList(page: page, pageSize: pageSize);
      return _parseData(response);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> getDetail(int stationId) async {
    try {
      final response = await remoteDataSource.getDetail(stationId);
      return _parseData(response);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> create(Map<String, dynamic> data) async {
    try {
      final response = await remoteDataSource.create(data);
      final parsed = _parseData(response);
      return parsed.fold(
        (failure) => Left(failure),
        (_) => const Right(null),
      );
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> update(int stationId, Map<String, dynamic> data) async {
    try {
      final response = await remoteDataSource.update(stationId, data);
      final parsed = _parseData(response);
      return parsed.fold(
        (failure) => Left(failure),
        (_) => const Right(null),
      );
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> delete(int stationId) async {
    try {
      final response = await remoteDataSource.delete(stationId);
      final parsed = _parseData(response);
      return parsed.fold(
        (failure) => Left(failure),
        (_) => const Right(null),
      );
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<dynamic>>> getStatistics(int stationId, String startDate, String endDate, String period) async {
    try {
      final response = await remoteDataSource.getStatistics(stationId, startDate, endDate, period);
      return _parseList(response);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }
}
