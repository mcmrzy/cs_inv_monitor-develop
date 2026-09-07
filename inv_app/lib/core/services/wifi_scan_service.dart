// WiFi 扫描封装层（自研 MethodChannel 实现，替代停更的 wifi_scan 0.4.1+2 插件）：
// 1. 原插件作者 18 个月停更，且应用 Kotlin Gradle Plugin（KGP），Flutter 3.44+ 产生
//    KGP 构建警告，未来 Flutter 版本将直接构建失败；
// 2. 本项目仅用到 4 个方法 + 5 个字段，故在 WifiScanPlugin.kt 以等价实现替代，
//    页面层接口（scanWifiNetworks / ScannedWifiNetwork）保持不变，调用点零改动；
// 3. 原生侧权限检查沿用原插件语义（0=不支持, 1=可以, 2=缺位置权限, 5=位置服务未开启），
//    权限请求仍由页面层 permission_handler 统一负责；
// 4. 本封装增加 8 秒超时兜底：插件/系统扫描挂起时返回空列表，避免"扫描不到一直扫"。
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ScannedWifiNetwork {
  final String? ssid;
  final String? bssid;
  final String? capabilities;
  final int? level;
  final int? frequency;

  const ScannedWifiNetwork({
    this.ssid,
    this.bssid,
    this.capabilities,
    this.level,
    this.frequency,
  });

  factory ScannedWifiNetwork.fromMap(Map<dynamic, dynamic> map) {
    return ScannedWifiNetwork(
      ssid: map['ssid'] as String?,
      bssid: map['bssid'] as String?,
      capabilities: map['capabilities'] as String?,
      level: map['level'] as int?,
      frequency: map['frequency'] as int?,
    );
  }
}

/// 自研原生 WiFi 扫描通道（WifiScanPlugin.kt）
const _wifiScanChannel = MethodChannel('csergy/wifi_scan');

/// 返回码（与原生侧保持一致）
const _kCanYes = 1;

/// 单次扫描整体超时：系统扫描（4 次/2 分钟节流）或权限弹窗异常时防止无限等待
const _kScanTimeout = Duration(seconds: 8);

/// Starts a platform Wi-Fi scan when allowed, then returns the latest cached
/// results. Permission/service failures are represented by an empty list so
/// callers can keep their existing localized error handling.
Future<List<ScannedWifiNetwork>> scanWifiNetworks({
  bool triggerScan = true,
}) async {
  if (!Platform.isAndroid) return const [];
  try {
    if (triggerScan) {
      final canStart = await _wifiScanChannel
          .invokeMethod<int>('canStartScan')
          .timeout(_kScanTimeout);
      if (canStart == _kCanYes) {
        await _wifiScanChannel
            .invokeMethod<bool>('startScan')
            .timeout(_kScanTimeout);
      }
    }

    final canRead = await _wifiScanChannel
        .invokeMethod<int>('canGetScannedResults')
        .timeout(_kScanTimeout);
    if (canRead != _kCanYes) {
      return const [];
    }

    final results = await _wifiScanChannel
        .invokeMethod<List<dynamic>>('getScannedResults')
        .timeout(_kScanTimeout);
    return (results ?? const [])
        .whereType<Map>()
        .map(ScannedWifiNetwork.fromMap)
        .toList();
  } on TimeoutException {
    debugPrint('wifi_scan_service: 扫描超时，返回空列表（避免无限等待）');
    return const [];
  } on PlatformException catch (e) {
    debugPrint('wifi_scan_service: 扫描失败: ${e.message}');
    return const [];
  } catch (e) {
    debugPrint('wifi_scan_service: 扫描异常: $e');
    return const [];
  }
}
