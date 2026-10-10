import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/services/connection_mode_service.dart';
import 'package:inv_app/core/services/network_status_service.dart';
import 'package:inv_app/core/services/realtime_data_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/features/device/presentation/pages/device_realtime_page.dart';
import 'package:inv_app/features/device/presentation/pages/device_storage_page.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';
import 'package:inv_app/features/station/presentation/pages/home_page.dart';
import 'package:inv_app/features/station/presentation/pages/station_detail_page.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../bms_summary_test.dart' show summaryFixture;
import '../../../../helpers/golden_fonts.dart';
import '../../../../helpers/mock_providers.dart';

class _StationEvent extends Fake implements StationEvent {}
class _DeviceEvent extends Fake implements DeviceEvent {}

void main() {
  late MockStationBloc stationBloc;
  late MockDeviceBloc deviceBloc;
  late MockRealtimeDataService realtimeService;
  late MockConnectionModeService mode;
  late Map<String, dynamic> payload;
  final boundary = GlobalKey();
  final station = <String, dynamic>{
    'id': 7, 'station_name': 'Solar Station', 'online_count': 2,
    'timezone': 'Europe/Berlin',
  };

  Map<String, dynamic> battery({bool expired = false}) {
    final now = DateTime.now().toUtc();
    return {...summaryFixture(), 'age_ms': 0, 'warning_flag': 0,
      'protection_flag': 0, 'status_fault_flag': 0,
      'updated_at': now.toIso8601String(),
      'reported_at': now.toIso8601String(),
      'expires_at': now.add(Duration(seconds: expired ? -1 : 210)).toIso8601String(),
    };
  }

  Map<String, dynamic> device(String sn, {bool hasBattery = true}) => {
    'sn': sn, 'alias': 'Inverter $sn', 'status': 1,
    'model_category': 'inverter',
    if (hasBattery) 'bms_summary': battery(),
  };

  Future<GoRouter> pump(WidgetTester tester, Widget page,
      {int width = 390, double scale = 1, bool dark = false,
       String location = '/source', Locale locale = const Locale('en')}) async {
    tester.view.physicalSize = Size(width.toDouble(), 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final router = GoRouter(initialLocation: location, routes: [
      GoRoute(path: '/source', builder: (_, state) => page),
      GoRoute(path: '/device/:sn/storage', builder: (_, state) =>
          DeviceStoragePage(sn: state.pathParameters['sn']!)),
      GoRoute(path: '/device/:sn/history', builder: (_, state) =>
          Scaffold(body: Text('HISTORY ${state.pathParameters['sn']} ${state.uri.queryParameters['tz']}'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(RepaintBoundary(key: boundary,
      child: MultiBlocProvider(providers: [
        BlocProvider<StationBloc>.value(value: stationBloc),
        BlocProvider<DeviceBloc>.value(value: deviceBloc),
      ], child: ScreenUtilInit(designSize: const Size(375, 812), minTextAdapt: true,
        builder: (_, child) => MaterialApp.router(
          routerConfig: router, locale: locale,
          theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light,
            fontFamily: kGoldenFontFamily, useMaterial3: true),
          localizationsDelegates: const [AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      )),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    return router;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File('build/station_bms_previews/$name.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  setUpAll(() async {
    registerFallbackValue(_StationEvent());
    registerFallbackValue(_DeviceEvent());
    await loadGoldenFonts();
    final loader = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await loader.load();
  });
  setUp(() {
    stationBloc = MockStationBloc();
    deviceBloc = MockDeviceBloc();
    realtimeService = MockRealtimeDataService();
    mode = MockConnectionModeService();
    final network = MockNetworkStatusService();
    when(() => stationBloc.state).thenReturn(StationDetailLoaded(
      stationId: 7, station: station, devices: [device('A'), device('B')]));
    when(() => stationBloc.stream).thenAnswer((_) => const Stream.empty());
    when(() => deviceBloc.state).thenReturn(DeviceInitial());
    when(() => deviceBloc.stream).thenAnswer((_) => const Stream.empty());
    when(() => realtimeService.getLatestData(any())).thenReturn(null);
    when(() => realtimeService.realtimeDataStream).thenAnswer((_) => const Stream.empty());
    when(() => realtimeService.statusStream).thenAnswer((_) => const Stream.empty());
    when(() => realtimeService.alarmStream).thenAnswer((_) => const Stream.empty());
    when(() => mode.isLocal).thenReturn(false);
    when(() => mode.isGuestLocalMode).thenReturn(false);
    when(() => mode.init()).thenAnswer((_) async {});
    when(() => network.isOffline).thenReturn(false);
    when(() => network.statusStream).thenAnswer((_) => const Stream.empty());
    payload = {'bms_summary': battery()};
    final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(requestOptions: options, statusCode: 200,
        data: {'code': 0, 'data': options.path.endsWith('/weather')
          ? {'temp_min': 20, 'temp_max': 25}
          : options.path.endsWith('/realtime') ? {'realtime': payload}
          : {'realtime_data': payload, 'online_status': {'online': true}}}));
    }));
    getIt.registerSingleton<Dio>(dio);
    getIt.registerSingleton<RealtimeDataService>(realtimeService);
    getIt.registerSingleton<ConnectionModeService>(mode);
    getIt.registerSingleton<NetworkStatusService>(network);
  });
  tearDown(() async => getIt.reset());

  testWidgets('station energy metrics fit 320px at large system text scale', (tester) async {
    await pump(tester, const StationDetailPage(stationId: 7), width: 320, scale: 1.8);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('aggregate batteries require explicit owner selection and history preserves owner/timezone', (tester) async {
    final router = await pump(tester, const StationDetailPage(stationId: 7));
    await tester.tap(find.byKey(const ValueKey('station-energy-battery')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(router.routeInformationProvider.value.uri.path, '/source');
    expect(find.byKey(const ValueKey('storage-choice-A')), findsOneWidget);
    expect(find.byKey(const ValueKey('storage-choice-B')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('storage-choice-B')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.widget<DeviceStoragePage>(find.byType(DeviceStoragePage)).sn, 'B');
    await tester.tap(find.byKey(const ValueKey('storage-history')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('HISTORY B Europe/Berlin'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('selected inverter battery opens that owner without a chooser', (tester) async {
    await pump(tester, const StationDetailPage(stationId: 7));
    await tester.tap(find.text('All').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('B').last);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const ValueKey('station-energy-battery')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.widget<DeviceStoragePage>(find.byType(DeviceStoragePage)).sn, 'B');
    expect(find.byKey(const ValueKey('storage-choice-A')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no BMS and collector placeholders never create a battery target', (tester) async {
    when(() => stationBloc.state).thenReturn(StationDetailLoaded(stationId: 7,
      station: station, devices: [device('A', hasBattery: false),
        {...device('C'), 'model_category': 'collector'}]));
    final router = await pump(tester, const StationDetailPage(stationId: 7));
    await tester.tap(find.byKey(const ValueKey('station-energy-battery')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(router.routeInformationProvider.value.uri.path, '/source');
    expect(find.byKey(const ValueKey('storage-choice-C')), findsNothing);
    expect(find.textContaining('No storage battery connected'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('station inverter children deduplicate SNs and do not nest batteries under collectors', (tester) async {
    when(() => stationBloc.state).thenReturn(StationDetailLoaded(stationId: 7,
      station: station, devices: [device('A'), device('A'),
        {...device('C'), 'model_category': 'collector'}]));
    await pump(tester, const StationDetailPage(stationId: 7, initialTab: 2));
    expect(find.byKey(const ValueKey('battery-A')), findsOneWidget);
    expect(find.byKey(const ValueKey('battery-C')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('battery-A')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(DeviceStoragePage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('detail visible history is cloud only', (tester) async {
    await pump(tester, const DeviceRealtimePage(sn: 'B', type: 'inv'));
    expect(find.byKey(const ValueKey('device-detail-history')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('device-detail-history')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('HISTORY B '), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    when(() => mode.isLocal).thenReturn(true);
    await pump(tester, const DeviceRealtimePage(sn: 'B', type: 'inv'));
    expect(find.byIcon(Icons.history_rounded), findsNothing);
    expect(find.byIcon(Icons.battery_charging_full_rounded), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await pump(tester, const DeviceStoragePage(sn: 'B'));
    expect(find.byKey(const ValueKey('storage-history')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [320, 390]) {
    testWidgets('real station action sheet $width large text flat aligned icons', (tester) async {
      when(() => stationBloc.state).thenReturn(StationSummaryLoaded(
        stations: [station], summary: const {}));
      await pump(tester, const HomePage(), width: width, scale: 1.5,
        locale: const Locale('zh'));
      await tester.longPress(find.text('Solar Station'));
      await tester.pump(const Duration(milliseconds: 600));
      final sheet = find.byType(BottomSheet);
      final iconBoxes = tester.widgetList<Container>(find.descendant(
        of: sheet, matching: find.byType(Container))).where((container) =>
          container.constraints?.maxWidth == 44 && container.constraints?.maxHeight == 44).toList();
      expect(iconBoxes, hasLength(5));
      for (final container in iconBoxes) {
        final decoration = container.decoration! as BoxDecoration;
        expect(decoration.gradient, isNull);
        expect(decoration.boxShadow, isNull);
      }
      expect(iconBoxes.map((c) => (c.decoration! as BoxDecoration).color).toSet().length,
        greaterThanOrEqualTo(4));
      await capture(tester, 'station-actions-$width-large');
      await tester.pumpWidget(const SizedBox());
    });

    for (final legacy in [false, true]) {
      testWidgets('real storage $width large text ${legacy ? 'legacy' : 'summary'} navigation', (tester) async {
        if (legacy) payload = {'bms_online': 1, 'bms_soc': 80.5,
          'bms_soh': 98, 'battery_voltage': 51.2, 'battery_current': -12};
        await pump(tester, const DeviceStoragePage(sn: 'B'), width: width,
          scale: 1.5, locale: const Locale('zh'));
        for (var tab = 0; tab < 3; tab++) {
          await tester.tap(find.byKey(ValueKey('bms-tab-$tab')));
          await tester.pump(const Duration(milliseconds: 300));
          await capture(tester, 'storage-${legacy ? 'legacy' : 'summary'}-$width-large-tab$tab');
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
