import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/entities/device_model_field.dart';
import 'package:inv_app/features/device/data/datasources/device_remote_data_source.dart';
import 'package:inv_app/features/device/domain/repositories/device_repository.dart';
import 'package:inv_app/core/services/mqtt_service.dart';

class DeviceRepositoryImpl implements DeviceRepository {
  final DeviceRemoteDataSource remoteDataSource;
  final MQTTService mqttService;

  DeviceRepositoryImpl(this.remoteDataSource, this.mqttService);

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
      return Left(ServerFailure(data['message'] ?? '请求失败'));
    }
    return Left(ServerFailure('响应格式错误'));
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> getList({int? stationId, int? status, int page = 1, int pageSize = 20}) async {
    try {
      final response = await remoteDataSource.getList(stationId: stationId, status: status, page: page, pageSize: pageSize);
      return _parseData(response);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> getDetail(String sn) async {
    try {
      final response = await remoteDataSource.getDetail(sn);
      return _parseData(response);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> getRealtimeData(String sn) async {
    try {
      final response = await remoteDataSource.getRealtimeData(sn);
      return _parseData(response);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> bind(String sn, int? stationId) async {
    try {
      final response = await remoteDataSource.bind(sn, stationId);
      final parsed = _parseData(response);
      return parsed.fold((failure) => Left(failure), (_) => const Right(null));
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> unbind(String sn) async {
    try {
      final response = await remoteDataSource.unbind(sn);
      final parsed = _parseData(response);
      return parsed.fold((failure) => Left(failure), (_) => const Right(null));
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> control(String sn, String cmdType, Map<String, dynamic> params) async {
    try {
      final response = await remoteDataSource.control(sn, cmdType, params);
      final parsed = _parseData(response);
      return parsed.fold((failure) => Left(failure), (_) => const Right(null));
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> sendCommand({required String sn, required String command, required Map<String, dynamic> params}) async {
    return control(sn, command, params);
  }

  @override
  InverterRealtime? parseRealtimeData(dynamic raw) {
    if (raw == null) return null;
    try {
      if (raw is Map<String, dynamic>) {
        return InverterRealtime.fromJson(raw);
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<Either<Failure, List<dynamic>>> getHistory(String sn, String startDate, String endDate, String period) async {
    try {
      final response = await remoteDataSource.getHistory(sn, startDate, endDate, period);
      return _parseList(response);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> getStatistics(String sn, String startDate, String endDate, String period) async {
    try {
      final response = await remoteDataSource.getStatistics(sn, startDate, endDate, period);
      return _parseData(response);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<dynamic>>> scanLocal() async {
    try {
      final response = await remoteDataSource.scanLocal();
      return _parseList(response);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<Map<String, dynamic>>>> getModelFieldsByCode(String modelCode) async {
    try {
      final response = await remoteDataSource.getModelFieldsByCode(modelCode);
      final data = response.data;
      if (data is Map<String, dynamic> && data['code'] == 0) {
        final inner = data['data'];
        if (inner is List) return Right(inner.cast<Map<String, dynamic>>());
        return const Right([]);
      }
      return Left(ServerFailure('获取字段元数据失败'));
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }
}
