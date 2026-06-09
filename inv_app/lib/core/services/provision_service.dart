import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ScanResult {
  final String ssid;
  final int rssi;
  final bool encrypted;

  ScanResult({required this.ssid, required this.rssi, this.encrypted = true});
}

class ProvisionResult {
  final bool success;
  final String message;
  final String? ssid;
  final String? ip;

  ProvisionResult({required this.success, required this.message, this.ssid, this.ip});
}

class ProvisionService {
  static const String _provisionHost = '192.168.4.1';
  static const int _httpTimeout = 5;

  String get baseUrl => 'http://$_provisionHost';

  Future<List<ScanResult>> scanWiFi() async {
    final client = HttpClient();
    client.connectionTimeout = Duration(seconds: _httpTimeout);
    try {
      final request = await client.getUrl(Uri.parse('$baseUrl/scan'));
      final response = await request.close().timeout(Duration(seconds: 8));
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);
        if (data['status'] == 'scanning') {
          await Future.delayed(const Duration(seconds: 3));
          return scanWiFi();
        }
        final networks = data['networks'] as List? ?? [];
        return networks.map((n) => ScanResult(
          ssid: n['ssid'] ?? '',
          rssi: n['rssi'] ?? -100,
          encrypted: (n['enc'] ?? 1) == 1,
        )).toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
      }
    } catch (_) {}
    return [];
  }

  Future<ProvisionResult> configure(String ssid, String password) async {
    final client = HttpClient();
    client.connectionTimeout = Duration(seconds: _httpTimeout);
    try {
      final request = await client.postUrl(Uri.parse('$baseUrl/config'));
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode({'ssid': ssid, 'password': password}));
      final response = await request.close().timeout(Duration(seconds: 10));
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data['result'] == 'ok') {
        return ProvisionResult(success: true, message: data['message'] ?? '配置成功');
      }
      return ProvisionResult(success: false, message: data['message'] ?? '配置失败');
    } catch (e) {
      return ProvisionResult(success: false, message: '请求超时: $e');
    }
  }

  Future<ProvisionResult> configureCompat(String ssid, String password) async {
    final client = HttpClient();
    client.connectionTimeout = Duration(seconds: _httpTimeout);
    try {
      final request = await client.postUrl(Uri.parse('$baseUrl/'));
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode({'cmd': 'set_wifi', 'ssid': ssid, 'password': password}));
      final response = await request.close().timeout(Duration(seconds: 10));
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data['result'] == 'ok') {
        return ProvisionResult(success: true, message: data['message'] ?? '配置成功');
      }
      return ProvisionResult(success: false, message: data['message'] ?? '配置失败');
    } catch (e) {
      return ProvisionResult(success: false, message: '请求超时: $e');
    }
  }

  Future<ProvisionResult> checkStatus() async {
    final client = HttpClient();
    client.connectionTimeout = Duration(seconds: _httpTimeout);
    try {
      final request = await client.getUrl(Uri.parse('$baseUrl/wifi_status'));
      final response = await request.close().timeout(Duration(seconds: 5));
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data['connected'] == true) {
        return ProvisionResult(
          success: true,
          message: 'WiFi 已连接',
          ssid: data['ssid'],
          ip: data['ip'],
        );
      }
      return ProvisionResult(success: false, message: '等待连接...');
    } catch (_) {
      return ProvisionResult(success: false, message: '设备正在重启...');
    }
  }

  Future<String?> getApInfo() async {
    final client = HttpClient();
    client.connectionTimeout = Duration(seconds: _httpTimeout);
    try {
      final request = await client.getUrl(Uri.parse('$baseUrl/ap_info'));
      final response = await request.close().timeout(Duration(seconds: 5));
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data['result'] == 'ok') {
        return data['ap_ssid'] as String?;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> testConnection() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 2);
      final request = await client.getUrl(Uri.parse('$baseUrl/ap_info'));
      final response = await request.close().timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
