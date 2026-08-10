import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/ble/ble_binding_service.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/offline/offline_op_log_store.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockBleDeviceManager extends Mock implements BleDeviceManager {}

class MockBleDeviceKeyStore extends Mock implements BleDeviceKeyStore {}

class MockDio extends Mock implements Dio {}

class MockBleDeviceSession extends Mock implements BleDeviceSession {}

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
