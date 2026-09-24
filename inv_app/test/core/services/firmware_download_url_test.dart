import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/firmware_download_service.dart';

void main() {
  test('downloaded DSP and BMS firmware require explicit BLE channel', () {
    DownloadedFirmwareInfo item(String target, List<String>? channels) =>
        DownloadedFirmwareInfo(
          firmwareId: 1,
          filePath: 'firmware.bin',
          fileName: 'firmware.bin',
          fileSize: 1,
          targetChip: target,
          supportedChannels: channels,
        );

    expect(item('dsp', ['remote', 'ble']).supportsLocalChannel('ble'), isTrue);
    expect(item('bms', ['remote', 'ble']).supportsLocalChannel('ble'), isTrue);
    expect(item('dsp', ['remote', 'ble']).supportsLocalChannel('wifi_ap'),
        isFalse);
    expect(item('bms', null).supportsLocalChannel('ble'), isFalse);
    expect(item('arm', null).supportsLocalChannel('ble'), isTrue);
  });

  test('resolveFirmwareUrl keeps absolute URLs', () {
    expect(
      FirmwareDownloadService.resolveFirmwareUrl(
        'https://download.example.com/fw.bin',
      ),
      'https://download.example.com/fw.bin',
    );
  });

  test('resolveFirmwareUrl prefixes relative paths with API origin', () {
    final resolved =
        FirmwareDownloadService.resolveFirmwareUrl('/firmware/esp_1.6.0.bin');
    expect(resolved, startsWith('http'));
    expect(resolved, endsWith('/firmware/esp_1.6.0.bin'));
    expect(resolved, isNot(contains('/api/v1/firmware/esp_1.6.0.bin')));
  });

  test('resolveFirmwareUrl handles empty input', () {
    expect(FirmwareDownloadService.resolveFirmwareUrl('  '), '');
  });
}
