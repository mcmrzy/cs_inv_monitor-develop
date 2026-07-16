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
