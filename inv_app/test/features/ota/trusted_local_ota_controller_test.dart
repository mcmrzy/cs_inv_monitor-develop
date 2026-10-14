import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/local_communication_service.dart';
import 'package:inv_app/features/ota/domain/entities/local_channel.dart';
import 'package:inv_app/features/ota/domain/repositories/local_communication_repository.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';
import 'package:inv_app/features/ota/presentation/controller/local_ota_controller.dart';
import 'package:mocktail/mocktail.dart';

class LocalTransport extends Mock implements LocalCommunicationRepository {}
class Repository extends Mock implements OtaRepository {}

void main() {
  setUpAll(() => registerFallbackValue(const LocalOtaManifest(target: 'arm', taskId: 'task', version: '1.0', sha256: '', signature: '', securityVersion: 0)));
  for (final channel in LocalCommunicationChannel.values) {
    test('${channel.name}: matching reported hardware cannot authorize upload', () async {
      final transport = LocalTransport();
      when(() => transport.getDeviceInfo(any())).thenAnswer((_) async => {'model': 'MODEL', 'hardware_version': 'HW-1', 'ota_manifest_v2_chunked': true});
      when(() => transport.uploadFirmware(deviceIP: any(named: 'deviceIP'), filePath: any(named: 'filePath'), manifest: any(named: 'manifest'), onProgress: any(named: 'onProgress'))).thenAnswer((_) async {});
      when(() => transport.triggerUpgrade(any())).thenAnswer((_) async {});
      when(() => transport.getProgress(any())).thenAnswer((_) async => {'status': 'failed'});
      final controller = LocalOTAController(communication: transport, repository: Repository(), channel: channel, deviceSN: 'SN001', deviceIP: '192.168.4.1');
      addTearDown(controller.dispose);
      const manifest = LocalOtaManifest(target: 'arm', taskId: 'task', version: '1.0', sha256: '', signature: '', securityVersion: 0);
      registerFallbackValue(manifest);
      await controller.execute(filePath: 'file.bin', manifest: manifest, fallbackVersion: '1.0', firmwareModel: 'MODEL', firmwareHardwareVersions: ['HW-1'], firmwareId: 12);
      verifyNever(() => transport.uploadFirmware(deviceIP: any(named: 'deviceIP'), filePath: any(named: 'filePath'), manifest: any(named: 'manifest'), onProgress: any(named: 'onProgress')));
      verifyNever(() => transport.triggerUpgrade(any()));
      expect(controller.state.phase, LocalOTAPhase.failed);
    });
  }
}
