import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/errors/ota_error_types.dart';
import 'package:inv_app/core/services/local_communication_service.dart';
import 'package:inv_app/features/ota/domain/entities/local_channel.dart';
import 'package:inv_app/features/ota/domain/repositories/local_communication_repository.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';
import 'package:inv_app/features/ota/domain/repositories/trusted_local_ota_transport.dart';
import 'package:inv_app/features/ota/presentation/controller/local_ota_controller.dart';
import 'package:mocktail/mocktail.dart';

class _MockOtaRepository extends Mock implements OtaRepository {}

class _FakeLocalCommunication implements LocalCommunicationRepository {
  final List<String> calls = [];
  Object? triggerError;
  Map<String, dynamic> deviceInfo = const {
    'device_model': 'INV-10K',
    'hardware_version': 'HW-1',
  };
  Map<String, dynamic> progress = const {
    'status': 'failed',
    'progress': 0,
    'message': 'device rejected upgrade',
  };
  final List<Map<String, dynamic>> deviceInfoSequence = [];

  @override
  Future<void> uploadFirmware({
    required String deviceIP,
    required String filePath,
    required LocalOtaManifest manifest,
    void Function(int sent, int total)? onProgress,
  }) async {
    calls.add('upload');
  }

  @override
  Future<void> triggerUpgrade(String deviceIP) async {
    calls.add('trigger');
    final error = triggerError;
    if (error != null) throw error;
  }

  @override
  Future<Map<String, dynamic>> getProgress(String deviceIP) async {
    calls.add('progress');
    return progress;
  }

  @override
  Future<bool> connectToDevice({
    required String deviceSN,
    required String deviceIP,
    String? password,
    String? macAddress,
  }) async =>
      true;

  @override
  Future<void> disconnect() async {}

  @override
  Future<Map<String, dynamic>> getDeviceInfo(String deviceIP) async {
    calls.add('info');
    if (deviceInfoSequence.isNotEmpty) {
      return deviceInfoSequence.removeAt(0);
    }
    return deviceInfo;
  }

  @override
  Future<bool> isConnectedToDeviceAP() async => true;

  @override
  Future<bool> testConnection(String deviceIP) async => true;

  @override
  Future<String> readParameter(String deviceIP, String paramName) async => '';

  @override
  Future<bool> writeParameter(
    String deviceIP,
    String paramName,
    String value,
  ) async =>
      true;

  @override
  Future<Map<String, dynamic>> controlDevice(
    String deviceIP,
    String command, {
    Map<String, dynamic>? params,
  }) async =>
      const {};
}

// A test updater adapter which has completed the trusted preflight contract.
// Production BLE/WiFi adapters must implement cryptographic validation first.
class _TrustedCommunication extends _FakeLocalCommunication implements TrustedLocalOtaTransport {
  @override
  Future<TrustedLocalOtaPreflight> preflightTrustedInstall({required String deviceSN, required int firmwareId, required LocalOtaManifest manifest, required List<String> firmwareBoardCodes}) async => TrustedLocalOtaPreflight(deviceSN: deviceSN, target: manifest.target, boardCode: 'MAIN-A', boardUid: 'abcdef0123456789', identityRevision: 2, moduleRevision: 1, authorizationId: 'auth-test', firmwareId: firmwareId, sha256: manifest.sha256);
}

