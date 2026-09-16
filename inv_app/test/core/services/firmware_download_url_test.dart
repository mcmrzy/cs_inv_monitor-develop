import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/firmware_download_service.dart';

void main() {
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
