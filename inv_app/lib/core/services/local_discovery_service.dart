import 'package:wifi_iot/wifi_iot.dart';

class DiscoveredDevice {
  final String ssid;
  final int rssi;
  final bool isEncrypted;
  final String? bssid;
  final int? frequency;

  DiscoveredDevice({
    required this.ssid,
    required this.rssi,
    this.isEncrypted = true,
    this.bssid,
    this.frequency,
  });

  bool get isCSInvAP {
    final upper = ssid.toUpperCase();
    return upper.startsWith('CS-INV') || upper.startsWith('CS_INV');
  }

  int get signalLevel {
    if (rssi >= -50) return 4;
    if (rssi >= -60) return 3;
    if (rssi >= -70) return 2;
    return 1;
  }
}

class LocalDiscoveryService {
  Future<List<DiscoveredDevice>> scanCSInvAPs() async {
    try {
      final results = await WiFiForIoTPlugin.loadWifiList();
      if (results.isEmpty) return [];

      final devices = results.map((ap) {
        final ssid = (ap.ssid ?? '').trim();
        final rssi = int.tryParse(ap.level?.toString() ?? '') ?? -100;
        final capabilities = ap.capabilities ?? '';
        final isEncrypted = capabilities.contains('WPA') || capabilities.contains('WEP') || capabilities.contains('PSK');

        return DiscoveredDevice(
          ssid: ssid,
          rssi: rssi,
          isEncrypted: isEncrypted,
          bssid: ap.bssid,
          frequency: int.tryParse(ap.frequency?.toString() ?? ''),
        );
      }).where((d) => d.ssid.isNotEmpty).toList();

      devices.sort((a, b) => b.rssi.compareTo(a.rssi));

      return devices.where((d) => d.isCSInvAP).toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> isConnectedToCSInvAP() async {
    try {
      final ssid = await WiFiForIoTPlugin.getSSID();
      if (ssid == null) return false;
      final upper = ssid.toUpperCase();
      return upper.startsWith('CS-INV') || upper.startsWith('CS_INV');
    } catch (_) {
      return false;
    }
  }

  Future<bool> connectToAP(String ssid, {String? password}) async {
    try {
      final isRegistered = await WiFiForIoTPlugin.isRegisteredWifiNetwork(ssid);
      if (isRegistered == true) {
        return await WiFiForIoTPlugin.findAndConnect(ssid, password: password ?? '');
      }
      return await WiFiForIoTPlugin.connect(ssid, password: password ?? '', withInternet: false);
    } catch (_) {
      return false;
    }
  }

  Future<bool> disconnectFromAP() async {
    try {
      return await WiFiForIoTPlugin.disconnect();
    } catch (_) {
      return false;
    }
  }
}
