import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:inv_app/core/services/ble/ble_binding_service.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/offline/offline_op_log_store.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockBleDeviceManager extends Mock implements BleDeviceManager {}

class MockBleDeviceKeyStore extends Mock implements BleDeviceKeyStore {}

class MockDio extends Mock implements Dio {}

class MockBleDeviceSession extends Mock implements BleDeviceSession {}

class MockBleAdapter extends Mock implements BleAdapter {}

class MockBleGattConnection extends Mock implements BleGattConnection {}

void main() {
  late MockBleDeviceManager manager;
  late MockBleDeviceKeyStore keyStore;
  late MockDio dio;
  late OfflineOpLogStore logStore;
  late BleBindingService service;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    manager = MockBleDeviceManager();
    keyStore = MockBleDeviceKeyStore();
    dio = MockDio();
    logStore = OfflineOpLogStore(
      openDb: () async => databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: OfflineOpLogStore.onCreate,
        ),
      ),
    );
    service = BleBindingService(
      manager: manager,
      keyStore: keyStore,
      dio: dio,
      logStore: logStore,
    );
  });

  // 通用 stub：连接成功、INFO 未绑定、本地无 key、补登记成功
  MockBleDeviceSession stubSession() {
    final session = MockBleDeviceSession();
    when(() => manager.connectDevice('AA:BB:CC:DD:EE:FF', autoConnect: any(named: 'autoConnect'), autoReconnect: any(named: 'autoReconnect')))
        .thenAnswer((_) async => session);
    when(() => session.sn).thenReturn('H1CNA6K20001');
    when(() => session.readInfo()).thenAnswer((_) async => {'sn': 'H1CNA6K20001', 'bound': false});
    when(() => keyStore.read('H1CNA6K20001')).thenAnswer((_) async => null);
    when(() => keyStore.write(any(), any())).thenAnswer((_) async {});
    return session;
  }

  MockBleDeviceSession stubCurrentSession() {
    final session = stubSession();
    when(() => session.sn).thenReturn('H1CNA00135000014');
    when(() => keyStore.read('H1CNA00135000014')).thenAnswer((_) async => null);
    when(() => session.readInfo()).thenAnswer(
      (_) async => {
        'v': 2,
        'type': 'info',
        'session_id': 'current-session',
        'body': {
          'device_sn': 'H1CNA00135000014',
          'proto_version': 2,
          'capabilities': [
            'info',
            'telemetry',
            'control',
            'ota',
            'ota_binary_v1',
          ],
          'bound': true,
        },
      },
    );
    when(
      () => session.bind(
        any(),
        pin: any(named: 'pin'),
        issuedAt: any(named: 'issuedAt'),
      ),
    ).thenThrow(StateError('AUTH characteristic not found'));
    return session;
  }

  group('current firmware without AUTH', () {
    test(
        'binds through server PIN validation without writing AUTH or a local key',
        () async {
      final info = await stubCurrentSession().readInfo();
      final adapter = MockBleAdapter();
      final connection = MockBleGattConnection();
      when(() => adapter.connect(any(), autoConnect: any(named: 'autoConnect')))
          .thenAnswer((_) async => connection);
      when(() => connection.linkState).thenAnswer((_) => const Stream.empty());
      when(
        () => connection.read(
          BleCtProtocol.provisioningServiceUuid,
          BleCtProtocol.provisioningSnCharUuid,
        ),
      ).thenAnswer((_) async => utf8.encode('H1CNA00135000014'));
      when(
        () => connection.read(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.infoCharUuid,
        ),
      ).thenAnswer((_) async => utf8.encode(jsonEncode(info)));
      when(() => connection.subscribe(any(), any()))
          .thenAnswer((_) => const Stream.empty());
      when(
        () => connection.subscribe(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.authCharUuid,
        ),
      ).thenThrow(StateError('AUTH characteristic not found'));
      when(
        () => connection.write(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.authCharUuid,
          any(),
        ),
      ).thenThrow(StateError('AUTH characteristic not found'));
      when(() => connection.disconnect()).thenAnswer((_) async {});
      final session = BleDeviceSession(
        adapter: adapter,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        keyStore: keyStore,
      );
      addTearDown(session.dispose);
      await session.connect(autoReconnect: false);
      when(
        () => manager.connectDevice(
          'AA:BB:CC:DD:EE:FF',
          autoConnect: any(named: 'autoConnect'),
          autoReconnect: any(named: 'autoReconnect'),
        ),
      ).thenAnswer((_) async => session);
      when(() => dio.post('/devices/bind', data: any(named: 'data')))
          .thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/devices/bind'),
          data: {'code': 0, 'data': null},
        ),
      );

      final outcome = await service.bindAfterProvision(
        macAddress: 'AA:BB:CC:DD:EE:FF',
        pin: '123456',
      );

      expect(outcome, BindOutcome.bound);
      final data = verify(
        () => dio.post('/devices/bind', data: captureAny(named: 'data')),
      ).captured.single;
      expect(data, {'sn': 'H1CNA00135000014', 'pin': '123456'});
      expect(session.state, BleDeviceState.ready);
      verifyNever(
        () => connection.write(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.authCharUuid,
          any(),
        ),
      );
      verifyNever(() => keyStore.write(any(), any()));
      expect(await logStore.pendingCount(), 0);
    });

    test('a stale local key cannot skip server ownership validation', () async {
      stubCurrentSession();
      when(() => keyStore.read('H1CNA00135000014'))
          .thenAnswer((_) async => 'stale-local-key');
      when(() => dio.post('/devices/bind', data: any(named: 'data')))
          .thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/devices/bind'),
          data: {'code': 5002, 'message': 'device already bound'},
        ),
      );

      expect(
        await service.bindAfterProvision(
          macAddress: 'AA:BB:CC:DD:EE:FF',
          pin: '123456',
        ),
        BindOutcome.failed,
      );
      verify(() => dio.post('/devices/bind', data: any(named: 'data')))
          .called(1);
    });

    for (final body in <dynamic>[
      {'code': 5010, 'message': 'invalid pin'},
      {'code': 5002, 'message': 'device already bound'},
      {'code': 403, 'message': 'permission denied'},
      {'code': 500, 'message': 'system error'},
      {'message': 'missing code'},
      {'code': '0'},
      null,
    ]) {
      test('rejects unsuccessful or malformed cloud response $body', () async {
        final session = stubCurrentSession();
        when(() => dio.post('/devices/bind', data: any(named: 'data')))
            .thenAnswer(
          (_) async => Response(
            requestOptions: RequestOptions(path: '/devices/bind'),
            data: body,
          ),
        );

        final outcome = await service.bindAfterProvision(
          macAddress: 'AA:BB:CC:DD:EE:FF',
          pin: '123456',
        );

        expect(
          outcome,
          body is Map && body['code'] == 5010
              ? BindOutcome.invalidPin
              : BindOutcome.failed,
        );
        verify(() => dio.post('/devices/bind', data: any(named: 'data')))
            .called(1);
        verifyNever(
          () => session.bind(
            any(),
            pin: any(named: 'pin'),
            issuedAt: any(named: 'issuedAt'),
          ),
        );
        verifyNever(() => keyStore.write(any(), any()));
        expect(await logStore.pendingCount(), 0);
      });
    }

    for (final status in [null, 400, 401, 403, 409, 500]) {
      test('does not defer cloud rejection or network failure (HTTP $status)',
          () async {
        stubCurrentSession();
        final options = RequestOptions(path: '/devices/bind');
        when(() => dio.post('/devices/bind', data: any(named: 'data')))
            .thenThrow(
          DioException(
            requestOptions: options,
            type: status == null
                ? DioExceptionType.connectionError
                : DioExceptionType.badResponse,
            response: status == null
                ? null
                : Response(
                    requestOptions: options,
                    statusCode: status,
                    data: {'code': status == 400 ? 5010 : status},
                  ),
          ),
        );

        expect(
          await service.bindAfterProvision(
            macAddress: 'AA:BB:CC:DD:EE:FF',
            pin: '123456',
          ),
          status == 400
              ? BindOutcome.invalidPin
              : status == 401
                  ? BindOutcome.needLoginForSync
                  : BindOutcome.failed,
        );
        verify(() => dio.post('/devices/bind', data: any(named: 'data')))
            .called(1);
        verifyNever(() => keyStore.write(any(), any()));
        expect(await logStore.pendingCount(), 0);
      });
    }

    for (final pin in [null, '', '12345', '1234567', 'abcdef']) {
      test('requires a six-digit PIN ($pin)', () async {
        stubCurrentSession();

        expect(
          await service.bindAfterProvision(
            macAddress: 'AA:BB:CC:DD:EE:FF',
            pin: pin,
          ),
          BindOutcome.invalidPin,
        );
        verifyNever(() => dio.post('/devices/bind', data: any(named: 'data')));
        verifyNever(() => keyStore.write(any(), any()));
      });
    }
  });

  test('current cloud binding forwards optional station context', () async {
    stubCurrentSession();
    when(() => dio.post('/devices/bind', data: any(named: 'data')))
        .thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: '/devices/bind'),
          data: {'code': 0},
        ));

    expect(await service.bindAfterProvision(
      macAddress: 'AA:BB:CC:DD:EE:FF',
      knownSn: 'H1CNA00135000014',
      pin: '123456',
      stationId: 42,
    ), BindOutcome.bound);
    expect(verify(() => dio.post('/devices/bind', data: captureAny(named: 'data')))
        .captured.single, {'sn': 'H1CNA00135000014', 'pin': '123456', 'station_id': 42});
    verifyNever(() => keyStore.write(any(), any()));
    expect(await logStore.pendingCount(), 0);
  });

  test('full flow: local key gen, device bind, store, offline-capable', () async {
    final session = stubSession();
    // 设备端 bind 成功
    when(() => session.bind(any(), pin: any(named: 'pin'), issuedAt: any(named: 'issuedAt'))).thenAnswer((_) async {});
    // 补登记成功
    when(() => dio.post('/devices/bind', data: any(named: 'data'))).thenAnswer((_) async {
      return Response(
        requestOptions: RequestOptions(path: '/devices/bind'),
        data: {'code': 0, 'data': {'message': 'bound'}},
      );
    });

    final outcome = await service.bindAfterProvision(
      macAddress: 'AA:BB:CC:DD:EE:FF',
      knownSn: 'H1CNA6K20001',
    );

    expect(outcome, BindOutcome.bound);
    // 本地生成 key 写入设备（32B Base64）
    final captured = verify(() => session.bind(captureAny(), pin: any(named: 'pin'), issuedAt: any(named: 'issuedAt'))).captured;
    expect(captured.single, isA<String>());
    verify(() => keyStore.write('H1CNA6K20001', captured.single as String)).called(1);
    // 绑定日志已记录
    expect(await logStore.pendingCount(), 1);
  });

  test('skips when already bound locally', () async {
    final session = stubSession();
    when(() => keyStore.read('H1CNA6K20001')).thenAnswer((_) async => 'existing-key');

    final outcome = await service.bindAfterProvision(
      macAddress: 'AA:BB:CC:DD:EE:FF',
      knownSn: 'H1CNA6K20001',
    );

    expect(outcome, BindOutcome.alreadyBound);
    verifyNever(() => session.bind(any(), pin: any(named: 'pin'), issuedAt: any(named: 'issuedAt')));
    verifyNever(() => dio.post('/devices/bind', data: any(named: 'data')));
    expect(await logStore.pendingCount(), 0);
  });

  test('invalid PIN returns invalidPin', () async {
    final session = stubSession();
    when(() => session.bind(any(), pin: any(named: 'pin'), issuedAt: any(named: 'issuedAt')))
        .thenThrow(const BleCommandException('BIND_REJECTED', 'invalid_pin'));

    final outcome = await service.bindAfterProvision(
      macAddress: 'AA:BB:CC:DD:EE:FF',
      knownSn: 'H1CNA6K20001',
      pin: '000000',
    );

    expect(outcome, BindOutcome.invalidPin);
    verifyNever(() => keyStore.write(any(), any()));
  });

  test('locked PIN returns locked', () async {
    final session = stubSession();
    when(() => session.bind(any(), pin: any(named: 'pin'), issuedAt: any(named: 'issuedAt')))
        .thenThrow(const BleCommandException('BIND_REJECTED', 'locked'));

    final outcome = await service.bindAfterProvision(
      macAddress: 'AA:BB:CC:DD:EE:FF',
      knownSn: 'H1CNA6K20001',
      pin: '000000',
    );

    expect(outcome, BindOutcome.locked);
  });

  test('offline bind still succeeds (registration 401 -> needLoginForSync only when logged-in requirement)', () async {
    final session = stubSession();
    when(() => session.bind(any(), pin: any(named: 'pin'), issuedAt: any(named: 'issuedAt'))).thenAnswer((_) async {});
    // 补登记：网络不通（DioException 非 401）
    when(() => dio.post('/devices/bind', data: any(named: 'data'))).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/devices/bind'),
        type: DioExceptionType.connectionError,
      ),
    );

    final outcome = await service.bindAfterProvision(
      macAddress: 'AA:BB:CC:DD:EE:FF',
      knownSn: 'H1CNA6K20001',
    );

    // 离网绑定成功：本地 key 已存、日志已记，补登记失败不影响结果
    expect(outcome, BindOutcome.bound);
    expect(await logStore.pendingCount(), 1);
  });

  test('registration 401 returns needLoginForSync', () async {
    final session = stubSession();
    when(() => session.bind(any(), pin: any(named: 'pin'), issuedAt: any(named: 'issuedAt'))).thenAnswer((_) async {});
    when(() => dio.post('/devices/bind', data: any(named: 'data'))).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/devices/bind'),
        response: Response(
          requestOptions: RequestOptions(path: '/devices/bind'),
          statusCode: 401,
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    final outcome = await service.bindAfterProvision(
      macAddress: 'AA:BB:CC:DD:EE:FF',
      knownSn: 'H1CNA6K20001',
    );

    expect(outcome, BindOutcome.needLoginForSync);
    expect(await logStore.pendingCount(), 1);
  });
}
