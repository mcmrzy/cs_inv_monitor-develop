import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/features/dashboard/data/datasources/dashboard_remote_data_source.dart';
import 'package:inv_app/features/dashboard/domain/entities/trend_data_point.dart';
import 'package:inv_app/features/dashboard/domain/entities/station_rank_item.dart';
import 'package:inv_app/features/dashboard/domain/repositories/dashboard_repository.dart';

class DashboardRepositoryImpl implements DashboardRepository {
  final DashboardRemoteDataSource remoteDataSource;

  DashboardRepositoryImpl(this.remoteDataSource);

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

  Map<String, dynamic> _parseData(Response response) {
    final data = response.data;
    if (data is Map<String, dynamic>) {
      if (data['code'] == 0) {
        final inner = data['data'];
        if (inner is Map<String, dynamic>) {
          return inner;
        }
        return <String, dynamic>{};
      }
      throw ServerFailure(data['message'] ?? 'Request failed');
    }
    throw ServerFailure('Response format error');
  }

  List<dynamic> _parseList(Response response) {
    final data = response.data;
    if (data is Map<String, dynamic>) {
      if (data['code'] == 0) {
        final inner = data['data'];
        if (inner is List) {
          return inner;
        }
        if (inner is Map<String, dynamic> && inner['list'] is List) {
          return inner['list'] as List;
        }
        return [];
      }
      throw ServerFailure(data['message'] ?? 'Request failed');
    }
    if (data is List) {
      return data;
    }
    throw ServerFailure('Response format error');
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> getStatistics() async {
    try {
      final response = await remoteDataSource.getStatistics();
      return Right(_parseData(response));
    } on Failure catch (f) {
      return Left(f);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<TrendDataPoint>>> getTrendData({String type = 'day'}) async {
    try {
      final response = await remoteDataSource.getTrendData(type: type);
      final list = _parseList(response);
      final points = list
          .whereType<Map<String, dynamic>>()
          .map((e) => TrendDataPoint.fromJson(e))
          .toList();
      return Right(points);
    } on Failure catch (f) {
      return Left(f);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> getDeviceDistribution() async {
    try {
      final response = await remoteDataSource.getDeviceDistribution();
      return Right(_parseData(response));
    } on Failure catch (f) {
      return Left(f);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<StationRankItem>>> getStationRanking() async {
    try {
      final response = await remoteDataSource.getStationRanking();
      final list = _parseList(response);
      final items = list
          .whereType<Map<String, dynamic>>()
          .map((e) => StationRankItem.fromJson(e))
          .toList();
      return Right(items);
    } on Failure catch (f) {
      return Left(f);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }
}
