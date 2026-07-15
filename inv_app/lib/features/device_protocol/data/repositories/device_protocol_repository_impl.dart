import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/core/services/data_cache_service.dart';
import 'package:inv_app/features/device_protocol/data/datasources/device_protocol_remote_data_source.dart';
import 'package:inv_app/features/device_protocol/domain/entities/device_protocol_entities.dart';
import 'package:inv_app/features/device_protocol/domain/repositories/device_protocol_repository.dart';

class DeviceProtocolRepositoryImpl implements DeviceProtocolRepository {
  const DeviceProtocolRepositoryImpl(this.remoteDataSource, this.cacheService);

  final DeviceProtocolRemoteDataSource remoteDataSource;
  final DataCacheService cacheService;

  static String _alarmKey(String sn) => 'protocol_alarm_events_$sn';
  static String _parallelKey(String sn) => 'protocol_parallel_state_$sn';
  static String _threePhaseKey(String sn) => 'protocol_three_phase_$sn';

  @override
  Future<Either<Failure, CachedProtocolData<List<AlarmProtocolEvent>>>>
      getAlarmEvents(String sn) async {
    final key = _alarmKey(sn);
    try {
      final data = _unwrap(await remoteDataSource.getAlarmEvents(sn));
      final items =
          _items(data).map(AlarmProtocolEvent.fromJson).toList(growable: false);
      await _saveCache(key, data);
      return Right(CachedProtocolData(value: items));
    } on DioException catch (error) {
      return _networkCacheOrFailure(
        error,
        key,
        (data) => _items(data)
            .map(AlarmProtocolEvent.fromJson)
            .toList(growable: false),
      );
    } on FormatException catch (error) {
      return Left(ServerFailure('告警事件响应格式错误：${error.message}'));
    } catch (error) {
      return Left(UnknownFailure(error.toString()));
    }
  }

  @override
  Future<Either<Failure, CachedProtocolData<DeviceParallelState>>>
      getParallelState(String sn) async {
    final key = _parallelKey(sn);
    try {
      final data = _unwrap(await remoteDataSource.getParallelState(sn));
      final state = DeviceParallelState.fromJson(data);
      await _saveCache(key, data);
      return Right(CachedProtocolData(value: state));
    } on DioException catch (error) {
      return _networkCacheOrFailure(
        error,
        key,
        DeviceParallelState.fromJson,
      );
    } on FormatException catch (error) {
      return Left(ServerFailure('并机状态响应格式错误：${error.message}'));
    } catch (error) {
      return Left(UnknownFailure(error.toString()));
    }
  }

  @override
  Future<Either<Failure, CachedProtocolData<List<ThreePhaseSample>>>>
      getThreePhase(String sn) async {
    final key = _threePhaseKey(sn);
    try {
      final data = _unwrap(await remoteDataSource.getThreePhase(sn));
      final items =
          _items(data).map(ThreePhaseSample.fromJson).toList(growable: false);
      await _saveCache(key, data);
      return Right(CachedProtocolData(value: items));
    } on DioException catch (error) {
      return _networkCacheOrFailure(
        error,
        key,
        (data) =>
            _items(data).map(ThreePhaseSample.fromJson).toList(growable: false),
      );
    } on FormatException catch (error) {
      return Left(ServerFailure('三相历史响应格式错误：${error.message}'));
    } catch (error) {
      return Left(UnknownFailure(error.toString()));
    }
  }

  Map<String, dynamic> _unwrap(Response<dynamic> response) {
    final body = response.data;
    if (body is! Map) {
      throw const FormatException('response body is not an object');
    }
    final json = Map<String, dynamic>.from(body);
    if (json['code'] != 0) {
      throw FormatException(json['message']?.toString() ?? 'request failed');
    }
    final data = json['data'];
    if (data is! Map) {
      throw const FormatException('response data is not an object');
    }
    return Map<String, dynamic>.from(data);
  }

  List<Map<String, dynamic>> _items(Map<String, dynamic> data) {
    final raw = data['items'];
    if (raw is! List) {
      throw const FormatException('response items is not an array');
    }
    return raw.map((item) {
      if (item is! Map) {
        throw const FormatException('response item is not an object');
      }
      return Map<String, dynamic>.from(item);
    }).toList(growable: false);
  }

  Future<void> _saveCache(String key, Map<String, dynamic> data) async {
    try {
      await cacheService.save(key, data);
    } catch (_) {
      // Cache persistence is best-effort; valid server data still wins.
    }
  }

  Either<Failure, CachedProtocolData<T>> _networkCacheOrFailure<T>(
    DioException error,
    String key,
    T Function(Map<String, dynamic>) parser,
  ) {
    if (!_isNetworkError(error)) {
      return Left(_mapDioError(error));
    }
    final cached = cacheService.load(key);
    if (cached is Map) {
      try {
        final timestamp = cacheService.getTimestamp(key);
        return Right(
          CachedProtocolData(
            value: parser(Map<String, dynamic>.from(cached)),
            isFromCache: true,
            cachedAt: timestamp > 0
                ? DateTime.fromMillisecondsSinceEpoch(timestamp)
                : null,
          ),
        );
      } catch (_) {
        // A malformed cache must not turn an error into an empty success.
      }
    }
    return Left(_mapDioError(error));
  }

  bool _isNetworkError(DioException error) {
    return error.response == null ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout;
  }

  Failure _mapDioError(DioException error) {
    final status = error.response?.statusCode;
    switch (status) {
      case 401:
        return const UnauthorizedFailure('登录状态已失效');
      case 403:
        return const ForbiddenFailure('无权限访问该设备');
      case 404:
        return const NotFoundFailure('设备或协议数据不存在');
      case 422:
        return ValidationFailure(error.message ?? '请求参数错误');
      case null:
        return const NetworkFailure('网络不可用，且没有可用的本地缓存');
      default:
        return ServerFailure('服务请求失败（HTTP $status）');
    }
  }
}
