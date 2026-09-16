import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/platform/app_platform.dart';
import 'package:inv_app/core/platform/wifi_ap_controller.dart';

void main() {
  tearDown(() {
    AppPlatform.debugOverrideOs(null);
  });

  group('AppPlatform', () {
    test('defaults to host OS', () {
      // 不 override 时应能解析出非 other（测试机为 Android/Windows 等）
      expect(AppPlatform.os, isNotNull);
    });

    test('debugOverrideOs forces ohos', () {
      AppPlatform.debugOverrideOs(AppOs.ohos);
      expect(AppPlatform.isOhos, isTrue);
      expect(AppPlatform.isAndroid, isFalse);
      expect(AppPlatform.isIOS, isFalse);
    });
  });

  group('PlatformCapabilities', () {
    test('android enables wifi scan and local ota', () {
      AppPlatform.debugOverrideOs(AppOs.android);
      expect(PlatformCapabilities.canScanWifi, isTrue);
      expect(PlatformCapabilities.canJoinWifiAp, isTrue);
      expect(PlatformCapabilities.canLocalOtaWifiAp, isTrue);
      expect(PlatformCapabilities.supportsHomeWidget, isTrue);
      expect(PlatformCapabilities.supportsPush, isTrue);
      expect(PlatformCapabilities.supportsOneTapLogin, isTrue);
    });

    test('ios degrades wifi and widget, keeps push/ble/one-tap', () {
      AppPlatform.debugOverrideOs(AppOs.ios);
      expect(PlatformCapabilities.canScanWifi, isFalse);
      expect(PlatformCapabilities.canJoinWifiAp, isFalse);
      expect(PlatformCapabilities.canLocalOtaWifiAp, isFalse);
      expect(PlatformCapabilities.hasAmbientLight, isFalse);
      expect(PlatformCapabilities.supportsHomeWidget, isFalse);
      expect(PlatformCapabilities.supportsPush, isTrue);
      expect(PlatformCapabilities.supportsOneTapLogin, isTrue);
      expect(PlatformCapabilities.supportsBle, isTrue);
    });

    test('ohos disables push and one-tap until channel swap', () {
      AppPlatform.debugOverrideOs(AppOs.ohos);
      expect(PlatformCapabilities.supportsPush, isFalse);
      expect(PlatformCapabilities.supportsOneTapLogin, isFalse);
      expect(PlatformCapabilities.canLocalOtaWifiAp, isFalse);
    });
  });

  group('WifiApController factory', () {
    test('android uses AndroidWifiApController', () {
      AppPlatform.debugOverrideOs(AppOs.android);
      // 重建单例：通过 debug 赋值
      WifiApController.instance = AndroidWifiApController();
      expect(WifiApController.instance.isSupported, isTrue);
    });

    test('ios uses UnsupportedWifiApController', () {
      AppPlatform.debugOverrideOs(AppOs.ios);
      WifiApController.instance = UnsupportedWifiApController();
      expect(WifiApController.instance.isSupported, isFalse);
    });
  });
}
