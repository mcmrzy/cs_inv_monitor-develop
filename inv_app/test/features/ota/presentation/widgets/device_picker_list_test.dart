import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/features/ota/presentation/widgets/device_picker_list.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mock_providers.dart';
import '../../../../helpers/pump_app.dart';

class _ReadTrackingMap extends MapBase<String, dynamic> {
  _ReadTrackingMap(this._values);

  final Map<String, dynamic> _values;
  int readCount = 0;

  @override
  dynamic operator [](Object? key) {
    readCount += 1;
    return _values[key];
  }

  @override
  void operator []=(String key, dynamic value) => _values[key] = value;

  @override
  void clear() => _values.clear();

  @override
  Iterable<String> get keys => _values.keys;

  @override
  dynamic remove(Object? key) => _values.remove(key);
}

void main() {
  late MockDeviceBloc deviceBloc;

  setUp(() {
    deviceBloc = MockDeviceBloc();
    when(() => deviceBloc.stream)
        .thenAnswer((_) => const Stream<DeviceState>.empty());
  });

  Future<void> pumpPicker(
    WidgetTester tester,
    List<dynamic> devices, {
    ValueChanged<Map<String, dynamic>>? onSelected,
    bool showCapabilities = false,
    String? hint,
  }) async {
    when(() => deviceBloc.state).thenReturn(
      DeviceListLoaded(devices: devices, total: devices.length),
    );

    await pumpApp(
      tester,
      DevicePickerList(
        onSelected: onSelected ?? (_) {},
        showCapabilities: showCapabilities,
        hint: hint,
      ),
      deviceBloc: deviceBloc,
    );
  }

  testWidgets('initial frame only reads device rows near the viewport',
      (tester) async {
    final devices = List.generate(
      200,
      (index) => _ReadTrackingMap({
        'sn': 'SN-${index.toString().padLeft(3, '0')}',
        'name': 'Device $index',
        'model': 'CS-L10-6K2',
        'firmware_version': '1.0.$index',
        'status': 1,
      }),
    );

    await pumpPicker(tester, devices);

    expect(devices[150].readCount, 0);
    expect(find.text('Device 150'), findsNothing);
    verify(
      () => deviceBloc.add(const DeviceListRequested(pageSize: 200)),
    ).called(1);
  });

  testWidgets('scrolling lazily builds later device rows', (tester) async {
    final devices = List.generate(
      200,
      (index) => _ReadTrackingMap({
        'sn': 'SN-${index.toString().padLeft(3, '0')}',
        'name': 'Device $index',
        'model': 'CS-L10-6K2',
        'status': 1,
      }),
    );

    await pumpPicker(tester, devices);
    expect(devices[100].readCount, 0);
    final verticalScrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable &&
          widget.axisDirection == AxisDirection.down,
    );

    await tester.scrollUntilVisible(
      find.text('Device 100'),
      600,
      scrollable: verticalScrollable,
    );
    await tester.pumpAndSettle();

    expect(find.text('Device 100'), findsOneWidget);
    expect(devices[100].readCount, greaterThan(0));
  });

  testWidgets('keeps search, hint, capabilities, order, and tap payload',
      (tester) async {
    final devices = <Map<String, dynamic>>[
      {
        'sn': 'INV-001',
        'name': 'First inverter',
        'model': 'CS-L10-6K2',
        'firmware_version': '1.2.3',
        'status': 1,
      },
      {
        'sn': 'INV-002',
        'name': 'Second inverter',
        'model': 'CS-INV-A1',
        'status': 0,
      },
    ];
    Map<String, dynamic>? selected;
    final l10n =
        await AppLocalizations.delegate.load(const Locale('zh', 'CN'));

    await pumpPicker(
      tester,
      devices,
      onSelected: (device) => selected = device,
      showCapabilities: true,
      hint: 'Choose one device',
    );

    expect(find.text('Choose one device'), findsOneWidget);
    expect(find.text('BLE'), findsOneWidget);
    expect(find.text('WiFi'), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('First inverter')).dy,
      lessThan(tester.getTopLeft(find.text('Second inverter')).dy),
    );

    await tester.enterText(find.byType(TextField), '  inv-002  ');
    await tester.pumpAndSettle();

    expect(find.text('First inverter'), findsNothing);
    expect(find.text('Second inverter'), findsOneWidget);
    await tester.tap(find.text('Second inverter'));
    expect(selected, equals(devices[1]));
    expect(identical(selected, devices[1]), isFalse);

    await tester.enterText(find.byType(TextField), 'not-found');
    await tester.pumpAndSettle();

    expect(find.text(l10n.noSearchResults), findsOneWidget);
    expect(find.text('Choose one device'), findsOneWidget);
  });
}
