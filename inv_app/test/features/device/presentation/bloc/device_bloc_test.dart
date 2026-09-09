import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/core/data/local_cache_database.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/data_cache_service.dart';
import 'package:inv_app/core/services/offline/offline_op_log_store.dart';

import '../../../../helpers/mock_providers.dart';
import '../../../../helpers/test_data.dart';

/// 解绑副作用依赖的本地 mock（验证 fold-emit 契约用）
class _MockBleDeviceKeyStore extends Mock implements BleDeviceKeyStore {}

class _MockOfflineOpLogStore extends Mock implements OfflineOpLogStore {}

class _MockLocalCacheDatabase extends Mock implements LocalCacheDatabase {}

void main() {
  late DeviceBloc deviceBloc;
  late MockDeviceRepository mockDeviceRepository;
  late MockRealtimeDataService mockRealtimeDataService;
  late MockDataCacheService mockDataCacheService;

  setUpAll(() {
    // mocktail：any() 匹配自定义类型需要注册 fallback（解绑副作用日志）
    registerFallbackValue(
      OfflineOpLog(
        logId: 'fallback',
        deviceSn: 'fallback',
        action: 'unbind',
        channel: 'cloud',
        opTime: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
  });

  setUp(() {
    mockDeviceRepository = MockDeviceRepository();
    mockRealtimeDataService = MockRealtimeDataService();
    mockDataCacheService = MockDataCacheService();

    // DeviceBloc._startMQTTRealtime 依赖 RealtimeDataService 的实时数据流
    when(() => mockRealtimeDataService.realtimeDataStream)
        .thenAnswer((_) => const Stream<InverterRealtime>.empty());

    deviceBloc = DeviceBloc(
      repository: mockDeviceRepository,
      realtimeDataService: mockRealtimeDataService,
      dataCacheService: mockDataCacheService,
    );
  });

  tearDown(() {
    deviceBloc.close();
  });

  test('initial state is DeviceInitial', () {
    expect(deviceBloc.state, equals(DeviceInitial()));
  });

  test('local polling does not overlap while a request is pending', () {
    fakeAsync((async) {
      final repository = MockDeviceRepository();
      final realtimeService = MockRealtimeDataService();
      final localService = MockLocalCommunicationService();
      final pendingConnect = Completer<void>();

      when(() => realtimeService.realtimeDataStream)
          .thenAnswer((_) => const Stream<InverterRealtime>.empty());
      when(() => localService.connect(any()))
          .thenAnswer((_) => pendingConnect.future);
      when(() => localService.getRealtimeData()).thenAnswer(
        (_) async => <String, dynamic>{},
      );

      final bloc = DeviceBloc(
        repository: repository,
        realtimeDataService: realtimeService,
        localCommunicationService: localService,
      );
      bloc.add(const DeviceStartLocalPoll(deviceIP: '192.168.4.1'));
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      verify(() => localService.connect('192.168.4.1')).called(1);

      async.elapse(const Duration(seconds: 9));
      async.flushMicrotasks();
      verifyNever(() => localService.connect(any()));

      pendingConnect.complete();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      verify(() => localService.connect('192.168.4.1')).called(1);

      bloc.close();
      async.flushMicrotasks();
    });
  });

  test('a new local polling generation is not blocked by an old request', () {
    fakeAsync((async) {
      final repository = MockDeviceRepository();
      final realtimeService = MockRealtimeDataService();
      final localService = MockLocalCommunicationService();
      final oldConnect = Completer<void>();
      final newConnect = Completer<void>();

      when(() => realtimeService.realtimeDataStream)
          .thenAnswer((_) => const Stream<InverterRealtime>.empty());
      when(() => localService.connect('192.168.4.1'))
          .thenAnswer((_) => oldConnect.future);
      when(() => localService.connect('192.168.4.2'))
          .thenAnswer((_) => newConnect.future);
      when(() => localService.getRealtimeData()).thenAnswer(
        (_) async => <String, dynamic>{},
      );

      final bloc = DeviceBloc(
        repository: repository,
        realtimeDataService: realtimeService,
        localCommunicationService: localService,
      );
      bloc.add(const DeviceStartLocalPoll(deviceIP: '192.168.4.1'));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      verify(() => localService.connect('192.168.4.1')).called(1);

      bloc.add(const DeviceStartLocalPoll(deviceIP: '192.168.4.2'));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      verify(() => localService.connect('192.168.4.2')).called(1);

      oldConnect.complete();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      verifyNever(() => localService.connect('192.168.4.2'));

      newConnect.complete();
      async.flushMicrotasks();
      bloc.close();
      async.flushMicrotasks();
    });
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
            createTestDeviceListResponse(),
          ),
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

    // P1 fold-emit 契约：副作用（清 BLE 凭证等）是异步的，
    // 不能在 emit 前 await——否则 fold 的 async 闭包不会被等待，
    // emit 落到事件处理器结束之后，状态丢失/StateError。
    // 用一个永不完成的 keyStore.delete 模拟慢副作用，
    // 断言 DeviceUnbindSuccess 仍同步发出且副作用已被触发。
    test('emits DeviceUnbindSuccess without awaiting slow local side effects',
        () async {
      final keyStore = _MockBleDeviceKeyStore();
      final logStore = _MockOfflineOpLogStore();
      final localCache = _MockLocalCacheDatabase();
      final sideEffectGate = Completer<void>();
      when(() => keyStore.delete(any()))
          .thenAnswer((_) => sideEffectGate.future);
      when(() => logStore.add(any())).thenAnswer((_) async {});
      when(() => localCache.deleteDevice(any())).thenAnswer((_) async {});

      when(() => mockDeviceRepository.unbind(any())).thenAnswer(
        (_) async => right<Failure, void>(null),
      );

      final bloc = DeviceBloc(
        repository: mockDeviceRepository,
        realtimeDataService: mockRealtimeDataService,
        dataCacheService: mockDataCacheService,
        bleKeyStore: keyStore,
        offlineLogStore: logStore,
        localCache: localCache,
      );

      final states = <DeviceState>[];
      final subscription = bloc.stream.listen(states.add);
      bloc.add(const DeviceUnbindRequested(sn: 'TEST_SN_1'));
      await pumpEventQueue();

      expect(
        states.last,
        isA<DeviceUnbindSuccess>(),
        reason: '副作用未完成也必须先发出成功状态',
      );
      // 副作用已被触发但尚未完成
      verify(() => keyStore.delete('TEST_SN_1')).called(1);
      verifyNever(() => logStore.add(any()));

      // 收尾：放行副作用，避免悬挂的 future 影响其他用例
      sideEffectGate.complete();
      await pumpEventQueue();
      await subscription.cancel();
      await bloc.close();
    });
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

    // P0：历史曲线页指标透传链路——event.metric 必须进入
    // DeviceHistoryLoaded，页面据此做 y 映射；后端原始行数据
    // （time/avg_power/energy_produce 等字段）原样透传不做改写。
    blocTest<DeviceBloc, DeviceState>(
      'passes metric and raw backend rows through to DeviceHistoryLoaded',
      build: () {
        final backendRows = [
          {
            'time': '2026-09-08T05:00:00Z',
            'avg_power': 1.5,
            'max_power': 3.2,
            'energy_produce': 0.8,
            'avg_temperature': 40.0,
            'run_minutes': 60,
          },
          {
            'time': '2026-09-08T06:00:00Z',
            'avg_power': 2.0,
            'max_power': 4.0,
            'energy_produce': 1.2,
            'avg_temperature': 41.0,
            'run_minutes': 60,
          },
        ];
        when(
          () => mockDeviceRepository.getHistory(
            any(),
            any(),
            any(),
            any(),
          ),
        ).thenAnswer((_) async => right<Failure, List<dynamic>>(backendRows));
        return deviceBloc;
      },
      act: (bloc) => bloc.add(
        const DeviceHistoryRequested(
          sn: 'TEST_SN_1',
          period: 'hour',
          startDate: '2026-09-08',
          endDate: '2026-09-08',
          metric: 'pv',
        ),
      ),
      expect: () => [
        isA<DeviceHistoryLoaded>()
            .having((s) => s.metric, 'metric', 'pv')
            .having((s) => s.period, 'period', 'hour')
            .having((s) => s.data.length, 'data.length', 2)
            .having(
              (s) => s.data.first['energy_produce'],
              'data.first.energy_produce',
              0.8,
            )
            .having(
              (s) => s.data.first['time'],
              'data.first.time',
              '2026-09-08T05:00:00Z',
            ),
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
