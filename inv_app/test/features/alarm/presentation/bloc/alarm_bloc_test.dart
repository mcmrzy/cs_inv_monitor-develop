import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:inv_app/features/alarm/presentation/bloc/alarm_bloc.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/errors/failures.dart';

import '../../../../helpers/mock_providers.dart';
import '../../../../helpers/test_data.dart';

void main() {
  late AlarmBloc alarmBloc;
  late MockAlarmRepository mockAlarmRepository;
  late MockDataCacheService mockDataCacheService;
  late MockMQTTService mockMQTTService;

  setUp(() {
    mockAlarmRepository = MockAlarmRepository();
    mockDataCacheService = MockDataCacheService();
    mockMQTTService = MockMQTTService();

    // Default MQTT stubs
    when(() => mockMQTTService.alarmStream)
        .thenAnswer((_) => const Stream<AlarmData>.empty());

    alarmBloc = AlarmBloc(
      repository: mockAlarmRepository,
      dataCacheService: mockDataCacheService,
      mqttService: mockMQTTService,
    );
  });

  tearDown(() {
    alarmBloc.close();
  });

  test('initial state is AlarmInitial', () {
    expect(alarmBloc.state, equals(AlarmInitial()));
  });

  // ---------------------------------------------------------------------------
  // AlarmListRequested
  // ---------------------------------------------------------------------------
  group('AlarmListRequested', () {
    blocTest<AlarmBloc, AlarmState>(
      'emits [AlarmListLoaded] on success',
      build: () {
        when(() => mockAlarmRepository.getList(
              stationId: any(named: 'stationId'),
              status: any(named: 'status'),
              page: any(named: 'page'),
              pageSize: any(named: 'pageSize'),
            ),).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>(
            createTestAlarmListResponse(),
          ),
        );
        when(() => mockDataCacheService.save(any(), any()))
            .thenAnswer((_) async {});
        return alarmBloc;
      },
      act: (bloc) => bloc.add(const AlarmListRequested()),
      expect: () => [
        isA<AlarmListLoaded>().having(
          (s) => s.isFromCache,
          'isFromCache',
          false,
        ),
      ],
    );

    blocTest<AlarmBloc, AlarmState>(
      'emits [AlarmError] on failure without cache',
      build: () {
        when(() => mockAlarmRepository.getList(
              stationId: any(named: 'stationId'),
              status: any(named: 'status'),
              page: any(named: 'page'),
              pageSize: any(named: 'pageSize'),
            ),).thenAnswer(
          (_) async =>
              left<Failure, Map<String, dynamic>>(createTestServerFailure()),
        );
        when(() => mockDataCacheService.load(any())).thenReturn(null);
        return alarmBloc;
      },
      act: (bloc) => bloc.add(const AlarmListRequested()),
      expect: () => [
        isA<AlarmError>(),
      ],
    );

    blocTest<AlarmBloc, AlarmState>(
      'emits [AlarmListLoaded] from cache on failure',
      build: () {
        when(() => mockAlarmRepository.getList(
              stationId: any(named: 'stationId'),
              status: any(named: 'status'),
              page: any(named: 'page'),
              pageSize: any(named: 'pageSize'),
            ),).thenAnswer(
          (_) async => left<Failure, Map<String, dynamic>>(
              createTestNetworkFailure(),),
        );
        when(() => mockDataCacheService.load(any())).thenReturn(
          createTestAlarmListResponse(),
        );
        return alarmBloc;
      },
      act: (bloc) => bloc.add(const AlarmListRequested()),
      expect: () => [
        isA<AlarmListLoaded>().having(
          (s) => s.isFromCache,
          'isFromCache',
          true,
        ),
      ],
    );

    blocTest<AlarmBloc, AlarmState>(
      'saves data to cache on success',
      build: () {
        final responseData = createTestAlarmListResponse();
        when(() => mockAlarmRepository.getList(
              stationId: any(named: 'stationId'),
              status: any(named: 'status'),
              page: any(named: 'page'),
              pageSize: any(named: 'pageSize'),
            ),).thenAnswer(
          (_) async =>
              right<Failure, Map<String, dynamic>>(responseData),
        );
        when(() => mockDataCacheService.save(any(), any()))
            .thenAnswer((_) async {});
        return alarmBloc;
      },
      act: (bloc) => bloc.add(const AlarmListRequested()),
      verify: (_) {
        verify(() => mockDataCacheService.save(
              'alarm_list',
              any(),
            ),).called(1);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // AlarmDetailRequested
  // ---------------------------------------------------------------------------
  group('AlarmDetailRequested', () {
    blocTest<AlarmBloc, AlarmState>(
      'emits [AlarmDetailLoaded] on success',
      build: () {
        when(() => mockAlarmRepository.getDetail(any())).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>(
            createTestAlarmMap(),
          ),
        );
        return alarmBloc;
      },
      act: (bloc) => bloc.add(const AlarmDetailRequested(alarmId: 1)),
      expect: () => [
        isA<AlarmDetailLoaded>(),
      ],
    );

    blocTest<AlarmBloc, AlarmState>(
      'emits [AlarmError] on failure',
      build: () {
        when(() => mockAlarmRepository.getDetail(any())).thenAnswer(
          (_) async => left<Failure, Map<String, dynamic>>(
            createTestServerFailure(),
          ),
        );
        return alarmBloc;
      },
      act: (bloc) => bloc.add(const AlarmDetailRequested(alarmId: 1)),
      expect: () => [
        isA<AlarmError>(),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // AlarmMarkReadRequested
  // ---------------------------------------------------------------------------
  group('AlarmMarkReadRequested', () {
    blocTest<AlarmBloc, AlarmState>(
      'emits [AlarmLoading, AlarmMarkReadSuccess] on success',
      build: () {
        when(() => mockAlarmRepository.markRead(any())).thenAnswer(
          (_) async => right<Failure, void>(null),
        );
        return alarmBloc;
      },
      act: (bloc) =>
          bloc.add(const AlarmMarkReadRequested(alarmIds: [1, 2])),
      expect: () => [
        isA<AlarmLoading>(),
        isA<AlarmMarkReadSuccess>(),
      ],
    );

    blocTest<AlarmBloc, AlarmState>(
      'emits [AlarmLoading, AlarmError] on failure',
      build: () {
        when(() => mockAlarmRepository.markRead(any())).thenAnswer(
          (_) async => left<Failure, void>(createTestServerFailure()),
        );
        return alarmBloc;
      },
      act: (bloc) =>
          bloc.add(const AlarmMarkReadRequested(alarmIds: [1, 2])),
      expect: () => [
        isA<AlarmLoading>(),
        isA<AlarmError>(),
      ],
    );
  });
}
