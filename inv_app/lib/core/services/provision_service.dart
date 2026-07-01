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

  /// 发送配网配置，自动尝试多种请求格式以兼容不同设备固件
  Future<ProvisionResult> configure(String ssid, String password) async {
    final encodedSsid = Uri.encodeComponent(ssid);
    final encodedPwd = Uri.encodeComponent(password);

    // 按优先级尝试多种格式
    final attempts = [
      // 1. JSON body → POST /config
      () => _postJson('$baseUrl/config', {'ssid': ssid, 'password': password}),
      // 2. 表单编码 → POST /config
      () => _postForm('$baseUrl/config', 'ssid=$encodedSsid&password=$encodedPwd'),
      // 3. URL 查询参数 → POST /config?ssid=...&password=...
      () => _postForm('$baseUrl/config?ssid=$encodedSsid&password=$encodedPwd', ''),
      // 4. JSON body → POST / (兼容格式)
      () => _postJson('$baseUrl/', {'cmd': 'set_wifi', 'ssid': ssid, 'password': password}),
      // 5. 表单编码 → POST /
      () => _postForm('$baseUrl/', 'ssid=$encodedSsid&password=$encodedPwd'),
      // 6. GET 查询参数 → GET /config?ssid=...&password=...
      () => _getWithParams('$baseUrl/config?ssid=$encodedSsid&password=$encodedPwd'),
    ];

    ProvisionResult? lastResult;
    for (final attempt in attempts) {
      final result = await attempt();
      if (result.success) return result;
      lastResult = result;
      // 如果是超时错误，直接返回（说明设备不可达）
      if (result.message.startsWith('Request timeout')) return result;
    }
    return lastResult ?? ProvisionResult(success: false, message: 'All attempts failed');
  }

  /// POST JSON 请求
  Future<ProvisionResult> _postJson(String url, Map<String, dynamic> body) async {
    final client = HttpClient();
    client.connectionTimeout = Duration(seconds: _httpTimeout);
    try {
      final request = await client.postUrl(Uri.parse(url));
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode(body));
      final response = await request.close().timeout(Duration(seconds: 10));
      final responseBody = await response.transform(utf8.decoder).join();
      return _parseResponse(responseBody, 'JSON POST $url');
    } on FormatException {
      return ProvisionResult(success: false, message: 'Format mismatch (JSON POST)');
    } catch (e) {
      return ProvisionResult(success: false, message: 'Request timeout: $e');
    }
  }

  /// POST 表单/URL编码 请求
  Future<ProvisionResult> _postForm(String url, String formBody) async {
    final client = HttpClient();
    client.connectionTimeout = Duration(seconds: _httpTimeout);
    try {
      final request = await client.postUrl(Uri.parse(url));
      request.headers.set('Content-Type', 'application/x-www-form-urlencoded');
      if (formBody.isNotEmpty) request.write(formBody);
      final response = await request.close().timeout(Duration(seconds: 10));
      final responseBody = await response.transform(utf8.decoder).join();
      return _parseResponse(responseBody, 'FORM POST $url');
    } on FormatException {
      return ProvisionResult(success: false, message: 'Format mismatch (FORM POST)');
    } catch (e) {
      return ProvisionResult(success: false, message: 'Request timeout: $e');
    }
  }

  /// GET 带查询参数 请求
  Future<ProvisionResult> _getWithParams(String url) async {
    final client = HttpClient();
    client.connectionTimeout = Duration(seconds: _httpTimeout);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(Duration(seconds: 10));
      final responseBody = await response.transform(utf8.decoder).join();
      return _parseResponse(responseBody, 'GET $url');
    } on FormatException {
      return ProvisionResult(success: false, message: 'Format mismatch (GET)');
    } catch (e) {
      return ProvisionResult(success: false, message: 'Request timeout: $e');
    }
  }

  /// 解析设备 HTTP 响应（兼容 JSON 和纯文本）
  ProvisionResult _parseResponse(String body, String tag) {
    if (body.isEmpty) {
      return ProvisionResult(success: false, message: '[$tag] Empty response');
    }
    // 尝试 JSON 解析
    try {
      final data = jsonDecode(body);
      if (data is Map && data['result'] == 'ok') {
        return ProvisionResult(success: true, message: data['message']?.toString() ?? 'OK');
      }
      final msg = data is Map ? (data['message']?.toString() ?? body) : body;
      return ProvisionResult(success: false, message: '[$tag] $msg');
    } catch (_) {
      // 非 JSON 响应，尝试识别常见成功标识
      final lower = body.toLowerCase();
      if (lower.contains('ok') || lower.contains('success') || lower.contains('connected')) {
        return ProvisionResult(success: true, message: body);
      }
      return ProvisionResult(success: false, message: '[$tag] $body');
    }
  }

  Future<ProvisionResult> configureCompat(String ssid, String password) async {
    // 已合并到 configure() 中，保留兼容接口
    return configure(ssid, password);
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
          message: 'WiFi connected',
          ssid: data['ssid'],
          ip: data['ip'],
        );
      }
      return ProvisionResult(success: false, message: 'Waiting for connection...');
    } catch (_) {
      return ProvisionResult(success: false, message: 'Device rebooting...');
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
