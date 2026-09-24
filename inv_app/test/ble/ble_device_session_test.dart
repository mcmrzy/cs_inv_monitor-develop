import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  late StreamController<List<int>> commandNotify;
  late StreamController<BleLinkState> linkState;
  late List<Map<String, dynamic>> authWrites;
  late List<Map<String, dynamic>> commandWrites;

  const mac = 'AA:BB:CC:DD:EE:FF';
  const sessionId = 'AAECAwQFBgcICQoLDA0ODw==';
  const deviceKeyBase64 = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=';

  Map<String, dynamic> v2Info({
    List<String> capabilities = const ['info', 'telemetry', 'control'],
  }) =>
      {
        'v': 2,
        'type': 'info',
        'message_id': 'info-001',
        'session_id': sessionId,
        'body': {
          'device_sn': 'H1CNA6K20001',
          'proto_version': 2,
          'capabilities': capabilities,
          'bound': true,
        },
      };

  setUp(() {
    adapter = MockBleAdapter();
    connection = MockBleGattConnection();
    keyStore = MockBleDeviceKeyStore();
    authNotify = StreamController<List<int>>.broadcast();
    commandNotify = StreamController<List<int>>.broadcast();
    linkState = StreamController<BleLinkState>.broadcast();
    authWrites = [];
    commandWrites = [];

    when(() => adapter.connect(any(), autoConnect: any(named: 'autoConnect')))
        .thenAnswer((_) async => connection);
    when(() => connection.linkState).thenAnswer((_) => linkState.stream);
    when(() => connection.read(
          BleCtProtocol.provisioningServiceUuid,
          BleCtProtocol.provisioningSnCharUuid,
        )).thenAnswer((_) async => utf8.encode('H1CNA6K20001'));
    when(() => connection.read(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.infoCharUuid,
        )).thenAnswer((_) async => utf8.encode(jsonEncode(v2Info())));
    when(() => connection.subscribe(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.authCharUuid,
        )).thenAnswer((_) => authNotify.stream);
    when(() => connection.subscribe(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.cmdResultCharUuid,
        )).thenAnswer((_) => commandNotify.stream);
    when(() => connection.subscribe(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.telemetryCharUuid,
        )).thenAnswer((_) => const Stream.empty());
    when(() => connection.subscribe(
          BleCtProtocol.provisioningServiceUuid,
          BleCtProtocol.otaStatusCharUuid,
        )).thenAnswer((_) => const Stream.empty());
    when(() => connection.write(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.authCharUuid,
          any(),
        )).thenAnswer((invocation) async {
      final bytes = invocation.positionalArguments[2] as List<int>;
      authWrites.add(
        (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>(),
      );
    });
    when(() => connection.write(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.commandCharUuid,
          any(),
        )).thenAnswer((invocation) async {
      final bytes = invocation.positionalArguments[2] as List<int>;
      commandWrites.add(
        (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>(),
      );
    });
    when(() => keyStore.read(any())).thenAnswer((_) async => null);
  });

  tearDown(() async {
    await authNotify.close();
    await commandNotify.close();
    await linkState.close();
  });

  Future<BleDeviceSession> connectSession({
    Duration? authTimeout,
    bool autoReconnect = true,
  }) async {
    final session = BleDeviceSession(
      adapter: adapter,
      macAddress: mac,
      keyStore: keyStore,
      authTimeout: authTimeout,
    );
    await session.connect(autoReconnect: autoReconnect);
    return session;
  }

  Future<void> waitForAuthWrites(int count) async {
    for (var i = 0; i < 20 && authWrites.length < count; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(authWrites, hasLength(greaterThanOrEqualTo(count)));
  }

  Map<String, dynamic> authResponse({
    required String type,
    required String messageId,
    required String inReplyTo,
    required Map<String, dynamic> body,
    String responseSessionId = sessionId,
  }) =>
      {
        'v': 2,
        'type': type,
        'message_id': messageId,
        'in_reply_to': inReplyTo,
        'session_id': responseSessionId,
        'body': body,
      };

  Future<void> authenticateSession(BleDeviceSession session) async {
    final future = session.authenticate(deviceKeyBase64);
    await waitForAuthWrites(1);
    final init = authWrites[0];
    authNotify.add(utf8.encode(jsonEncode(authResponse(
      type: 'auth.challenge',
      messageId: 'challenge-command-test',
      inReplyTo: init['message_id'] as String,
      body: {
        'device_nonce': 'EBESExQVFhcYGRobHB0eHw==',
        'device_ts': 1789459200,
      },
    ))));
    await waitForAuthWrites(2);
    final proof = authWrites[1];
    final phoneNonce = base64Decode(
      ((init['body'] as Map)['phone_nonce'] as String),
    );
    final expected = BleCtProtocol.computeAuthProof(
      key: base64Decode(deviceKeyBase64),
      role: BleAuthProofRole.device,
      sessionId: sessionId,
      phoneNonce: phoneNonce,
      deviceNonce: base64Decode('EBESExQVFhcYGRobHB0eHw=='),
      deviceTimestamp: 1789459200,
    );
    authNotify.add(utf8.encode(jsonEncode(authResponse(
      type: 'auth.result',
      messageId: 'result-command-test',
      inReplyTo: proof['message_id'] as String,
      body: {'result': 'ok', 'device_proof': base64Encode(expected)},
    ))));
    await future;
  }

  test('mutual proof calculation matches the frozen golden vector', () {
    final contract = jsonDecode(
      File('../contracts/ble/l10-v2-vectors.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final vectors = contract['vectors'] as List<dynamic>;
    final vector = (vectors.cast<Map<String, dynamic>>()).singleWhere(
      (item) => item['id'] == 'auth-mutual-proof',
    );
    final keyHex = vector['key_hex_test_only'] as String;
    final key = [
      for (var i = 0; i < keyHex.length; i += 2)
        int.parse(keyHex.substring(i, i + 2), radix: 16),
    ];
    final phoneNonce = base64Decode(vector['phone_nonce_b64'] as String);
    final deviceNonce = base64Decode(vector['device_nonce_b64'] as String);

    expect(
      base64Encode(
        BleCtProtocol.computeAuthProof(
          key: key,
          role: BleAuthProofRole.phone,
          sessionId: vector['session_id'] as String,
          phoneNonce: phoneNonce,
          deviceNonce: deviceNonce,
          deviceTimestamp: vector['device_ts'] as int,
        ),
      ),
      vector['phone_proof_b64'],
    );
    expect(
      base64Encode(
        BleCtProtocol.computeAuthProof(
          key: key,
          role: BleAuthProofRole.device,
          sessionId: vector['session_id'] as String,
          phoneNonce: phoneNonce,
          deviceNonce: deviceNonce,
          deviceTimestamp: vector['device_ts'] as int,
        ),
      ),
      vector['device_proof_b64'],
    );
  });

  test('connect probes INFO and exposes v2 capabilities', () async {
    final session = await connectSession();

    expect(session.sn, 'H1CNA6K20001');
    expect(session.protocolVersion, 2);
    expect(session.capabilities, containsAll(['telemetry', 'control']));
    expect(session.supportsSecureDirectControl, isTrue);
    expect(session.connectionSessionId, sessionId);
  });

  test('connect remains ready when current firmware omits AUTH characteristic',
      () async {
    when(() => connection.subscribe(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.authCharUuid,
        )).thenThrow(StateError('AUTH characteristic not found'));

    final session = await connectSession();

    expect(session.state, BleDeviceState.ready);
    expect(session.protocolVersion, 2);
    expect(session.sn, 'H1CNA6K20001');
  });

  test('asynchronous missing AUTH notification does not abort the session',
      () async {
    when(() => connection.subscribe(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.authCharUuid,
        )).thenAnswer(
      (_) => Stream<List<int>>.error(StateError('AUTH characteristic missing')),
    );

    final session = await connectSession();
    await Future<void>.delayed(Duration.zero);

    expect(session.state, BleDeviceState.ready);
  });

  test('v2 authenticate verifies both proofs before becoming ready', () async {
    final session = await connectSession();
    final authFuture = session.authenticate(deviceKeyBase64);
    await waitForAuthWrites(1);

    final init = authWrites[0];
    expect(init['v'], 2);
    expect(init['type'], 'auth.init');
    expect(init.containsKey('in_reply_to'), isFalse);
    expect(init['session_id'], sessionId);
    final phoneNonce = base64Decode(
      ((init['body'] as Map)['phone_nonce']) as String,
    );
    expect(phoneNonce, hasLength(16));

    const deviceNonceBase64 = 'EBESExQVFhcYGRobHB0eHw==';
    const deviceTimestamp = 1789459200;
    authNotify.add(
      utf8.encode(
        jsonEncode(
          authResponse(
            type: 'auth.challenge',
            messageId: 'challenge-001',
            inReplyTo: init['message_id'] as String,
            body: {
              'device_nonce': deviceNonceBase64,
              'device_ts': deviceTimestamp,
            },
          ),
        ),
      ),
    );
    await waitForAuthWrites(2);

    final proof = authWrites[1];
    expect(proof['type'], 'auth.proof');
    expect(proof.containsKey('in_reply_to'), isFalse);
    final expectedPhoneProof = BleCtProtocol.computeAuthProof(
      key: base64Decode(deviceKeyBase64),
      role: BleAuthProofRole.phone,
      sessionId: sessionId,
      phoneNonce: phoneNonce,
      deviceNonce: base64Decode(deviceNonceBase64),
      deviceTimestamp: deviceTimestamp,
    );
    expect((proof['body'] as Map)['phone_proof'],
        base64Encode(expectedPhoneProof));

    final expectedDeviceProof = BleCtProtocol.computeAuthProof(
      key: base64Decode(deviceKeyBase64),
      role: BleAuthProofRole.device,
      sessionId: sessionId,
      phoneNonce: phoneNonce,
      deviceNonce: base64Decode(deviceNonceBase64),
      deviceTimestamp: deviceTimestamp,
    );
    authNotify.add(
      utf8.encode(
        jsonEncode(
          authResponse(
            type: 'auth.result',
            messageId: 'result-001',
            inReplyTo: proof['message_id'] as String,
            body: {
              'result': 'ok',
              'device_proof': base64Encode(expectedDeviceProof),
            },
          ),
        ),
      ),
    );

    await authFuture;
    expect(session.state, BleDeviceState.ready);
  });

  test('mismatched session and in_reply_to notifications stay stale', () async {
    final session = await connectSession(
      authTimeout: const Duration(milliseconds: 30),
    );
    final authFuture = session.authenticate(deviceKeyBase64);
    await waitForAuthWrites(1);
    final initId = authWrites.single['message_id'] as String;

    authNotify.add(
      utf8.encode(
        jsonEncode(
          authResponse(
            type: 'auth.challenge',
            messageId: 'old-session',
            inReplyTo: initId,
            responseSessionId: 'EBESExQVFhcYGRobHB0eHw==',
            body: {
              'device_nonce': 'EBESExQVFhcYGRobHB0eHw==',
              'device_ts': 1789459200,
            },
          ),
        ),
      ),
    );
    authNotify.add(
      utf8.encode(
        jsonEncode(
          authResponse(
            type: 'auth.challenge',
            messageId: 'old-request',
            inReplyTo: 'previous-auth-init',
            body: {
              'device_nonce': 'EBESExQVFhcYGRobHB0eHw==',
              'device_ts': 1789459200,
            },
          ),
        ),
      ),
    );

    await expectLater(
      authFuture,
      throwsA(
        isA<BleCommandException>().having(
          (error) => error.code,
          'code',
          'AUTH_TIMEOUT',
        ),
      ),
    );
    expect(authWrites, hasLength(1));
    expect(session.state, isNot(BleDeviceState.ready));
  });

  test('wrong device proof never enters ready', () async {
    final session = await connectSession();
    final authFuture = session.authenticate(deviceKeyBase64);
    await waitForAuthWrites(1);
    final init = authWrites[0];
    authNotify.add(
      utf8.encode(
        jsonEncode(
          authResponse(
            type: 'auth.challenge',
            messageId: 'challenge-bad-proof',
            inReplyTo: init['message_id'] as String,
            body: {
              'device_nonce': 'EBESExQVFhcYGRobHB0eHw==',
              'device_ts': 1789459200,
            },
          ),
        ),
      ),
    );
    await waitForAuthWrites(2);
    final proof = authWrites[1];
    authNotify.add(
      utf8.encode(
        jsonEncode(
          authResponse(
            type: 'auth.result',
            messageId: 'result-bad-proof',
            inReplyTo: proof['message_id'] as String,
            body: {
              'result': 'ok',
              'device_proof': base64Encode(List<int>.filled(32, 0)),
            },
          ),
        ),
      ),
    );

    await expectLater(
      authFuture,
      throwsA(
        isA<BleCommandException>().having(
          (error) => error.code,
          'code',
          'UNAUTHENTICATED',
        ),
      ),
    );
    expect(session.state, isNot(BleDeviceState.ready));
  });

  test('disconnect aborts the current auth attempt and never becomes ready',
      () async {
    final session = await connectSession();
    final authFuture = session.authenticate(deviceKeyBase64);
    await waitForAuthWrites(1);

    linkState.add(BleLinkState.disconnected);

    await expectLater(
      authFuture,
      throwsA(
        isA<BleCommandException>().having(
          (error) => error.code,
          'code',
          'UNAUTHENTICATED',
        ),
      ),
    );
    expect(session.state, BleDeviceState.disconnected);
  });

  test('releasing a stale OTA lease keeps the newer lease active', () async {
    final session = await connectSession(autoReconnect: false);
    final staleLease = await session.acquireOtaLease();

    linkState.add(BleLinkState.disconnected);
    for (var i = 0;
        i < 20 && session.state != BleDeviceState.disconnected;
        i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(session.state, BleDeviceState.disconnected);

    await session.connect(autoReconnect: false);
    expect(session.state, BleDeviceState.ready);
    final activeLease = await session.acquireOtaLease();

    staleLease.release();

    expect(session.isOtaInProgress, isTrue);
    activeLease.release();
  });

  test('v1 device explicitly rejects secure direct authentication', () async {
    when(() => connection.read(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.infoCharUuid,
        )).thenAnswer(
      (_) async => utf8.encode(
        jsonEncode({
          'sn': 'H1CNA6K20001',
          'bound': true,
          'proto_ver': '1.0',
        }),
      ),
    );
    final session = await connectSession();

    expect(session.supportsSecureDirectControl, isFalse);
    await expectLater(
      session.authenticate(deviceKeyBase64),
      throwsA(
        isA<BleCommandException>().having(
          (error) => error.code,
          'code',
          'UNSUPPORTED_SECURE_DIRECT_CONTROL',
        ),
      ),
    );
    expect(authWrites, isEmpty);
    // 2026-09-22 起鉴权失败不再阻塞会话：连接即就绪
    expect(session.state, BleDeviceState.ready);
  });

  test('readInfo returns INFO json', () async {
    when(() => connection.read(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.infoCharUuid,
        )).thenAnswer((_) async => utf8.encode(
          jsonEncode(v2Info()),
        ));

    final session = await connectSession();
    final info = await session.readInfo();

    expect((info['body'] as Map)['device_sn'], 'H1CNA6K20001');
    expect((info['body'] as Map)['bound'], true);
  });

  test('readTelemetrySnapshot returns telemetry json', () async {
    when(() => connection.read(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.telemetryCharUuid,
        )).thenAnswer((_) async => utf8.encode('{"power_w":3000,"status":1}'));

    final session = await connectSession();
    final data = await session.readTelemetrySnapshot();

    expect(data['power_w'], 3000);
  });

  test('bind writes bind message and completes on ok notify', () async {
    when(() => connection.write(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.authCharUuid,
          any(),
        )).thenAnswer((_) async {});

    final session = await connectSession();
    // 2026-09-22 起连接即就绪（不再要求绑定/鉴权）
    expect(session.state, BleDeviceState.ready);

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
        )).thenAnswer((_) async {});

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
        )).thenAnswer((_) async {});

    final session = await connectSession();
    final pinFuture = session.checkPin('123456');
    authNotify
        .add(utf8.encode(jsonEncode({'mode': 'pin_check', 'result': 'ok'})));
    await pinFuture; // 不抛异常即通过
  });

  test('checkPin throws PIN_REJECTED on rejected notify', () async {
    when(() => connection.write(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.authCharUuid,
          any(),
        )).thenAnswer((_) async {});

    final session = await connectSession();
    final pinFuture = session.checkPin('000000');
    authNotify.add(utf8.encode(jsonEncode(
        {'mode': 'pin_check', 'result': 'rejected', 'error': 'invalid_pin'})));
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
        )).thenAnswer((_) async {});

    final session = await connectSession();
    final pinFuture = session.checkPin('000000');
    authNotify.add(utf8.encode(jsonEncode(
        {'mode': 'pin_check', 'result': 'rejected', 'error': 'locked'})));
    await expectLater(
      pinFuture,
      throwsA(isA<BleCommandException>()
          .having((e) => e.code, 'code', 'PIN_LOCKED')),
    );
  });

  test('command uses v2 envelope and completes only on applied result',
      () async {
    final session = await connectSession();
    await authenticateSession(session);

    final future = session.sendCommand('set_param', {
      'param_id': 'output_priority',
      'value': 1,
    });
    for (var i = 0; i < 20 && commandWrites.isEmpty; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    final request = commandWrites.single;
    final body = (request['body'] as Map).cast<String, dynamic>();
    expect(request['v'], 2);
    expect(request['type'], 'control.request');
    expect(request['session_id'], sessionId);
    expect(body['session_id'], sessionId);
    expect(body['operation_id'], isNotEmpty);
    expect(body['command_id'], isNotEmpty);
    expect(body['sequence'], 1);

    Map<String, dynamic> result(String status) => {
          'v': 2,
          'type': 'control.result',
          'message_id': 'device-result-$status',
          'in_reply_to': request['message_id'],
          'session_id': sessionId,
          'body': {
            'operation_id': body['operation_id'],
            'command_id': body['command_id'],
            'status': status,
            'result_id': 'result-1',
            'error': null,
            'actual': {'param_id': 'output_priority', 'value': 1},
            'parameter_revision': 3,
          },
        };
    commandNotify.add(utf8.encode(jsonEncode(result('accepted'))));
    await Future<void>.delayed(Duration.zero);
    commandNotify.add(utf8.encode(jsonEncode(result('applied'))));

    expect(await future, {'param_id': 'output_priority', 'value': 1});
  });

  test('stale command result cannot complete a current request', () async {
    final session = await connectSession();
    await authenticateSession(session);
    final future = session.sendCommand('power_on');
    for (var i = 0; i < 20 && commandWrites.isEmpty; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    final request = commandWrites.single;
    final body = request['body'] as Map;
    var completed = false;
    future.then((_) => completed = true);
    commandNotify.add(utf8.encode(jsonEncode({
      'v': 2,
      'type': 'control.result',
      'message_id': 'stale-result',
      'in_reply_to': 'old-message',
      'session_id': sessionId,
      'body': {
        'command_id': body['command_id'],
        'status': 'applied',
        'actual': {},
      },
    })));
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);

    commandNotify.add(utf8.encode(jsonEncode({
      'v': 2,
      'type': 'control.result',
      'message_id': 'current-result',
      'in_reply_to': request['message_id'],
      'session_id': sessionId,
      'body': {
        'command_id': body['command_id'],
        'status': 'applied',
        'actual': {'power': 'on'},
      },
    })));
    expect(await future, {'power': 'on'});
  });
}
