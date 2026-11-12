import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/features/device/presentation/pages/modbus_panel_page.dart';

class _PanelSession implements BleDeviceSession {
  final states = StreamController<BleDeviceState>.broadcast();
  BleDeviceState connectionState = BleDeviceState.ready;
  final sample = <String, dynamic>{
    'device_sn': 'PANEL-3KU',
    'online': true,
    'age_ms': 0,
    'updated_at': '2026-11-12T07:00:00Z',
    'pv': {'pv_power': 1860, 'pv_voltage': 185.6},
    'ac': {'power': 1250, 'frequency': 50},
    'battery': {'soc': 72, 'charge_state': 'charging'},
  };

  @override
  String get sn => 'PANEL-3KU';
  @override
  String get macAddress => '00:00:00:00:00:01';
  @override
  String get connectionSessionId => 'local-session';
  @override
  bool get supportsPanelApi => true;
  @override
  bool get isOtaInProgress => false;
  @override
  BleDeviceState get state => connectionState;
  @override
  Stream<BleDeviceState> get stateStream => states.stream;
  @override
  Stream<Map<String, dynamic>> get telemetry => const Stream.empty();

  @override
  Future<Map<String, dynamic>> readTelemetrySnapshot() async => sample;

  @override
  Future<Map<String, dynamic>> sendCommand(
    String action, [
    Map<String, dynamic> params = const {},
  ]) async =>
      {
        'model': '3KU',
        'count': 0,
        'online': true,
        'context': 1,
        'confirmed': true,
        'power_on': false,
        'power_off': true,
      };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('device page switches from parameters to Bluetooth settings',
      (tester) async {
    final session = _PanelSession();
    await tester
        .pumpWidget(MaterialApp(home: ModbusPanelPage(session: session)));
    await tester.pumpAndSettle();

    expect(find.text('3KU'), findsOneWidget);
    expect(find.text('1,860 W'), findsOneWidget);
    expect(find.textContaining('Live Bluetooth data'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Bluetooth settings'));
    await tester.pumpAndSettle();
    expect(find.text('Inverter settings'), findsOneWidget);
    expect(find.text('Panel settings'), findsOneWidget);
    expect(find.text('1,860 W'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await session.states.close();
  });

  testWidgets(
      'a disconnect retains measurements and labels them as last readings',
      (tester) async {
    final session = _PanelSession();
    await tester
        .pumpWidget(MaterialApp(home: ModbusPanelPage(session: session)));
    await tester.pumpAndSettle();

    session.connectionState = BleDeviceState.disconnected;
    session.states.add(BleDeviceState.disconnected);
    await tester.pumpAndSettle();
    expect(find.text('1,860 W'), findsOneWidget);
    expect(find.textContaining('Last readings'), findsOneWidget);
    expect(find.textContaining('Live Bluetooth data'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await session.states.close();
  });

  testWidgets('the settings entry works on a narrow screen with larger text',
      (tester) async {
    final session = _PanelSession();
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: ModbusPanelPage(session: session, startInSettings: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inverter settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await session.states.close();
  });
}
