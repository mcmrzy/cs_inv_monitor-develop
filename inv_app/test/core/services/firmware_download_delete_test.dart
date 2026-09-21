import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/firmware_download_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 已下载固件删除语义：固件文件、续传分片与持久化记录一并清除，
/// 且不影响其他固件记录（列表/校验依赖这些键）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fw_delete_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<File> writeFirmware(String name, {int size = 16, int fill = 7}) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(List<int>.filled(size, fill));
    return file;
  }

  test('delete removes firmware file, part file and persisted records',
      () async {
    final file = await writeFirmware('esp_1.6.0.bin');
    final part = File('${file.path}.part');
    await part.writeAsBytes(List<int>.filled(8, 1));

    SharedPreferences.setMockInitialValues({
      'firmware_path_7': file.path,
      'firmware_size_7': 16,
      'firmware_sha256_7': 'abc',
      'firmware_meta_7': '{"version":"1.6.0","target_chip":"esp"}',
    });
    final prefs = await SharedPreferences.getInstance();
    final service = FirmwareDownloadService(prefs);

    await service.deleteDownloadedFirmware(7);

    expect(await file.exists(), isFalse);
    expect(await part.exists(), isFalse);
    expect(prefs.getString('firmware_path_7'), isNull);
    expect(prefs.getInt('firmware_size_7'), isNull);
    expect(prefs.getString('firmware_sha256_7'), isNull);
    expect(prefs.getString('firmware_meta_7'), isNull);
  });

  test('delete keeps other downloaded firmware intact', () async {
    final kept = await writeFirmware('arm_1.2.0.bin', size: 32, fill: 3);
    final removed = await writeFirmware('esp_1.6.0.bin');

    SharedPreferences.setMockInitialValues({
      'firmware_path_7': removed.path,
      'firmware_size_7': 16,
      'firmware_path_9': kept.path,
      'firmware_size_9': 32,
    });
    final prefs = await SharedPreferences.getInstance();
    final service = FirmwareDownloadService(prefs);

    await service.deleteDownloadedFirmware(7);

    expect(await removed.exists(), isFalse);
    expect(await kept.exists(), isTrue);
    expect(prefs.getString('firmware_path_9'), kept.path);
    expect(prefs.getInt('firmware_size_9'), 32);
  });

  test('delete on unknown firmware id is a no-op', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = FirmwareDownloadService(prefs);

    await service.deleteDownloadedFirmware(404);

    expect(prefs.getKeys().where((k) => k.startsWith('firmware_')), isEmpty);
  });

  test('delete tolerates an already missing firmware file', () async {
    final missing = File('${tempDir.path}/gone.bin');
    SharedPreferences.setMockInitialValues({
      'firmware_path_5': missing.path,
    });
    final prefs = await SharedPreferences.getInstance();
    final service = FirmwareDownloadService(prefs);

    await service.deleteDownloadedFirmware(5);

    expect(prefs.getString('firmware_path_5'), isNull);
  });
}
