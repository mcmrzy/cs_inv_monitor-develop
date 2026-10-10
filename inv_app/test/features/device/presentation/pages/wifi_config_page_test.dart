import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/platform/app_platform.dart';
import 'package:inv_app/core/platform/wifi_ap_controller.dart';
import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:inv_app/core/services/connection_mode_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/features/device/presentation/pages/wifi_config_page.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../helpers/pump_app.dart';

class _MockConnectionModeService extends Mock
    implements ConnectionModeService {}

class _MockBleAdapter extends Mock implements BleAdapter {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const scanChannel = MethodChannel('csergy/wifi_scan');
  const wifiChannel = MethodChannel('wifi_iot');
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late WifiApController originalController;
  var associated = false;
  var scanReads = 0;
  var hangScan = false;
  Completer<int>? locationStatus;
  final routeCalls = <bool>[];

  setUp(() async {
    await getIt.reset();
    originalController = WifiApController.instance;
    WifiApController.instance = AndroidWifiApController();
    AppPlatform.debugOverrideOs(AppOs.android);
    associated = false;
    scanReads = 0;
    hangScan = false;
    locationStatus = null;
    routeCalls.clear();
    getIt
        .registerSingleton<ConnectionModeService>(_MockConnectionModeService());
    final adapter = _MockBleAdapter();
    when(() => adapter.stopScan()).thenAnswer((_) async {});
    getIt.registerSingleton<BleAdapter>(adapter);
    messenger.setMockMethodCallHandler(permissions, (call) async {
      switch (call.method) {
        case 'checkPermissionStatus':
          return 0;
        case 'requestPermissions':
          return {
            for (final id in call.arguments as List)
              id: id == Permission.location.value ? 1 : 0,
          };
        case 'checkServiceStatus':
          return locationStatus == null ? 1 : locationStatus!.future;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(wifiChannel, (call) async {
      switch (call.method) {
        case 'isEnabled':
          return true;
        case 'getSSID':
          return associated ? 'CS_INV_TEST' : null;
        case 'connect':
          associated = true;
          return true;
        case 'forceWifiUsage':
          final force = (call.arguments as Map)['useWifi'] as bool;
          routeCalls.add(force);
          if (force && !associated) return Completer<bool>().future;
          return true;
      }
      throw StateError('Unexpected WiFi call: ${call.method}');
    });
    messenger.setMockMethodCallHandler(scanChannel, (call) async {
      switch (call.method) {
        case 'forceWifiUsage':
          final force = (call.arguments as Map)['useWifi'] as bool;
          routeCalls.add(force);
          return !force || associated;
        case 'canStartScan':
        case 'canGetScannedResults':
          return 1;
        case 'startScan':
          return false; // Throttled scans can still read cached results.
        case 'getScannedResults':
          scanReads++;
          if (hangScan) return Completer<List<dynamic>>().future;
          return [
            {'ssid': 'CS_INV_TEST', 'level': -40},
            {'ssid': 'Home WiFi', 'level': -60},
          ];
      }
      throw StateError('Unexpected scan call: ${call.method}');
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(scanChannel, null);
    messenger.setMockMethodCallHandler(wifiChannel, null);
    messenger.setMockMethodCallHandler(permissions, null);
    WifiApController.instance = originalController;
    AppPlatform.debugOverrideOs(null);
    await getIt.reset();
  });

  Future<void> advance(WidgetTester tester, int seconds) async {
    for (var i = 0; i < seconds * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<AppLocalizations> openHotspot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpMinimalApp(tester, const WifiConfigPage());
    final l10n = AppLocalizations.of(
      tester.element(find.byType(WifiConfigPage)),
    )!;
    await tester.tap(find.text(l10n.hotspotProvision));
    await advance(tester, 4);
    return l10n;
  }

  testWidgets('unassociated phone scans, then rescan finishes after WiFi loss',
      (tester) async {
    final l10n = await openHotspot(tester);
    expect(associated, isFalse);
    expect(find.text('CS_INV_TEST'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('CS_INV_TEST'));
    await advance(tester, 4);
    expect(find.text(l10n.scanNearbyWifi), findsOneWidget);
    associated = false;
    await tester.tap(find.text(l10n.scanNearbyWifi));
    await advance(tester, 3);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Home WiFi'), findsOneWidget);

    // A second scan must remain usable after the failed route restore.
    final previousReads = scanReads;
    await tester.tap(find.text(l10n.scanNearbyWifi));
    await advance(tester, 3);
    expect(scanReads, greaterThan(previousReads));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled rescan does not restore routing after a late failure',
      (tester) async {
    final l10n = await openHotspot(tester);
    await tester.tap(find.text('CS_INV_TEST'));
    await advance(tester, 4);
    hangScan = true;
    await tester.tap(find.text(l10n.scanNearbyWifi));
    await advance(tester, 1);
    await tester.tap(find.text(l10n.bleProvision));
    await tester.pump();
    final releases = routeCalls.length;
    await advance(tester, 20);
    expect(routeCalls.skip(releases), isEmpty);
    await tester.tap(find.text(l10n.hotspotProvision));
    hangScan = false;
    await advance(tester, 4);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled permission check cannot rebind WiFi in error cleanup',
      (tester) async {
    final l10n = await openHotspot(tester);
    await tester.tap(find.text('CS_INV_TEST'));
    await advance(tester, 4);
    locationStatus = Completer<int>();
    await tester.tap(find.text(l10n.scanNearbyWifi));
    await tester.pump();
    await tester.tap(find.text(l10n.bleProvision));
    await tester.pump();
    final releases = routeCalls.length;
    locationStatus!.completeError(PlatformException(code: 'cancelled'));
    await tester.pump();
    expect(routeCalls.skip(releases), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
