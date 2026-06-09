import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/features/statistics/data/datasources/statistics_remote_data_source.dart';
import 'package:inv_app/features/statistics/domain/repositories/statistics_repository.dart';

class StatisticsRepositoryImpl implements StatisticsRepository {
  final StatisticsRemoteDataSource remoteDataSource;

  StatisticsRepositoryImpl(this.remoteDataSource);

  Failure _mapError(DioException e) {
    final statusCode = e.response?.statusCode;
    final message = e.message ?? e.toString();
    switch (statusCode) {
      case 401:
        return UnauthorizedFailure('未授权，请重新登录');
      case 403:
        return ForbiddenFailure('无权限访问');
      case 404:
        return NotFoundFailure('资源不存在');
      case 422:
        return ValidationFailure(message);
      case null:
        return NetworkFailure('网络连接失败');
      default:
        return ServerFailure('服务器错误: $statusCode');
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
      return Left(ServerFailure(data['message'] ?? '请求失败'));
    }
    return Left(ServerFailure('响应格式错误'));
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> getOverview() async {
    try {
      final response = await remoteDataSource.getOverview();
      return _parseData(response);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> getStationStatistics(int stationId, String startDate, String endDate, String period) async {
    try {
      final response = await remoteDataSource.getStationStatistics(stationId, startDate, endDate, period);
      return _parseData(response);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> getDeviceStatistics(String sn, String startDate, String endDate, String period) async {
    try {
      final response = await remoteDataSource.getDeviceStatistics(sn, startDate, endDate, period);
      return _parseData(response);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }
}
