import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/platform/wifi_ap_controller.dart';
import 'package:wifi_iot/wifi_iot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('wifi_iot');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final security in AppWifiSecurity.values) {
    test('connect preserves native ${security.name} security and arguments',
        () async {
      MethodCall? connectCall;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'isEnabled') return true;
        connectCall = call;
        return true;
      });

      final result = await AndroidWifiApController().connect(
        'CS-INV-test',
        password: 'test-password',
        security: security,
        joinOnce: false,
        withInternet: false,
        isHidden: true,
        timeoutInSeconds: 8,
      );

      expect(result, isTrue);
      expect(connectCall?.method, 'connect');
      expect(connectCall?.arguments, {
        'ssid': 'CS-INV-test',
        'bssid': null,
        'password': 'test-password',
        'join_once': false,
        'with_internet': false,
        'is_hidden': true,
        'timeout_in_seconds': 8,
        'security': security.name.toUpperCase(),
      });
    });
  }

  test('setEnabled retains null completion and native settings arguments',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'setEnabled');
      expect(call.arguments, {
        'state': true,
        'shouldOpenSettings': true,
      });
      return true;
    });

    final result = await WiFiForIoTPlugin.setEnabled(
      true,
      shouldOpenSettings: true,
    );
    expect(result, isNull);
  });

  test('a missing plugin preserves boolean and nullable fallback values',
      () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw MissingPluginException(),
    );

    expect(await WiFiForIoTPlugin.isEnabled(), isFalse);
    expect(await WiFiForIoTPlugin.disconnect(), isFalse);
    expect(await WiFiForIoTPlugin.getSSID(), isNull);
    expect(await WiFiForIoTPlugin.setEnabled(true), isNull);
  });

  test('platform errors remain observable to callers', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'permission_denied'),
    );

    await expectLater(
      WiFiForIoTPlugin.isEnabled(),
      throwsA(isA<PlatformException>()),
    );
    expect(await AndroidWifiApController().isEnabled(), isFalse);
  });
}
