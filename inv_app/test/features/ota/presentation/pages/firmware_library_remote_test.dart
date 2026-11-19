import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/core/services/firmware_download_service.dart';
import 'package:inv_app/core/services/network_status_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/features/device/domain/repositories/device_repository.dart';
import 'package:inv_app/features/ota/domain/entities/device_firmware_overview.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';
import 'package:inv_app/features/ota/presentation/pages/firmware_library_page.dart';
import '../../../../helpers/pump_app.dart';

class _Devices extends Mock implements DeviceRepository {}

class _Ota extends Mock implements OtaRepository {}

class _Downloads extends Mock implements FirmwareDownloadService {}
class _Network extends Mock implements NetworkStatusService {}

void main() {
  late _Devices devices;
  late _Ota ota;
  late _Downloads downloads;
  final remote = FirmwareResource(
      id: 7,
      model: 'L10',
      version: '1.0.18',
      fileUrl: '/firmware.bin',
      targetChip: 'esp',
      publishedAt: DateTime(2026, 10, 9),
      supportedChannels: const ['remote', 'ble'],);
  const local = FirmwareResource(
      id: 8,
      model: 'L10',
      version: '2.0',
      fileUrl: '/arm.bin',
      targetChip: 'arm',
      hardwareVersions: ['HW-1'],
      supportedChannels: ['ble'],);

  setUp(() {
    devices = _Devices();
    ota = _Ota();
    downloads = _Downloads();
    when(() => devices.getList(
            page: any(named: 'page'), pageSize: any(named: 'pageSize'),),)
        .thenAnswer((_) async => const Right({
              'items': [
                {'sn': 'SN', 'model': 'L10', 'status': 1},
              ],
              'total': 1,
            }),);
    when(() => ota.getFirmwareResources('SN'))
        .thenAnswer((_) async => Right([remote, local]));
    when(() => downloads.isFirmwareDownloaded(any()))
        .thenAnswer((_) async => true);
    when(() => ota.triggerFirmware(any(), any(),
            idempotencyKey: any(named: 'idempotencyKey'),),)
        .thenAnswer((_) async => const Right(<OtaTriggerTask>[]));
    getIt.registerSingleton<DeviceRepository>(devices);
    getIt.registerSingleton<OtaRepository>(ota);
    getIt.registerSingleton<FirmwareDownloadService>(downloads);
  });
  tearDown(() async => getIt.reset());

  testWidgets(
      'downloaded firmware retains remote action, confirms exact device and firmware',
      (tester) async {
    await pumpMinimalApp(tester, const FirmwareLibraryPage(initialSn: 'SN'));
    expect(find.byKey(const ValueKey('remote-upgrade-7')), findsOneWidget);
    expect(find.byKey(const ValueKey('remote-upgrade-8')), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('remote-upgrade-7')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('remote-upgrade-7')));
    await tester.pumpAndSettle();
    verifyNever(() => ota.triggerFirmware(any(), any(),
        idempotencyKey: any(named: 'idempotencyKey'),),);
    expect(find.textContaining('SN\n'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();
    verify(() => ota.triggerFirmware('SN', [7],
        idempotencyKey: any(named: 'idempotencyKey'),),).called(1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('device release history loads only the requested SN and shows full notes',
      (tester) async {
    const notes = '修复通信掉线\n优化重连\n改进升级进度\n完善故障记录';
    when(() => ota.getFirmwareResources('TARGET'))
        .thenAnswer((_) async => const Right([
              FirmwareResource(
                id: 17, model: 'L10', version: '1.1.0',
                fileUrl: '/historical.bin', targetChip: 'esp', changelog: notes,
              ),
            ]));
    await pumpMinimalApp(tester, const FirmwareLibraryPage(initialSn: 'TARGET', deviceHistory: true));
    expect(find.text('历史发布版本'), findsOneWidget);
    expect(find.text('TARGET'), findsOneWidget);
    expect(find.text('1.1.0'), findsOneWidget);
    final notesWidget = tester.widget<Text>(find.text(notes));
    expect(notesWidget.maxLines, isNull);
    verify(() => ota.getFirmwareResources('TARGET')).called(1);
    verifyNever(() => ota.getFirmwareResources('SN'));
    verifyNever(() => devices.getList(
      page: any(named: 'page'), pageSize: any(named: 'pageSize'),
    ));
  });

  testWidgets('device history waits for the network and reloads when it returns',
      (tester) async {
    final network = _Network();
    var offline = true;
    final connectivity = StreamController<bool>.broadcast();
    addTearDown(connectivity.close);
    when(() => network.isOffline).thenAnswer((_) => offline);
    when(() => network.statusStream).thenAnswer((_) => connectivity.stream);
    getIt.registerSingleton<NetworkStatusService>(network);
    await pumpMinimalApp(
      tester,
      const FirmwareLibraryPage(initialSn: 'SN', deviceHistory: true),
    );
    expect(find.text('请先下载固件'), findsOneWidget);
    verifyNever(() => ota.getFirmwareResources(any()));
    verifyNever(() => devices.getList(
      page: any(named: 'page'), pageSize: any(named: 'pageSize'),
    ));

    offline = false;
    connectivity.add(true);
    await tester.pumpAndSettle();
    expect(find.text('请先下载固件'), findsNothing);
    expect(find.text('1.0.18'), findsOneWidget);
    verify(() => ota.getFirmwareResources('SN')).called(1);
  });

  testWidgets('offline resources keep remote button disabled', (tester) async {
    when(() => devices.getList(
            page: any(named: 'page'), pageSize: any(named: 'pageSize'),),)
        .thenAnswer((_) async => const Right({
              'items': [
                {'sn': 'SN', 'model': 'L10', 'status': 0},
              ],
              'total': 1,
            }),);
    await pumpMinimalApp(tester, const FirmwareLibraryPage());
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('remote-upgrade-7')),)
            .onPressed,
        isNull,);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ambiguous failure retries with same idempotency key',
      (tester) async {
    final keys = <String>[];
    when(() => ota.triggerFirmware(any(), any(),
        idempotencyKey: any(named: 'idempotencyKey'),),).thenAnswer((call) async {
      keys.add(call.namedArguments[#idempotencyKey] as String);
      return const Left(ServerFailure('timeout'));
    });
    await pumpMinimalApp(tester, const FirmwareLibraryPage());
    for (var i = 0; i < 2; i++) {
      await tester
          .ensureVisible(find.byKey(const ValueKey('remote-upgrade-7')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remote-upgrade-7')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '确认'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    }
    expect(keys, hasLength(2));
    expect(keys[0], keys[1]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('English downloaded resources fit 320 width and large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpMinimalApp(tester, const FirmwareLibraryPage(),
        locale: const Locale('en'),);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
