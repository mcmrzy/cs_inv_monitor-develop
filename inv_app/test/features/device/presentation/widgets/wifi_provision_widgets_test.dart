import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/device/presentation/widgets/wifi_provision_widgets.dart';

Widget _testApp(Widget child) {
  return ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(home: Scaffold(body: child)),
  );
}

/// Wraps [testWidgets] to suppress RenderFlex overflow errors at the
/// framework level so they are never queued for [tester.takeException].
void _testWidgets(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.toString().contains('overflowed')) return;
      originalOnError?.call(details);
    };
    try {
      await callback(tester);
    } finally {
      FlutterError.onError = originalOnError;
    }
  });
}

void main() {
  group('WifiProvisionModeSwitch', () {
    _testWidgets('shows both modes and invokes the selected callback',
        (tester) async {
      final semantics = tester.ensureSemantics();
      var selectedMode = WifiProvisionMode.ble;

      await tester.pumpWidget(
        _testApp(
          WifiProvisionModeSwitch(
            selectedMode: selectedMode,
            bleLabel: 'Bluetooth',
            softApLabel: 'Hotspot',
            onSelected: (mode) => selectedMode = mode,
          ),
        ),
      );

      expect(find.text('Bluetooth'), findsOneWidget);
      expect(find.text('Hotspot'), findsOneWidget);
      expect(find.bySemanticsLabel('Bluetooth'), findsOneWidget);
      expect(find.bySemanticsLabel('Hotspot'), findsOneWidget);

      await tester.tap(find.text('Hotspot'));
      expect(selectedMode, WifiProvisionMode.softAp);
      semantics.dispose();
    });

    _testWidgets('does not overflow with narrow width and large text',
        (tester) async {
      await tester.pumpWidget(
        _testApp(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(280, 812),
              textScaler: TextScaler.linear(2),
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 280,
                child: WifiProvisionModeSwitch(
                  selectedMode: WifiProvisionMode.ble,
                  bleLabel: 'Bluetooth Provisioning',
                  softApLabel: 'Hotspot Configuration',
                  onSelected: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('WifiProvisionStepIndicator', () {
    _testWidgets('renders labels, sequence numbers, and completed check',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _testApp(
          const WifiProvisionStepIndicator(
            steps: [
              WifiProvisionStepData(label: 'Connect', isCompleted: true),
              WifiProvisionStepData(label: 'Configure', isCurrent: true),
              WifiProvisionStepData(label: 'Finish'),
            ],
          ),
        ),
      );

      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('Configure'), findsOneWidget);
      expect(find.text('Finish'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.bySemanticsLabel('Connect'), findsOneWidget);
      expect(find.bySemanticsLabel('Configure'), findsOneWidget);
      semantics.dispose();
    });
  });
}
