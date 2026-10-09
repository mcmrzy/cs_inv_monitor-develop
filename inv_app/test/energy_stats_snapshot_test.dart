import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/features/device/presentation/widgets/energy_dashboard_tabs.dart';

import 'helpers/pump_app.dart';

void main() {
  testWidgets(
      'partial energy sample keeps missing values unavailable and zero visible',
      (tester) async {
    final sample = InverterRealtime.fromJson({'daily_pv_energy': 0});
    await pumpMinimalApp(tester, Scaffold(body: EnergyStatsTab(data: sample)));
    expect(find.text('0.0 kWh'), findsOneWidget);
    expect(find.text('--'), findsWidgets);
    expect(find.text('0 kg'), findsNothing);
  });

  testWidgets(
      'server cumulative total survives a reset counter without summing',
      (tester) async {
    for (final counter in [0.0, 80.0, 120.0]) {
      await pumpMinimalApp(
          tester,
          Scaffold(
              body: EnergyStatsTab(
                  data: InverterRealtime.fromJson({'total_pv_energy': counter}),
                  recordedTotalPV: 100)));
      expect(
          find.text('${counter > 100 ? counter : 100.0} kWh'), findsOneWidget);
      if (counter > 0) expect(find.text('${counter + 100} kWh'), findsNothing);
    }
  });

  testWidgets('invalid totals stay missing and a genuine zero stays zero',
      (tester) async {
    for (final invalid in [-1.0, double.nan, double.infinity]) {
      await pumpMinimalApp(tester,
          Scaffold(body: EnergyStatsTab(data: null, recordedTotalPV: invalid)));
      expect(find.text('--'), findsWidgets);
      expect(find.textContaining('NaN'), findsNothing);
      expect(find.text('0.0 kWh'), findsNothing);
    }
    await pumpMinimalApp(tester,
        const Scaffold(body: EnergyStatsTab(data: null, recordedTotalPV: 0)));
    expect(find.text('0.0 kWh'), findsOneWidget);
    expect(find.text('0 kg'), findsOneWidget);
  });

  testWidgets(
      'zero subcounters remain visible and load aliases retain readings',
      (tester) async {
    await pumpMinimalApp(
        tester,
        Scaffold(
            body: EnergyStatsTab(
                data: InverterRealtime.fromJson({
          'gen_energy_daily': 0,
          'output_energy_daily': 2,
          'output_energy_total': 12,
        }))));
    expect(find.text('0.0 kWh'), findsOneWidget);
    expect(find.text('2.0 kWh'), findsNWidgets(2));
    expect(find.text('12.0 kWh'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
