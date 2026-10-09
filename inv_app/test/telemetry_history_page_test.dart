import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/features/device/data/device_telemetry_api.dart';
import 'package:inv_app/features/device/presentation/pages/device_telemetry_history_page.dart';
import 'package:inv_app/features/device/presentation/widgets/energy_dashboard_tabs.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timezone/timezone.dart' as tz;

import 'helpers/pump_app.dart';

class _Dio extends Mock implements Dio {}

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
        'pv1_voltage': 138.6
      },
    ]);
  }
}

void main() {
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
