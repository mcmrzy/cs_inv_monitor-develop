import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// 宿主操作系统（与 Flutter TargetPlatform 区分：这里关心原生壳）
enum AppOs { android, ios, ohos, fuchsia, other }

/// 当前运行平台与能力矩阵。
///
/// UI / 业务层应通过 [PlatformCapabilities] 判断功能是否可用，
/// 不要直接 `Platform.isAndroid` 散落判断——鸿蒙（ohos）接入后
/// 只需在此扩展，调用方零改动。
class AppPlatform {
  AppPlatform._();

  static AppOs? _cached;

  static AppOs get os {
    final cached = _cached;
    if (cached != null) return cached;
    if (kIsWeb) {
      _cached = AppOs.other;
      return _cached!;
    }
    if (Platform.isAndroid) {
      _cached = AppOs.android;
    } else if (Platform.isIOS) {
      _cached = AppOs.ios;
    } else if (Platform.operatingSystem == 'ohos') {
      // OpenHarmony Flutter 的 dart:io 将 OS 标识为 ohos
      _cached = AppOs.ohos;
    } else if (Platform.isFuchsia) {
      _cached = AppOs.fuchsia;
    } else {
      _cached = AppOs.other;
    }
    return _cached!;
  }

  static bool get isAndroid => os == AppOs.android;
  static bool get isIOS => os == AppOs.ios;
  static bool get isOhos => os == AppOs.ohos;

  /// 测试钩子：单元测试可强制指定 OS
  @visibleForTesting
  static void debugOverrideOs(AppOs? value) => _cached = value;
}

/// 功能级能力矩阵：UI 隐藏入口、服务降级的唯一依据。
///
/// 当前策略：
/// - WiFi 扫描 / 热点加入 / 本地 OTA（WiFi AP）：仅 Android
/// - 环境光：仅 Android 自研通道
/// - 桌面小组件：仅 Android（iOS WidgetKit 二期再开）
/// - 推送 / 一键登录：Android + iOS（鸿蒙需换华为通道）
/// - BLE：Android + iOS
class PlatformCapabilities {
  PlatformCapabilities._();

  /// 是否可主动扫描周边 WiFi 列表
  /// iOS 无 NEHotspotHelper 资质时无法枚举；鸿蒙待接入后评估
  static bool get canScanWifi => AppPlatform.isAndroid;

  /// 是否可编程加入指定 WiFi 热点（含 forceWifiUsage）
  static bool get canJoinWifiAp => AppPlatform.isAndroid;

  /// 本地 OTA（WiFi AP 直连设备热点）
  static bool get canLocalOtaWifiAp => canJoinWifiAp && canScanWifi;

  /// 环境光传感器通道
  static bool get hasAmbientLight => AppPlatform.isAndroid;

  /// 桌面小组件
  static bool get supportsHomeWidget => AppPlatform.isAndroid;

  /// 厂商推送（当前 JPush）
  static bool get supportsPush => AppPlatform.isAndroid || AppPlatform.isIOS;

  /// 运营商一键登录（当前 JVerify）
  static bool get supportsOneTapLogin =>
      AppPlatform.isAndroid || AppPlatform.isIOS;

  /// BLE 直连 / 配网
  static bool get supportsBle => AppPlatform.isAndroid || AppPlatform.isIOS;
}
