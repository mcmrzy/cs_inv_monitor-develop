import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/core/services/mqtt_service.dart';
import 'package:inv_app/features/alarm/data/datasources/alarm_remote_data_source.dart';
import 'package:inv_app/features/alarm/data/repositories/alarm_repository_impl.dart';
import 'package:inv_app/features/dashboard/data/datasources/dashboard_remote_data_source.dart';
import 'package:inv_app/features/dashboard/data/repositories/dashboard_repository_impl.dart';
import 'package:inv_app/features/device/data/datasources/device_remote_data_source.dart';
import 'package:inv_app/features/device/data/repositories/device_repository_impl.dart';
import 'package:inv_app/features/ota/data/datasources/ota_remote_data_source.dart';
import 'package:inv_app/features/ota/data/repositories/ota_repository_impl.dart';
import 'package:inv_app/features/station/data/datasources/station_remote_data_source.dart';
import 'package:inv_app/features/station/data/repositories/station_repository_impl.dart';

class _DeviceRemote extends Mock implements DeviceRemoteDataSource {}

class _StationRemote extends Mock implements StationRemoteDataSource {}

class _AlarmRemote extends Mock implements AlarmRemoteDataSource {}

class _DashboardRemote extends Mock implements DashboardRemoteDataSource {}

class _OtaRemote extends Mock implements OtaRemoteDataSource {}

class _Mqtt extends Mock implements MQTTService {}

Response<dynamic> responseWith(dynamic data) => Response<dynamic>(
      data: data,
      statusCode: 200,
      requestOptions: RequestOptions(path: '/test'),
    );

void expectFormatFailure(dynamic result) {
  expect(result.isLeft(), isTrue);
  result.fold(
    (failure) {
      expect(failure, isA<ServerFailure>());
      expect(failure.message, contains('Response format error'));
    },
    (_) => fail('Malformed success payload must not be accepted'),
  );
}

void main() {
  group('read response contracts', () {
    test('device list rejects a successful envelope with list data', () async {
      final remote = _DeviceRemote();
      when(
        () => remote.getList(
          stationId: any(named: 'stationId'),
          status: any(named: 'status'),
          page: any(named: 'page'),
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer((_) async => responseWith({'code': 0, 'data': []}));

      final result = await DeviceRepositoryImpl(remote, _Mqtt()).getList();
      expectFormatFailure(result);
    });

    test('station list rejects null data instead of returning an empty page',
        () async {
      final remote = _StationRemote();
      when(
        () => remote.getList(
          page: any(named: 'page'),
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer((_) async => responseWith({'code': 0, 'data': null}));

      final result = await StationRepositoryImpl(remote).getList();
      expectFormatFailure(result);
    });

    test('alarm list rejects list data when a page object is required',
        () async {
      final remote = _AlarmRemote();
      when(
        () => remote.getList(
          stationId: any(named: 'stationId'),
          status: any(named: 'status'),
          page: any(named: 'page'),
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer((_) async => responseWith({'code': 0, 'data': []}));

      final result = await AlarmRepositoryImpl(remote).getList();
      expectFormatFailure(result);
    });

    test('dashboard statistics rejects non-object data', () async {
      final remote = _DashboardRemote();
      when(remote.getStatistics)
          .thenAnswer((_) async => responseWith({'code': 0, 'data': []}));

      final result = await DashboardRepositoryImpl(remote).getStatistics();
      expectFormatFailure(result);
    });

    test('dashboard trend rejects non-list data', () async {
      final remote = _DashboardRemote();
      when(() => remote.getTrendData(type: any(named: 'type')))
          .thenAnswer((_) async => responseWith({'code': 0, 'data': {}}));

      final result = await DashboardRepositoryImpl(remote).getTrendData();
      expectFormatFailure(result);
    });

    test('OTA package list rejects an unexpected successful shape', () async {
      final remote = _OtaRemote();
      when(() => remote.getAvailablePackages(any()))
          .thenAnswer((_) async => responseWith({'code': 0, 'data': {}}));

      final result =
          await OtaRepositoryImpl(remote).getAvailablePackages('SN1');
      expectFormatFailure(result);
    });
  });

  test('write endpoints may still acknowledge success with null data',
      () async {
    final remote = _DeviceRemote();
    when(() => remote.unbind(any()))
        .thenAnswer((_) async => responseWith({'code': 0, 'data': null}));

    final result = await DeviceRepositoryImpl(remote, _Mqtt()).unbind('SN1');
    expect(result.isRight(), isTrue);
  });
}
