import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/ble/ble_direct_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/features/profile/presentation/pages/offline_mode_settings_page.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mock_providers.dart';
import '../../../../helpers/pump_app.dart';

class _Manager extends Mock implements BleDeviceManager {}

class _DirectService extends Mock implements BleDirectService {}

void main() {
  late _Manager manager;
  late _DirectService direct;
  late MockStorageService storage;

  setUp(() {
    getIt.pushNewScope();
    manager = _Manager();
    direct = _DirectService();
    storage = MockStorageService();
    when(() => manager.sessions).thenReturn({});
    when(() => manager.readyPanelFor(any())).thenReturn(null);
    when(() => manager.sessionOf(any())).thenReturn(null);
    when(() => storage.getIsBleAutoConnect()).thenAnswer((_) async => true);
    when(() => storage.getBlePollInterval()).thenAnswer((_) async => 180);
    when(() => storage.getIsOfflineMode()).thenAnswer((_) async => false);
    when(() => storage.getDirectConnectedDevices()).thenAnswer((_) async => {});
    when(() => direct.scanResults).thenReturn(const [
      BleDiscoveredDevice(macAddress: '01', name: 'CS_INV_3KU-001'),
      BleDiscoveredDevice(macAddress: '02', name: 'CS_INV_3KU-002'),
    ]);
    when(() => direct.scanResultsStream)
        .thenAnswer((_) => const Stream.empty());
    getIt.registerSingleton<BleDeviceManager>(manager);
    getIt.registerSingleton<BleDirectService>(direct);
    getIt.registerSingleton<StorageService>(storage);
  });
  tearDown(() => getIt.popScope());

  testWidgets(
      'target connection only shows the matching device and a scan action',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    when(() => storage.getIsBleDirectEnabled()).thenAnswer((_) async => true);
    await pumpMinimalApp(
      tester,
      const OfflineModeSettingsPage(expectedSn: '3KU-001'),
    );

    expect(find.text('目标设备'), findsOneWidget);
    expect(find.text('3KU-002'), findsNothing);
    expect(find.text('连接设备').hitTestable(), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bluetooth-discovery-action')));
    verify(() => direct.rescan()).called(1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Bluetooth off exposes the enable action and hides discovered rows',
      (tester) async {
    when(() => storage.getIsBleDirectEnabled()).thenAnswer((_) async => false);
    await pumpMinimalApp(tester, const OfflineModeSettingsPage());
    expect(find.text('蓝牙直连已关闭'), findsOneWidget);
    expect(find.text('开启蓝牙直连').hitTestable(), findsOneWidget);
    expect(find.text('3KU-001'), findsNothing);
  });

  testWidgets('compact discovery row opens only the selected device',
      (tester) async {
    when(() => storage.getIsBleDirectEnabled()).thenAnswer((_) async => true);
    when(() => manager.connectDevice('02', autoReconnect: false)).thenThrow(
      const BleCommandException('NOT_READY', 'Device not ready'),
    );
    await pumpMinimalApp(tester, const OfflineModeSettingsPage());

    expect(find.byTooltip('连接设备'), findsNWidgets(2));
    await tester.tap(find.text('3KU-002'));
    await tester.pumpAndSettle();

    verify(() => manager.connectDevice('02', autoReconnect: false)).called(1);
    verifyNever(() => manager.connectDevice('01', autoReconnect: false));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
