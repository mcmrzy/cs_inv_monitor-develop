import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/local_communication_service.dart';
import 'package:inv_app/features/ota/domain/entities/local_channel.dart';
import 'package:inv_app/features/ota/domain/repositories/local_communication_repository.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';
import 'package:inv_app/features/ota/presentation/controller/local_ota_controller.dart';
import 'package:mocktail/mocktail.dart';

class _MockOtaRepository extends Mock implements OtaRepository {}

class _FakeLocalCommunication implements LocalCommunicationRepository {
  final List<String> calls = [];
  Object? triggerError;

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
    return const {
      'status': 'failed',
      'progress': 0,
      'message': 'device rejected upgrade',
    };
  }

  @override
  Future<bool> connectToDevice({
    required String deviceSN,
    required String deviceIP,
    String? password,
  }) async => true;

  @override
  Future<void> disconnect() async {}

  @override
  Future<Map<String, dynamic>> getDeviceInfo(String deviceIP) async => const {};

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
  ) async => true;

  @override
  Future<Map<String, dynamic>> controlDevice(
    String deviceIP,
    String command, {
    Map<String, dynamic>? params,
  }) async => const {};
}

void main() {
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

  Future<void> execute() => controller.execute(
        filePath: '/tmp/firmware.bin',
        manifest: manifest,
        fallbackVersion: manifest.version,
      );

  test('uploads, triggers, then polls in strict order', () async {
    await execute();

    expect(communication.calls, ['upload', 'trigger', 'progress']);
  });

  test(
    'trigger failure ends as failed without polling and releases connection',
    () async {
      final error = StateError('trigger rejected');
      communication.triggerError = error;

      await execute();

      expect(communication.calls, ['upload', 'trigger']);
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

      await execute();

      expect(communication.calls, ['upload', 'trigger']);
      expect(controller.state.phase, LocalOTAPhase.failed);
      expect(controller.state.error, same(error));
      expect(terminateCount, 1);
    },
  );
}
