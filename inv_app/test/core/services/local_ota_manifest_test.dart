import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/local_communication_service.dart';

void main() {
  LocalOtaManifest manifest({
    String target = 'esp',
    String sha256 =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    String signature =
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==',
    int securityVersion = 1,
  }) {
    return LocalOtaManifest(
      target: target,
      taskId: 'local-42-123456',
      version: '1.2.3',
      sha256: sha256,
      signature: signature,
      securityVersion: securityVersion,
    );
  }

  test('accepts a canonical signed local OTA manifest', () {
    expect(manifest().validate, returnsNormally);
    expect(manifest(target: 'arm').validate, returnsNormally);
  });

  test('rejects metadata the device would reject', () {
    expect(() => manifest(target: 'dsp').validate(), throwsArgumentError);
    expect(() => manifest(sha256: 'A' * 64).validate(), throwsArgumentError);
    expect(() => manifest(signature: 'not-base64').validate(),
        throwsArgumentError);
    expect(() => manifest(securityVersion: 0).validate(), throwsArgumentError);
    expect(() => manifest(securityVersion: 0x100000000).validate(),
        throwsArgumentError);
  });
}
