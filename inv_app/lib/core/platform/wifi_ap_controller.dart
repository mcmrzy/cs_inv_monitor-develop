import 'package:flutter/foundation.dart';
import 'package:wifi_iot/wifi_iot.dart' as wifi_iot;

import 'package:inv_app/core/platform/app_platform.dart';

/// WiFi 安全类型（与 wifi_iot 的 NetworkSecurity 解耦）
enum AppWifiSecurity { none, wpa, wep }

/// WiFi 热点控制抽象：开关、连接、强制走 WiFi、读当前 SSID。
///
/// 上层（本地 OTA / 配网 / 逆变器连接监控）只依赖本接口；
/// Android 实现委托 wifi_iot，其它平台返回不支持。
abstract class WifiApController {
  /// 当前平台是否具备完整热点控制能力
  bool get isSupported;

  Future<bool> isEnabled();

  /// 请求开启 WiFi；Android 10+ 可跳转系统设置页
  Future<bool> setEnabled(bool enable, {bool shouldOpenSettings = false});

  /// 加入指定 SSID
  Future<bool> connect(
    String ssid, {
    String? password,
    AppWifiSecurity security = AppWifiSecurity.none,
    bool joinOnce = true,
    bool withInternet = false,
    bool isHidden = false,
    int timeoutInSeconds = 30,
  });

  /// 系统是否已保存该 SSID（Android）
  Future<bool> isRegistered(String ssid);

  /// 优先复用系统已保存网络连接（Android）
  Future<bool> findAndConnect(String ssid, {String password = ''});

  Future<bool> disconnect();

  /// 强制 HTTP 流量走 WiFi（Android 侧绑定蜂窝/WiFi 分流时必需）
  Future<void> forceWifiUsage(bool force);

  Future<String?> get currentSsid;

  /// 系统 WiFi 是否已连接（任意网络）
  Future<bool> isConnected();

  static WifiApController _instance = _create();

  static WifiApController get instance => _instance;

  @visibleForTesting
  static set instance(WifiApController value) => _instance = value;

  static WifiApController _create() {
    if (PlatformCapabilities.canJoinWifiAp) {
      return AndroidWifiApController();
    }
    return UnsupportedWifiApController();
  }
}

/// Android：委托 wifi_iot（third_party 打补丁版本）
class AndroidWifiApController implements WifiApController {
  @override
  bool get isSupported => true;

  @override
  Future<bool> isEnabled() async {
    try {
      return await wifi_iot.WiFiForIoTPlugin.isEnabled();
    } catch (e) {
      debugPrint('[WifiAp] isEnabled failed: $e');
      return false;
    }
  }

  @override
  Future<bool> setEnabled(
    bool enable, {
    bool shouldOpenSettings = false,
  }) async {
    try {
      await wifi_iot.WiFiForIoTPlugin.setEnabled(
        enable,
        shouldOpenSettings: shouldOpenSettings,
      );
      return true;
    } catch (e) {
      debugPrint('[WifiAp] setEnabled failed: $e');
      return false;
    }
  }

  @override
  Future<bool> connect(
    String ssid, {
    String? password,
    AppWifiSecurity security = AppWifiSecurity.none,
    bool joinOnce = true,
    bool withInternet = false,
    bool isHidden = false,
    int timeoutInSeconds = 30,
  }) async {
    try {
      return await wifi_iot.WiFiForIoTPlugin.connect(
        ssid,
        password: password,
        security: _mapSecurity(security),
        joinOnce: joinOnce,
        withInternet: withInternet,
        isHidden: isHidden,
        timeoutInSeconds: timeoutInSeconds,
      );
    } catch (e) {
      debugPrint('[WifiAp] connect($ssid) failed: $e');
      return false;
    }
  }

  @override
  Future<bool> isRegistered(String ssid) async {
    try {
      return await wifi_iot.WiFiForIoTPlugin.isRegisteredWifiNetwork(ssid);
    } catch (e) {
      debugPrint('[WifiAp] isRegistered failed: $e');
      return false;
    }
  }

  @override
  Future<bool> findAndConnect(String ssid, {String password = ''}) async {
    try {
      return await wifi_iot.WiFiForIoTPlugin.findAndConnect(
        ssid,
        password: password,
      );
    } catch (e) {
      debugPrint('[WifiAp] findAndConnect($ssid) failed: $e');
      return false;
    }
  }

  @override
  Future<bool> disconnect() async {
    try {
      return await wifi_iot.WiFiForIoTPlugin.disconnect();
    } catch (e) {
      debugPrint('[WifiAp] disconnect failed: $e');
      return false;
    }
  }

  @override
  Future<void> forceWifiUsage(bool force) async {
    try {
      await wifi_iot.WiFiForIoTPlugin.forceWifiUsage(force);
    } catch (_) {
      // 与历史行为一致：失败不阻断业务
    }
  }

  @override
  Future<String?> get currentSsid async {
    try {
      return await wifi_iot.WiFiForIoTPlugin.getSSID();
    } catch (e) {
      debugPrint('[WifiAp] getSSID failed: $e');
      return null;
    }
  }

  @override
  Future<bool> isConnected() async {
    try {
      return await wifi_iot.WiFiForIoTPlugin.isConnected();
    } catch (e) {
      debugPrint('[WifiAp] isConnected failed: $e');
      return false;
    }
  }

  wifi_iot.NetworkSecurity _mapSecurity(AppWifiSecurity security) {
    switch (security) {
      case AppWifiSecurity.none:
        return wifi_iot.NetworkSecurity.NONE;
      case AppWifiSecurity.wpa:
        return wifi_iot.NetworkSecurity.WPA;
      case AppWifiSecurity.wep:
        return wifi_iot.NetworkSecurity.WEP;
    }
  }
}

/// iOS / 鸿蒙等：能力不支持时静默降级，调用方应先查 [PlatformCapabilities]
class UnsupportedWifiApController implements WifiApController {
  @override
  bool get isSupported => false;

  @override
  Future<bool> isEnabled() async => false;

  @override
  Future<bool> setEnabled(
    bool enable, {
    bool shouldOpenSettings = false,
  }) async {
    return false;
  }

  @override
  Future<bool> connect(
    String ssid, {
    String? password,
    AppWifiSecurity security = AppWifiSecurity.none,
    bool joinOnce = true,
    bool withInternet = false,
    bool isHidden = false,
    int timeoutInSeconds = 30,
  }) async {
    debugPrint('[WifiAp] connect unsupported on ${AppPlatform.os.name}: $ssid');
    return false;
  }

  @override
  Future<bool> isRegistered(String ssid) async => false;

  @override
  Future<bool> findAndConnect(String ssid, {String password = ''}) async {
    return false;
  }

  @override
  Future<bool> disconnect() async => true;

  @override
  Future<void> forceWifiUsage(bool force) async {}

  @override
  Future<String?> get currentSsid async => null;

  @override
  Future<bool> isConnected() async => false;
}
