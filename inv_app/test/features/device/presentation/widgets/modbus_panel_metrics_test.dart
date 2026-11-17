import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/device/presentation/widgets/modbus_panel_metrics.dart';

import '../../../../helpers/pump_app.dart';

void main() {
  for (final width in [360.0, 260.0]) {
    testWidgets(
        'highlighted readings preserve missing and stale values at $width',
        (tester) async {
      await pumpMinimalApp(
          tester,
          Scaffold(
            body: Center(
                child: SizedBox(
              width: width,
              child: const ModbusPanelMetrics(
                emphasizeFirst: true,
                values: [
                  ('Grid voltage', '231.2 V*'),
                  ('Grid input power', '--*'),
                  ('Output voltage', '230.0 V'),
                  ('Output power', '0 W'),
                ],
                staleLabel: 'Last reading',
              ),
            )),
          ));
      expect(find.text('231.2 V'), findsOneWidget);
      expect(find.text('Last reading'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('0 W'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('readings remain legible on narrow screens with large text',
      (tester) async {
    await pumpMinimalApp(
      tester,
      const Scaffold(
        body: Center(
          child: SizedBox(
            width: 280,
            child: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(2)),
              child: ModbusPanelMetrics(
                values: [
                  ('Battery state of charge', '75.2 %'),
                  ('Inverter temperature', '36 C*'),
                  ('Generator voltage', '--*'),
                ],
                staleLabel: 'Last reading',
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('75.2 %'), findsOneWidget);
    expect(find.text('36 C'), findsOneWidget);
    expect(find.text('Last reading'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('current and target values fit inside a parameter dialog',
      (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpMinimalApp(
      tester,
      const Scaffold(
        body: AlertDialog(
          title: Text('Maximum charging current'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: ModbusPanelMetrics(
                values: [
                  ('Current value', '60 A'),
                  ('Target value', '70 A'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('60 A'), findsOneWidget);
    expect(find.text('70 A'), findsOneWidget);
  });
}