void main() {
  test('collector DSP and BMS installation get a longer polling window', () {
    expect(LocalOTAController.pollTimeoutForTarget('esp'),
        const Duration(seconds: 180),);
    expect(LocalOTAController.pollTimeoutForTarget('dsp'),
        const Duration(minutes: 20),);
    expect(LocalOTAController.pollTimeoutForTarget('bms'),
        const Duration(minutes: 20),);
  });

  const manifest = LocalOtaManifest(
    target: 'arm',
    taskId: 'local-test-1',
    version: '1.2.3',
    sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    signature: 'test-signature',
    securityVersion: 1,
  );

  late _FakeLocalCommunication communication;
  late LocalOTAController controller;
  late int terminateCount;

  setUp(() {
    communication = _FakeLocalCommunication();
    terminateCount = 0;
    controller = LocalOTAController(
      communication: communication,
      repository: _MockOtaRepository(),
      channel: LocalCommunicationChannel.ble,
      deviceSN: 'SN001',
      deviceIP: '192.168.4.1',
      onTerminateConnection: () => terminateCount++,
    );
  });

  tearDown(() => controller.dispose());

  void enableTrusted({_MockOtaRepository? repository}) {
    final trusted = _TrustedCommunication()
      ..deviceInfo = communication.deviceInfo
      ..progress = communication.progress
      ..triggerError = communication.triggerError
      ..deviceInfoSequence.addAll(communication.deviceInfoSequence);
    controller.dispose();
    communication = trusted;
    controller = LocalOTAController(communication: trusted, repository: repository ?? _MockOtaRepository(), channel: LocalCommunicationChannel.ble, deviceSN: 'SN001', deviceIP: '192.168.4.1', onTerminateConnection: () => terminateCount++);
  }

  Future<void> execute() => controller.execute(
        filePath: '/tmp/firmware.bin',
        manifest: manifest,
        fallbackVersion: manifest.version,
        firmwareModel: 'INV-10K',
        firmwareHardwareVersions: const ['HW-1'],
        firmwareBoardCodes: const ['MAIN-A'],
        firmwareId: 42,
      );

  test('uploads, triggers, then polls in strict order', () async {
    enableTrusted();
    await execute();

    expect(communication.calls, ['info', 'upload', 'trigger', 'progress']);
  });

  test('unknown hardware stops local OTA before any upload bytes', () async {
    communication.deviceInfo = const {'device_model': 'INV-10K'};
    await execute();
    expect(communication.calls, ['info']);
    expect(controller.state.phase, LocalOTAPhase.failed);
    expect(controller.state.error, isA<LocalOtaHardwareException>());
    expect(OtaErrorMapper.l10nKeyOf(controller.state.error!),
        'ota_err_device_hardware_unknown',);
  });

  for (final channel in LocalCommunicationChannel.values) {
    test('${channel.name} hardware mismatch prevents upload and trigger',
        () async {
      controller.dispose();
      controller = LocalOTAController(
        communication: communication,
        repository: _MockOtaRepository(),
        channel: channel,
        deviceSN: 'SN001',
        deviceIP: '192.168.4.1',
      );
      communication.deviceInfo = const {
        'device_model': 'INV-10K',
        'hardware_version': 'HW-2',
      };
      await execute();
      expect(communication.calls, ['info']);
      expect(controller.state.error, isA<LocalOtaHardwareException>());
      expect(OtaErrorMapper.l10nKeyOf(controller.state.error!),
          'ota_err_hardware_mismatch',);
    });
  }

  test('legacy cached firmware without scope cannot upload', () async {
    await controller.execute(
      filePath: '/tmp/old.bin',
      manifest: manifest,
      fallbackVersion: manifest.version,
      firmwareModel: 'INV-10K',
      firmwareHardwareVersions: const [],
    );
    expect(communication.calls, ['info']);
    expect(OtaErrorMapper.l10nKeyOf(controller.state.error!),
        'ota_err_firmware_hardware_unknown',);
  });

  test('matching shared legacy hardware is diagnostic and cannot authorize installation',
      () async {
    communication.deviceInfo = const {
      'device_model': 'INV-10K',
      'hw_version': ' hw-2 ',
    };
    await controller.execute(
      filePath: '/tmp/shared.bin',
      manifest: manifest,
      fallbackVersion: manifest.version,
      firmwareModel: 'INV-10K',
      firmwareHardwareVersions: const ['HW-1', 'HW-2'],
    );
    expect(communication.calls, ['info']);
    expect(controller.state.error, isA<LocalOtaAuthorizationRequiredException>());
  });

  for (final reported in ['1', 'V1', 'HW1']) {
    test('hardware prefixes are distinct: $reported cannot match HW-1',
        () async {
      communication.deviceInfo = {
        'device_model': 'INV-10K',
        'hardware_version': reported,
      };
      await execute();
      expect(communication.calls, ['info']);
      expect(OtaErrorMapper.l10nKeyOf(controller.state.error!),
          'ota_err_hardware_mismatch',);
    });
  }

  test(
    'trigger failure ends as failed without polling and releases connection',
    () async {
      final error = StateError('trigger rejected');
      communication.triggerError = error;
      enableTrusted();

      await execute();

      expect(communication.calls, ['info', 'upload', 'trigger']);
      expect(controller.state.phase, LocalOTAPhase.failed);
      expect(controller.state.error, same(error));
      expect(terminateCount, 1);
    },
  );

  test(
    'trigger timeout ends as failed without polling and releases connection',
    () async {
      final error = TimeoutException('trigger timed out');
      communication.triggerError = error;
      enableTrusted();

      await execute();

      expect(communication.calls, ['info', 'upload', 'trigger']);
      expect(controller.state.phase, LocalOTAPhase.failed);
      expect(controller.state.error, same(error));
      expect(terminateCount, 1);
    },
  );

  test('BLE model mismatch fails closed before upload', () async {
    communication.deviceInfo = const {'device_model': 'INV-20K'};

    await execute();

    expect(communication.calls, ['info']);
    expect(controller.state.phase, LocalOTAPhase.failed);
    expect(controller.state.error, isA<LocalOtaDeviceModelException>());
    expect(terminateCount, 1);
  });

  test('BMS is rejected before upload when BLE INFO omits the module',
      () async {
    communication.deviceInfo = const {
      'device_model': 'INV-10K',
      'supported_upgrade_modules': [
        'communication_module',
        'system_controller',
      ],
    };

    await controller.execute(
      filePath: '/tmp/bms.bin',
      manifest: const LocalOtaManifest(
        target: 'bms',
        taskId: 'local-bms-1',
        version: '1.2.3',
        sha256: '',
        signature: '',
        securityVersion: 0,
      ),
      fallbackVersion: '1.2.3',
      firmwareModel: 'INV-10K',
      firmwareHardwareVersions: const ['HW-1'],
    );

    expect(communication.calls, ['info']);
    expect(controller.state.phase, LocalOTAPhase.failed);
    expect(controller.state.error, isA<LocalOtaUnsupportedTargetException>());
  });

  test('WiFi missing device model fails closed before upload', () async {
    controller.dispose();
    communication.deviceInfo = const {};
    controller = LocalOTAController(
      communication: communication,
      repository: _MockOtaRepository(),
      channel: LocalCommunicationChannel.wifiAp,
      deviceSN: 'SN001',
      deviceIP: '192.168.4.1',
      onTerminateConnection: () => terminateCount++,
    );

    await execute();

    expect(communication.calls, ['info']);
    expect(controller.state.phase, LocalOTAPhase.failed);
    expect(controller.state.error, isA<LocalOtaDeviceModelException>());
    expect(terminateCount, 1);
  });

  test('reports a module version recovered after reboot to the cloud',
      () async {
    final repository = _MockOtaRepository();
    when(
      () => repository.reportLocalOTAResult(
        sn: any(named: 'sn'),
        targetChip: any(named: 'targetChip'),
        newVersion: any(named: 'newVersion'),
        firmwareId: any(named: 'firmwareId'),
      ),
    ).thenAnswer((_) async => const Right(<String, dynamic>{}));
    controller.dispose();
    communication
      ..progress = const {'status': 'done', 'progress': 100}
      ..deviceInfoSequence.addAll(const [
        {'device_model': 'INV-10K', 'hardware_version': 'HW-1'},
        {'device_model': 'INV-10K', 'firmware_arm': '1.2.3'},
      ]);
    controller = LocalOTAController(
      communication: communication,
      repository: repository,
      channel: LocalCommunicationChannel.ble,
      deviceSN: 'SN001',
      deviceIP: '192.168.4.1',
      onTerminateConnection: () => terminateCount++,
    );

    enableTrusted(repository: repository);

    await controller.execute(
      filePath: '/tmp/firmware.bin',
      manifest: manifest,
      fallbackVersion: '',
      firmwareModel: 'INV-10K',
      firmwareHardwareVersions: const ['HW-1'],
      firmwareBoardCodes: const ['MAIN-A'],
      firmwareId: 42,
    );

    expect(controller.state.newVersion, '1.2.3');
    verify(
      () => repository.reportLocalOTAResult(
        sn: 'SN001',
        targetChip: 'arm',
        newVersion: '1.2.3',
        firmwareId: 42,
      ),
    ).called(1);
  });

  test('BMS done with only ARM metadata cannot invent the requested version',
      () async {
    final repository = _MockOtaRepository();
    when(
      () => repository.reportLocalOTAResult(
        sn: any(named: 'sn'),
        targetChip: any(named: 'targetChip'),
        newVersion: any(named: 'newVersion'),
      ),
    ).thenAnswer((_) async => const Right(<String, dynamic>{}));
    controller.dispose();
    communication
      ..deviceInfo = const {
        'device_model': 'INV-10K',
        'hardware_version': 'HW-1',
        'supported_upgrade_modules': ['communication_module', 'bms'],
      }
      ..progress = const {
        'status': 'done',
        'progress': 100,
        'arm_version': '9.9.9',
        'firmware_arm': '9.9.9',
      };
    controller = LocalOTAController(
      communication: communication,
      repository: repository,
      channel: LocalCommunicationChannel.ble,
      deviceSN: 'SN001',
      deviceIP: '192.168.4.1',
    );

    await controller.execute(
      filePath: '/tmp/bms.bin',
      manifest: const LocalOtaManifest(
        target: 'bms',
        taskId: 'local-bms-2',
        version: '2.3.4',
        sha256: '',
        signature: '',
        securityVersion: 0,
      ),
      fallbackVersion: '',
      firmwareModel: 'INV-10K',
      firmwareHardwareVersions: const ['HW-1'],
    );

    expect(controller.state.newVersion, isNull);
    expect(controller.state.phase, LocalOTAPhase.failed);
    verifyNever(() => repository.reportLocalOTAResult(
          sn: 'SN001',
          targetChip: 'bms',
          newVersion: '2.3.4',
        ),);
  });
}
