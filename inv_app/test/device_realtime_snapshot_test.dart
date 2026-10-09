import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/services/realtime_data_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/features/device/presentation/pages/device_realtime_page.dart';
import 'package:inv_app/features/device/presentation/widgets/energy_dashboard_tabs.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers/pump_app.dart';

class _Bloc extends MockBloc<DeviceEvent, DeviceState> implements DeviceBloc {}

class _Realtime extends Mock implements RealtimeDataService {}

class _Dio extends Mock implements Dio {}

void main() {
  late _Bloc bloc;
  late _Realtime realtime;
  late StreamController<InverterRealtime> samples;
  Map<String, dynamic>? detail;
  Completer<Map<String, dynamic>>? pendingDetail;
  void completeDetail(Map<String, dynamic> value) {
    detail = value;
    pendingDetail?.complete(value);
    pendingDetail = null;
  }

  final time = DateTime.now().toUtc();
  late List<String> paths;

  InverterRealtime sample(int seconds, {double? score, double power = 400}) =>
      InverterRealtime.fromJson({
        'device_sn': 'SN',
        'updated_at': time.add(Duration(seconds: seconds)).toIso8601String(),
        'output_power': power,
        'online': true,
        if (score != null) 'derived': {'health_score': score},
      });

  setUp(() {
    bloc = _Bloc();
    when(() => bloc.state).thenReturn(DeviceInitial());
    realtime = _Realtime();
    samples = StreamController.broadcast();
    when(() => realtime.realtimeDataStream).thenAnswer((_) => samples.stream);
    when(() => realtime.statusStream).thenAnswer((_) => const Stream.empty());
    when(() => realtime.getLatestData('SN')).thenReturn(null);
    detail = null;
    pendingDetail = null;
    paths = [];
    final dio = _Dio();
    when(() => dio.get(any())).thenAnswer((call) async {
      final path = call.positionalArguments.first as String;
      paths.add(path);
      final data = path == '/devices/by-sn/SN'
          ? detail ?? await (pendingDetail = Completer()).future
          : path.endsWith('/statistics')
              ? {'total_energy': 100}
              : <String, dynamic>{};
      return Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {'code': 0, 'data': data});
    });
    getIt.registerSingleton<Dio>(dio);
    getIt.registerSingleton<RealtimeDataService>(realtime);
  });
  tearDown(() async {
    await samples.close();
    await bloc.close();
    await getIt.reset();
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester, const DeviceRealtimePage(sn: 'SN', type: 'inv'),
        deviceBloc: bloc, locale: const Locale('en'));
  }

  Future<DeviceHealthTab> health(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.health_and_safety_outlined));
    await tester.pumpAndSettle();
    return tester.widget<DeviceHealthTab>(find.byType(DeviceHealthTab));
  }

  testWidgets(
      'explicit offline wins over status one; missing bool accepts fault two',
      (tester) async {
    completeDetail({
      'device': {'status': 1},
      'online_status': {'online': false},
      'realtime_data': {'output_power': 0}
    });
    await open(tester);
    expect((await health(tester)).online, false);
    await tester.pumpWidget(const SizedBox());
    completeDetail({
      'device': {'status': 2},
      'realtime_data': {'output_power': 0}
    });
    await open(tester);
    expect((await health(tester)).online, true);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'accepted snapshots replace derived fields and reject older polls',
      (tester) async {
    completeDetail({
      'device': {'status': 1},
      'realtime_data': {
        'output_power': 400,
        'updated_at': time.toIso8601String(),
        'derived': {'health_score': 30},
      }
    });
    await open(tester);
    expect((await health(tester)).flat['derived_health_score'], 30);
    samples.add(sample(1, score: 80));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<DeviceHealthTab>(find.byType(DeviceHealthTab))
            .flat['derived_health_score'],
        80);
    samples.add(sample(2));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<DeviceHealthTab>(find.byType(DeviceHealthTab))
            .flat
            .containsKey('derived_health_score'),
        false);
    samples.add(sample(1, score: 10, power: 10));
    await tester.pumpAndSettle();
    final current =
        tester.widget<DeviceHealthTab>(find.byType(DeviceHealthTab));
    expect(current.data?.ac?.power, 400);
    expect(current.flat.containsKey('derived_health_score'), false);
    await tester.pumpWidget(const SizedBox());
  });

  for (final dated in [true, false]) {
    testWidgets(
        'delayed ${dated ? 'older' : 'undated'} detail cannot replace poll or online state',
        (tester) async {
      when(() => realtime.getLatestData('SN')).thenReturn(sample(0, score: 60));
      await open(tester);
      samples.add(sample(1, score: 80));
      await tester.pumpAndSettle();
      completeDetail({
        'device': {'status': 0},
        'online_status': {'online': false},
        'realtime_data': {
          'output_power': 10,
          if (dated) 'updated_at': time.toIso8601String(),
          'derived': {'health_score': 10}
        }
      });
      await tester.pumpAndSettle();
      final current = await health(tester);
      expect(current.online, true);
      expect(current.data?.ac?.power, 400);
      expect(current.flat['derived_health_score'], 80);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'production page wires server statistics to cumulative energy card',
      (tester) async {
    completeDetail({
      'device': {'status': 1},
      'realtime_data': {'total_pv_energy': 0}
    });
    await open(tester);
    await tester.tap(find.byIcon(Icons.insights_outlined));
    await tester.pumpAndSettle();
    expect(paths, contains('/devices/by-sn/SN/statistics'));
    expect(find.text('100.0 kWh'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
