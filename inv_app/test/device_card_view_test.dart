import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:inv_app/core/widgets/device_list_view.dart';
import 'helpers/pump_app.dart';

void main() {
  final now = DateTime.now().toUtc();
  Map<String, dynamic> fixture() => {
        'sn': 'H1ZZX0013900002H',
        'alias': 'Long inverter name with several words for wrapping',
        'model': 'L10',
        'model_category': 'inverter',
        'rated_power': 10,
        'rated_power_w': 10000,
        'status': 1,
        'current_power': 1234,
        'daily_energy': 12.56,
        'telemetry_updated_at': now.toIso8601String(),
        'station_name': 'Station with a long name',
        'firmware_arm': '1.0.18',
        'bms_summary': {
          'layout': 0,
          'battery_count': 1,
          'bms_online': 1,
          'soc_raw': 805,
          'soc': 80.5,
          'voltage': 51.2,
          'current': -12.0,
          'age_ms': 100,
          'expires_at': now.add(const Duration(seconds: 200)).toIso8601String()
        },
      };

  testWidgets(
      'compact card shows identity, correct units and mapped battery without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    final fontPath = Platform.environment['DEVICE_CARD_PREVIEW_FONT'];
    if (fontPath != null) {
      await tester.runAsync(() async {
        final font = FontLoader('Roboto')
          ..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView));
        await font.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      });
    }
    await pumpMinimalApp(
        tester,
        Scaffold(
            body: RepaintBoundary(
                key: boundary,
                child: ListView(children: [DeviceCard(device: fixture())]))));
    expect(find.text('10.00 kW'), findsOneWidget);
    expect(find.text('1.23 kW'), findsOneWidget);
    expect(find.text('12.56 kWh'), findsOneWidget);
    expect(find.text('SN H1ZZX0013900002H'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('battery-H1ZZX0013900002H')), findsOneWidget);
    expect(tester.takeException(), isNull);
    final path = Platform.environment['DEVICE_CARD_PREVIEW'];
    if (path != null) {
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(path).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });

  testWidgets(
      'same-SN refresh updates values and offline suppresses current power',
      (tester) async {
    final device = fixture();
    await pumpMinimalApp(tester,
        Scaffold(body: DeviceListView(devices: [device], showSearch: false)));
    expect(find.text('1.23 kW'), findsOneWidget);
    await pumpMinimalApp(
        tester,
        Scaffold(
            body: DeviceListView(devices: [
          {...device, 'status': 0, 'daily_energy': 20}
        ], showSearch: false)));
    expect(find.text('20.00 kWh'), findsOneWidget);
    expect(find.text('1.23 kW'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('battery child opens only storage, not parent inverter detail',
      (tester) async {
    var parentOpened = 0;
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(
              body: ListView(children: [DeviceCard(device: fixture())]))),
      GoRoute(
          path: '/device/:sn',
          builder: (_, __) {
            parentOpened++;
            return const Scaffold(body: Text('Parent'));
          }),
      GoRoute(
          path: '/device/:sn/storage',
          builder: (_, __) => const Scaffold(body: Text('Battery detail'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp.router(
                routerConfig: router,
                locale: const Locale('zh'),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate
                ])));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('battery-H1ZZX0013900002H')));
    await tester.tap(find.byKey(const ValueKey('battery-H1ZZX0013900002H')));
    await tester.pumpAndSettle();
    expect(find.text('Battery detail'), findsOneWidget);
    expect(parentOpened, 0);
    expect(tester.takeException(), isNull);
  });
}
