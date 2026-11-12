import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:dio/dio.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/utils/device_card_data.dart';
import 'package:inv_app/core/utils/grid_power.dart';
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
        return const UnauthorizedFailure('Unauthorized');
      case 403:
        return const ForbiddenFailure('Access denied');
      case 404:
        return const NotFoundFailure('Not found');
      case 409:
        return const ValidationFailure('Device assignment changed');
      case 422:
        return ValidationFailure(message);
      case null:
        return const NetworkFailure('Network error');
      default:
        return ServerFailure('Server error: $statusCode');
    }
  }

  Either<Failure, Map<String, dynamic>> _parseData(
    Response response, {
    bool allowEmpty = false,
  }) {
    final data = response.data;
    if (data is Map<String, dynamic>) {
      if (data['code'] == 0) {
        final inner = data['data'];
        if (inner is Map<String, dynamic>) {
          return Right(inner);
        }
        if (allowEmpty && inner == null) {
          return const Right(<String, dynamic>{});
        }
        return const Left(
          ServerFailure('Response format error: expected object data'),
        );
      }
      return Left(ServerFailure(data['message'] ?? 'Request failed'));
    }
    return const Left(ServerFailure('Response format error'));
  }

  Either<Failure, List<dynamic>> _parseList(Response response) {
    final data = response.data;
    if (data is Map<String, dynamic>) {
      if (data['code'] == 0) {
        final inner = data['data'];
        if (inner is List) {
          return Right(inner);
        }
        return const Left(
          ServerFailure('Response format error: expected list data'),
        );
      }
      return Left(ServerFailure(data['message'] ?? 'Request failed'));
    }
    return const Left(ServerFailure('Response format error'));
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
  Future<Either<Failure, Map<String, dynamic>>> getList({
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response =
          await remoteDataSource.getList(page: page, pageSize: pageSize);
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
      return await _parseData(response).match(
        (failure) async => Left(failure),
        (data) async => Right(await _withRealtimePower(data)),
      );
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  // Web reads the device realtime endpoint in addition to the station SQL
  // snapshot. Use the same source, while retaining authorized server totals
  // whenever a complete fresh reading cannot be obtained.
  Future<Map<String, dynamic>> _withRealtimePower(
      Map<String, dynamic> data,) async {
    final station = data['station'];
    if (station is! Map<String, dynamic>) return data;
    final sns = <String>{};
    for (final device in (data['devices'] as List? ?? const [])) {
      if (device is! Map) continue;
      if (device['status'] != 1 && device['status'] != 2) continue;
      if (deviceCategory(Map<String, dynamic>.from(device)) != 'inv') continue;
      final sn = device['sn'];
      if (sn is String && sn.isNotEmpty) sns.add(sn);
    }
    if (sns.isEmpty) return data;
    final deadline = DateTime.now().add(const Duration(seconds: 8));

    Future<InverterRealtime?> read(String sn) async {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) return null;
      final cancel = CancelToken();
      try {
        final response = await remoteDataSource
            .getDeviceRealtime(sn, cancelToken: cancel)
            .timeout(
          remaining,
          onTimeout: () {
            cancel.cancel('Station realtime deadline exceeded');
            throw TimeoutException('Station realtime deadline exceeded');
          },
        );
        final body = _parseData(response).getOrElse((_) => {});
        final raw = body['realtime'];
        if (body['online'] != true || raw is! Map<String, dynamic>) return null;
        final reading = InverterRealtime.fromJson({
          ...raw,
          'device_sn': sn,
          'updated_at': raw['updated_at'] ?? body['data_time'],
          'online': true,
        });
        final stamp = reading.updatedAt;
        final age = stamp == null ? null : DateTime.now().difference(stamp);
        return age != null &&
                age >= Duration.zero &&
                age < const Duration(minutes: 5)
            ? reading
            : null;
      } on DioException {
        return null;
      } on TimeoutException {
        return null;
      } on FormatException {
        return null;
      } on TypeError {
        return null;
      }
    }

    final readings = <InverterRealtime>[];
    final targets = sns.toList();
    for (var start = 0; start < targets.length; start += 4) {
      final batch = await Future.wait(targets.skip(start).take(4).map(read));
      if (batch.any((reading) => reading == null)) return data;
      readings.addAll(batch.cast<InverterRealtime>());
    }
    final next = Map<String, dynamic>.from(station);
    double? number(dynamic value) =>
        value is num && value.isFinite ? value.toDouble() : null;
    void total(String key, double? Function(InverterRealtime) extract) {
      final values = readings.map(extract).toList();
      if (values.every((value) => value != null)) {
        next[key] = values.fold<double>(0, (sum, value) => sum + value!);
      }
    }

    total('pv_power', (r) => number(r.telemetryFields['pv_total_power']));
    total('load_power', (r) => number(r.telemetryFields['output_power']));
    total('batt_power', (r) {
      final charge = number(r.telemetryFields['battery_charge_power']);
      final discharge = number(r.telemetryFields['battery_discharge_power']);
      return charge != null || discharge != null
          ? (charge ?? 0) - (discharge ?? 0)
          : number(r.telemetryFields['battery_power']);
    });
    final soc = readings
        .map((r) => number(r.telemetryFields['battery_soc']))
        .whereType<double>()
        .where((value) => value >= 0 && value <= 100)
        .toList();
    if (soc.isNotEmpty) {
      next['batt_soc'] = soc.reduce((a, b) => a + b) / soc.length;
    }
    final grid =
        readings.map((r) => measuredGridPower(r.telemetryFields)).toList();
    if (grid.every((value) => value != null)) {
      next['grid_power'] = grid.fold<double>(0, (sum, value) => sum + value!);
      next['grid_updated_at'] = readings
          .map((r) => r.updatedAt!)
          .reduce(
            (a, b) => a.isBefore(b) ? a : b,
          )
          .toUtc()
          .toIso8601String();
    }
    return {...data, 'station': next};
  }

  @override
  Future<Either<Failure, void>> create(Map<String, dynamic> data) async {
    try {
      final response = await remoteDataSource.create(data);
      final parsed = _parseData(response, allowEmpty: true);
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
  Future<Either<Failure, void>> update(
    int stationId,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await remoteDataSource.update(stationId, data);
      final parsed = _parseData(response, allowEmpty: true);
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
      final parsed = _parseData(response, allowEmpty: true);
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
  Future<Either<Failure, void>> unbindDevice(String sn) async {
    try {
      final response = await remoteDataSource.unbindDevice(sn);
      final parsed = _parseData(response, allowEmpty: true);
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
  Future<Either<Failure, void>> rebindDevice(
      String sn, int newStationId,) async {
    try {
      final response = await remoteDataSource.rebindDevice(sn, newStationId);
      final parsed = _parseData(response, allowEmpty: true);
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
  Future<Either<Failure, void>> bindDevice(String sn, int stationId) async {
    try {
      final response = await remoteDataSource.bindDevice(sn, stationId);
      final parsed = _parseData(response, allowEmpty: true);
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
  Future<Either<Failure, void>> deleteDevice(String sn) async {
    try {
      final response = await remoteDataSource.deleteDevice(sn);
      final parsed = _parseData(response, allowEmpty: true);
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
  Future<Either<Failure, void>> reorderDevices(
      int stationId, List<String> deviceOrder,) async {
    try {
      final response =
          await remoteDataSource.reorderDevices(stationId, deviceOrder);
      final parsed = _parseData(response, allowEmpty: true);
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
  Future<Either<Failure, void>> reorderStations(List<int> stationOrder) async {
    try {
      final response = await remoteDataSource.reorderStations(stationOrder);
      final parsed = _parseData(response, allowEmpty: true);
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
  Future<Either<Failure, List<dynamic>>> getStatistics(
    int stationId,
    String startDate,
    String endDate,
    String period,
  ) async {
    try {
      final response = await remoteDataSource.getStatistics(
        stationId,
        startDate,
        endDate,
        period,
      );
      return _parseList(response);
    } on DioException catch (e) {
      return Left(_mapError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }
}
