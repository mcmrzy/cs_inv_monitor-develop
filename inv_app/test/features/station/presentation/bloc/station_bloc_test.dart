import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';
import 'package:inv_app/core/errors/failures.dart';

import '../../../../helpers/mock_providers.dart';
import '../../../../helpers/test_data.dart';

void main() {
  late StationBloc stationBloc;
  late MockStationRepository mockStationRepository;
  late MockStorageService mockStorageService;
  late MockDataCacheService mockDataCacheService;

  setUp(() {
    mockStationRepository = MockStationRepository();
    mockStorageService = MockStorageService();
    mockDataCacheService = MockDataCacheService();

    stationBloc = StationBloc(
      repository: mockStationRepository,
      storageService: mockStorageService,
      dataCacheService: mockDataCacheService,
    );
  });

  tearDown(() {
    stationBloc.close();
  });

  test('initial state is StationInitial', () {
    expect(stationBloc.state, equals(StationInitial()));
  });

  // ---------------------------------------------------------------------------
  // StationSummaryRequested
  // ---------------------------------------------------------------------------
  group('StationSummaryRequested', () {
    blocTest<StationBloc, StationState>(
      'emits [StationSummaryLoaded] on success',
      build: () {
        when(() => mockStationRepository.getSummary()).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'stations': [createTestStationMap()],
            'summary': {'total_power': 100.0},
          }),
        );
        when(() => mockDataCacheService.save(any(), any()))
            .thenAnswer((_) async {});
        return stationBloc;
      },
      act: (bloc) => bloc.add(StationSummaryRequested()),
      expect: () => [
        isA<StationSummaryLoaded>().having(
          (s) => s.isFromCache,
          'isFromCache',
          false,
        ),
      ],
      verify: (_) {
        verify(() => mockDataCacheService.save(
              'station_summary',
              any(),
            ),).called(1);
      },
    );

    blocTest<StationBloc, StationState>(
      'emits [StationError] on failure without cache',
      build: () {
        when(() => mockStationRepository.getSummary()).thenAnswer(
          (_) async =>
              left<Failure, Map<String, dynamic>>(createTestServerFailure()),
        );
        when(() => mockDataCacheService.load(any())).thenReturn(null);
        return stationBloc;
      },
      act: (bloc) => bloc.add(StationSummaryRequested()),
      expect: () => [
        isA<StationError>(),
      ],
    );

    blocTest<StationBloc, StationState>(
      'emits [StationSummaryLoaded] from cache on failure',
      build: () {
        when(() => mockStationRepository.getSummary()).thenAnswer(
          (_) async => left<Failure, Map<String, dynamic>>(
              createTestNetworkFailure(),),
        );
        when(() => mockDataCacheService.load(any())).thenReturn({
          'stations': [createTestStationMap()],
          'summary': {'total_power': 100.0},
        });
        return stationBloc;
      },
      act: (bloc) => bloc.add(StationSummaryRequested()),
      expect: () => [
        isA<StationSummaryLoaded>().having(
          (s) => s.isFromCache,
          'isFromCache',
          true,
        ),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // StationListRequested
  // ---------------------------------------------------------------------------
  group('StationListRequested', () {
    blocTest<StationBloc, StationState>(
      'emits [StationLoading, StationListLoaded] on success from initial',
      build: () {
        when(() => mockStationRepository.getList(
              page: any(named: 'page'),
              pageSize: any(named: 'pageSize'),
            ),).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>(
            createTestStationListResponse(),
          ),
        );
        return stationBloc;
      },
      act: (bloc) => bloc.add(const StationListRequested()),
      expect: () => [
        isA<StationLoading>(),
        isA<StationListLoaded>(),
      ],
    );

    blocTest<StationBloc, StationState>(
      'emits [StationError] on failure',
      build: () {
        when(() => mockStationRepository.getList(
              page: any(named: 'page'),
              pageSize: any(named: 'pageSize'),
            ),).thenAnswer(
          (_) async => left<Failure, Map<String, dynamic>>(
            createTestServerFailure(),
          ),
        );
        return stationBloc;
      },
      act: (bloc) => bloc.add(const StationListRequested()),
      expect: () => [
        isA<StationLoading>(),
        isA<StationError>(),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // StationDetailRequested
  // ---------------------------------------------------------------------------
  group('StationDetailRequested', () {
    blocTest<StationBloc, StationState>(
      'emits [StationLoading, StationDetailLoaded] on success',
      build: () {
        when(() => mockStationRepository.getDetail(any())).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'station': createTestStationMap(),
            'devices': [createTestDeviceMap()],
          }),
        );
        when(() => mockDataCacheService.save(any(), any()))
            .thenAnswer((_) async {});
        return stationBloc;
      },
      act: (bloc) => bloc.add(const StationDetailRequested(stationId: 1)),
      expect: () => [
        isA<StationLoading>(),
        isA<StationDetailLoaded>(),
      ],
    );

    blocTest<StationBloc, StationState>(
      'emits [StationLoading, StationError] on failure without cache',
      build: () {
        when(() => mockStationRepository.getDetail(any())).thenAnswer(
          (_) async => left<Failure, Map<String, dynamic>>(
            createTestServerFailure(),
          ),
        );
        when(() => mockDataCacheService.load(any())).thenReturn(null);
        return stationBloc;
      },
      act: (bloc) => bloc.add(const StationDetailRequested(stationId: 1)),
      expect: () => [
        isA<StationLoading>(),
        isA<StationError>(),
      ],
    );

    blocTest<StationBloc, StationState>(
      'emits [StationLoading, StationDetailLoaded] from cache on failure',
      build: () {
        when(() => mockStationRepository.getDetail(any())).thenAnswer(
          (_) async => left<Failure, Map<String, dynamic>>(
              createTestNetworkFailure(),),
        );
        when(() => mockDataCacheService.load(any())).thenReturn({
          'station': createTestStationMap(),
          'devices': [createTestDeviceMap()],
        });
        return stationBloc;
      },
      act: (bloc) => bloc.add(const StationDetailRequested(stationId: 1)),
      expect: () => [
        isA<StationLoading>(),
        isA<StationDetailLoaded>().having(
          (s) => s.isFromCache,
          'isFromCache',
          true,
        ),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // StationCreateRequested
  // ---------------------------------------------------------------------------
  group('StationCreateRequested', () {
    blocTest<StationBloc, StationState>(
      'emits [StationCreateSuccess, ...] on success',
      build: () {
        when(() => mockStationRepository.create(any())).thenAnswer(
          (_) async => right<Failure, void>(null),
        );
        when(() => mockStationRepository.getSummary()).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'stations': [],
            'summary': {},
          }),
        );
        when(() => mockDataCacheService.save(any(), any()))
            .thenAnswer((_) async {});
        return stationBloc;
      },
      act: (bloc) => bloc.add(
        const StationCreateRequested(data: {'name': 'New Station'}),
      ),
      expect: () => [
        isA<StationCreateSuccess>(),
        isA<StationSummaryLoaded>(),
      ],
    );

    blocTest<StationBloc, StationState>(
      'emits [StationError] on failure',
      build: () {
        when(() => mockStationRepository.create(any())).thenAnswer(
          (_) async => left<Failure, void>(createTestServerFailure()),
        );
        return stationBloc;
      },
      act: (bloc) => bloc.add(
        const StationCreateRequested(data: {'name': 'New Station'}),
      ),
      expect: () => [
        isA<StationError>(),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // StationUpdateRequested
  // ---------------------------------------------------------------------------
  group('StationUpdateRequested', () {
    blocTest<StationBloc, StationState>(
      'emits [StationUpdateSuccess, ...] on success',
      build: () {
        when(() => mockStationRepository.update(any(), any())).thenAnswer(
          (_) async => right<Failure, void>(null),
        );
        when(() => mockStationRepository.getSummary()).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'stations': [],
            'summary': {},
          }),
        );
        when(() => mockDataCacheService.save(any(), any()))
            .thenAnswer((_) async {});
        return stationBloc;
      },
      act: (bloc) => bloc.add(
        const StationUpdateRequested(stationId: 1, data: {'name': 'Updated'}),
      ),
      expect: () => [
        isA<StationUpdateSuccess>(),
        isA<StationSummaryLoaded>(),
      ],
    );

    blocTest<StationBloc, StationState>(
      'emits [StationError] on failure',
      build: () {
        when(() => mockStationRepository.update(any(), any())).thenAnswer(
          (_) async => left<Failure, void>(createTestServerFailure()),
        );
        return stationBloc;
      },
      act: (bloc) => bloc.add(
        const StationUpdateRequested(stationId: 1, data: {'name': 'Updated'}),
      ),
      expect: () => [
        isA<StationError>(),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // StationDeleteRequested
  // ---------------------------------------------------------------------------
  group('StationDeleteRequested', () {
    blocTest<StationBloc, StationState>(
      'emits [StationDeleteSuccess, ...] on success',
      build: () {
        when(() => mockStationRepository.delete(any())).thenAnswer(
          (_) async => right<Failure, void>(null),
        );
        when(() => mockStationRepository.getSummary()).thenAnswer(
          (_) async => right<Failure, Map<String, dynamic>>({
            'stations': [],
            'summary': {},
          }),
        );
        when(() => mockDataCacheService.save(any(), any()))
            .thenAnswer((_) async {});
        return stationBloc;
      },
      act: (bloc) => bloc.add(const StationDeleteRequested(stationId: 1)),
      expect: () => [
        isA<StationDeleteSuccess>(),
        isA<StationSummaryLoaded>(),
      ],
    );

    blocTest<StationBloc, StationState>(
      'emits [StationError] on failure',
      build: () {
        when(() => mockStationRepository.delete(any())).thenAnswer(
          (_) async => left<Failure, void>(createTestServerFailure()),
        );
        return stationBloc;
      },
      act: (bloc) => bloc.add(const StationDeleteRequested(stationId: 1)),
      expect: () => [
        isA<StationError>(),
      ],
    );
  });
}
