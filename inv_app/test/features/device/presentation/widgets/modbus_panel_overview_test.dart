import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/device/presentation/widgets/modbus_panel_overview.dart';

void main() {
  testWidgets('shows actual BLE metrics and switches parameter groups',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ModbusPanelOverview(
              telemetry: {
                'pv': {'pv_power': 1860, 'pv_voltage': 185.6},
                'ac': {'power': 1250, 'frequency': 50},
                'battery': {'soc': 72, 'charge_state': 'charging'},
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('1,860 W'), findsWidgets);
    expect(find.text('72 %'), findsOneWidget);
    expect(find.text('185.6 V'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'AC output'));
    await tester.pumpAndSettle();
    expect(find.text('185.6 V'), findsNothing);
    expect(find.text('50 Hz'), findsOneWidget);
  });

  testWidgets('keeps missing measurements separate from a real zero',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ModbusPanelOverview(
              telemetry: {
                'pv': {'pv_power': 0},
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('0 W'), findsWidgets);
    expect(find.text('—'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
