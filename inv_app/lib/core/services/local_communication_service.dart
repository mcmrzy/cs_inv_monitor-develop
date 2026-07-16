import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:inv_app/core/errors/ota_error_types.dart';
import 'package:inv_app/core/services/local_discovery_service.dart';
import 'package:wifi_iot/wifi_iot.dart';

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
    return Dio(BaseOptions(
      baseUrl: 'http://$ip',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 30),
    ),);
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
    await _dio.post('/api/v1/control', data: {
      'cmd_type': cmdType,
      ...params,
    },);
  }

  Future<void> sendControl(String deviceIP, String cmdType, Map<String, dynamic> params) async {
    final dio = _createDio(deviceIP);
    await dio.post('/api/v1/control', data: {
      'cmd_type': cmdType,
      ...params,
    },);
  }

  Future<Map<String, dynamic>> getDeviceInfo() async {
    await _ensureWifiUsage();
    
    try {
      final socket = await Socket.connect(_deviceIP, 80, timeout: const Duration(seconds: 5));
      
      final request = 'GET /ota/info HTTP/1.0\r\n\r\n';
      socket.write(request);
      await socket.flush();
      
      final completer = Completer<String>();
      final buffer = StringBuffer();
      
      socket.listen(
        (data) { buffer.write(utf8.decode(data)); },
        onDone: () { if (!completer.isCompleted) completer.complete(buffer.toString()); },
        onError: (e) { if (!completer.isCompleted) completer.completeError(e!); },
      );
      
      final response = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => buffer.toString(),
      );
      
      try { socket.destroy(); } catch (_) {}
      
      final jsonStart = response.indexOf('{');
      final jsonEnd = response.lastIndexOf('}');
      if (jsonStart >= 0 && jsonEnd > jsonStart) {
        return json.decode(response.substring(jsonStart, jsonEnd + 1)) as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      debugPrint('getDeviceInfo failed: $e');
      return {};
    }
  }

  Future<void> configureWiFi(String ssid, String password) async {
    await _dio.post('/api/v1/wifi/config', data: {
      'ssid': ssid,
      'password': password,
    },);
  }

  Future<Map<String, dynamic>> checkWiFiStatus() async {
    final response = await _dio.get('/api/v1/wifi/status');
    return response.data as Map<String, dynamic>;
  }

  /// 上传固件文件到设备
  /// target: 'esp' → 使用 octet-stream 直传；'arm' → 使用 multipart + target 字段
  Future<void> uploadFirmware(
    String filePath, {
    String target = 'esp',
    void Function(int sent, int total)? onProgress,
  }) async {
    await _ensureWifiUsage();
    debugPrint('Uploading firmware to: http://${_deviceIP}/ota/upload (target=$target)');
  
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    debugPrint('File size: ${bytes.length} bytes');
  
    if (target == 'arm') {
      await _uploadMultipart(bytes, file.path, onProgress: onProgress);
    } else {
      await _uploadOctetStream(bytes, onProgress: onProgress);
    }
  }
  
  /// ESP 固件上传：原始二进制 octet-stream
  Future<void> _uploadOctetStream(
    Uint8List bytes, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final socket = await Socket.connect(_deviceIP, 80, timeout: const Duration(seconds: 10));
    debugPrint('Socket connected for upload (octet-stream)');
  
    final requestHeader = 'POST /ota/upload HTTP/1.0\r\n'
        'Host: ${_deviceIP}\r\n'
        'Content-Type: application/octet-stream\r\n'
        'Content-Length: ${bytes.length}\r\n'
        '\r\n';
  
    socket.write(requestHeader);
    await socket.flush();
  
    await _sendBodyAndWaitResponse(socket, bytes, onProgress: onProgress);
  }
  
  /// ARM 固件上传：multipart/form-data + target=arm
  Future<void> _uploadMultipart(
    Uint8List bytes,
    String filePath, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final boundary = '----CSInvOta${DateTime.now().millisecondsSinceEpoch}';
    final fileName = filePath.split(RegExp(r'[/\\]')).last;
  
    // 构造 multipart body
    final head = utf8.encode(
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="target"\r\n\r\n'
      'arm\r\n'
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="file"; filename="$fileName"\r\n'
      'Content-Type: application/octet-stream\r\n\r\n',
    );
    final tail = utf8.encode('\r\n--$boundary--\r\n');
  
    final body = Uint8List(head.length + bytes.length + tail.length);
    body.setRange(0, head.length, head);
    body.setRange(head.length, head.length + bytes.length, bytes);
    body.setRange(head.length + bytes.length, body.length, tail);
  
    final socket = await Socket.connect(_deviceIP, 80, timeout: const Duration(seconds: 10));
    debugPrint('Socket connected for upload (multipart, target=arm)');
  
    final requestHeader = 'POST /ota/upload HTTP/1.0\r\n'
        'Host: ${_deviceIP}\r\n'
        'Content-Type: multipart/form-data; boundary=$boundary\r\n'
        'Content-Length: ${body.length}\r\n'
        '\r\n';
  
    socket.write(requestHeader);
    await socket.flush();
  
    await _sendBodyAndWaitResponse(socket, body, onProgress: onProgress);
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
    } catch (e) {
      if (sent >= body.length - chunkSize) {
        debugPrint('Upload: connection reset after sending $sent/${body.length} bytes, ESP32 likely restarting');
        try { socket.destroy(); } catch (_) {}
        return;
      }
      try { socket.destroy(); } catch (_) {}
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
        debugPrint('Upload: connection error after all data sent (${e.runtimeType}), ESP32 likely restarting');
        if (!completer.isCompleted) {
          completer.complete('');
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
      debugPrint('Upload: timeout/error after all data sent, assuming ESP32 restart');
      try { socket.destroy(); } catch (_) {}
      return;
    }
  
    debugPrint('Upload response: $response');
  
    try {
      socket.destroy();
    } catch (_) {}
  
    if (response.isNotEmpty && !response.contains('200')) {
      throw Exception('Upload failed: $response');
    }
  }

  Future<Map<String, dynamic>> getOTAProgress() async {
    await _ensureWifiUsage();
    debugPrint('Getting OTA progress from: http://$_deviceIP/ota/progress');
    
    try {
      final socket = await Socket.connect(_deviceIP, 80, timeout: const Duration(seconds: 5));
      
      final request = 'GET /ota/progress HTTP/1.0\r\n\r\n';
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
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _udpPort);
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

            devices.add(DiscoveredDevice(
              ssid: json['ssid'] ?? json['name'] ?? '',
              rssi: json['rssi'] ?? -100,
              isEncrypted: false,
              bssid: json['mac'] ?? json['bssid'],
            ),);
          } catch (_) {
            try {
              final data = utf8.decode(datagram.data);
              devices.add(DiscoveredDevice(
                ssid: data.trim(),
                rssi: -100,
                isEncrypted: false,
              ),);
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
      
      final socket = await Socket.connect(_deviceIP, 80, timeout: const Duration(seconds: 5));
      debugPrint('Socket connected');
      
      final request = 'GET /ota/info HTTP/1.0\r\n\r\n';
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
