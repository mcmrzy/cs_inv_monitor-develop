import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/local_communication_service.dart';
import 'package:inv_app/features/ota/domain/repositories/trusted_local_ota_transport.dart';

void main() {
  const hash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const manifest = LocalOtaManifest(target: 'arm', taskId: 'task', version: '1.0', sha256: hash, signature: '', securityVersion: 1);
  const receipt = TrustedLocalOtaPreflight(deviceSN: 'SN-A', target: 'arm', boardCode: 'MAIN-A', boardUid: 'abcdef0123456789', identityRevision: 2, moduleRevision: 1, authorizationId: 'authorization-A', firmwareId: 12, sha256: hash);

  test('signed transport receipt must bind device file target and board', () {
    expect(receipt.matches(expectedSN: 'SN-A', expectedFirmwareId: 12, manifest: manifest, firmwareBoardCodes: ['MAIN-A']), isTrue);
    expect(receipt.matches(expectedSN: 'SN-B', expectedFirmwareId: 12, manifest: manifest, firmwareBoardCodes: ['MAIN-A']), isFalse);
    expect(receipt.matches(expectedSN: 'SN-A', expectedFirmwareId: 13, manifest: manifest, firmwareBoardCodes: ['MAIN-A']), isFalse);
    expect(receipt.matches(expectedSN: 'SN-A', expectedFirmwareId: 12, manifest: manifest, firmwareBoardCodes: ['MAIN-B']), isFalse);
    expect(receipt.matches(expectedSN: 'SN-A', expectedFirmwareId: 12, manifest: manifest, firmwareBoardCodes: []), isFalse);
  });
}
