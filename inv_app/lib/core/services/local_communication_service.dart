import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:inv_app/core/services/local_discovery_service.dart';

class LocalCommunicationService {
  static const String _defaultGateway = '192.168.4.1';
  static const String _defaultBasePath = '/api/v1';
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
      baseUrl: 'http://$ip$_defaultBasePath',
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
      sendTimeout: const Duration(seconds: 5),
    ));
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
    final response = await dio.get('/realtime');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getParams([String? deviceIP]) async {
    final dio = deviceIP != null ? _createDio(deviceIP) : _dio;
    final response = await dio.get('/params');
    return response.data as Map<String, dynamic>;
  }

  Future<void> updateParams(Map<String, dynamic> params) async {
    await _dio.put('/params', data: params);
  }

  Future<void> setParams(String deviceIP, Map<String, dynamic> params) async {
    final dio = _createDio(deviceIP);
    await dio.put('/params', data: params);
  }

  Future<void> sendCommand(String cmdType, Map<String, dynamic> params) async {
    await _dio.post('/control', data: {
      'cmd_type': cmdType,
      ...params,
    });
  }

  Future<void> sendControl(String deviceIP, String cmdType, Map<String, dynamic> params) async {
    final dio = _createDio(deviceIP);
    await dio.post('/control', data: {
      'cmd_type': cmdType,
      ...params,
    });
  }

  Future<Map<String, dynamic>> getDeviceInfo() async {
    final response = await _dio.get('/info');
    return response.data as Map<String, dynamic>;
  }

  Future<void> configureWiFi(String ssid, String password) async {
    await _dio.post('/wifi/config', data: {
      'ssid': ssid,
      'password': password,
    });
  }

  Future<Map<String, dynamic>> checkWiFiStatus() async {
    final response = await _dio.get('/wifi/status');
    return response.data as Map<String, dynamic>;
  }

  Future<void> startOTA(String filePath) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
    });
    await _dio.post('/ota/start', data: formData);
  }

  Future<Map<String, dynamic>> getOTAProgress() async {
    final response = await _dio.get('/ota/progress');
    return response.data as Map<String, dynamic>;
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
            ));
          } catch (_) {
            try {
              final data = utf8.decode(datagram.data);
              devices.add(DiscoveredDevice(
                ssid: data.trim(),
                rssi: -100,
                isEncrypted: false,
              ));
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
      await _dio.get('/info');
      return true;
    } catch (_) {
      return false;
    }
  }

  void disconnect() {
    _deviceIP = _defaultGateway;
    _connectedSSID = null;
    _dio = _createDio(_deviceIP);
  }
}
