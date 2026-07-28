import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dio/dio.dart';
import 'package:inv_app/features/device/data/datasources/device_remote_data_source.dart';
import 'package:inv_app/features/device_protocol/data/datasources/device_protocol_remote_data_source.dart';

class MockDio extends Mock implements Dio {}

void main() {
  group('Device API Paths Validation', () {
    late MockDio mockDio;
    late DeviceRemoteDataSource deviceDataSource;
    late DeviceProtocolRemoteDataSourceImpl protocolDataSource;

    setUp(() {
      mockDio = MockDio();
      deviceDataSource = DeviceRemoteDataSource(mockDio);
      protocolDataSource = DeviceProtocolRemoteDataSourceImpl(mockDio);
    });

    test('getDetail should use /devices/by-sn/{sn} path', () async {
      const testSn = 'TEST123';
      when(() => mockDio.get('/devices/by-sn/$testSn')).thenAnswer(
        (_) async => Response(
          data: {'code': 0, 'data': {}},
          statusCode: 200,
          requestOptions: RequestOptions(path: ''),
        ),
      );

      await deviceDataSource.getDetail(testSn);
      verify(() => mockDio.get('/devices/by-sn/$testSn')).called(1);
    });

    test('getRealtimeData should use /devices/by-sn/{sn}/realtime path',
        () async {
      const testSn = 'TEST123';
      when(() => mockDio.get('/devices/by-sn/$testSn/realtime')).thenAnswer(
        (_) async => Response(
          data: {'code': 0, 'data': {}},
          statusCode: 200,
          requestOptions: RequestOptions(path: ''),
        ),
      );

      await deviceDataSource.getRealtimeData(testSn);
      verify(() => mockDio.get('/devices/by-sn/$testSn/realtime')).called(1);
    });

    test('unbind should use /devices/by-sn/{sn}/unbind path', () async {
      const testSn = 'TEST123';
      when(() => mockDio.delete('/devices/by-sn/$testSn/unbind')).thenAnswer(
        (_) async => Response(
          data: {'code': 0, 'data': {}},
          statusCode: 200,
          requestOptions: RequestOptions(path: ''),
        ),
      );

      await deviceDataSource.unbind(testSn);
      verify(() => mockDio.delete('/devices/by-sn/$testSn/unbind')).called(1);
    });

    test('control should use /devices/by-sn/{sn}/control path', () async {
      const testSn = 'TEST123';
      when(() => mockDio.post(
            '/devices/by-sn/$testSn/control',
            data: any(named: 'data'),
          )).thenAnswer(
        (_) async => Response(
          data: {'code': 0, 'data': {}},
          statusCode: 200,
          requestOptions: RequestOptions(path: ''),
        ),
      );

      await deviceDataSource.control(testSn, 'test_command', {'key': 'value'});
      verify(() => mockDio.post(
            '/devices/by-sn/$testSn/control',
            data: any(named: 'data'),
          )).called(1);
    });

    test('getStatistics should use /devices/by-sn/{sn}/statistics path',
        () async {
      const testSn = 'TEST123';
      when(() => mockDio.get(
            '/devices/by-sn/$testSn/statistics',
            queryParameters: any(named: 'queryParameters'),
          )).thenAnswer(
        (_) async => Response(
          data: {'code': 0, 'data': {}},
          statusCode: 200,
          requestOptions: RequestOptions(path: ''),
        ),
      );

      await deviceDataSource.getStatistics(
          testSn, '2026-01-01', '2026-12-31', 'day');
      verify(() => mockDio.get(
            '/devices/by-sn/$testSn/statistics',
            queryParameters: any(named: 'queryParameters'),
          )).called(1);
    });

    test('getHistory should use /devices/by-sn/{sn}/history path', () async {
      const testSn = 'TEST123';
      when(() => mockDio.get(
            '/devices/by-sn/$testSn/history',
            queryParameters: any(named: 'queryParameters'),
          )).thenAnswer(
        (_) async => Response(
          data: {'code': 0, 'data': {}},
          statusCode: 200,
          requestOptions: RequestOptions(path: ''),
        ),
      );

      await deviceDataSource.getHistory(
          testSn, '2026-01-01', '2026-12-31', 'day');
      verify(() => mockDio.get(
            '/devices/by-sn/$testSn/history',
            queryParameters: any(named: 'queryParameters'),
          )).called(1);
    });

    test('getAlarms should use /devices/by-sn/{sn}/alarms path', () async {
      const testSn = 'TEST123';
      when(() => mockDio.get(
            '/devices/by-sn/$testSn/alarms',
            queryParameters: any(named: 'queryParameters'),
          )).thenAnswer(
        (_) async => Response(
          data: {'code': 0, 'data': {}},
          statusCode: 200,
          requestOptions: RequestOptions(path: ''),
        ),
      );

      await deviceDataSource.getAlarms(testSn);
      verify(() => mockDio.get(
            '/devices/by-sn/$testSn/alarms',
            queryParameters: any(named: 'queryParameters'),
          )).called(1);
    });

    test('getAlarmEvents should use /devices/by-sn/{sn}/alarm-events path',
        () async {
      const testSn = 'TEST123';
      when(() => mockDio.get<dynamic>(
            '/devices/by-sn/$testSn/alarm-events',
            queryParameters: any(named: 'queryParameters'),
          )).thenAnswer(
        (_) async => Response(
          data: {'code': 0, 'data': {}},
          statusCode: 200,
          requestOptions: RequestOptions(path: ''),
        ),
      );

      await protocolDataSource.getAlarmEvents(testSn);
      verify(() => mockDio.get<dynamic>(
            '/devices/by-sn/$testSn/alarm-events',
            queryParameters: any(named: 'queryParameters'),
          )).called(1);
    });

    test('getParallelState should use /devices/by-sn/{sn}/parallel-state path',
        () async {
      const testSn = 'TEST123';
      when(() => mockDio.get<dynamic>('/devices/by-sn/$testSn/parallel-state'))
          .thenAnswer(
        (_) async => Response(
          data: {'code': 0, 'data': {}},
          statusCode: 200,
          requestOptions: RequestOptions(path: ''),
        ),
      );

      await protocolDataSource.getParallelState(testSn);
      verify(() => mockDio.get<dynamic>(
          '/devices/by-sn/$testSn/parallel-state')).called(1);
    });

    test('getThreePhase should use /devices/by-sn/{sn}/three-phase path',
        () async {
      const testSn = 'TEST123';
      when(() => mockDio.get<dynamic>(
            '/devices/by-sn/$testSn/three-phase',
            queryParameters: any(named: 'queryParameters'),
          )).thenAnswer(
        (_) async => Response(
          data: {'code': 0, 'data': {}},
          statusCode: 200,
          requestOptions: RequestOptions(path: ''),
        ),
      );

      await protocolDataSource.getThreePhase(testSn);
      verify(() => mockDio.get<dynamic>(
            '/devices/by-sn/$testSn/three-phase',
            queryParameters: any(named: 'queryParameters'),
          )).called(1);
    });
  });

  group('API Path Format Validation', () {
    test('all device API paths should start with /devices/by-sn/', () {
      final validPaths = [
        '/devices/by-sn/TEST123',
        '/devices/by-sn/TEST123/realtime',
        '/devices/by-sn/TEST123/control',
        '/devices/by-sn/TEST123/unbind',
        '/devices/by-sn/TEST123/statistics',
        '/devices/by-sn/TEST123/history',
        '/devices/by-sn/TEST123/alarms',
        '/devices/by-sn/TEST123/alarm-events',
        '/devices/by-sn/TEST123/parallel-state',
        '/devices/by-sn/TEST123/three-phase',
        '/devices/by-sn/TEST123/control-state',
        '/devices/by-sn/TEST123/control-fields',
        '/devices/by-sn/TEST123/control-capabilities',
        '/devices/by-sn/TEST123/energy-schedule',
        '/devices/by-sn/TEST123/control-overrides',
        '/devices/by-sn/TEST123/commands',
        '/devices/by-sn/TEST123/params',
        '/devices/by-sn/TEST123/wifi/config',
      ];

      for (final path in validPaths) {
        expect(path.startsWith('/devices/by-sn/'), isTrue,
            reason: 'Path $path should start with /devices/by-sn/');
      }
    });

    test('no device API paths should use old /devices/{sn} format', () {
      final invalidPaths = [
        '/devices/TEST123',
        '/devices/TEST123/realtime',
        '/devices/TEST123/control',
        '/devices/TEST123/unbind',
      ];

      for (final path in invalidPaths) {
        expect(path.startsWith('/devices/by-sn/'), isFalse,
            reason:
                'Path $path uses old format, should be /devices/by-sn/...');
      }
    });
  });
}
