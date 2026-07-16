import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/features/alarm/presentation/bloc/alarm_bloc.dart';

import '../../../../helpers/mock_providers.dart';

void main() {
  late MockAlarmRepository repository;
  late MockDataCacheService cache;

  setUp(() {
    repository = MockAlarmRepository();
    cache = MockDataCacheService();
  });

  AlarmBloc buildBloc() => AlarmBloc(
        repository: repository,
        dataCacheService: cache,
      );

  group('AlarmListRequested failure visibility', () {
    blocTest<AlarmBloc, AlarmState>(
      'does not hide a server failure with cached alarms',
      build: () {
        when(() => repository.getList(
              stationId: any(named: 'stationId'),
              status: any(named: 'status'),
              page: any(named: 'page'),
              pageSize: any(named: 'pageSize'),
            )).thenAnswer(
          (_) async => const Left<Failure, Map<String, dynamic>>(
            ServerFailure('Server error: 500'),
          ),
        );
        when(() => cache.load(any())).thenReturn({
          'items': [
            {'id': 1, 'message': 'cached alarm'},
          ],
          'total': 1,
        });
        return buildBloc();
      },
      act: (bloc) => bloc.add(const AlarmListRequested()),
      expect: () => [isA<AlarmError>()],
    );

    blocTest<AlarmBloc, AlarmState>(
      'uses explicitly marked cache on network failure',
      build: () {
        when(() => repository.getList(
              stationId: any(named: 'stationId'),
              status: any(named: 'status'),
              page: any(named: 'page'),
              pageSize: any(named: 'pageSize'),
            )).thenAnswer(
          (_) async => const Left<Failure, Map<String, dynamic>>(
            NetworkFailure('Network error'),
          ),
        );
        when(() => cache.load(any())).thenReturn({
          'items': [
            {'id': 1, 'message': 'cached alarm'},
          ],
          'total': 1,
        });
        return buildBloc();
      },
      act: (bloc) => bloc.add(const AlarmListRequested()),
      expect: () => [
        isA<AlarmListLoaded>().having(
          (state) => state.isFromCache,
          'isFromCache',
          true,
        ),
      ],
    );
  });
}
