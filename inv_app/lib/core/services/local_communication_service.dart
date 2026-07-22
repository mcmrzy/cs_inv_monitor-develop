import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:inv_app/core/errors/ota_error_types.dart';
import 'package:inv_app/core/services/local_discovery_service.dart';
import 'package:wifi_iot/wifi_iot.dart';

class LocalOtaManifest {
  final String target;
  final String taskId;
  final String version;
  final String sha256;
  final String signature;
  final int securityVersion;
  final int timeoutSeconds;

  const LocalOtaManifest({
    required this.target,
    required this.taskId,
    required this.version,
    required this.sha256,
    required this.signature,
    required this.securityVersion,
    this.timeoutSeconds = 300,
  });

  void validate() {
    if (target != 'esp' && target != 'arm') {
      throw ArgumentError.value(target, 'target', 'must be esp or arm');
    }
    final asciiToken = RegExp(r'^[\x21-\x7e]+$');
    if (taskId.length > 63 ||
        version.length > 31 ||
        !asciiToken.hasMatch(taskId) ||
        !asciiToken.hasMatch(version)) {
      throw ArgumentError('Invalid OTA task ID or firmware version');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw ArgumentError(
        'OTA SHA-256 must be 64 lowercase hexadecimal characters',
      );
    }
    var canonicalSignature = false;
    try {
      final decoded = base64.decode(signature);
      canonicalSignature =
          decoded.length == 64 && base64.encode(decoded) == signature;
    } on FormatException {
      canonicalSignature = false;
    }
    if (!canonicalSignature) {
      throw ArgumentError('OTA Ed25519 signature must be canonical Base64');
    }
    if (securityVersion <= 0 ||
        securityVersion > 0xffffffff ||
        timeoutSeconds < 60 ||
        timeoutSeconds > 3600) {
      throw ArgumentError('Invalid OTA security version or timeout');
    }
  }
}

class LocalCommunicationService {
  static const String _defaultGateway = '192.168.4.1';
  static const int _udpPort = 8888;
  static const Duration _udpTimeout = Duration(seconds: 3);
  static const String _discoveryCommand = 'CS_INV_DISCOVERY';

  late Dio _dio;
  String _deviceIP = _defaultGateway;
  String? _connectedSSID;

  LocalCommunicationService() {
    _dio = _createDio(_deviceIP);
  }

