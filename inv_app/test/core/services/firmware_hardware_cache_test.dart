import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/firmware_download_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory documents;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('hardware_cache_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => documents.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await documents.delete(recursive: true);
  });

  Future<File> existingImage(int id) async {
    final dir = Directory('${documents.path}/firmware');
    await dir.create();
    return File('${dir.path}/${id}_same.bin')..writeAsBytesSync([1, 2, 3]);
  }

  test('downloaded hardware range survives service recreation', () async {
    await existingImage(7);
    final prefs = await SharedPreferences.getInstance();
    final download = FirmwareDownloadService(prefs);
    await download.downloadFirmware(
      url: 'https://example.test/same.bin',
      fileName: 'same.bin',
      firmwareId: 7,
      expectedSize: 3,
      deviceModel: 'L10',
      targetChip: 'arm',
      version: '1.2.0',
      hardwareVersions: const ['HW-1', 'HW-2'],
    );
    download.dispose();
    final restarted =
        FirmwareDownloadService(await SharedPreferences.getInstance());
    final items = await restarted.listDownloadedFirmwares();
    expect(items.single.hardwareVersions, ['HW-1', 'HW-2']);
    expect(jsonDecode(prefs.getString('firmware_meta_7')!)['hardware_versions'],
        ['HW-1', 'HW-2'],);
    restarted.dispose();
  });

  test('same filename hardware builds keep separate bytes and scope', () async {
    final first = await existingImage(7);
    final second = await existingImage(8);
    final download =
        FirmwareDownloadService(await SharedPreferences.getInstance());
    for (final id in [7, 8]) {
      await download.downloadFirmware(
        url: 'https://example.test/same.bin',
        fileName: 'same.bin',
        firmwareId: id,
        expectedSize: 3,
        hardwareVersions: ['HW-${id - 6}'],
      );
    }
    final items = await download.listDownloadedFirmwares();
    expect(
        items.map((item) => item.filePath).toSet(), {first.path, second.path},);
    expect(items.map((item) => item.hardwareVersions.single), ['HW-1', 'HW-2']);
    download.dispose();
  });

  test('old cache remains removable but has no hardware upgrade metadata',
      () async {
    final file = await existingImage(9);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('firmware_path_9', file.path);
    await prefs.setInt('firmware_size_9', 3);
    await prefs.setString(
        'firmware_meta_9',
        jsonEncode({
          'device_model': 'L10',
          'target_chip': 'arm',
          'version': '1.2.0',
          'signature': 'signature',
          'security_version': 1,
        }),);
    final download = FirmwareDownloadService(prefs);
    final items = await download.listDownloadedFirmwares();
    expect(items.single.hardwareVersions, isEmpty);
    expect(items.single.hasUpgradeMetadata, isFalse);
    await download.deleteDownloadedFirmware(9);
    expect(await file.exists(), isFalse);
    download.dispose();
  });
}
