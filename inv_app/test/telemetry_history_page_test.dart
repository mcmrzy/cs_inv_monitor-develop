import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/device/data/device_telemetry_api.dart';
import 'package:inv_app/features/device/presentation/pages/device_telemetry_history_page.dart';
import 'package:inv_app/features/device/presentation/widgets/telemetry_history_fields.dart';
import 'package:inv_app/features/device/presentation/widgets/energy_dashboard_tabs.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'helpers/pump_app.dart';
import 'helpers/golden_fonts.dart';

class _Dio extends Mock implements Dio {}

ThemeData _previewTheme(bool dark) {
  final base = dark ? AppTheme.dark : AppTheme.light;
  final label =
      base.textTheme.labelLarge!.copyWith(fontFamily: kGoldenFontFamily);
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: kGoldenFontFamily),
    primaryTextTheme:
        base.primaryTextTheme.apply(fontFamily: kGoldenFontFamily),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: base.appBarTheme.titleTextStyle
          ?.copyWith(fontFamily: kGoldenFontFamily),
    ),
    chipTheme: base.chipTheme.copyWith(
      labelStyle:
          base.chipTheme.labelStyle?.copyWith(fontFamily: kGoldenFontFamily),
    ),
    filledButtonTheme: FilledButtonThemeData(
        style: (base.filledButtonTheme.style ?? const ButtonStyle())
            .copyWith(textStyle: WidgetStatePropertyAll(label))),
  );
}

class _HistoryApi extends DeviceTelemetryApi {
  _HistoryApi() : super(Dio());
  bool fail = false;
  final List<(int, String)> requests = [];

  @override
  Future<DeviceTelemetryPage> getHistory(String sn, DateTime day,
      {int page = 1, int pageSize = 20, String granularity = 'raw'}) async {
    requests.add((page, granularity));
    if (fail) throw Exception('unavailable');
    return DeviceTelemetryPage(total: 21, items: [
      {
        'time': '2026-10-09T02:00:00Z',
        'pv_total_power': 620,
        'output_power': 510,
        'battery_soc': 0,
        'pv1_voltage': 138.6,
        'bms_soc': 78,
        'bms_capacity_remain': 125,
        'bms_mos_temp': -5,
      },
    ]);
  }
}

