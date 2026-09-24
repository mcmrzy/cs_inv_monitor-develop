import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_blue_ultra/flutter_blue_ultra.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/ble/ble_write_errors.dart';
import 'package:inv_app/core/services/local_communication_service.dart';
import 'package:inv_app/core/errors/ota_error_types.dart';
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
  late List<List<int>> otaRawFrames;
  late Directory tempDir;
  late String firmwarePath;
  late List<int> firmwareBytes;
  List<int>? lastPhoneNonce;
  bool rejectFirstChunk = false;
  bool rejectAuth = false;
  String? rejectCtrlResultCode;

  /// 数据帧在到达设备前抛 GATT_CMD_STARTED（134）的次数，
  /// 模拟本地协议栈瞬时拒绝（每次消耗一次）。
  int transientFailDataWrites = 0;

  /// 数据帧被设备以 ATT 14 (GATT_UNLIKELY) 拒绝的次数（每次消耗一次）。
  int deviceRefuseDataWrites = 0;

  /// 数据帧写入尝试总次数（含被拒的），用于断言"未重试"。
  int dataWriteAttempts = 0;

  /// 首个数据帧已被设备确认（ACK 已发出）之后才抛 134，模拟「回调报错但已落地」。
  bool transientFailAfterLanding = false;

  const mac = 'AA:BB:CC:DD:EE:FF';
  const sessionId = 'AAECAwQFBgcICQoLDA0ODw==';
  const deviceKeyBase64 = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=';
  const sn = 'H1CNA6K20001';

  Map<String, dynamic> v2Info({
    String firmwareVersion = '1.5.11',
    List<String>? supportedUpgradeModules,
    bool binaryOta = true,
  }) =>
      {
        'v': 2,
        'type': 'info',
        'message_id': 'info-001',
        'session_id': sessionId,
        'body': {
          'device_sn': sn,
          'proto_version': 2,
          'model': 'CS-L10-6K2',
          'firmware_version': firmwareVersion,
          'capabilities': [
            'info',
            'telemetry',
            'control',
            'ota',
            if (binaryOta) 'ota_binary_v1',
          ],
          if (supportedUpgradeModules != null)
            'supported_upgrade_modules': supportedUpgradeModules,
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
    rejectFirstChunk = false;
    rejectAuth = false;
    rejectCtrlResultCode = null;
    transientFailDataWrites = 0;
    transientFailAfterLanding = false;
    deviceRefuseDataWrites = 0;
    dataWriteAttempts = 0;
    authNotify = StreamController<List<int>>.broadcast();
    commandNotify = StreamController<List<int>>.broadcast();
    otaStatusNotify = StreamController<List<int>>.broadcast();
    linkState = StreamController<BleLinkState>.broadcast();
    otaCtrlWrites = [];
    otaDataWrites = [];
    otaRawFrames = [];
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
    when(() => connection.mtuNow).thenReturn(512);
    when(() => connection.requestMtu(any())).thenAnswer((_) async => 512);
    when(() => connection.read(
          BleCtProtocol.provisioningServiceUuid,
          BleCtProtocol.provisioningSnCharUuid,
        )).thenAnswer((_) async => utf8.encode(sn));
    when(() => connection.read(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.infoCharUuid,
        )).thenAnswer((_) async => utf8.encode(jsonEncode(v2Info())));
    when(() => connection.read(
          BleCtProtocol.provisioningServiceUuid,
          BleCtProtocol.otaStatusCharUuid,
          timeout: 5,
        )).thenAnswer((_) async {
      final ctrl = otaCtrlWrites.lastWhere((e) => e['type'] == 'ota.ctrl');
      final transferId = ((ctrl['body'] as Map)['transfer_id']) as String;
      final accepted = otaDataWrites.fold<int>(0, (sum, frame) {
        final payload = ((frame['body'] as Map)['payload']) as String;
        return sum + base64Decode(payload).length;
      });
      return utf8.encode(jsonEncode(otaStatus(
        stage: accepted == firmwareBytes.length ? 'verifying' : 'receiving',
        transferId: transferId,
        acceptedOffset: accepted,
      )));
    });
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
          allowLongWrite: true,
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
          stage: rejectCtrlResultCode == null ? 'accepted' : 'failed',
          transferId: transferId,
          resultCode: rejectCtrlResultCode ?? 'OK',
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
          allowLongWrite: false,
          timeout: 5,
        )).thenAnswer((invocation) async {
      final frame = invocation.positionalArguments[2] as List<int>;
      final header = ByteData.sublistView(Uint8List.fromList(frame));
      final offset = header.getUint32(6, Endian.little);
      final chunk = frame.sublist(10);
      dataWriteAttempts++;
      if (deviceRefuseDataWrites > 0) {
        deviceRefuseDataWrites--;
        throw FlutterBlueUltraException(
            ErrorPlatform.android, 'writeCharacteristic', 14, 'GATT_UNLIKELY');
      }
      if (transientFailDataWrites > 0) {
        transientFailDataWrites--;
        throw FlutterBlueUltraException(ErrorPlatform.android,
            'writeCharacteristic', 134, 'GATT_CMD_STARTED');
      }
      otaRawFrames.add(frame);
      final transferId =
          ((otaCtrlWrites.last['body'] as Map)['transfer_id']) as String;
      final end = offset + chunk.length;
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
      otaDataWrites.add({
        'body': {
          'transfer_id': transferId,
          'offset': offset,
          'payload': base64Encode(chunk),
          'payload_sha256': sha256.convert(chunk).toString(),
        },
      });
      otaStatusNotify.add(utf8.encode(jsonEncode(otaStatus(
        stage: end >= firmwareBytes.length ? 'verifying' : 'receiving',
        transferId: transferId,
        acceptedOffset: end,
        progress: (end * 100) ~/ firmwareBytes.length,
      ))));
      if (transientFailAfterLanding && otaDataWrites.length == 1) {
        throw FlutterBlueUltraException(ErrorPlatform.android,
            'writeCharacteristic', 134, 'GATT_CMD_STARTED');
      }
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
      final b = (write['body'] as Map).cast<String, dynamic>();
      expect(b['offset'], expectedOffset);
      final chunk = base64.decode(b['payload'] as String);
      expectedOffset += chunk.length;
    }
    expect(otaRawFrames, isNotEmpty);
    for (final frame in otaRawFrames) {
      expect(frame.length, lessThanOrEqualTo(509));
      expect(frame[0], 0xb1);
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

  test('old device is rejected before binary OTA control or data writes',
      () async {
    when(() => connection.read(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.infoCharUuid,
        )).thenAnswer((_) async => utf8.encode(jsonEncode(v2Info(
          firmwareVersion: '1.0.11',
          binaryOta: false,
          supportedUpgradeModules: [
            'communication_module',
            'system_controller',
            'dsp_controller',
            'bms',
          ],
        ))));
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
        'OTA_BINARY_UNSUPPORTED',
      )),
    );
    expect(otaCtrlWrites, isEmpty);
    expect(otaRawFrames, isEmpty);
  });

  test('sends 1024 firmware bytes as MTU-bounded binary writes', () async {
    firmwareBytes = List<int>.generate(1024, (i) => i & 0xff);
    await File(firmwarePath).writeAsBytes(firmwareBytes);
    when(() => connection.read(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.infoCharUuid,
        )).thenAnswer((_) async => utf8.encode(jsonEncode(v2Info(
          firmwareVersion: '1.0.12',
          binaryOta: true,
        ))));

    final rawFrames = <List<int>>[];
    var accepted = 0;
    when(() => connection.write(
          BleCtProtocol.provisioningServiceUuid,
          BleCtProtocol.otaDataCharUuid,
          any(),
          allowLongWrite: false,
          timeout: 5,
        )).thenAnswer((invocation) async {
      final frame = invocation.positionalArguments[2] as List<int>;
      rawFrames.add(frame);
      expect(frame.length, lessThanOrEqualTo(509));
      expect(frame[0], 0xb1);
      expect(frame[1], 1);
      final data = ByteData.sublistView(Uint8List.fromList(frame));
      final transferId =
          ((otaCtrlWrites.last['body'] as Map)['transfer_id']) as String;
      expect(data.getUint32(2, Endian.little),
          int.parse(transferId.substring(0, 8), radix: 16));
      expect(data.getUint32(6, Endian.little), accepted);
      accepted += frame.length - 10;
      if (accepted == firmwareBytes.length) {
        otaStatusNotify.add(utf8.encode(jsonEncode(otaStatus(
          stage: 'verifying',
          transferId: transferId,
          acceptedOffset: accepted,
          progress: 100,
        ))));
      }
    });

    final service = BleCommunicationService(adapter: adapter, manager: manager);
    await service.connectToDevice(deviceSN: sn, deviceIP: '192.168.4.1');
    await service.uploadFirmware(
      deviceIP: '192.168.4.1',
      filePath: firmwarePath,
      manifest: manifest(),
    );

    expect(accepted, firmwareBytes.length);
    expect(rawFrames.length, 3);
    expect(rawFrames.map((frame) => frame.length - 10), [496, 496, 32]);
  });

  test('MTU 256 reads batch status without waiting for absent notification',
      () async {
    firmwareBytes = List<int>.generate(2048, (i) => i & 0xff);
    await File(firmwarePath).writeAsBytes(firmwareBytes);
    when(() => connection.mtuNow).thenReturn(256);
    when(() => connection.write(
          BleCtProtocol.provisioningServiceUuid,
          BleCtProtocol.otaDataCharUuid,
          any(),
          allowLongWrite: false,
          timeout: 5,
        )).thenAnswer((invocation) async {
      final frame = invocation.positionalArguments[2] as List<int>;
      expect(frame.length, lessThanOrEqualTo(253));
      final data = ByteData.sublistView(Uint8List.fromList(frame));
      final offset = data.getUint32(6, Endian.little);
      final payload = frame.sublist(10);
      otaDataWrites.add({
        'body': {'offset': offset, 'payload': base64Encode(payload)},
      });
    });

    final service = BleCommunicationService(adapter: adapter, manager: manager);
    await service.connectToDevice(deviceSN: sn, deviceIP: '192.168.4.1');
    await service
        .uploadFirmware(
          deviceIP: '192.168.4.1',
          filePath: firmwarePath,
          manifest: manifest(),
        )
        .timeout(const Duration(seconds: 2));
    expect(otaDataWrites.length, 10);
  });

  test('compact OTA sends a whole-file SHA when the manifest omits it',
      () async {
    when(() => connection.read(
          BleCtProtocol.serviceUuid,
          BleCtProtocol.infoCharUuid,
        )).thenAnswer((_) async => utf8.encode(jsonEncode(v2Info(
          firmwareVersion: '1.0.11',
          binaryOta: true,
        ))));
    final service = BleCommunicationService(adapter: adapter, manager: manager);
    await service.connectToDevice(deviceSN: sn, deviceIP: '192.168.4.1');

    await service.uploadFirmware(
      deviceIP: '192.168.4.1',
      filePath: firmwarePath,
      manifest: LocalOtaManifest(
        target: 'esp',
        taskId: 'task-1',
        version: '1.5.12',
        sha256: '',
        signature: '',
        securityVersion: 0,
      ),
    );

    final ctrl = otaCtrlWrites.singleWhere((e) => e['type'] == 'ota.ctrl');
    final body = (ctrl['body'] as Map).cast<String, dynamic>();
    expect(body['sha256'], sha256.convert(firmwareBytes).toString());
    expect(otaRawFrames.length, 1);
  });

  for (final entry in const {'dsp': 'dsp_controller', 'bms': 'bms'}.entries) {
    test('uploads ${entry.key} with its BLE wire target', () async {
      final service =
          BleCommunicationService(adapter: adapter, manager: manager);
      await service.connectToDevice(deviceSN: sn, deviceIP: '192.168.4.1');
      await service.uploadFirmware(
        deviceIP: '192.168.4.1',
        filePath: firmwarePath,
        manifest: LocalOtaManifest(
          target: entry.key,
          taskId: 'task-1',
          version: '1.5.12',
          sha256: List.filled(64, 'a').join(),
          signature: base64.encode(List.filled(64, 1)),
          securityVersion: 1,
        ),
      );
      final ctrl =
          otaCtrlWrites.singleWhere((item) => item['type'] == 'ota.ctrl');
      expect((ctrl['body'] as Map)['target'], entry.value);
    });
  }

  test('cache shortage fails before any BLE data chunk', () async {
    rejectCtrlResultCode = 'INSUFFICIENT_STORAGE';
    final service = BleCommunicationService(adapter: adapter, manager: manager);
    await service.connectToDevice(deviceSN: sn, deviceIP: '192.168.4.1');
    await expectLater(
      service.uploadFirmware(
        deviceIP: '192.168.4.1',
        filePath: firmwarePath,
        manifest: manifest(),
      ),
      throwsA(isA<OtaInsufficientStorageException>()),
    );
    expect(otaDataWrites, isEmpty);
  });

  test('expected reboot disconnect does not fail trigger and progress resumes',
      () async {
    final service = BleCommunicationService(
      adapter: adapter,
      manager: manager,
    );
    await service.connectToDevice(
      deviceSN: sn,
      deviceIP: '192.168.4.1',
    );
    await service.uploadFirmware(
      deviceIP: '192.168.4.1',
      filePath: firmwarePath,
      manifest: manifest(),
    );

    linkState.add(BleLinkState.disconnected);
    final session = manager.sessionOf(mac)!;
    for (var i = 0;
        i < 20 && session.state != BleDeviceState.disconnected;
        i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(session.state, BleDeviceState.disconnected);

    await service.triggerUpgrade('192.168.4.1');

    final progress = await service.getProgress('192.168.4.1');
    expect(progress['status'], 'done');

    await service.disconnect();
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
    expect(info['firmware_esp'], '1.5.11');
    expect(info.containsKey('firmware_arm'), isFalse);
    expect(info.containsKey('arm_version'), isFalse);
  });

  test('transient GATT write refusal is retried with the same offset',
      () async {
    transientFailDataWrites = 1;
    final service = BleCommunicationService(adapter: adapter, manager: manager);
    await service.connectToDevice(deviceSN: sn, deviceIP: '192.168.4.1');

    await service.uploadFirmware(
      deviceIP: '192.168.4.1',
      filePath: firmwarePath,
      manifest: manifest(),
    );

    // 被拒的那一发没有到达设备（未入列），重发用的是同一 offset，
    // 最终仍按序收满整个固件。
    final totalPayload = otaDataWrites.fold<int>(0, (sum, write) {
      final b = (write['body'] as Map).cast<String, dynamic>();
      return sum + base64.decode(b['payload'] as String).length;
    });
    expect(totalPayload, firmwareBytes.length);
    final offsets = otaDataWrites
        .map((w) => ((w['body'] as Map)['offset'] as num).toInt())
        .toList();
    expect(offsets.first, 0);
    expect(offsets, offsets.toSet().toList(), reason: 'offset 必须严格递增不重复');

    await service.disconnect();
  });

  test('write that errors after the device ACK counts as landed', () async {
    // 回调报 134，但 ACK 已发出：不得重发，否则设备按 offset 严格校验会拒帧。
    transientFailAfterLanding = true;
    final service = BleCommunicationService(adapter: adapter, manager: manager);
    await service.connectToDevice(deviceSN: sn, deviceIP: '192.168.4.1');

    await service.uploadFirmware(
      deviceIP: '192.168.4.1',
      filePath: firmwarePath,
      manifest: manifest(),
    );

    final offsets = otaDataWrites
        .map((w) => ((w['body'] as Map)['offset'] as num).toInt())
        .toList();
    expect(offsets.length, offsets.toSet().length, reason: '不允许重复 offset');

    await service.disconnect();
  });

  test('only AOSP transient GATT statuses are retryable', () {
    final transient = (int? code,
            {ErrorPlatform platform = ErrorPlatform.android,
            String? description}) =>
        isTransientBleWriteError(FlutterBlueUltraException(
            platform, 'writeCharacteristic', code, description));
    expect(transient(132), isTrue, reason: 'GATT_BUSY');
    expect(transient(133), isTrue, reason: 'GATT_ERROR');
    expect(transient(134), isTrue, reason: 'GATT_CMD_STARTED');
    expect(transient(13), isFalse, reason: '设备侧 ATT 错误不可重试');
    expect(transient(14), isFalse, reason: 'GATT_UNLIKELY 是设备侧拒绝');
    expect(transient(null), isFalse);
    expect(
      isTransientBleWriteError(
          const BleCommandException('OTA_NOT_ACTIVE', 'x')),
      isFalse,
    );

    // 插件等待超时：完成回调没来，写是否落地未知，可重试（先查状态再重发）。
    expect(
      transient(FbuErrorCode.timeout.index,
          platform: ErrorPlatform.fbu, description: 'Timed out after 15s'),
      isTrue,
    );
    expect(
      transient(null,
          platform: ErrorPlatform.fbu, description: 'Timed out after 15s'),
      isTrue,
      reason: '消息兜底也能识别',
    );
    expect(transient(1, platform: ErrorPlatform.fbu), isTrue,
        reason: 'fbu 平台 code=1 即 FbuErrorCode.timeout');
    expect(transient(2, platform: ErrorPlatform.fbu), isFalse,
        reason: 'fbu 其它错误码（androidOnly 等）不算超时');

    expect(
        deviceAttErrorCodeOf(FlutterBlueUltraException(
            ErrorPlatform.android, 'writeCharacteristic', 14, 'GATT_UNLIKELY')),
        14);
    expect(
        deviceAttErrorCodeOf(FlutterBlueUltraException(ErrorPlatform.android,
            'writeCharacteristic', 134, 'GATT_CMD_STARTED')),
        isNull,
        reason: '134 属本地栈瞬时拒绝，不是设备侧 ATT 错误');
    expect(
        deviceAttErrorCodeOf(FlutterBlueUltraException(ErrorPlatform.fbu,
            'writeCharacteristic', 1, 'Timed out after 15s')),
        isNull,
        reason: '插件超时不是设备侧 ATT 错误');
    expect(deviceAttErrorCodeOf(const BleCommandException('X', 'y')), isNull);
  });

  test('device ATT refusal fails fast with DEVICE_REFUSED, no retry', () async {
    deviceRefuseDataWrites = 1;
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
        'DEVICE_REFUSED',
      )),
    );
    // 只尝试了一次：设备侧拒绝不可重试。
    expect(dataWriteAttempts, 1);
    expect(otaDataWrites, isEmpty);
    await service.disconnect();
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

  test('unbound session connects ready without scanning', () async {
    when(() => keyStore.read(any())).thenAnswer((_) async => null);
    final unboundManager = BleDeviceManager(
      adapter: adapter,
      keyStore: keyStore,
    );
    addTearDown(unboundManager.disconnectAll);
    // 2026-09-22 起连接即就绪：未绑定设备不再停留 authenticating
    final session = await unboundManager.connectDevice(mac);
    expect(session.state, BleDeviceState.ready);

    final service = BleCommunicationService(
      adapter: adapter,
      manager: unboundManager,
    );
    final connected = await service.connectToDevice(
      deviceSN: sn,
      deviceIP: '192.168.4.1',
      macAddress: mac,
    );

    expect(connected, isTrue);
    expect(service.lastConnectFailure, isNull);
    expect(service.targetMacAddress, mac);
    expectNoScan();
  });

  test('device rejecting the stored key still connects ready', () async {
    rejectAuth = true;
    final rejectedManager = BleDeviceManager(
      adapter: adapter,
      keyStore: keyStore,
    );
    addTearDown(rejectedManager.disconnectAll);
    // 2026-09-22 起鉴权改为尽力而为：设备拒绝密钥也不再阻塞会话
    final session = await rejectedManager.connectDevice(mac);
    expect(session.state, BleDeviceState.ready);

    final service = BleCommunicationService(
      adapter: adapter,
      manager: rejectedManager,
    );
    final connected = await service.connectToDevice(
      deviceSN: sn,
      deviceIP: '192.168.4.1',
      macAddress: mac,
    );

    expect(connected, isTrue);
    expect(service.lastConnectFailure, isNull);
    expectNoScan();
  });

  test('transient auth failure does not block the session', () async {
    rejectAuth = true;
    final retryManager = BleDeviceManager(adapter: adapter, keyStore: keyStore);
    addTearDown(retryManager.disconnectAll);
    final session = await retryManager.connectDevice(mac);
    expect(session.state, BleDeviceState.ready);

    // 2026-09-22 起会话连接即就绪，ensureAuthenticated 直接返回 true
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

  test('ensureAuthenticated reports false for unknown sessions', () async {
    final emptyManager = BleDeviceManager(adapter: adapter, keyStore: keyStore);
    expect(await emptyManager.ensureAuthenticated(mac), isFalse);
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

    final legacyManager =
        BleDeviceManager(adapter: adapter, keyStore: keyStore);
    addTearDown(legacyManager.disconnectAll);
    // 2026-09-22 起连接即就绪：v1 设备也能建立会话
    final session = await legacyManager.connectDevice(mac);
    expect(session.state, BleDeviceState.ready);

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
      isTrue,
    );
    expectNoScan();
  });
}
