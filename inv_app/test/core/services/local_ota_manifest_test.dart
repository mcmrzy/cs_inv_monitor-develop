import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/firmware_download_service.dart';
import 'package:inv_app/core/services/local_communication_service.dart';

void main() {
  group('DownloadedFirmwareInfo', () {
    const complete = DownloadedFirmwareInfo(
      firmwareId: 7,
      filePath: '/tmp/fw.bin',
      fileName: 'fw.bin',
      fileSize: 1024,
      deviceModel: 'CS-L10-6K2',
      targetChip: 'arm',
      version: '1.2.3',
      sha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      signature: 'signature',
      securityVersion: 1,
    );

    test('complete offline metadata includes model and file size', () {
      expect(complete.hasUpgradeMetadata, isTrue);
    });

    test('missing firmware model is not upgrade-ready', () {
      expect(
        DownloadedFirmwareInfo(
          firmwareId: complete.firmwareId,
          filePath: complete.filePath,
          fileName: complete.fileName,
          fileSize: complete.fileSize,
          targetChip: complete.targetChip,
          version: complete.version,
          sha256: complete.sha256,
          signature: complete.signature,
          securityVersion: complete.securityVersion,
        ).hasUpgradeMetadata,
        isFalse,
      );
    });

    test('non-positive file size is not upgrade-ready', () {
      expect(
        DownloadedFirmwareInfo(
          firmwareId: complete.firmwareId,
          filePath: complete.filePath,
          fileName: complete.fileName,
          fileSize: 0,
          deviceModel: complete.deviceModel,
          targetChip: complete.targetChip,
          version: complete.version,
          sha256: complete.sha256,
          signature: complete.signature,
          securityVersion: complete.securityVersion,
        ).hasUpgradeMetadata,
        isFalse,
      );
    });

    test('local channel support follows explicit module capabilities', () {
      const bleOnly = DownloadedFirmwareInfo(
        firmwareId: 8,
        filePath: '/tmp/fw.bin',
        fileName: 'fw.bin',
        fileSize: 1024,
        targetChip: 'arm',
        supportedChannels: ['ble'],
      );
      const remoteOnly = DownloadedFirmwareInfo(
        firmwareId: 9,
        filePath: '/tmp/fw.bin',
        fileName: 'fw.bin',
        fileSize: 1024,
        targetChip: 'arm',
        supportedChannels: ['remote'],
      );
      const dspBle = DownloadedFirmwareInfo(
        firmwareId: 10,
        filePath: '/tmp/fw.bin',
        fileName: 'fw.bin',
        fileSize: 1024,
        targetChip: 'dsp',
        supportedChannels: ['ble'],
      );

      expect(bleOnly.supportsLocalChannel('ble'), isTrue);
      expect(bleOnly.supportsLocalChannel('wifi_ap'), isFalse);
      expect(remoteOnly.supportsLocalChannel('ble'), isFalse);
      expect(dspBle.supportsLocalChannel('ble'), isTrue);
      expect(dspBle.supportsLocalChannel('wifi_ap'), isFalse);
    });
  });

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
    expect(manifest(target: 'dsp').validate, returnsNormally);
    expect(manifest(target: 'bms').validate, returnsNormally);
  });

  test('accepts unsigned manifest with optional metadata omitted', () {
    // 2026-09-21：签名/安全版本/SHA-256 改为可选（服务端固件记录可能未签名），
    // 设备端对空签名跳过验签、对 0 安全版本跳过回滚检查。
    expect(
      manifest(
        sha256: '',
        signature: '',
        securityVersion: 0,
      ).validate,
      returnsNormally,
    );
  });

  test('rejects metadata the device would reject', () {
    expect(() => manifest(target: 'gpu').validate(), throwsArgumentError);
    expect(() => manifest(sha256: 'A' * 64).validate(), throwsArgumentError);
    expect(
      () => manifest(signature: 'not-base64').validate(),
      throwsArgumentError,
    );
    expect(
      () => manifest(securityVersion: 0x100000000).validate(),
      throwsArgumentError,
    );
  });
}
