import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:inv_app/core/errors/ota_error_types.dart';
import 'package:inv_app/core/services/local_communication_service.dart';
import 'package:inv_app/core/services/wifi_scan_service.dart';
import 'package:inv_app/features/ota/domain/repositories/local_communication_repository.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_iot/wifi_iot.dart';

/// WiFi AP 通信服务实现
/// 用于本地OTA升级，通过设备WiFi热点进行固件传输
class WifiApCommunicationService implements LocalCommunicationRepository {
  static const String _defaultGateway = '192.168.4.1';
  String? _connectedSSID;
  String _deviceIP = _defaultGateway;

  WifiApCommunicationService();

  /// 确保HTTP请求走WiFi网络
  Future<void> _ensureWifiUsage() async {
    try {
      await WiFiForIoTPlugin.forceWifiUsage(true);
    } catch (_) {}
  }

  @override
  Future<bool> connectToDevice({
    required String deviceSN,
    required String deviceIP,
    String? password,
  }) async {
    try {
      // 检查位置权限
      final locationStatus = await _checkLocationPermission();
      if (!locationStatus) {
        debugPrint('Location permission not granted');
        return false;
      }

      // 启用WiFi
      await WiFiForIoTPlugin.forceWifiUsage(true);

      // 扫描WiFi网络
      final networks = await scanWifiNetworks();
      final sn = deviceSN.toUpperCase();
      final target = networks.where((n) {
        final ssid = (n.ssid ?? '').toUpperCase();
        return ssid == 'CS_INV_$sn' || ssid == 'CS-INV-$sn';
      }).toList();

      if (target.isEmpty) {
        debugPrint('Device hotspot not found for SN: $deviceSN');
        return false;
      }

      final network = target.first;
      final ssid = network.ssid ?? '';
      final cap = network.capabilities?.toUpperCase() ?? '';
      final isOpen =
          !cap.contains('WPA') && !cap.contains('WEP') && !cap.contains('EAP');

      // 连接WiFi
      final connected = await WiFiForIoTPlugin.connect(
        ssid,
        password: password,
        security: isOpen ? NetworkSecurity.NONE : NetworkSecurity.WPA,
        joinOnce: true,
      );

      if (!connected) {
        debugPrint('Failed to connect to WiFi: $ssid');
        return false;
      }

      // 等待连接稳定
      await WiFiForIoTPlugin.forceWifiUsage(true);
      await Future.delayed(const Duration(seconds: 3));

      // 验证连接
      final currentSsid = await WiFiForIoTPlugin.getSSID();
      if (currentSsid == null ||
          !(currentSsid.toUpperCase().contains('CS_INV') ||
              currentSsid.toUpperCase().contains('CS-INV'))) {
        debugPrint('Connection verification failed');
        return false;
      }

      _connectedSSID = currentSsid;
      _deviceIP = deviceIP;

      debugPrint('Connected to device WiFi: $_connectedSSID');
      return true;
    } catch (e) {
      debugPrint('connectToDevice error: $e');
      return false;
    }
  }

  Future<bool> _checkLocationPermission() async {
    try {
      final status = await Permission.location.request();
      if (!status.isGranted && !status.isLimited) {
        return false;
      }
      final serviceEnabled = await Permission.location.serviceStatus.isEnabled;
      return serviceEnabled;
    } catch (e) {
      debugPrint('Permission check error: $e');
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await WiFiForIoTPlugin.disconnect().catchError((_) => false);
      await WiFiForIoTPlugin.forceWifiUsage(false).catchError((_) => false);
      _connectedSSID = null;
      _deviceIP = _defaultGateway;
    } catch (e) {
      debugPrint('disconnect error: $e');
    }
  }

  @override
  Future<void> uploadFirmware({
    required String deviceIP,
    required String filePath,
    required LocalOtaManifest manifest,
    void Function(int sent, int total)? onProgress,
  }) async {
    await _ensureWifiUsage();

    final file = File(filePath);
    if (!await file.exists()) {
      throw LocalFirmwareException('Firmware file not found: $filePath');
    }

    final bytes = await file.readAsBytes();
    debugPrint('Uploading firmware: ${bytes.length} bytes to $deviceIP');

    final socket = await Socket.connect(
      deviceIP,
      80,
      timeout: const Duration(seconds: 10),
    );

    try {
      // 强类型 manifest 直取字段，根治此前 Map 键名错位
      // （页面传 task_id/timeout_seconds 而此处读 taskId/timeoutSeconds，
      // 导致 X-OTA-Task-Id 恒为空、X-OTA-Timeout 恒为默认值）
      final requestHeader = 'POST /ota/upload HTTP/1.1\r\n'
          'Host: $deviceIP\r\n'
          'Connection: close\r\n'
          'Content-Type: application/octet-stream\r\n'
          'Content-Length: ${bytes.length}\r\n'
          'X-OTA-Size: ${bytes.length}\r\n'
          'X-OTA-Target: ${manifest.target}\r\n'
          'X-OTA-Task-Id: ${manifest.taskId}\r\n'
          'X-OTA-Version: ${manifest.version}\r\n'
          'X-OTA-SHA256: ${manifest.sha256}\r\n'
          'X-OTA-Signature: ${manifest.signature}\r\n'
          'X-OTA-Security-Version: ${manifest.securityVersion}\r\n'
          'X-OTA-Timeout: ${manifest.timeoutSeconds}\r\n'
          '\r\n';

      socket.write(requestHeader);
      await socket.flush();

      await _sendBodyAndWaitResponse(socket, bytes, onProgress: onProgress);
    } finally {
      try {
        socket.destroy();
      } catch (_) {}
    }
  }

