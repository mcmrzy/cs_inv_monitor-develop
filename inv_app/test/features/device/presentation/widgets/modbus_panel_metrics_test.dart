import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/device/presentation/widgets/modbus_panel_metrics.dart';

void main() {
  testWidgets('readings remain legible on narrow screens with large text',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              child: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: const ModbusPanelMetrics(
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
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
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
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('60 A'), findsOneWidget);
    expect(find.text('70 A'), findsOneWidget);
  });
}
