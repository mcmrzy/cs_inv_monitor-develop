import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/firmware_download_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/features/ota/domain/entities/local_channel.dart';
import 'package:inv_app/features/ota/presentation/pages/local_ota_page.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/pump_app.dart';

class _MockDownloadService extends Mock implements FirmwareDownloadService {}

class _MockBleAdapter extends Mock implements BleAdapter {}

class _MockKeyStore extends Mock implements BleDeviceKeyStore {}

/// 近场升级执行页的"已下载固件删除"入口：二次确认后才删除，
/// 删除当前选中项时选择被清空（避免保留指向已删文件的路径）。
void main() {
  late _MockDownloadService downloadService;

  final espFirmware = DownloadedFirmwareInfo(
    firmwareId: 7,
    filePath: '/tmp/esp_1.6.0.bin',
    fileName: 'esp_1.6.0.bin',
    fileSize: 1024 * 512,
    deviceModel: 'CS-L10-6K2',
    targetChip: 'esp',
    version: '1.6.0',
    sha256: 'a' * 64,
    signature: 'sig',
    securityVersion: 1,
  );

  setUp(() async {
    await getIt.reset();
    downloadService = _MockDownloadService();
    when(() => downloadService.progressStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => downloadService.listDownloadedFirmwares())
        .thenAnswer((_) async => [espFirmware]);
    when(() => downloadService.deleteDownloadedFirmware(any()))
        .thenAnswer((_) async {});
    getIt.registerSingleton<FirmwareDownloadService>(downloadService);

    final adapter = _MockBleAdapter();
    when(() => adapter.stopScan()).thenAnswer((_) async {});
    getIt.registerSingleton<BleAdapter>(adapter);
    getIt.registerSingleton<BleDeviceManager>(
      BleDeviceManager(adapter: adapter, keyStore: _MockKeyStore()),
    );
  });

  tearDown(() async {
    await getIt.reset();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 900);
    addTearDown(tester.view.reset);
    await pumpMinimalApp(
      tester,
      const LocalOTAPage(
        deviceSN: 'H1CNA6K20001',
        deviceIP: '192.168.4.1',
        channel: LocalCommunicationChannel.ble,
      ),
    );
  }

  testWidgets('delete asks for confirmation and removes the download',
      (tester) async {
    await pumpPage(tester);

    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();

    // 二次确认：标题与说明都来自 l10n，删除按钮为通用「删除」
    expect(find.text('删除已下载固件'), findsOneWidget);
    expect(find.textContaining('1.6.0'), findsWidgets);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    verify(() => downloadService.deleteDownloadedFirmware(7)).called(1);
  });

  testWidgets('cancel keeps the downloaded firmware', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    verifyNever(() => downloadService.deleteDownloadedFirmware(any()));
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
  });
}