  Future<void> _sendBodyAndWaitResponse(
    Socket socket,
    Uint8List body, {
    void Function(int sent, int total)? onProgress,
  }) async {
    const chunkSize = 4096;
    int sent = 0;

    while (sent < body.length) {
      final end = (sent + chunkSize < body.length) ? sent + chunkSize : body.length;
      socket.add(body.sublist(sent, end));
      sent = end;
      await socket.flush();
      if (onProgress != null) {
        onProgress(sent, body.length);
      }
      await Future.delayed(const Duration(milliseconds: 5));
    }

    debugPrint('Upload data sent ($sent bytes), waiting for response...');

    final completer = Completer<String>();
    final responseBuf = StringBuffer();

    socket.listen(
      (data) {
        responseBuf.write(utf8.decode(data));
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete(responseBuf.toString());
        }
      },
      onError: (e) {
        if (!completer.isCompleted) {
          completer.completeError(e!);
        }
      },
    );

    String response;
    try {
      response = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => responseBuf.toString(),
      );
    } catch (e) {
      throw Exception('Device did not confirm the OTA upload: $e');
    }

    debugPrint('Upload response: $response');

    final statusLineEnd = response.indexOf('\r\n');
    final statusLine = statusLineEnd >= 0 ? response.substring(0, statusLineEnd) : response;
    final statusMatch = RegExp(r'^HTTP/\d(?:\.\d)?\s+(\d{3})').firstMatch(statusLine);
    final statusCode = statusMatch == null ? null : int.tryParse(statusMatch.group(1)!);

    if (statusCode == null || statusCode < 200 || statusCode >= 300) {
      final bodyStart = response.indexOf('\r\n\r\n');
      final responseBody = bodyStart >= 0 ? response.substring(bodyStart + 4) : response;
      throw OtaUploadRejectedException(
        'Upload rejected (${statusCode ?? 'invalid response'}): $responseBody',
      );
    }
  }

  @override
  Future<void> triggerUpgrade(String deviceIP) async {
    await _ensureWifiUsage();
    debugPrint('Trigger upgrade on: $deviceIP');

    try {
      final response = await _rawHttpPost(deviceIP, 80, '/ota/trigger', '');
      debugPrint('Trigger upgrade response: $response');

      // 解析 HTTP 状态行判定成功，不再用 contains('200') 弱校验
      // （响应体含 "200" 字样会误判成功）
      final statusCode = _parseStatusCode(response);
      if (statusCode == null || statusCode < 200 || statusCode >= 300) {
        throw OtaUploadRejectedException(
          'Trigger upgrade failed (${statusCode ?? 'invalid response'})',
        );
      }
    } catch (e) {
      debugPrint('triggerUpgrade error: $e');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> getProgress(String deviceIP) async {
    await _ensureWifiUsage();
    debugPrint('Getting OTA progress from: http://$deviceIP/ota/progress');

    try {
      final response = await _rawHttpGet(deviceIP, 80, '/ota/progress');
      debugPrint('OTA progress response: $response');
      return _extractJson(response);
    } on SocketException catch (e) {
      throw DeviceConnectionException('设备连接失败: $e');
    } catch (e) {
      debugPrint('Get OTA progress failed: $e');
      return {};
    }
  }

  @override
  Future<Map<String, dynamic>> getDeviceInfo(String deviceIP) async {
    await _ensureWifiUsage();

    try {
      final response = await _rawHttpGet(deviceIP, 80, '/ota/info');
      return _extractJson(response);
    } catch (e) {
      debugPrint('getDeviceInfo failed: $e');
      return {};
    }
  }

  @override
  Future<bool> testConnection(String deviceIP) async {
    try {
      await _ensureWifiUsage();
      debugPrint('Testing connection to: http://$deviceIP/ota/info');

      final response = await _rawHttpGet(deviceIP, 80, '/ota/info');
      debugPrint('Response received (${response.length} chars)');

      // 解析 HTTP 状态行：2xx 才视为连接可用
      final statusCode = _parseStatusCode(response);
      return statusCode != null && statusCode >= 200 && statusCode < 300;
    } catch (e) {
      debugPrint('Test connection failed: $e');
      return false;
    }
  }

  @override
  Future<bool> isConnectedToDeviceAP() async {
    try {
      final ssid = await WiFiForIoTPlugin.getSSID();
      if (ssid == null || ssid.isEmpty || ssid == '<unknown ssid>') {
        return false;
      }
      final upper = ssid.toUpperCase();
      return upper.contains('CS_INV') || upper.contains('CS-INV');
    } catch (_) {
      return false;
    }
  }

  String? get connectedSSID => _connectedSSID;
  String get deviceIP => _deviceIP;

  // ============ 参数读写 / 控制命令 ============

  /// 设备直连会话鉴权协议头预留（固件团队协同项）：
  /// 设备端实现会话鉴权后，在连接/绑定后获取会话凭证，
  /// 此处统一为控制/参数/配网接口附加 `X-Device-Session` 请求头；
  /// 当前返回 null 表示不携带鉴权头，保留协议接入点。
  String? _deviceSessionToken() {
    // TODO(固件团队): 设备端会话鉴权落地后接入会话凭证
    return null;
  }

  /// 组装含预留鉴权头的公共请求头行
  String _authHeaderLines() {
    final token = _deviceSessionToken();
    return token == null ? '' : 'X-Device-Session: $token\r\n';
  }

  /// 简易 HTTP GET（Socket 实现，与 getDeviceInfo 同模式）
  Future<String> _rawHttpGet(String host, int port, String path) async {
    await _ensureWifiUsage();
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 5),
    );
    socket.write(
      'GET $path HTTP/1.0\r\n'
      'Host: $host\r\n'
      '${_authHeaderLines()}'
      '\r\n',
    );
    await socket.flush();
    final completer = Completer<String>();
    final buffer = StringBuffer();
    socket.listen(
      (data) => buffer.write(utf8.decode(data)),
      onDone: () {
        if (!completer.isCompleted) completer.complete(buffer.toString());
      },
      onError: (e) {
        if (!completer.isCompleted) completer.completeError(e!);
      },
    );
    final response = await completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => buffer.toString(),
    );
    try { socket.destroy(); } catch (_) {}
    return response;
  }

  /// 简易 HTTP POST（Socket 实现）
  Future<String> _rawHttpPost(
    String host, int port, String path, String body,
  ) async {
    await _ensureWifiUsage();
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 5),
    );
    final bodyBytes = utf8.encode(body);
    socket.write(
      'POST $path HTTP/1.0\r\n'
      'Host: $host\r\n'
      '${_authHeaderLines()}'
      'Content-Type: application/json\r\n'
      'Content-Length: ${bodyBytes.length}\r\n'
      '\r\n'
      '$body',
    );
    await socket.flush();
    final completer = Completer<String>();
    final buffer = StringBuffer();
    socket.listen(
      (data) => buffer.write(utf8.decode(data)),
      onDone: () {
        if (!completer.isCompleted) completer.complete(buffer.toString());
      },
      onError: (e) {
        if (!completer.isCompleted) completer.completeError(e!);
      },
    );
    final response = await completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => buffer.toString(),
    );
    try { socket.destroy(); } catch (_) {}
    return response;
  }

  /// 从 HTTP 响应中提取 JSON 对象
  Map<String, dynamic> _extractJson(String response) {
    final start = response.indexOf('{');
    final end = response.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return json.decode(response.substring(start, end + 1))
          as Map<String, dynamic>;
    }
    return {};
  }

  /// 解析 HTTP 响应状态行中的状态码（如 "HTTP/1.1 200 OK" → 200）；
  /// 无法解析时返回 null，调用方不应视为成功
  int? _parseStatusCode(String response) {
    final statusLineEnd = response.indexOf('\r\n');
    final statusLine =
        statusLineEnd >= 0 ? response.substring(0, statusLineEnd) : response;
    final match = RegExp(r'^HTTP/\d(?:\.\d)?\s+(\d{3})').firstMatch(statusLine);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  @override
  Future<String> readParameter(String deviceIP, String paramName) async {
    final raw = await _rawHttpGet(
      deviceIP, 80, '/api/params?name=${Uri.encodeComponent(paramName)}',
    );
    final data = _extractJson(raw);
    return data['value']?.toString() ?? '';
  }

  @override
  Future<bool> writeParameter(
    String deviceIP, String paramName, String value,
  ) async {
    final body = json.encode({'name': paramName, 'value': value});
    final raw = await _rawHttpPost(deviceIP, 80, '/api/params', body);
    final data = _extractJson(raw);
    return data['success'] == true || data['code'] == 0;
  }

  @override
  Future<Map<String, dynamic>> controlDevice(
    String deviceIP,
    String command, {
    Map<String, dynamic>? params,
  }) async {
    final body = json.encode({
      'command': command,
      if (params != null) 'params': params,
    });
    final raw = await _rawHttpPost(deviceIP, 80, '/api/control', body);
    return _extractJson(raw);
  }
}