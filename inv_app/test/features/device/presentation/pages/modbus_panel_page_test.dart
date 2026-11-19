import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/features/device/presentation/pages/modbus_panel_aux_page.dart';
import 'package:inv_app/features/device/presentation/pages/modbus_panel_page.dart';

class _PanelSession implements BleDeviceSession {
  _PanelSession({this.multipleCategories = false});

  final bool multipleCategories;
  final states = StreamController<BleDeviceState>.broadcast();
  BleDeviceState connectionState = BleDeviceState.ready;
  int value = 24;
  Future<void>? secondSettingGate;
  bool writeObserved = true;
  final writes = <Map<String, dynamic>>[];
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
  ]) async {
    switch (action) {
      case 'panel_setting':
        if (multipleCategories && params['index'] == 1) {
          await secondSettingGate;
          return {
            'id': 'panel_4112',
            'label': 'Output frequency',
            'group': 'Output',
            'access': 1,
            'value': 50,
            'text': '50 Hz',
            'context': 1,
          };
        }
        return {
          'id': 'panel_4101',
          'label': 'Charging current',
          'group': 'Battery',
          'access': 0,
          'value': value,
          'text': '$value A',
          'context': 1,
        };
      case 'panel_step':
        return {'value': 25, 'text': '25 A', 'context': 1};
      case 'set_param':
        writes.add(Map<String, dynamic>.from(params));
        if (!writeObserved) return {'submitted': true, 'observed': false};
        value = params['value'] as int;
        return {'observed': true, 'value': value};
      default:
        return {
          'model': '3KU',
          'count': multipleCategories ? 2 : 1,
          'online': true,
          'context': 1,
          'confirmed': true,
          'power_on': false,
          'power_off': true,
        };
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('parallel 6KU configuration is editable in connection settings',
      (tester) async {
    await tester.pumpWidget(ScreenUtilInit(
      builder: (_, __) => MaterialApp(
        home: ModbusPanelStatusPage(
          kind: ModbusPanelStatusKind.diagnostics,
          sendCommand: (_, __) async => {
            'model': '6KU Parallel',
            'detected': '6KU Parallel',
            'profile': 2,
            'context': 1,
            'address': 1,
            'baud': 9600,
            'parity': 0,
            'online': true,
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Edit connection configuration').hitTestable(),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Edit connection configuration'));
    await tester.pumpAndSettle();
    expect(find.text('6KU (parallel)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final stayConnected in [true, false]) {
    testWidgets(
        'large power button confirms before sending connected=$stayConnected',
        (tester) async {
      final session = _PanelSession();
      await tester.pumpWidget(ScreenUtilInit(
        builder: (_, __) =>
            MaterialApp(home: ModbusPanelPage(session: session)),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Device'));
      await tester.pumpAndSettle();
      final start = find.widgetWithText(FilledButton, 'Start');
      final stop = find.widgetWithText(FilledButton, 'Stop');
      expect(tester.widget<FilledButton>(start).onPressed, isNull);
      expect(tester.getSize(stop).height, greaterThanOrEqualTo(124));
      await tester.tap(stop);
      await tester.pumpAndSettle();
      expect(session.writes, isEmpty);
      expect(find.byType(AlertDialog), findsOneWidget);
      if (!stayConnected) {
        session.connectionState = BleDeviceState.disconnected;
        session.states.add(BleDeviceState.disconnected);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.widgetWithText(FilledButton, 'Stop inverter'));
      await tester.pumpAndSettle();
      expect(
        session.writes,
        stayConnected ? [containsPair('param_id', 'panel_4123')] : isEmpty,
      );
      if (stayConnected) expect(session.writes.single['value'], 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await session.states.close();
    });
  }

  testWidgets('full readings switch category without showing another group',
      (tester) async {
    final battery = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(ScreenUtilInit(
      builder: (_, __) => MaterialApp(
          home: ModbusPanelStatusPage(
        kind: ModbusPanelStatusKind.metrics,
        sendCommand: (_, params) async => params['page'] == 1
            ? battery.future
            : {
                'rows': [
                  ['Grid voltage', '230 V'],
                ],
              },
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('230 V'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Battery and charging'));
    await tester.pump();
    expect(find.text('230 V'), findsNothing);
    battery.complete({
      'rows': [
        ['Battery voltage', '25.8 V*'],
      ],
    });
    await tester.pumpAndSettle();
    expect(find.text('25.8 V'), findsOneWidget);
    expect(find.text('Last reading'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('device page switches from parameters to Bluetooth settings',
      (tester) async {
    final session = _PanelSession();
    await tester.pumpWidget(ScreenUtilInit(
        builder: (_, __) =>
            MaterialApp(home: ModbusPanelPage(session: session))));
    await tester.pumpAndSettle();

    expect(find.text('3KU'), findsOneWidget);
    expect(find.text('1,860 W'), findsWidgets);
    expect(find.textContaining('Live Bluetooth data'), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Inverter settings'), findsOneWidget);
    expect(find.text('Charging current'), findsOneWidget);
    expect(find.text('Read device'), findsOneWidget);
    expect(find.text('1,860 W'), findsNothing);
    await tester.tap(find.text('Device'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Wi-Fi setup').hitTestable(),
      120,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Wi-Fi setup'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await session.states.close();
  });

  for (final observed in [true, false]) {
    testWidgets(
        'Bluetooth settings distinguish readback from submission $observed',
        (tester) async {
      final session = _PanelSession()..writeObserved = observed;
      await tester.pumpWidget(ScreenUtilInit(
        builder: (_, __) => MaterialApp(
          home: ModbusPanelPage(session: session, startInSettings: true),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Charging current').hitTestable(),
        120,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Charging current'));
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      expect(find.descendant(of: dialog, matching: find.text('Current value')),
          findsOneWidget);
      await tester.tap(find.byTooltip('Increase'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: dialog, matching: find.text('Target value')),
          findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('25 A')),
          findsOneWidget);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(
          find.text(observed ? 'Verified by readback' : 'Accepted by inverter'),
          findsOneWidget);
      expect(
          find.descendant(
              of: dialog, matching: find.text(observed ? '25 A' : '24 A')),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await session.states.close();
    });
  }

  testWidgets(
      'a disconnect retains measurements and labels them as last readings',
      (tester) async {
    final session = _PanelSession();
    await tester.pumpWidget(ScreenUtilInit(
        builder: (_, __) =>
            MaterialApp(home: ModbusPanelPage(session: session))));
    await tester.pumpAndSettle();

    session.connectionState = BleDeviceState.disconnected;
    session.states.add(BleDeviceState.disconnected);
    await tester.pumpAndSettle();
    expect(find.text('1,860 W'), findsWidgets);
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
      ScreenUtilInit(
        builder: (_, __) => MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: ModbusPanelPage(session: session, startInSettings: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inverter settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await session.states.close();
  });

  testWidgets('Bluetooth settings focus one category and search across groups',
      (tester) async {
    final session = _PanelSession(multipleCategories: true);
    await tester.pumpWidget(
      ScreenUtilInit(
        builder: (_, __) => MaterialApp(
          home: ModbusPanelPage(session: session, startInSettings: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Parameter categories'), findsOneWidget);
    expect(find.text('Charging current'), findsNothing);
    await tester.tap(find.text('Battery'));
    await tester.pumpAndSettle();
    expect(find.text('Charging current'), findsOneWidget);
    expect(find.text('Output frequency'), findsNothing);

    await tester.tap(find.text('All categories'));
    await tester.pumpAndSettle();
    expect(find.text('Output'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'frequency');
    await tester.pumpAndSettle();
    expect(find.text('Output frequency'), findsOneWidget);
    expect(find.text('Charging current'), findsNothing);
    expect(session.writes, isEmpty);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await session.states.close();
  });

  testWidgets('reading settings preserves the current view until the read ends',
      (tester) async {
    final session = _PanelSession(multipleCategories: true);
    await tester.pumpWidget(
      ScreenUtilInit(
        builder: (_, __) => MaterialApp(
          home: ModbusPanelPage(session: session, startInSettings: true),
        ),
      ),
    );
    addTearDown(session.states.close);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Battery'));
    await tester.pumpAndSettle();

    final read = find.widgetWithText(OutlinedButton, 'Read device');
    final position = tester.getRect(read);
    final pending = Completer<void>();
    session.secondSettingGate = pending.future;
    session.value = 27;
    await tester.tap(read);
    await tester.pump();

    expect(find.text('24 A'), findsOneWidget);
    expect(find.text('27 A'), findsNothing);
    expect(tester.getRect(read), position);
    expect(tester.widget<OutlinedButton>(read).onPressed, isNull);

    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('24 A'), findsNothing);
    expect(find.text('27 A'), findsOneWidget);
    expect(tester.getRect(read), position);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
