import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:mocktail/mocktail.dart';

class MockBleAdapter extends Mock implements BleAdapter {}

class MockBleGattConnection extends Mock implements BleGattConnection {}

class MockBleDeviceKeyStore extends Mock implements BleDeviceKeyStore {}

void main() {
  late MockBleAdapter adapter;
  late MockBleGattConnection connection;
  late MockBleDeviceKeyStore keyStore;
  late StreamController<List<int>> authNotify;

  const mac = 'AA:BB:CC:DD:EE:FF';

  setUp(() {
    adapter = MockBleAdapter();
    connection = MockBleGattConnection();
    keyStore = MockBleDeviceKeyStore();
    authNotify = StreamController<List<int>>.broadcast();

    when(() => adapter.connect(any(), autoConnect: any(named: 'autoConnect')))
        .thenAnswer((_) async => connection);
    when(() => connection.linkState)
        .thenAnswer((_) => const Stream.empty());
    when(() => connection.read(
          BleCtProtocol.provisioningServiceUuid,
          BleCtProtocol.provisioningSnCharUuid,
        ))
        .thenAnswer((_) async => utf8.encode('H1CNA6K20001'));
    when(() => connection.subscribe(any(), any())).thenAnswer((_) => authNotify.stream);
    when(() => keyStore.read(any())).thenAnswer((_) async => null);
  });

  tearDown(() => authNotify.close());

  Future<BleDeviceSession> connectSession() async {
    final session = BleDeviceSession(
      adapter: adapter,
      macAddress: mac,
      keyStore: keyStore,
    );
    await session.connect();
    return session;
  }

  test('readInfo returns INFO json', () async {
    when(() => connection.read(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.infoCharUuid,
        ))
        .thenAnswer((_) async => utf8.encode(
              '{"sn":"H1CNA6K20001","bound":false,"proto_ver":"1.0"}',
            ));

    final session = await connectSession();
    final info = await session.readInfo();

    expect(info['sn'], 'H1CNA6K20001');
    expect(info['bound'], false);
  });

  test('readTelemetrySnapshot returns telemetry json', () async {
    when(() => connection.read(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.telemetryCharUuid,
        ))
        .thenAnswer((_) async => utf8.encode('{"power_w":3000,"status":1}'));

    final session = await connectSession();
    final data = await session.readTelemetrySnapshot();

    expect(data['power_w'], 3000);
  });

  test('bind writes bind message and completes on ok notify', () async {
    when(() => connection.write(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.authCharUuid,
          any(),
        ))
        .thenAnswer((_) async {});

    final session = await connectSession();
    // 未绑定设备：连接后停留在 authenticating
    expect(session.state, BleDeviceState.authenticating);

    final bindFuture = session.bind('a2V5LWJhc2U2NA==');
    // 设备 notify 返回 bind 结果
    authNotify.add(utf8.encode(jsonEncode({'mode': 'bind', 'result': 'ok'})));
    await bindFuture; // 不抛异常即通过
  });

  test('bind throws BleCommandException when rejected', () async {
    when(() => connection.write(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.authCharUuid,
          any(),
        ))
        .thenAnswer((_) async {});

    final session = await connectSession();
    final bindFuture = session.bind('a2V5LWJhc2U2NA==');
    authNotify.add(utf8.encode(jsonEncode({
      'mode': 'bind',
      'result': 'error',
      'error': 'already_bound',
    })));
    await expectLater(
      bindFuture,
      throwsA(isA<BleCommandException>()
          .having((e) => e.code, 'code', 'BIND_REJECTED')),
    );
  });

  test('readTelemetrySnapshot throws when not connected', () async {
    final session = BleDeviceSession(
      adapter: adapter,
      macAddress: mac,
      keyStore: keyStore,
    );
    await expectLater(
      session.readTelemetrySnapshot(),
      throwsA(isA<BleCommandException>()),
    );
  });

  test('checkPin succeeds on ok notify', () async {
    when(() => connection.write(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.authCharUuid,
          any(),
        ))
        .thenAnswer((_) async {});

    final session = await connectSession();
    final pinFuture = session.checkPin('123456');
    authNotify.add(utf8.encode(jsonEncode({'mode': 'pin_check', 'result': 'ok'})));
    await pinFuture; // 不抛异常即通过
  });

  test('checkPin throws PIN_REJECTED on rejected notify', () async {
    when(() => connection.write(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.authCharUuid,
          any(),
        ))
        .thenAnswer((_) async {});

    final session = await connectSession();
    final pinFuture = session.checkPin('000000');
    authNotify.add(utf8.encode(jsonEncode({'mode': 'pin_check', 'result': 'rejected', 'error': 'invalid_pin'})));
    await expectLater(
      pinFuture,
      throwsA(isA<BleCommandException>()
          .having((e) => e.code, 'code', 'PIN_REJECTED')),
    );
  });

  test('checkPin throws PIN_LOCKED on locked notify', () async {
    when(() => connection.write(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.authCharUuid,
          any(),
        ))
        .thenAnswer((_) async {});

    final session = await connectSession();
    final pinFuture = session.checkPin('000000');
    authNotify.add(utf8.encode(jsonEncode({'mode': 'pin_check', 'result': 'rejected', 'error': 'locked'})));
    await expectLater(
      pinFuture,
      throwsA(isA<BleCommandException>()
          .having((e) => e.code, 'code', 'PIN_LOCKED')),
    );
  });
}
