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

  ProvisionResult({
    required this.success,
    required this.message,
    this.ssid,
    this.ip,
  });
}

class ProvisionService {
  static const String _provisionHost = '192.168.4.1';
  static const int _httpTimeout = 5;

  String get baseUrl => 'http://$_provisionHost';

  Future<List<ScanResult>> scanWiFi() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: _httpTimeout);
    try {
      final request = await client.getUrl(Uri.parse('$baseUrl/scan'));
      final response =
          await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);
        if (data['status'] == 'scanning') {
          await Future.delayed(const Duration(seconds: 3));
          return scanWiFi();
        }
        final networks = data['networks'] as List? ?? [];
        return networks
            .map(
              (n) => ScanResult(
                ssid: n['ssid'] ?? '',
                rssi: n['rssi'] ?? -100,
                encrypted: (n['auth'] as num? ?? 0).toInt() != 0,
              ),
            )
            .toList()
          ..sort((a, b) => b.rssi.compareTo(a.rssi));
      }
    } catch (_) {
      return [];
    } finally {
      client.close(force: true);
    }
    return [];
  }

  /// 使用当前 ESP32-C2 App 配网协议发送 Wi-Fi 配置。
  Future<ProvisionResult> configure(String ssid, String password) async {
    return _postJson('$baseUrl/config', {'ssid': ssid, 'password': password});
  }

  /// POST JSON 请求
  Future<ProvisionResult> _postJson(
    String url,
    Map<String, dynamic> body,
  ) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: _httpTimeout);
    try {
      final request = await client.postUrl(Uri.parse(url));
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode(body));
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      final responseBody = await response.transform(utf8.decoder).join();
      return _parseResponse(
        response.statusCode,
        responseBody,
        'JSON POST $url',
      );
    } on FormatException {
      return ProvisionResult(
        success: false,
        message: 'Format mismatch (JSON POST)',
      );
    } catch (e) {
      return ProvisionResult(success: false, message: 'Request timeout: $e');
    } finally {
      client.close(force: true);
    }
  }

  ProvisionResult _parseResponse(int statusCode, String body, String tag) {
    if (body.isEmpty) {
      return ProvisionResult(success: false, message: '[$tag] Empty response');
    }
    // 尝试 JSON 解析
    try {
      final data = jsonDecode(body);
      if (statusCode >= 200 &&
          statusCode < 300 &&
          data is Map &&
          (data['ok'] == true || data['result'] == 'ok')) {
        return ProvisionResult(
          success: true,
          message: data['message']?.toString() ?? 'OK',
        );
      }
      final msg = data is Map ? (data['message']?.toString() ?? body) : body;
      return ProvisionResult(success: false, message: '[$tag] $msg');
    } catch (_) {
      return ProvisionResult(success: false, message: '[$tag] $body');
    }
  }

  Future<ProvisionResult> configureCompat(String ssid, String password) async {
    // 已合并到 configure() 中，保留兼容接口
    return configure(ssid, password);
  }

  Future<ProvisionResult> checkStatus() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: _httpTimeout);
    try {
      final request = await client.getUrl(Uri.parse('$baseUrl/wifi_status'));
      final response =
          await request.close().timeout(const Duration(seconds: 5));
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data['connected'] == true) {
        return ProvisionResult(
          success: true,
          message: 'WiFi connected',
          ssid: data['ssid'],
          ip: data['ip'],
        );
      }
      return ProvisionResult(
        success: false,
        message: 'Waiting for connection...',
      );
    } catch (_) {
      return ProvisionResult(success: false, message: 'Device rebooting...');
    } finally {
      client.close(force: true);
    }
  }

  Future<String?> getApInfo() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: _httpTimeout);
    try {
      final request = await client.getUrl(Uri.parse('$baseUrl/wifi_status'));
      final response =
          await request.close().timeout(const Duration(seconds: 5));
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data['ok'] == true) {
        return data['ssid'] as String?;
      }
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
    return null;
  }

  Future<bool> testConnection() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.getUrl(Uri.parse('$baseUrl/ota/info'));
      final response =
          await request.close().timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