void main() {
  setUpAll(() async {
    await loadGoldenFonts();
    final previewFont = File('assets/fonts/NotoSansSC-VF.ttf');
    if (await previewFont.exists()) {
      final bytes = await previewFont.readAsBytes();
      final loader = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('saved history fields discard unknown keys and use safe defaults', () {
    expect(validHistoryFields(['obsolete']), commonHistoryFields);
    expect(validHistoryFields(['mppt_state', 'mppt_state', 'obsolete']),
        {'mppt_state'});
  });

  testWidgets(
      'selected BMS history shows engineering units independently of DSP SOC',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'telemetry_history_fields_v1': [
        'battery_soc',
        'bms_soc',
        'bms_capacity_remain',
        'bms_mos_temp'
      ]
    });
    await pumpApp(
        tester, DeviceTelemetryHistoryPage(sn: 'SN', api: _HistoryApi()));
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.text('78.0 %'), findsOneWidget);
    expect(find.text('125.0 Ah'), findsOneWidget);
    expect(find.text('-5.0 C'), findsOneWidget);
    expect(find.text('0.0 %'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final locale in [const Locale('zh'), const Locale('en')]) {
    for (final dark in [false, true]) {
      testWidgets(
          'history field layouts 320px large ${locale.languageCode} dark=$dark',
          (tester) async {
        tester.view.physicalSize = const Size(320, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final boundary = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: ScreenUtilInit(
            designSize: const Size(375, 812),
            minTextAdapt: true,
            builder: (_, child) => MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: locale,
              theme: _previewTheme(dark),
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: DeviceTelemetryHistoryPage(
                  sn: 'H1ZZX0013900002H', api: _HistoryApi()),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(ExpansionTile));
        await tester.pumpAndSettle();
        Future<void> capture(String state) async {
          expect(tester.takeException(), isNull);
          await tester.runAsync(() async {
            final render = boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            final image = await render.toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
                'build/history_previews/${locale.languageCode}-${dark ? 'dark' : 'light'}-$state.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('samples');
        await tester.tap(find.byIcon(Icons.tune_rounded));
        await tester.pumpAndSettle();
        await capture('fields');
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.show_chart_rounded));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('history defaults stay compact and selected fields persist',
      (tester) async {
    final api = _HistoryApi();
    await pumpApp(tester, DeviceTelemetryHistoryPage(sn: 'SN', api: api));
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.text('MPPT 状态'), findsNothing);
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('光伏').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'MPPT');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(find.text('MPPT 状态'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('telemetry_history_fields_v1'),
        contains('mppt_state'));
    await pumpApp(tester, const SizedBox());
    await pumpApp(tester, DeviceTelemetryHistoryPage(sn: 'SN', api: api));
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.text('MPPT 状态'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('canceling field changes preserves saved selection',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'telemetry_history_fields_v1': ['mppt_state']
    });
    await pumpApp(
        tester, DeviceTelemetryHistoryPage(sn: 'SN', api: _HistoryApi()));
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.restart_alt));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('telemetry_history_fields_v1'), ['mppt_state']);
  });

  testWidgets(
      'history chart uses actual telemetry power and preserves zero SOC',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _HistoryApi();
    await pumpApp(tester, DeviceTelemetryHistoryPage(sn: 'SN', api: api));
    await tester.tap(find.byIcon(Icons.show_chart_rounded));
    await tester.pumpAndSettle();
    final pv = tester.widget<LineChart>(find.byType(LineChart));
    expect(pv.data.lineBarsData.single.spots.single.y, 620);
    await tester.tap(find.text('AC (W)'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<LineChart>(find.byType(LineChart))
            .data
            .lineBarsData
            .single
            .spots
            .single
            .y,
        510);
    await tester.tap(find.text('SOC (%)'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<LineChart>(find.byType(LineChart))
            .data
            .lineBarsData
            .single
            .spots
            .single
            .y,
        0);
    expect(tester.takeException(), isNull);
  });
  test('history API uses bounded UTC range, paging and cloud column names',
      () async {
    final dio = _Dio();
    late Map<String, dynamic> query;
    when(() => dio.get<dynamic>(any(),
            queryParameters: any(named: 'queryParameters')))
        .thenAnswer((call) async {
      query = call.namedArguments[#queryParameters] as Map<String, dynamic>;
      return Response(
          requestOptions: RequestOptions(path: '/telemetry'),
          data: {
            'code': 0,
            'data': {
              'items': [
                {
                  'time': '2026-10-09T02:00:00Z',
                  'ac_active_power': 510,
                  'pv_total_power': 620,
                  'battery_soc': null
                }
              ],
              'total': 23
            },
          });
    });
    final day = DateTime(2026, 10, 9);
    final api = DeviceTelemetryApi(dio, timezone: 'Asia/Kolkata');
    final result = await api.getHistory('H1ZZX0013900002H', day, page: 2);
    expect(query['tz'], 'Asia/Kolkata');
    expect(query['start_time'],
        DateTime.utc(2026, 10, 8, 18, 30).toIso8601String());
    expect(
        query['end_time'],
        tz.TZDateTime(api.location, 2026, 10, 10)
            .subtract(const Duration(microseconds: 1))
            .toUtc()
            .toIso8601String());
    expect(query['page'], 2);
    expect(query['granularity'], 'raw');
    expect(query['sort'], 'desc');
    expect(result.total, 23);
    expect(result.items.single['output_power'], 510);
    expect(result.items.single['battery_soc'], isNull);
    await DeviceTelemetryApi(dio, timezone: 'America/New_York')
        .getHistory('SN', DateTime(2026, 3, 8), granularity: 'hour');
    final duration = DateTime.parse(query['end_time'] as String)
        .add(const Duration(microseconds: 1))
        .difference(DateTime.parse(query['start_time'] as String));
    expect(query['tz'], 'America/New_York');
    expect(duration, const Duration(hours: 23));
  });

  testWidgets(
      'server lifetime floor survives device counter reset and missing energy stays unknown',
      (tester) async {
    final data =
        InverterRealtime.fromJson({'total_pv_energy': 0, 'daily_pv_energy': 0});
    await pumpApp(tester,
        Scaffold(body: EnergyStatsTab(data: data, recordedTotalPV: 100)));
    expect(find.text('100.0 kWh'), findsOneWidget);
    expect(find.text('0.0 kWh'), findsOneWidget);
    expect(find.text('--'), findsWidgets);
    expect(find.text('100 kg'), findsOneWidget);
    await pumpApp(
        tester,
        Scaffold(
            body: EnergyStatsTab(
                data: InverterRealtime.fromJson({'total_pv_energy': 120}),
                recordedTotalPV: 100)));
    expect(find.text('120.0 kWh'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('historical values, zero SOC, expansion and page controls',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _HistoryApi();
    await pumpApp(
        tester, DeviceTelemetryHistoryPage(sn: 'H1ZZX0013900002H', api: api));
    expect(find.text('PV 620.0 W'), findsOneWidget);
    expect(find.text('AC 510.0 W'), findsOneWidget);
    expect(find.text('SOC 0.0 %'), findsOneWidget);
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.text('138.6 V'), findsOneWidget);
    expect(find.text('--'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('下一页'));
    await tester.pumpAndSettle();
    expect(api.requests.last.$1, 2);
    await tester.tap(find.text('小时汇总'));
    await tester.pumpAndSettle();
    expect(api.requests.last, (1, 'hour'));
  });

  testWidgets(
      'history request failure is recoverable and not a zero-filled table',
      (tester) async {
    final api = _HistoryApi()..fail = true;
    await pumpApp(tester, DeviceTelemetryHistoryPage(sn: 'SN', api: api));
    expect(find.text('PV 0.0 W'), findsNothing);
    api.fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('PV 620.0 W'), findsOneWidget);
  });

  testWidgets('realtime distinguishes PV1 power, total power and missing PV2',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rt = InverterRealtime.fromJson({
      'pv1_voltage': 138.6,
      'pv1_power': 432,
      'pv_total_power': 620,
      'battery_soc': 0,
    });
    await pumpApp(tester, Scaffold(body: RealtimeDataTab(data: rt)));
    expect(find.text('432.0 W'), findsOneWidget);
    expect(find.text('620.0 W'), findsOneWidget);
    expect(find.text('0.0 W'), findsNothing);
    expect(find.text('--'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
