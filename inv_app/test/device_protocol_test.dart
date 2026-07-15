import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/core/services/data_cache_service.dart';
import 'package:inv_app/features/device_protocol/data/datasources/device_protocol_remote_data_source.dart';
import 'package:inv_app/features/device_protocol/data/repositories/device_protocol_repository_impl.dart';
import 'package:inv_app/features/device_protocol/domain/entities/device_protocol_entities.dart';
import 'package:inv_app/features/device_protocol/domain/repositories/device_protocol_repository.dart';
import 'package:inv_app/features/device_protocol/presentation/bloc/device_protocol_bloc.dart';
import 'package:mocktail/mocktail.dart';

class _MockRemote extends Mock implements DeviceProtocolRemoteDataSource {}

class _MockCache extends Mock implements DataCacheService {}

class _MockRepository extends Mock implements DeviceProtocolRepository {}

Map<String, dynamic> _alarm() => {
      'id': 12,
      'device_sn': 'INV001',
      'source': 1,
      'code': '42',
      'level': 2,
      'state': 'active',
      'event_time': '2026-07-14T01:02:03Z',
      'received_at': '2026-07-14T01:02:05Z',
      'active_at': '2026-07-14T01:02:03Z',
    };

Map<String, dynamic> _parallel({bool enabled = true}) => {
      'has_parallel': enabled,
      'enabled': enabled,
      'station_id': 7,
      'master_sn': 'INV001',
      'mode': 'three_phase',
      'count': 1,
      'total_rated_power': 5000,
      'total_active_power': 1234.5,
      'sync_state': 'synced',
      'reported_at': '2026-07-14T01:02:05Z',
      'machines': const [],
    };

Map<String, dynamic> _threePhase() => {
      'event_time': '2026-07-14T01:03:00Z',
      'received_at': '2026-07-14T01:03:02Z',
      'voltage_l1': 220.1,
      'voltage_l2': 220.2,
      'voltage_l3': 220.3,
      'current_l1': 1.1,
      'current_l2': 1.2,
      'current_l3': 1.3,
      'active_power_l1': 240,
      'active_power_l2': 250,
      'active_power_l3': 260,
      'total_active_power': 750,
      'line_voltage_l1l2': 380.1,
      'line_voltage_l2l3': 380.2,
      'line_voltage_l3l1': 380.3,
      'frequency': 50.02,
      'voltage_unbalance': 0.1,
      'current_unbalance': 0.2,
    };

Response<dynamic> _success(Map<String, dynamic> data) => Response<dynamic>(
      requestOptions: RequestOptions(path: '/test'),
      statusCode: 200,
      data: {'code': 0, 'message': 'success', 'data': data},
    );

void main() {
  test('strongly typed entities retain sampling and receiving times', () {
    final alarm = AlarmProtocolEvent.fromJson(_alarm());
    final phase = ThreePhaseSample.fromJson(_threePhase());

    expect(alarm.isActive, isTrue);
    expect(alarm.eventTime.difference(alarm.receivedAt).inSeconds, -2);
    expect(phase.voltage, [220.1, 220.2, 220.3]);
    expect(phase.activePower, [240, 250, 260]);
  });

  test('disabled parallel topology remains a reported current state', () {
    final parallel = DeviceParallelState.fromJson(_parallel(enabled: false));

    expect(parallel.enabled, isFalse);
    expect(parallel.hasReportedState, isTrue);
  });

  group('DeviceProtocolRepositoryImpl', () {
    late _MockRemote remote;
    late _MockCache cache;
    late DeviceProtocolRepositoryImpl repository;

    setUp(() {
      remote = _MockRemote();
      cache = _MockCache();
      repository = DeviceProtocolRepositoryImpl(remote, cache);
      when(() => cache.save(any(), any())).thenAnswer((_) async {});
    });

    test('unwraps API envelope and parses alarm page', () async {
      final page = {
        'items': [_alarm()],
        'total': 1,
      };
      when(() => remote.getAlarmEvents('INV001'))
          .thenAnswer((_) async => _success(page));

      final result = await repository.getAlarmEvents('INV001');

      expect(result.getOrElse(() => throw Exception()).value, hasLength(1));
      verify(() => cache.save('protocol_alarm_events_INV001', page)).called(1);
    });

    test('cache write failure does not hide valid server data', () async {
      when(() => remote.getParallelState('INV001'))
          .thenAnswer((_) async => _success(_parallel()));
      when(() => cache.save(any(), any())).thenThrow(Exception('disk full'));

      final result = await repository.getParallelState('INV001');

      expect(result.isRight(), isTrue);
    });

    test('network failure returns timestamped offline cache', () async {
      final request = RequestOptions(path: '/three-phase');
      when(() => remote.getThreePhase('INV001')).thenThrow(
        DioException(
          requestOptions: request,
          type: DioExceptionType.connectionError,
        ),
      );
      when(() => cache.load('protocol_three_phase_INV001')).thenReturn({
        'items': [_threePhase()],
      });
      when(() => cache.getTimestamp('protocol_three_phase_INV001'))
          .thenReturn(1000);

      final result = await repository.getThreePhase('INV001');
      final data = result.getOrElse(() => throw Exception());

      expect(data.isFromCache, isTrue);
      expect(data.cachedAt, DateTime.fromMillisecondsSinceEpoch(1000));
      expect(data.value, hasLength(1));
    });

    test('HTTP 403 remains forbidden and does not read cache', () async {
      final request = RequestOptions(path: '/parallel-state');
      when(() => remote.getParallelState('INV001')).thenThrow(
        DioException(
          requestOptions: request,
          response: Response<dynamic>(
            requestOptions: request,
            statusCode: 403,
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final result = await repository.getParallelState('INV001');

      result.fold(
        (failure) => expect(failure, isA<ForbiddenFailure>()),
        (_) => fail('expected forbidden'),
      );
      verifyNever(() => cache.load(any()));
    });
  });

  blocTest<DeviceProtocolBloc, DeviceProtocolState>(
    'keeps empty and forbidden states distinct',
    build: () {
      final repository = _MockRepository();
      when(() => repository.getAlarmEvents('INV001')).thenAnswer(
        (_) async => const Right(CachedProtocolData(value: [])),
      );
      when(() => repository.getParallelState('INV001')).thenAnswer(
        (_) async => Right(
          CachedProtocolData(
            value: DeviceParallelState.fromJson(const {
              'has_parallel': false,
              'enabled': false,
            }),
          ),
        ),
      );
      when(() => repository.getThreePhase('INV001')).thenAnswer(
        (_) async => const Left(ForbiddenFailure('无权限访问该设备')),
      );
      return DeviceProtocolBloc(repository: repository);
    },
    act: (bloc) => bloc.add(const DeviceProtocolRequested('INV001')),
    expect: () => [
      const DeviceProtocolLoading(),
      isA<DeviceProtocolLoaded>()
          .having(
            (state) => state.alarms.status,
            'alarm status',
            ProtocolSectionStatus.empty,
          )
          .having(
            (state) => state.parallel.status,
            'parallel status',
            ProtocolSectionStatus.empty,
          )
          .having(
            (state) => state.threePhase.status,
            'three phase status',
            ProtocolSectionStatus.forbidden,
          ),
    ],
  );
}
