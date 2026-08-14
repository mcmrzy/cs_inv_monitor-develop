// wifi_scan 插件升级约束：
// 1. 当前 ^0.4.1+2 已是最新版（作者 18 个月停更），无替代品，API 34 下稳定运行；
// 2. 该插件应用 Kotlin Gradle Plugin（KGP），构建时会产生 KGP 警告（仅构建日志，不阻塞构建）；
// 3. 自研 MethodChannel 替换需处理 Android 12+ NEARBY_WIFI 权限迁移，风险>收益；
// 4. 待 AGP 9 升级立项时一并评估 fork 迁移，切勿单独升级 Android Gradle Plugin 至 AGP 9。
import 'package:wifi_scan/wifi_scan.dart';

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

  factory ScannedWifiNetwork.fromAccessPoint(WiFiAccessPoint accessPoint) {
    return ScannedWifiNetwork(
      ssid: accessPoint.ssid,
      bssid: accessPoint.bssid,
      capabilities: accessPoint.capabilities,
      level: accessPoint.level,
      frequency: accessPoint.frequency,
    );
  }
}

/// Starts a platform Wi-Fi scan when allowed, then returns the latest cached
/// results. Permission/service failures are represented by an empty list so
/// callers can keep their existing localized error handling.
Future<List<ScannedWifiNetwork>> scanWifiNetworks({
  bool triggerScan = true,
}) async {
  final scanner = WiFiScan.instance;
  if (triggerScan) {
    final canStart = await scanner.canStartScan();
    if (canStart == CanStartScan.yes) {
      await scanner.startScan();
    }
  }

  final canRead = await scanner.canGetScannedResults();
  if (canRead != CanGetScannedResults.yes) {
    return const [];
  }
  final accessPoints = await scanner.getScannedResults();
  return accessPoints.map(ScannedWifiNetwork.fromAccessPoint).toList();
}
