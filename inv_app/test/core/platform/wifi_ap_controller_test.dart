import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/platform/wifi_ap_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const scanChannel = MethodChannel('csergy/wifi_scan');
  const legacyChannel = MethodChannel('wifi_iot');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(scanChannel, null);
    messenger.setMockMethodCallHandler(legacyChannel, null);
  });

  testWidgets('route selection finishes without an associated WiFi network',
      (tester) async {
    final calls = <bool>[];
    messenger.setMockMethodCallHandler(scanChannel, (call) async {
      expect(call.method, 'forceWifiUsage');
      calls.add((call.arguments as Map)['useWifi'] as bool);
      return false;
    });
    // Models the legacy native requestNetwork call with no onAvailable event.
    final pending = Completer<bool>();
    messenger.setMockMethodCallHandler(
      legacyChannel,
      (_) => pending.future,
    );

    var finished = false;
    final controller = AndroidWifiApController();
    unawaited(controller.forceWifiUsage(true).then((_) => finished = true));
    await tester.pump();
    expect(finished, isTrue);
    await controller.forceWifiUsage(false);
    expect(calls, [true, false]);
  });

  testWidgets('a missing route reply is bounded and release can still run',
      (tester) async {
    final pending = Completer<bool>();
    messenger.setMockMethodCallHandler(scanChannel, (call) {
      return (call.arguments as Map)['useWifi'] == true
          ? pending.future
          : Future.value(true);
    });
    messenger.setMockMethodCallHandler(legacyChannel, (_) => pending.future);

    var finished = false;
    final controller = AndroidWifiApController();
    unawaited(controller.forceWifiUsage(true).then((_) => finished = true));
    await tester.pump();
    await tester.pump(const Duration(seconds: 8));
    expect(finished, isTrue);
    await controller.forceWifiUsage(false);
  });
}
