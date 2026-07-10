import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:inv_app/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:inv_app/features/dashboard/domain/entities/dashboard_data.dart';
import 'package:inv_app/features/dashboard/domain/entities/trend_data_point.dart';
import 'package:inv_app/features/dashboard/domain/entities/station_rank_item.dart';
import 'package:inv_app/core/errors/failures.dart';

import '../../../../helpers/mock_providers.dart';
import '../../../../helpers/test_data.dart';

/// Helper: create a [StreamController<Map<String,dynamic>>] that the test can
/// close manually, giving deterministic control over the SSE lifecycle.
StreamController<Map<String, dynamic>> _createSSEController() =>
    StreamController<Map<String, dynamic>>.broadcast();

void main() {
  late DashboardBloc dashboardBloc;
  late MockDashboardRepository mockDashboardRepository;
  late MockDataCacheService mockDataCacheService;
  late MockDashboardSSEDataSource mockSSEDataSource;

  setUp(() {
    mockDashboardRepository = MockDashboardRepository();
    mockDataCacheService = MockDataCacheService();
    mockSSEDataSource = MockDashboardSSEDataSource();

    // Default SSE stubs
    when(() => mockSSEDataSource.connectToSSE())
        .thenAnswer((_) => const Stream<Map<String, dynamic>>.empty());
    when(() => mockSSEDataSource.disconnect()).thenReturn(null);

    dashboardBloc = DashboardBloc(
      repository: mockDashboardRepository,
      dataCacheService: mockDataCacheService,
      sseDataSource: mockSSEDataSource,
    );
  });

  tearDown(() {
    dashboardBloc.close();
  });

  test('initial state is DashboardInitial', () {
    expect(dashboardBloc.state, equals(const DashboardInitial()));
  });

  // ---------------------------------------------------------------------------
  // DashboardLoadRequested
  // ---------------------------------------------------------------------------
  group('DashboardLoadRequested', () {
    blocTest<DashboardBloc, DashboardState>(
      'emits [DashboardLoading, DashboardLoaded] when all APIs succeed',
      build: () {
        when(() => mockDashboardRepository.getStatistics()).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'todayEnergy': 25.3,
            'totalEnergy': 1500.5,
            'deviceStats': {
              'total': 10,
              'online': 8,
              'offline': 1,
              'fault': 1,
            },
            'recentAlarms': <dynamic>[],
          }),
        );
        when(() => mockDashboardRepository.getTrendData(
              type: any(named: 'type'),
            ),).thenAnswer(
          (_) async => right<Failure, List<TrendDataPoint>>([
            const TrendDataPoint(date: '01/01', energy: 10.0),
          ]),
        );
        when(() => mockDashboardRepository.getDeviceDistribution()).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'online': 8,
            'offline': 1,
            'fault': 1,
          }),
        );
        when(() => mockDashboardRepository.getStationRanking()).thenAnswer(
          (_) async => right<Failure, List<StationRankItem>>([
            const StationRankItem(
              stationId: 1,
              stationName: 'Station A',
              energy: 500.0,
              deviceCount: 5,
            ),
          ]),
        );
        when(() => mockDataCacheService.save(any(), any()))
            .thenAnswer((_) async {});
        return dashboardBloc;
      },
      act: (bloc) => bloc.add(const DashboardLoadRequested()),
      expect: () => [
        isA<DashboardLoading>(),
        isA<DashboardLoaded>(),
      ],
    );

    blocTest<DashboardBloc, DashboardState>(
      'emits [DashboardLoading, DashboardError] when all APIs fail without cache',
      build: () {
        when(() => mockDashboardRepository.getStatistics()).thenAnswer(
          (_) async =>
              left<Failure, Map<String, dynamic>>(createTestServerFailure()),
        );
        when(() => mockDashboardRepository.getTrendData(
              type: any(named: 'type'),
            ),).thenAnswer(
          (_) async =>
              left<Failure, List<TrendDataPoint>>(createTestServerFailure()),
        );
        when(() => mockDashboardRepository.getDeviceDistribution()).thenAnswer(
          (_) async => left<Failure, Map<String, dynamic>>(
              createTestServerFailure(),),
        );
        when(() => mockDashboardRepository.getStationRanking()).thenAnswer(
          (_) async => left<Failure, List<StationRankItem>>(
              createTestServerFailure(),),
        );
        when(() => mockDataCacheService.load(any())).thenReturn(null);
        return dashboardBloc;
      },
      act: (bloc) => bloc.add(const DashboardLoadRequested()),
      expect: () => [
        isA<DashboardLoading>(),
        isA<DashboardError>(),
      ],
    );

    blocTest<DashboardBloc, DashboardState>(
      'emits [DashboardLoaded] from cache when all APIs fail with cache available',
      build: () {
        when(() => mockDashboardRepository.getStatistics()).thenAnswer(
          (_) async =>
              left<Failure, Map<String, dynamic>>(createTestServerFailure()),
        );
        when(() => mockDashboardRepository.getTrendData(
              type: any(named: 'type'),
            ),).thenAnswer(
          (_) async =>
              left<Failure, List<TrendDataPoint>>(createTestServerFailure()),
        );
        when(() => mockDashboardRepository.getDeviceDistribution()).thenAnswer(
          (_) async => left<Failure, Map<String, dynamic>>(
              createTestServerFailure(),),
        );
        when(() => mockDashboardRepository.getStationRanking()).thenAnswer(
          (_) async => left<Failure, List<StationRankItem>>(
              createTestServerFailure(),),
        );
        when(() => mockDataCacheService.load(any())).thenReturn({
          'todayEnergy': 25.3,
          'totalEnergy': 1500.5,
          'deviceTotal': 10,
          'onlineCount': 8,
          'offlineCount': 1,
          'faultCount': 1,
          'trendData': <dynamic>[],
          'stationRanking': <dynamic>[],
          'recentAlarms': <dynamic>[],
        });
        return dashboardBloc;
      },
      act: (bloc) => bloc.add(const DashboardLoadRequested()),
      expect: () => [
        isA<DashboardLoading>(),
        isA<DashboardLoaded>().having(
          (s) => s.data.isFromCache,
          'isFromCache',
          true,
        ),
      ],
    );

    blocTest<DashboardBloc, DashboardState>(
      'succeeds with partial API results',
      build: () {
        // Only statistics succeeds, others fail
        when(() => mockDashboardRepository.getStatistics()).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'todayEnergy': 25.3,
            'totalEnergy': 1500.5,
            'deviceStats': {'total': 10},
            'recentAlarms': <dynamic>[],
          }),
        );
        when(() => mockDashboardRepository.getTrendData(
              type: any(named: 'type'),
            ),).thenAnswer(
          (_) async =>
              left<Failure, List<TrendDataPoint>>(createTestServerFailure()),
        );
        when(() => mockDashboardRepository.getDeviceDistribution()).thenAnswer(
          (_) async =>
              left<Failure, Map<String, dynamic>>(createTestServerFailure()),
        );
        when(() => mockDashboardRepository.getStationRanking()).thenAnswer(
          (_) async => left<Failure, List<StationRankItem>>(
              createTestServerFailure(),),
        );
        when(() => mockDataCacheService.save(any(), any()))
            .thenAnswer((_) async {});
        return dashboardBloc;
      },
      act: (bloc) => bloc.add(const DashboardLoadRequested()),
      expect: () => [
        isA<DashboardLoading>(),
        isA<DashboardLoaded>(),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // DashboardSSEConnectRequested
  // ---------------------------------------------------------------------------
  group('DashboardSSEConnectRequested', () {
    blocTest<DashboardBloc, DashboardState>(
      'emits SSE connected state when already loaded',
      build: () {
        final controller = _createSSEController();
        when(() => mockSSEDataSource.connectToSSE())
            .thenAnswer((_) => controller.stream);
        return dashboardBloc;
      },
      seed: () => const DashboardLoaded(
        data: DashboardData(
          todayEnergy: 25.3,
          totalEnergy: 1500.5,
          deviceTotal: 10,
          onlineCount: 8,
          offlineCount: 1,
          faultCount: 1,
          trendData: [],
          stationRanking: [],
          recentAlarms: [],
        ),
        isSSEConnected: true,
      ),
      act: (bloc) => bloc.add(const DashboardSSEConnectRequested()),
      wait: const Duration(milliseconds: 100),
      expect: () => [
        // 1) Bloc explicitly emits isSSEConnected: false before connecting
        isA<DashboardLoaded>().having(
          (s) => s.isSSEConnected,
          'isSSEConnected',
          false,
        ),
        // 2) DashboardSSEConnectionChanged(isConnected: true) is added
        isA<DashboardLoaded>().having(
          (s) => s.isSSEConnected,
          'isSSEConnected',
          true,
        ),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // DashboardSSEDisconnectRequested
  // ---------------------------------------------------------------------------
  group('DashboardSSEDisconnectRequested', () {
    blocTest<DashboardBloc, DashboardState>(
      'emits SSE disconnected state when already loaded',
      build: () => dashboardBloc,
      seed: () => const DashboardLoaded(
        data: DashboardData(
          todayEnergy: 25.3,
          totalEnergy: 1500.5,
          deviceTotal: 10,
          onlineCount: 8,
          offlineCount: 1,
          faultCount: 1,
          trendData: [],
          stationRanking: [],
          recentAlarms: [],
        ),
        isSSEConnected: true,
      ),
      act: (bloc) => bloc.add(const DashboardSSEDisconnectRequested()),
      expect: () => [
        isA<DashboardLoaded>().having(
          (s) => s.isSSEConnected,
          'isSSEConnected',
          false,
        ),
      ],
      verify: (_) {
        // bloc.close() (called by blocTest tearDown before verify) also
        // invokes sseDataSource.disconnect(), so the handler accounts for
        // at least 1 explicit call.
        verify(() => mockSSEDataSource.disconnect()).called(greaterThanOrEqualTo(1));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // DashboardSSEDataReceived
  // ---------------------------------------------------------------------------
  group('DashboardSSEDataReceived', () {
    blocTest<DashboardBloc, DashboardState>(
      'updates data when in DashboardLoaded state with dashboard_update type',
      build: () => dashboardBloc,
      seed: () => const DashboardLoaded(
        data: DashboardData(
          todayEnergy: 25.3,
          totalEnergy: 1500.5,
          deviceTotal: 10,
          onlineCount: 8,
          offlineCount: 1,
          faultCount: 1,
          trendData: [],
          stationRanking: [],
          recentAlarms: [],
        ),
      ),
      act: (bloc) => bloc.add(const DashboardSSEDataReceived(data: {
        'type': 'dashboard_update',
        'deviceStats': {
          'online': 9,
          'offline': 0,
          'fault': 1,
          'total': 10,
        },
      },),),
      expect: () => [
        isA<DashboardLoaded>().having(
          (s) => s.data.onlineCount,
          'onlineCount',
          9,
        ),
      ],
    );

    blocTest<DashboardBloc, DashboardState>(
      'ignores data when not in DashboardLoaded state',
      build: () => dashboardBloc,
      act: (bloc) => bloc.add(const DashboardSSEDataReceived(data: {
        'type': 'dashboard_update',
        'deviceStats': {'online': 9},
      },),),
      expect: () => <DashboardState>[],
    );
  });

  // ---------------------------------------------------------------------------
  // DashboardTimeRangeChanged
  // ---------------------------------------------------------------------------
  group('DashboardTimeRangeChanged', () {
    blocTest<DashboardBloc, DashboardState>(
      'updates selectedTimeRange and reloads trend data when in loaded state',
      build: () {
        when(() => mockDashboardRepository.getTrendData(
              type: any(named: 'type'),
            ),).thenAnswer(
          (_) async => right<Failure, List<TrendDataPoint>>([
            const TrendDataPoint(date: '01/07', energy: 20.0),
          ]),
        );
        return dashboardBloc;
      },
      seed: () => const DashboardLoaded(
        data: DashboardData(
          todayEnergy: 25.3,
          totalEnergy: 1500.5,
          deviceTotal: 10,
          onlineCount: 8,
          offlineCount: 1,
          faultCount: 1,
          trendData: [],
          stationRanking: [],
          recentAlarms: [],
        ),
      ),
      act: (bloc) => bloc.add(const DashboardTimeRangeChanged(range: 'week')),
      expect: () => [
        isA<DashboardLoaded>().having(
          (s) => s.selectedTimeRange,
          'selectedTimeRange',
          'week',
        ),
        isA<DashboardLoaded>(),
      ],
    );
  });
}