  Dio _createDio(String ip) {
    return Dio(
      BaseOptions(
        baseUrl: 'http://$ip',
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 30),
      ),
    );
  }

  /// 确保HTTP请求走WiFi网络
  Future<void> _ensureWifiUsage() async {
    try {
      await WiFiForIoTPlugin.forceWifiUsage(true);
    } catch (_) {}
  }

  String get deviceIP => _deviceIP;
  String? get connectedSSID => _connectedSSID;

  Future<void> connect(String deviceIP) async {
    _deviceIP = deviceIP;
    _dio = _createDio(_deviceIP);
  }

  void setConnectedSSID(String ssid) {
    _connectedSSID = ssid;
  }

  Future<Map<String, dynamic>> getRealtimeData([String? deviceIP]) async {
    final dio = deviceIP != null ? _createDio(deviceIP) : _dio;
    final response = await dio.get('/api/v1/realtime');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getParams([String? deviceIP]) async {
    final dio = deviceIP != null ? _createDio(deviceIP) : _dio;
    final response = await dio.get('/api/v1/params');
    return response.data as Map<String, dynamic>;
  }

  Future<void> updateParams(Map<String, dynamic> params) async {
    await _dio.put('/api/v1/params', data: params);
  }

  Future<void> setParams(String deviceIP, Map<String, dynamic> params) async {
    final dio = _createDio(deviceIP);
    await dio.put('/api/v1/params', data: params);
  }

  Future<void> sendCommand(String cmdType, Map<String, dynamic> params) async {
    await _dio.post(
      '/api/v1/control',
      data: {
        'cmd_type': cmdType,
        ...params,
      },
    );
  }

  Future<void> sendControl(
    String deviceIP,
    String cmdType,
    Map<String, dynamic> params,
  ) async {
    final dio = _createDio(deviceIP);
    await dio.post(
      '/api/v1/control',
      data: {
        'cmd_type': cmdType,
        ...params,
      },
    );
  }

  Future<Map<String, dynamic>> getDeviceInfo() async {
    await _ensureWifiUsage();

    try {
      final socket = await Socket.connect(
        _deviceIP,
        80,
        timeout: const Duration(seconds: 5),
      );

      const request = 'GET /ota/info HTTP/1.0\r\n\r\n';
      socket.write(request);
      await socket.flush();

      final completer = Completer<String>();
      final buffer = StringBuffer();

      socket.listen(
        (data) {
          buffer.write(utf8.decode(data));
        },
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

      try {
        socket.destroy();
      } catch (_) {}

      final jsonStart = response.indexOf('{');
      final jsonEnd = response.lastIndexOf('}');
      if (jsonStart >= 0 && jsonEnd > jsonStart) {
        return json.decode(response.substring(jsonStart, jsonEnd + 1))
            as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      debugPrint('getDeviceInfo failed: $e');
      return {};
    }
  }

  Future<void> configureWiFi(String ssid, String password) async {
    await _dio.post(
      '/config',
      data: {
        'ssid': ssid,
        'password': password,
      },
    );
  }

  Future<Map<String, dynamic>> checkWiFiStatus() async {
    final response = await _dio.get('/wifi_status');
    return response.data as Map<String, dynamic>;
  }

  /// 上传固件文件到设备
  /// target: 'esp' → 使用 octet-stream 直传；'arm' → 使用 multipart + target 字段
  Future<void> uploadFirmware(
    String filePath, {
    required LocalOtaManifest manifest,
    void Function(int sent, int total)? onProgress,
  }) async {
    await _ensureWifiUsage();
    manifest.validate();
    debugPrint(
      'Uploading firmware to: http://$_deviceIP/ota/upload (target=${manifest.target})',
    );

    final file = File(filePath);
    final bytes = await file.readAsBytes();
    debugPrint('File size: ${bytes.length} bytes');

    await _uploadOctetStream(bytes, manifest, onProgress: onProgress);
  }

  /// ESP 固件上传：原始二进制 octet-stream
  Future<void> _uploadOctetStream(
    Uint8List bytes,
    LocalOtaManifest manifest, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final socket = await Socket.connect(
      _deviceIP,
      80,
      timeout: const Duration(seconds: 10),
    );
    debugPrint('Socket connected for upload (octet-stream)');

    final requestHeader = 'POST /ota/upload HTTP/1.1\r\n'
        'Host: $_deviceIP\r\n'
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
  }

  /// 分块发送 body 并等待设备响应（通用逻辑）
  Future<void> _sendBodyAndWaitResponse(
    Socket socket,
    Uint8List body, {
    void Function(int sent, int total)? onProgress,
  }) async {
    const chunkSize = 4096;
    int sent = 0;

    try {
      while (sent < body.length) {
        final end =
            (sent + chunkSize < body.length) ? sent + chunkSize : body.length;
        socket.add(body.sublist(sent, end));
        sent = end;
        await socket.flush();
        if (onProgress != null) {
          onProgress(sent, body.length);
        }
        await Future.delayed(const Duration(milliseconds: 5));
      }
      debugPrint('Upload data sent ($sent bytes), waiting for response...');
    } catch (e) {
      try {
        socket.destroy();
      } catch (_) {}
      throw Exception('Upload failed during send: $e');
    }

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
      try {
        socket.destroy();
      } catch (_) {}
      throw Exception('Device did not confirm the OTA upload: $e');
    }

    debugPrint('Upload response: $response');

    try {
      socket.destroy();
    } catch (_) {}

    final statusLineEnd = response.indexOf('\r\n');
    final statusLine =
        statusLineEnd >= 0 ? response.substring(0, statusLineEnd) : response;
    final statusMatch =
        RegExp(r'^HTTP/\d(?:\.\d)?\s+(\d{3})').firstMatch(statusLine);
    final statusCode =
        statusMatch == null ? null : int.tryParse(statusMatch.group(1)!);
    if (statusCode == null || statusCode < 200 || statusCode >= 300) {
      final bodyStart = response.indexOf('\r\n\r\n');
      final responseBody =
          bodyStart >= 0 ? response.substring(bodyStart + 4) : response;
      throw Exception(
        'Upload rejected (${statusCode ?? 'invalid response'}): $responseBody',
      );
    }
  }

  Future<Map<String, dynamic>> getOTAProgress() async {
    await _ensureWifiUsage();
    debugPrint('Getting OTA progress from: http://$_deviceIP/ota/progress');

    try {
      final socket = await Socket.connect(
        _deviceIP,
        80,
        timeout: const Duration(seconds: 5),
      );

      const request = 'GET /ota/progress HTTP/1.0\r\n\r\n';
      socket.write(request);
      await socket.flush();

      final completer = Completer<String>();
      final buffer = StringBuffer();

      socket.listen(
        (data) {
          buffer.write(utf8.decode(data));
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete(buffer.toString());
          }
        },
        onError: (e) {
          if (!completer.isCompleted) {
            completer.completeError(e!);
          }
        },
      );

      final response = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          return buffer.toString();
        },
      );

      debugPrint('OTA progress response: $response');

      try {
        socket.destroy();
      } catch (_) {}

      // 解析JSON响应
      final jsonStart = response.indexOf('{');
      final jsonEnd = response.lastIndexOf('}');
      if (jsonStart >= 0 && jsonEnd > jsonStart) {
        final jsonStr = response.substring(jsonStart, jsonEnd + 1);
        return json.decode(jsonStr) as Map<String, dynamic>;
      }
      return {};
    } on SocketException catch (e) {
      // 连接失败 = 设备离线（热点断开/重启中），向上层抛出
      throw DeviceConnectionException('设备连接失败: $e');
    } on TimeoutException catch (e) {
      // 超时 = 设备无响应
      throw DeviceConnectionException('设备响应超时: $e');
    } catch (e) {
      // 其他异常（JSON解析等），返回空Map（设备过渡状态）
      debugPrint('Get OTA progress parse failed: $e');
      return {};
    }
  }

  Future<List<DiscoveredDevice>> scanLocalDevices() async {
    final devices = <DiscoveredDevice>[];
    final completer = Completer<List<DiscoveredDevice>>();

    try {
      final socket =
          await RawDatagramSocket.bind(InternetAddress.anyIPv4, _udpPort);
      socket.broadcastEnabled = true;
      socket.multicastLoopback = false;

      final timeoutTimer = Timer(_udpTimeout, () {
        if (!completer.isCompleted) {
          completer.complete(devices);
        }
      });

      final commandBytes = utf8.encode(_discoveryCommand);
      socket.send(commandBytes, InternetAddress('255.255.255.255'), _udpPort);

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram == null) return;

          try {
            final data = utf8.decode(datagram.data);
            final json = jsonDecode(data) as Map<String, dynamic>;

            devices.add(
              DiscoveredDevice(
                ssid: json['ssid'] ?? json['name'] ?? '',
                rssi: json['rssi'] ?? -100,
                isEncrypted: false,
                bssid: json['mac'] ?? json['bssid'],
              ),
            );
          } catch (_) {
            try {
              final data = utf8.decode(datagram.data);
              devices.add(
                DiscoveredDevice(
                  ssid: data.trim(),
                  rssi: -100,
                  isEncrypted: false,
                ),
              );
            } catch (_) {}
          }
        }
      });

      final result = await completer.future;

      timeoutTimer.cancel();
      socket.close();

      return result;
    } catch (_) {
      return devices;
    }
  }

  Future<bool> testConnection() async {
    try {
      await _ensureWifiUsage();
      final url = 'http://$_deviceIP/ota/info';
      debugPrint('Testing connection to: $url');

      final socket = await Socket.connect(
        _deviceIP,
        80,
        timeout: const Duration(seconds: 5),
      );
      debugPrint('Socket connected');

      const request = 'GET /ota/info HTTP/1.0\r\n\r\n';
      socket.write(request);
      await socket.flush();
      debugPrint('Request sent');

      final completer = Completer<String>();
      final buffer = StringBuffer();

      socket.listen(
        (data) {
          buffer.write(utf8.decode(data));
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete(buffer.toString());
          }
        },
        onError: (e) {
          if (!completer.isCompleted) {
            completer.completeError(e!);
          }
        },
      );

      final response = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          return buffer.toString();
        },
      );

      debugPrint('Response received (${response.length} chars)');
      debugPrint('Response: $response');

      try {
        socket.destroy();
      } catch (_) {}

      return response.contains('200');
    } catch (e) {
      debugPrint('Test connection failed: $e');
      return false;
    }
  }

  void disconnect() {
    _deviceIP = _defaultGateway;
    _connectedSSID = null;
    _dio = _createDio(_deviceIP);
  }
}
