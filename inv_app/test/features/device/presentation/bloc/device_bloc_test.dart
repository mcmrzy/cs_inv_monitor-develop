import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/services/data_cache_service.dart';

import '../../../../helpers/mock_providers.dart';
import '../../../../helpers/test_data.dart';

void main() {
  late DeviceBloc deviceBloc;
  late MockDeviceRepository mockDeviceRepository;
  late MockMQTTService mockMQTTService;
  late MockDataCacheService mockDataCacheService;

  setUp(() {
    mockDeviceRepository = MockDeviceRepository();
    mockMQTTService = MockMQTTService();
    mockDataCacheService = MockDataCacheService();

    // Default MQTT stubs
    when(() => mockMQTTService.isConnected).thenReturn(false);
    when(() => mockMQTTService.realtimeDataStream)
        .thenAnswer((_) => const Stream<InverterRealtime>.empty());
    when(() => mockMQTTService.unsubscribeDeviceTopics(any())).thenReturn(null);
    when(() => mockMQTTService.subscribeDeviceTopics(any())).thenReturn(null);
    when(() =>
            mockMQTTService.waitForConnection(timeout: any(named: 'timeout')))
        .thenAnswer((_) async {});

    deviceBloc = DeviceBloc(
      repository: mockDeviceRepository,
      mqttService: mockMQTTService,
      dataCacheService: mockDataCacheService,
    );
  });

  tearDown(() {
    deviceBloc.close();
  });

  test('initial state is DeviceInitial', () {
    expect(deviceBloc.state, equals(DeviceInitial()));
  });

  // ---------------------------------------------------------------------------
  // DeviceListRequested
  // ---------------------------------------------------------------------------
  group('DeviceListRequested', () {
    blocTest<DeviceBloc, DeviceState>(
      'emits [DeviceLoading, DeviceListLoaded] on success',
      build: () {
        when(
          () => mockDeviceRepository.getList(
            stationId: any(named: 'stationId'),
            status: any(named: 'status'),
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          ),
        ).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>(
              createTestDeviceListResponse()),
        );
        when(() => mockDataCacheService.save(any(), any()))
            .thenAnswer((_) async {});
        return deviceBloc;
      },
      act: (bloc) => bloc.add(const DeviceListRequested()),
      expect: () => [
        isA<DeviceLoading>(),
        isA<DeviceListLoaded>(),
      ],
    );

    blocTest<DeviceBloc, DeviceState>(
      'emits [DeviceLoading, DeviceError] on failure without cache',
      build: () {
        when(
          () => mockDeviceRepository.getList(
            stationId: any(named: 'stationId'),
            status: any(named: 'status'),
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          ),
        ).thenAnswer(
          (_) async =>
              left<Failure, Map<String, dynamic>>(createTestServerFailure()),
        );
        when(() => mockDataCacheService.load(any())).thenReturn(null);
        return deviceBloc;
      },
      act: (bloc) => bloc.add(const DeviceListRequested()),
      expect: () => [
        isA<DeviceLoading>(),
        isA<DeviceError>(),
      ],
    );

    blocTest<DeviceBloc, DeviceState>(
      'does not hide a server failure with cached data',
      build: () {
        when(
          () => mockDeviceRepository.getList(
            stationId: any(named: 'stationId'),
            status: any(named: 'status'),
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          ),
        ).thenAnswer(
          (_) async =>
              left<Failure, Map<String, dynamic>>(createTestServerFailure()),
        );
        when(() => mockDataCacheService.load(any())).thenReturn(
          createTestDeviceListResponse(),
        );
        return deviceBloc;
      },
      act: (bloc) => bloc.add(const DeviceListRequested()),
      expect: () => [
        isA<DeviceLoading>(),
        isA<DeviceError>(),
      ],
    );

    blocTest<DeviceBloc, DeviceState>(
      'uses explicitly marked cache on network failure',
      build: () {
        when(
          () => mockDeviceRepository.getList(
            stationId: any(named: 'stationId'),
            status: any(named: 'status'),
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          ),
        ).thenAnswer(
          (_) async =>
              left<Failure, Map<String, dynamic>>(createTestNetworkFailure()),
        );
        when(() => mockDataCacheService.load(any())).thenReturn(
          createTestDeviceListResponse(),
        );
        return deviceBloc;
      },
      act: (bloc) => bloc.add(const DeviceListRequested()),
      expect: () => [
        isA<DeviceLoading>(),
        isA<DeviceListLoaded>().having(
          (state) => state.isFromCache,
          'isFromCache',
          true,
        ),
      ],
    );

    blocTest<DeviceBloc, DeviceState>(
      'saves data to cache on success',
      build: () {
        final responseData = createTestDeviceListResponse();
        when(
          () => mockDeviceRepository.getList(
            stationId: any(named: 'stationId'),
            status: any(named: 'status'),
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          ),
        ).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>(responseData),
        );
        when(() => mockDataCacheService.save(any(), any()))
            .thenAnswer((_) async {});
        return deviceBloc;
      },
      act: (bloc) => bloc.add(const DeviceListRequested()),
      verify: (_) {
        verify(
          () => mockDataCacheService.save(
            DataCacheService.deviceList,
            any(),
          ),
        ).called(1);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // DeviceDetailRequested
  // ---------------------------------------------------------------------------
  group('DeviceDetailRequested', () {
    blocTest<DeviceBloc, DeviceState>(
      'emits [DeviceLoading, DeviceDetailLoaded] on success',
      build: () {
        when(() => mockDeviceRepository.getDetail(any())).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'device': createTestDeviceMap(),
          }),
        );
        return deviceBloc;
      },
      act: (bloc) => bloc.add(const DeviceDetailRequested(sn: 'TEST_SN_1')),
      expect: () => [
        isA<DeviceLoading>(),
        isA<DeviceDetailLoaded>(),
      ],
    );

    blocTest<DeviceBloc, DeviceState>(
      'emits [DeviceLoading, DeviceError] on failure',
      build: () {
        when(() => mockDeviceRepository.getDetail(any())).thenAnswer(
          (_) async => left<Failure, Map<String, dynamic>>(
            createTestServerFailure(),
          ),
        );
        return deviceBloc;
      },
      act: (bloc) => bloc.add(const DeviceDetailRequested(sn: 'TEST_SN_1')),
      expect: () => [
        isA<DeviceLoading>(),
        isA<DeviceError>(),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // DeviceControlRequested (cloud mode)
  // ---------------------------------------------------------------------------
  group('DeviceControlRequested', () {
    blocTest<DeviceBloc, DeviceState>(
      'emits [DeviceLoading, DeviceControlSuccess] on cloud success',
      build: () {
        when(
          () => mockDeviceRepository.control(
            any(),
            any(),
            any(),
          ),
        ).thenAnswer((_) async => right<Failure, void>(null));
        return deviceBloc;
      },
      act: (bloc) => bloc.add(
        const DeviceControlRequested(
          sn: 'TEST_SN_1',
          cmdType: 'start',
          params: {},
        ),
      ),
      expect: () => [
        isA<DeviceLoading>(),
        isA<DeviceControlSuccess>(),
      ],
    );

    blocTest<DeviceBloc, DeviceState>(
      'emits [DeviceLoading, DeviceError] on cloud failure',
      build: () {
        when(
          () => mockDeviceRepository.control(
            any(),
            any(),
            any(),
          ),
        ).thenAnswer(
          (_) async => left<Failure, void>(createTestServerFailure()),
        );
        return deviceBloc;
      },
      act: (bloc) => bloc.add(
        const DeviceControlRequested(
          sn: 'TEST_SN_1',
          cmdType: 'start',
          params: {},
        ),
      ),
      expect: () => [
        isA<DeviceLoading>(),
        isA<DeviceError>(),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // DeviceBindRequested
  // ---------------------------------------------------------------------------
  group('DeviceBindRequested', () {
    blocTest<DeviceBloc, DeviceState>(
      'emits [DeviceLoading, DeviceBindSuccess] on success',
      build: () {
        when(
          () => mockDeviceRepository.bind(
            any(),
            any(),
          ),
        ).thenAnswer((_) async => right<Failure, void>(null));
        return deviceBloc;
      },
      act: (bloc) => bloc.add(const DeviceBindRequested(sn: 'TEST_SN_1')),
      expect: () => [
        isA<DeviceLoading>(),
        isA<DeviceBindSuccess>(),
      ],
    );

    blocTest<DeviceBloc, DeviceState>(
      'emits [DeviceLoading, DeviceError] on failure',
      build: () {
        when(
          () => mockDeviceRepository.bind(
            any(),
            any(),
          ),
        ).thenAnswer(
          (_) async => left<Failure, void>(createTestServerFailure()),
        );
        return deviceBloc;
      },
      act: (bloc) => bloc.add(const DeviceBindRequested(sn: 'TEST_SN_1')),
      expect: () => [
        isA<DeviceLoading>(),
        isA<DeviceError>(),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // DeviceUnbindRequested
  // ---------------------------------------------------------------------------
  group('DeviceUnbindRequested', () {
    blocTest<DeviceBloc, DeviceState>(
      'emits [DeviceLoading, DeviceUnbindSuccess] on success',
      build: () {
        when(() => mockDeviceRepository.unbind(any())).thenAnswer(
          (_) async => right<Failure, void>(null),
        );
        return deviceBloc;
      },
      act: (bloc) => bloc.add(const DeviceUnbindRequested(sn: 'TEST_SN_1')),
      expect: () => [
        isA<DeviceLoading>(),
        isA<DeviceUnbindSuccess>(),
      ],
    );

    blocTest<DeviceBloc, DeviceState>(
      'emits [DeviceLoading, DeviceError] on failure',
      build: () {
        when(() => mockDeviceRepository.unbind(any())).thenAnswer(
          (_) async => left<Failure, void>(createTestServerFailure()),
        );
        return deviceBloc;
      },
      act: (bloc) => bloc.add(const DeviceUnbindRequested(sn: 'TEST_SN_1')),
      expect: () => [
        isA<DeviceLoading>(),
        isA<DeviceError>(),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // DeviceHistoryRequested
  // ---------------------------------------------------------------------------
  group('DeviceHistoryRequested', () {
    blocTest<DeviceBloc, DeviceState>(
      'emits [DeviceHistoryLoaded] on success',
      build: () {
        when(
          () => mockDeviceRepository.getHistory(
            any(),
            any(),
            any(),
            any(),
          ),
        ).thenAnswer(
          (_) async => right<Failure, List<dynamic>>([
            {'date': '2024-01-01', 'value': 10.5},
          ]),
        );
        return deviceBloc;
      },
      act: (bloc) => bloc.add(
        const DeviceHistoryRequested(
          sn: 'TEST_SN_1',
          period: 'day',
          startDate: '2024-01-01',
          endDate: '2024-01-07',
          metric: 'power',
        ),
      ),
      expect: () => [
        isA<DeviceHistoryLoaded>(),
      ],
    );

    blocTest<DeviceBloc, DeviceState>(
      'emits [DeviceError] on failure',
      build: () {
        when(
          () => mockDeviceRepository.getHistory(
            any(),
            any(),
            any(),
            any(),
          ),
        ).thenAnswer(
          (_) async => left<Failure, List<dynamic>>(createTestServerFailure()),
        );
        return deviceBloc;
      },
      act: (bloc) => bloc.add(
        const DeviceHistoryRequested(
          sn: 'TEST_SN_1',
          period: 'day',
          startDate: '2024-01-01',
          endDate: '2024-01-07',
          metric: 'power',
        ),
      ),
      expect: () => [
        isA<DeviceError>(),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // DeviceRealtimeWSUpdate
  // ---------------------------------------------------------------------------
  group('DeviceRealtimeWSUpdate', () {
    blocTest<DeviceBloc, DeviceState>(
      'updates DeviceDetailLoaded with realtime data when in detail state',
      build: () {
        // First get into DeviceDetailLoaded state
        when(() => mockDeviceRepository.getDetail(any())).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'device': createTestDeviceMap(),
          }),
        );
        return deviceBloc;
      },
      seed: () => DeviceDetailLoaded(
        device: createTestDeviceMap(),
        realtimeData: null,
      ),
      act: (bloc) => bloc.add(
        DeviceRealtimeWSUpdate(
          InverterRealtime(deviceSN: 'TEST_SN_1', updatedAt: DateTime.now()),
        ),
      ),
      expect: () => [
        isA<DeviceDetailLoaded>().having(
          (s) => s.realtimeData,
          'realtimeData',
          isNotNull,
        ),
      ],
    );
  });
}
