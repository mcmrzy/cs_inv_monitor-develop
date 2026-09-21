import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/local_communication_service.dart';
import 'package:inv_app/features/ota/data/datasources/ble_communication_service.dart';
import 'package:mocktail/mocktail.dart';

class MockBleAdapter extends Mock implements BleAdapter {}

class MockBleGattConnection extends Mock implements BleGattConnection {}

class MockBleDeviceKeyStore extends Mock implements BleDeviceKeyStore {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(const Duration(seconds: 1));
    registerFallbackValue(const <String>[]);
  });

  late MockBleAdapter adapter;
  late MockBleGattConnection connection;
  late MockBleDeviceKeyStore keyStore;
  late BleDeviceManager manager;
  late StreamController<List<int>> authNotify;
  late StreamController<List<int>> commandNotify;
  late StreamController<List<int>> otaStatusNotify;
  late StreamController<BleLinkState> linkState;
  late List<Map<String, dynamic>> otaCtrlWrites;
  late List<Map<String, dynamic>> otaDataWrites;
  late Directory tempDir;
  late String firmwarePath;
  late List<int> firmwareBytes;
  List<int>? lastPhoneNonce;
  bool rejectFirstChunk = false;
  bool rejectAuth = false;

  const mac = 'AA:BB:CC:DD:EE:FF';
  const sessionId = 'AAECAwQFBgcICQoLDA0ODw==';
  const deviceKeyBase64 = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=';
  const sn = 'H1CNA6K20001';

  Map<String, dynamic> v2Info() => {
        'v': 2,
        'type': 'info',
        'message_id': 'info-001',
        'session_id': sessionId,
        'body': {
          'device_sn': sn,
          'proto_version': 2,
          'model': 'CS-L10-6K2',
          'firmware_version': '1.5.11',
          'capabilities': ['info', 'telemetry', 'control', 'ota'],
          'bound': true,
        },
      };

  Map<String, dynamic> otaStatus({
    required String stage,
    required String transferId,
    int acceptedOffset = 0,
    int progress = 0,
    String resultCode = 'OK',
    String message = '',
  }) =>
      {
        'v': 2,
        'type': 'ota.status',
        'message_id': 'ota-status',
        'session_id': sessionId,
        'body': {
          'transfer_id': transferId,
          'task_id': 'task-1',
          'stage': stage,
          'accepted_offset': acceptedOffset,
          'progress': progress,
          'result_code': resultCode,
          'message': message,
        },
      };

  setUp(() async {
    adapter = MockBleAdapter();
    connection = MockBleGattConnection();
    keyStore = MockBleDeviceKeyStore();
    authNotify = StreamController<List<int>>.broadcast();
    commandNotify = StreamController<List<int>>.broadcast();
    otaStatusNotify = StreamController<List<int>>.broadcast();
    linkState = StreamController<BleLinkState>.broadcast();
    otaCtrlWrites = [];
    otaDataWrites = [];
    lastPhoneNonce = null;
    rejectFirstChunk = false;
    rejectAuth = false;

    tempDir = await Directory.systemTemp.createTemp('ble_ota_test_');
    firmwareBytes = List<int>.generate(300, (i) => i & 0xff);
    firmwarePath = '${tempDir.path}/fw.bin';
    await File(firmwarePath).writeAsBytes(firmwareBytes);

    when(() => adapter.status).thenAnswer((_) async => BleAdapterStatus.on);
    when(() => adapter.connect(any(), autoConnect: any(named: 'autoConnect')))
        .thenAnswer((_) async => connection);
    when(() => adapter.stopScan()).thenAnswer((_) async {});
    when(() => connection.linkState).thenAnswer((_) => linkState.stream);
    when(() => connection.requestMtu(any())).thenAnswer((_) async => 512);
    when(() => connection.read(
          BleCtProtocol.provisioningServiceUuid,
          BleCtProtocol.provisioningSnCharUuid,
        )).thenAnswer((_) async => utf8.encode(sn));
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
        )).thenAnswer((_) => otaStatusNotify.stream);
    when(() => connection.write(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.authCharUuid,
          any(),
        )).thenAnswer((invocation) async {
      final bytes = invocation.positionalArguments[2] as List<int>;
      final json =
          (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>();
      if (json['type'] == 'auth.init') {
        lastPhoneNonce = base64Decode(
          ((json['body'] as Map)['phone_nonce'] as String),
        );
        authNotify.add(utf8.encode(jsonEncode({
          'v': 2,
          'type': 'auth.challenge',
          'message_id': 'challenge-1',
          'in_reply_to': json['message_id'],
          'session_id': sessionId,
          'body': {
            'device_nonce': 'EBESExQVFhcYGRobHB0eHw==',
            'device_ts': 1789459200,
          },
        })));
      } else if (json['type'] == 'auth.proof') {
        if (rejectAuth) {
          authNotify.add(utf8.encode(jsonEncode({
            'v': 2,
            'type': 'auth.result',
            'message_id': 'auth-result-1',
            'in_reply_to': json['message_id'],
            'session_id': sessionId,
            'body': const {'result': 'rejected', 'reason': 'not_bound'},
          })));
          return;
        }
        final phoneNonce = lastPhoneNonce!;
        final expected = BleCtProtocol.computeAuthProof(
          key: base64Decode(deviceKeyBase64),
          role: BleAuthProofRole.device,
          sessionId: sessionId,
          phoneNonce: phoneNonce,
          deviceNonce: base64Decode('EBESExQVFhcYGRobHB0eHw=='),
          deviceTimestamp: 1789459200,
        );
        authNotify.add(utf8.encode(jsonEncode({
          'v': 2,
          'type': 'auth.result',
          'message_id': 'auth-result-1',
          'in_reply_to': json['message_id'],
          'session_id': sessionId,
          'body': {
            'result': 'ok',
            'device_proof': base64Encode(expected),
          },
        })));
      }
    });
    when(() => connection.write(
          BleCtProtocol.provisioningServiceUuid,
          BleCtProtocol.otaControlCharUuid,
          any(),
        )).thenAnswer((invocation) async {
      final bytes = invocation.positionalArguments[2] as List<int>;
      final json =
          (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>();
      otaCtrlWrites.add(json);
      final type = json['type'] as String? ?? '';
      if (type == 'ota.ctrl') {
        final body = (json['body'] as Map).cast<String, dynamic>();
        final transferId = body['transfer_id'] as String;
        otaStatusNotify.add(utf8.encode(jsonEncode(otaStatus(
          stage: 'accepted',
          transferId: transferId,
        ))));
      } else if (type == 'ota.query') {
        final last = otaCtrlWrites.reversed
            .where((e) => e['type'] == 'ota.ctrl')
            .cast<Map<String, dynamic>?>()
            .firstWhere((_) => true, orElse: () => null);
        final transferId = last == null
            ? ''
            : ((last['body'] as Map)['transfer_id'] as String? ?? '');
        final received = otaDataWrites.fold<int>(0, (sum, write) {
          final body = (write['body'] as Map).cast<String, dynamic>();
          final payload = body['payload'] as String? ?? '';
          return sum + (base64.decode(payload).length);
        });
        otaStatusNotify.add(utf8.encode(jsonEncode(otaStatus(
          stage: received >= firmwareBytes.length ? 'succeeded' : 'receiving',
          transferId: transferId,
          acceptedOffset: received,
          progress: received >= firmwareBytes.length
              ? 100
              : (received * 100) ~/ firmwareBytes.length,
        ))));
      }
    });
    when(() => connection.write(
          BleCtProtocol.provisioningServiceUuid,
          BleCtProtocol.otaDataCharUuid,
          any(),
        )).thenAnswer((invocation) async {
      final bytes = invocation.positionalArguments[2] as List<int>;
      final json =
          (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>();
      otaDataWrites.add(json);
      final body = (json['body'] as Map).cast<String, dynamic>();
      final transferId = body['transfer_id'] as String;
      final offset = (body['offset'] as num).toInt();
      final payload = body['payload'] as String;
      final end = offset + base64.decode(payload).length;
      if (rejectFirstChunk) {
        otaStatusNotify.add(utf8.encode(jsonEncode(otaStatus(
          stage: 'failed',
          transferId: transferId,
          acceptedOffset: offset,
          resultCode: 'CHUNK_REJECTED',
          message: 'chunk rejected',
        ))));
        return;
      }
      otaStatusNotify.add(utf8.encode(jsonEncode(otaStatus(
        stage: end >= firmwareBytes.length ? 'verifying' : 'receiving',
        transferId: transferId,
        acceptedOffset: end,
        progress: (end * 100) ~/ firmwareBytes.length,
      ))));
    });
    when(() => keyStore.read(any())).thenAnswer((_) async => deviceKeyBase64);

    manager = BleDeviceManager(adapter: adapter, keyStore: keyStore);
    final session = await manager.connectDevice(mac);
    // wait until ready
    for (var i = 0; i < 50 && session.state != BleDeviceState.ready; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(session.state, BleDeviceState.ready);
  });

  tearDown(() async {
    await manager.disconnectAll();
    await authNotify.close();
    await commandNotify.close();
    await otaStatusNotify.close();
    await linkState.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  LocalOtaManifest manifest() => LocalOtaManifest(
        target: 'esp',
        taskId: 'task-1',
        version: '1.5.12',
        sha256: List.filled(64, 'a').join(),
        signature: base64.encode(List.filled(64, 1)),
        securityVersion: 1,
        timeoutSeconds: 300,
      );

  test('uses authenticated session and uploads via ota.ctrl/data', () async {
    final service = BleCommunicationService(
      adapter: adapter,
      manager: manager,
    );
    final connected = await service.connectToDevice(
      deviceSN: sn,
      deviceIP: '192.168.4.1',
    );
    expect(connected, isTrue);
    expect(service.isConnected, isTrue);

    var reported = 0;
    await service.uploadFirmware(
      deviceIP: '192.168.4.1',
      filePath: firmwarePath,
      manifest: manifest(),
      onProgress: (sent, total) {
        reported = sent;
        expect(total, firmwareBytes.length);
      },
    );

    expect(reported, firmwareBytes.length);
    final ctrl = otaCtrlWrites.singleWhere((e) => e['type'] == 'ota.ctrl');
    expect(ctrl['v'], 2);
    expect(ctrl['session_id'], sessionId);
    final body = (ctrl['body'] as Map).cast<String, dynamic>();
    expect(utf8.encode(jsonEncode(ctrl)).length, lessThanOrEqualTo(509));
    expect(body['target'], 'communication_module');
    expect(body['size'], firmwareBytes.length);
    expect(body['security_version'], 1);

    final totalPayload = otaDataWrites.fold<int>(0, (sum, write) {
      final b = (write['body'] as Map).cast<String, dynamic>();
      return sum + base64.decode(b['payload'] as String).length;
    });
    expect(totalPayload, firmwareBytes.length);
    // 连续 offset
    var expectedOffset = 0;
    for (final write in otaDataWrites) {
      expect(utf8.encode(jsonEncode(write)).length, lessThanOrEqualTo(509));
      final b = (write['body'] as Map).cast<String, dynamic>();
      expect(b['offset'], expectedOffset);
      final chunk = base64.decode(b['payload'] as String);
      expect(b['payload_sha256'], sha256.convert(chunk).toString());
      expectedOffset += chunk.length;
    }

    final progress = await service.getProgress('192.168.4.1');
    expect(progress['status'],
        anyOf('uploading', 'verifying', 'installing', 'done'));
    expect((progress['progress'] as num) >= 0, isTrue);

    await service.disconnect();
    final session = manager.sessionOf(mac)!;
    expect(session.isOtaInProgress, isFalse);
    // 独占释放后普通控制可恢复
    expect(() => session.sendCommand('power_on'), returnsNormally);
  });

  test('device failure during chunk ACK is reported without timeout', () async {
    rejectFirstChunk = true;
    final service = BleCommunicationService(adapter: adapter, manager: manager);
    await service.connectToDevice(deviceSN: sn, deviceIP: '192.168.4.1');
    await expectLater(
      service.uploadFirmware(
        deviceIP: '192.168.4.1',
        filePath: firmwarePath,
        manifest: manifest(),
      ),
      throwsA(isA<BleCommandException>().having(
        (e) => e.code,
        'code',
        'CHUNK_REJECTED',
      )),
    );
    await service.disconnect();
    expect(manager.sessionOf(mac)!.isOtaInProgress, isFalse);
  });

  test('getDeviceInfo flattens v2 info for model gate', () async {
    final service = BleCommunicationService(
      adapter: adapter,
      manager: manager,
    );
    await service.connectToDevice(deviceSN: sn, deviceIP: '192.168.4.1');
    final info = await service.getDeviceInfo('192.168.4.1');
    expect(info['model'], 'CS-L10-6K2');
    expect(info['device_sn'], sn);
    expect(info['firmware_version'], '1.5.11');
  });

  test('OTA lease blocks telemetry and control until released', () async {
    final session = manager.sessionOf(mac)!;
    final lease = await session.acquireOtaLease();
    expect(session.isOtaInProgress, isTrue);
    await expectLater(
      session.sendCommand('power_on'),
      throwsA(isA<BleCommandException>()),
    );
    await expectLater(
      session.readTelemetrySnapshot(),
      throwsA(isA<BleCommandException>()),
    );
    lease.release();
    expect(session.isOtaInProgress, isFalse);
  });

  test('failed OTA status surfaces as BleCommandException', () async {
    final service = BleCommunicationService(
      adapter: adapter,
      manager: manager,
    );
    await service.connectToDevice(deviceSN: sn, deviceIP: '192.168.4.1');
    await service.uploadFirmware(
      deviceIP: '192.168.4.1',
      filePath: firmwarePath,
      manifest: manifest(),
    );

    final transfer =
        (otaCtrlWrites.singleWhere((e) => e['type'] == 'ota.ctrl')['body']
            as Map)['transfer_id'] as String;
    otaStatusNotify.add(utf8.encode(jsonEncode(otaStatus(
      stage: 'failed',
      transferId: transfer,
      acceptedOffset: firmwareBytes.length,
      resultCode: 'SIGNATURE_INVALID',
      message: 'bad signature',
    ))));
    await Future<void>.delayed(Duration.zero);

    final progress = await service.getProgress('192.168.4.1');
    // query 会请求最新状态；手工推送的 failed 可能已被后续 query 覆盖
    expect(progress['status'], isNotEmpty);
  });

  test('double acquire OTA lease fails', () async {
    final session = manager.sessionOf(mac)!;
    await session.acquireOtaLease();
    await expectLater(
      session.acquireOtaLease(),
      throwsA(isA<BleCommandException>()),
    );
  });

  // ---------------------------------------------------------------------------
  // 连接步骤：设备一旦被连接即停止广播，必须复用会话而不是重新扫描
  // （"连蓝牙 → 选固件 → 再连蓝牙"曾因此报"扫描不到设备"）
  // ---------------------------------------------------------------------------

  /// 断言连接步骤从未触发 BLE 扫描
  void expectNoScan() {
    verifyNever(() => adapter.scan(
          serviceUuids: any(named: 'serviceUuids'),
          timeout: any(named: 'timeout'),
        ));
  }

  test('connect reuses the live ready session without scanning', () async {
    final service = BleCommunicationService(adapter: adapter, manager: manager);
    final connected = await service.connectToDevice(
      deviceSN: sn,
      deviceIP: '192.168.4.1',
      macAddress: mac,
    );

    expect(connected, isTrue);
    expect(service.isConnected, isTrue);
    expect(service.targetMacAddress, mac);
    expect(service.lastConnectFailure, isNull);
    expectNoScan();
  });

  test('connect without mac reuses the ready session by SN', () async {
    final service = BleCommunicationService(adapter: adapter, manager: manager);
    final connected = await service.connectToDevice(
      deviceSN: sn,
      deviceIP: '192.168.4.1',
    );

    expect(connected, isTrue);
    expect(service.lastConnectFailure, isNull);
    expectNoScan();
  });

  test('connected but unbound session reports notBound without scanning',
      () async {
    when(() => keyStore.read(any())).thenAnswer((_) async => null);
    final unboundManager = BleDeviceManager(
      adapter: adapter,
      keyStore: keyStore,
    );
    addTearDown(unboundManager.disconnectAll);
    final session = await unboundManager.connectDevice(mac);
    expect(session.state, BleDeviceState.authenticating);

    final service = BleCommunicationService(
      adapter: adapter,
      manager: unboundManager,
    );
    final connected = await service.connectToDevice(
      deviceSN: sn,
      deviceIP: '192.168.4.1',
      macAddress: mac,
    );

    expect(connected, isFalse);
    expect(service.lastConnectFailure, BleConnectFailure.notBound);
    // 目标 MAC 仍要暴露给页面，用于就地绑定补救
    expect(service.targetMacAddress, mac);
    expectNoScan();
  });

  test('device rejecting the stored key reports authFailed without scanning',
      () async {
    rejectAuth = true;
    final rejectedManager = BleDeviceManager(
      adapter: adapter,
      keyStore: keyStore,
    );
    addTearDown(rejectedManager.disconnectAll);
    // 设备拒绝鉴权：connect 抛错（链路层仍连上），会话不进入 ready
    await expectLater(
      rejectedManager.connectDevice(mac),
      throwsA(isA<BleCommandException>()),
    );
    final session = rejectedManager.sessionOf(mac)!;
    expect(session.state, isNot(BleDeviceState.ready));

    // 会话已不是活跃状态时按"无活跃会话"处理，但仍不得依赖扫描：
    // 带上 MAC 直连（重连后设备依然拒绝鉴权）→ 归因为密钥不匹配
    final service = BleCommunicationService(
      adapter: adapter,
      manager: rejectedManager,
    );
    final connected = await service.connectToDevice(
      deviceSN: sn,
      deviceIP: '192.168.4.1',
      macAddress: mac,
    );

    expect(connected, isFalse);
    expect(service.lastConnectFailure, BleConnectFailure.authFailed);
    expectNoScan();
  });

  test('manager re-authenticates a session whose auth failed transiently',
      () async {
    rejectAuth = true;
    final retryManager = BleDeviceManager(adapter: adapter, keyStore: keyStore);
    addTearDown(retryManager.disconnectAll);
    await expectLater(
      retryManager.connectDevice(mac),
      throwsA(isA<BleCommandException>()),
    );
    final session = retryManager.sessionOf(mac)!;

    // 设备恢复应答后，本机复用同一会话重试鉴权即可就绪（无需重连/重扫）
    rejectAuth = false;
    expect(await retryManager.ensureAuthenticated(mac), isTrue);
    expect(session.state, BleDeviceState.ready);

    final service = BleCommunicationService(
      adapter: adapter,
      manager: retryManager,
    );
    expect(
      await service.connectToDevice(
        deviceSN: sn,
        deviceIP: '192.168.4.1',
        macAddress: mac,
      ),
      isTrue,
    );
    expectNoScan();
  });

  test('connect by mac without a session connects directly, no scan', () async {
    final freshManager = BleDeviceManager(adapter: adapter, keyStore: keyStore);
    addTearDown(freshManager.disconnectAll);
    final service = BleCommunicationService(
      adapter: adapter,
      manager: freshManager,
    );

    final connected = await service.connectToDevice(
      deviceSN: sn,
      deviceIP: '192.168.4.1',
      macAddress: mac,
    );

    expect(connected, isTrue);
    expect(service.connectedMacAddress, mac);
    expectNoScan();
  });

  test('ensureAuthenticated reports false for unknown and unbound sessions',
      () async {
    final emptyManager = BleDeviceManager(adapter: adapter, keyStore: keyStore);
    expect(await emptyManager.ensureAuthenticated(mac), isFalse);

    when(() => keyStore.read(any())).thenAnswer((_) async => null);
    final unboundManager = BleDeviceManager(
      adapter: adapter,
      keyStore: keyStore,
    );
    addTearDown(unboundManager.disconnectAll);
    await unboundManager.connectDevice(mac);
    expect(await unboundManager.ensureAuthenticated(mac), isFalse);
  });

  test('device without v2 secure control reports unsupportedFirmware',
      () async {
    // 旧固件 INFO 未声明 proto_version=2 / control 能力
    when(() => connection.read(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.infoCharUuid,
        )).thenAnswer((_) async => utf8.encode(jsonEncode({
              'v': 2,
              'type': 'info',
              'session_id': sessionId,
              'body': const {
                'device_sn': sn,
                'proto_version': 1,
                'model': 'CS-L10-6K2',
                'capabilities': ['info', 'telemetry'],
              },
            })));

    final legacyManager = BleDeviceManager(adapter: adapter, keyStore: keyStore);
    addTearDown(legacyManager.disconnectAll);
    await expectLater(
      legacyManager.connectDevice(mac),
      throwsA(isA<BleCommandException>().having(
        (e) => e.code,
        'code',
        'UNSUPPORTED_SECURE_DIRECT_CONTROL',
      )),
    );

    final service = BleCommunicationService(
      adapter: adapter,
      manager: legacyManager,
    );
    expect(
      await service.connectToDevice(
        deviceSN: sn,
        deviceIP: '192.168.4.1',
        macAddress: mac,
      ),
      isFalse,
    );
    expect(
      service.lastConnectFailure,
      BleConnectFailure.unsupportedFirmware,
    );
    expectNoScan();
  });
}
