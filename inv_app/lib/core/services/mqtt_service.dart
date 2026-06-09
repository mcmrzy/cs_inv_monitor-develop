import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/entities/inverter_data.dart';

abstract class MQTTService {
  Future<void> connect(String clientId, {String? username, String? password});
  Future<void> disconnect();
  bool get isConnected;
  Future<void> waitForConnection({Duration? timeout});
  Future<void> reconnect();

  void subscribeDeviceTopics(String deviceSN);
  void unsubscribeDeviceTopics(String deviceSN);

  Stream<InverterRealtime> get realtimeDataStream;
  Stream<OnlineStatus> get statusStream;
  Stream<AlarmData> get alarmStream;
  Stream<OTANotification> get otaNotificationStream;

  InverterRealtime? getLatestData(String deviceSN);

  Future<void> sendCommand(String deviceSN, String cmdType, {Map<String, dynamic>? value});
}

class MQTTServiceImpl implements MQTTService {
  MqttServerClient? _client;
  Completer<void>? _connectionCompleter;
  String? _lastClientId;
  String? _lastUsername;
  String? _lastPassword;
  final Set<String> _subscribedTopics = {};
  StreamSubscription? _updateSubscription;
  bool _isConnecting = false;
  bool _intentionalDisconnect = false;

  final StreamController<InverterRealtime> _realtimeController = StreamController.broadcast();
  final StreamController<OnlineStatus> _statusController = StreamController.broadcast();
  final StreamController<AlarmData> _alarmController = StreamController.broadcast();
  final StreamController<OTANotification> _otaNotificationController = StreamController.broadcast();

  final Map<String, InverterRealtime> _latestData = {};

  @override
  bool get isConnected => _client?.connectionStatus?.state == MqttConnectionState.connected;

  @override
  Future<void> connect(String clientId, {String? username, String? password}) async {
    if (_isConnecting) {
      await waitForConnection(timeout: const Duration(seconds: 15));
      return;
    }

    if (isConnected && _lastClientId == clientId) {
      return;
    }

    _isConnecting = true;
    _intentionalDisconnect = false;
    _connectionCompleter = Completer<void>();

    _updateSubscription?.cancel();
    _updateSubscription = null;

    if (_client != null) {
      _client!.autoReconnect = false;
      _client!.disconnect();
      _client = null;
    }

    _client = MqttServerClient.withPort(AppConfig.mqttBrokerHost, clientId, AppConfig.mqttBrokerPort);
    _client!.secure = true;
    if (kDebugMode) {
      _client!.onBadCertificate = (Object _) => true;
    }
    _client!.keepAlivePeriod = 120;
    _client!.connectTimeoutPeriod = 30000;
    _client!.autoReconnect = true;
    _client!.onDisconnected = _onDisconnected;
    _client!.onConnected = _onConnected;
    _client!.onSubscribed = _onSubscribed;

    final connMessage = MqttConnectMessage()
      .withClientIdentifier(clientId)
      .startClean()
      .withWillQos(MqttQos.atMostOnce);

    _client!.connectionMessage = connMessage;

    _client!.logging(on: kDebugMode);

    _lastClientId = clientId;
    _lastUsername = username;
    _lastPassword = password;

    try {
      await _client!.connect(username, password);
      _updateSubscription = _client!.updates!.listen(_onMessage);
      if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
        _connectionCompleter!.complete();
      }
    } catch (e) {
      _client!.disconnect();
      _client = null;
      if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
        _connectionCompleter!.completeError(e);
      }
      rethrow;
    } finally {
      _isConnecting = false;
    }
  }

  @override
  Future<void> waitForConnection({Duration? timeout}) async {
    if (isConnected) return;
    if (_connectionCompleter == null) {
      throw Exception('MQTT client not initialized. Call connect() first.');
    }
    await _connectionCompleter!.future.timeout(
      timeout ?? const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('MQTT connection timeout'),
    );
  }

  @override
  Future<void> reconnect() async {
    if (_lastClientId == null) {
      throw Exception('No previous connection to reconnect to.');
    }
    await connect(_lastClientId!, username: _lastUsername, password: _lastPassword);
  }

  @override
  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _updateSubscription?.cancel();
    _updateSubscription = null;
    _subscribedTopics.clear();
    _lastClientId = null;
    _lastUsername = null;
    _lastPassword = null;
    if (_client != null) {
      _client!.autoReconnect = false;
      _client!.disconnect();
      _client = null;
    }
  }

  void _onConnected() {
    if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
      _connectionCompleter!.complete();
    } else {
      _connectionCompleter = Completer<void>()..complete();
    }
    _resubscribeAll();
  }

  void _onDisconnected() {
    if (_intentionalDisconnect) return;
    if (_connectionCompleter != null && _connectionCompleter!.isCompleted) {
      _connectionCompleter = Completer<void>();
    }
  }

  void _resubscribeAll() {
    if (_subscribedTopics.isEmpty) return;
    for (final topic in _subscribedTopics.toList()) {
      final qos = topic.contains('/alarm') || topic.contains('/status') && !topic.contains('/data/status')
          || topic.contains('/info')
          ? MqttQos.atLeastOnce
          : MqttQos.atMostOnce;
      _client?.subscribe(topic, qos);
    }
  }

  void _onSubscribed(String topic) {
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage?>>? messages) {
    if (messages == null) return;

    for (final message in messages) {
      final topic = message.topic;
      final payload = message.payload as MqttPublishMessage;
      final jsonString = MqttPublishPayload.bytesToStringAsString(payload.payload.message);

      try {
        final data = json.decode(jsonString) as Map<String, dynamic>;
        final sn = _extractSN(topic);

        if (topic.contains('/status') && !topic.contains('/data/status')) {
          _handleStatusMessage(sn, data);
        } else if (topic.contains('/data/ac')) {
          _handleACMessage(sn, data);
        } else if (topic.contains('/data/battery')) {
          _handleBatteryMessage(sn, data);
        } else if (topic.contains('/data/pv')) {
          _handlePVMessage(sn, data);
        } else if (topic.contains('/data/status')) {
          _handleSysStatusMessage(sn, data);
        } else if (topic.contains('/data/energy')) {
          _handleEnergyMessage(sn, data);
        } else if (topic.contains('/data/cells')) {
          _handleCellsMessage(sn, data);
        } else if (topic.contains('/data/alarm')) {
          _handleAlarmMessage(sn, data);
        } else if (topic.contains('/info')) {
          _handleInfoMessage(sn, data);
        } else if (topic.contains('/ota/notify')) {
          _handleOTANotifyMessage(sn, data);
        }
      } catch (e) {
      }
    }
  }

  String _extractSN(String topic) {
    final parts = topic.split('/');
    return parts.length >= 2 ? parts[1] : '';
  }

  InverterRealtime _getOrCreate(String sn) {
    return _latestData[sn] ?? InverterRealtime(deviceSN: sn, updatedAt: DateTime.now());
  }

  void _handleStatusMessage(String sn, Map<String, dynamic> data) {
    final status = OnlineStatus.fromJson(data);
    final rt = _getOrCreate(sn);
    final updated = InverterRealtime(
      deviceSN: sn,
      ac: rt.ac,
      battery: rt.battery,
      pv: rt.pv,
      sysStatus: rt.sysStatus,
      energy: rt.energy,
      cells: rt.cells,
      onlineStatus: status,
      deviceInfo: rt.deviceInfo,
      updatedAt: DateTime.now(),
    );
    _latestData[sn] = updated;
    _realtimeController.add(updated);
    _statusController.add(status);
  }

  void _handleACMessage(String sn, Map<String, dynamic> data) {
    final ac = ACData.fromJson(data);
    final rt = _getOrCreate(sn);
    final updated = InverterRealtime(
      deviceSN: sn,
      ac: ac,
      battery: rt.battery,
      pv: rt.pv,
      sysStatus: rt.sysStatus,
      energy: rt.energy,
      cells: rt.cells,
      onlineStatus: rt.onlineStatus,
      deviceInfo: rt.deviceInfo,
      updatedAt: DateTime.now(),
    );
    _latestData[sn] = updated;
    _realtimeController.add(updated);
  }

  void _handleBatteryMessage(String sn, Map<String, dynamic> data) {
    final battery = BatteryData.fromJson(data);
    final rt = _getOrCreate(sn);
    final updated = InverterRealtime(
      deviceSN: sn,
      ac: rt.ac,
      battery: battery,
      pv: rt.pv,
      sysStatus: rt.sysStatus,
      energy: rt.energy,
      cells: rt.cells,
      onlineStatus: rt.onlineStatus,
      deviceInfo: rt.deviceInfo,
      updatedAt: DateTime.now(),
    );
    _latestData[sn] = updated;
    _realtimeController.add(updated);
  }

  void _handlePVMessage(String sn, Map<String, dynamic> data) {
    final pv = PVData.fromJson(data);
    final rt = _getOrCreate(sn);
    final updated = InverterRealtime(
      deviceSN: sn,
      ac: rt.ac,
      battery: rt.battery,
      pv: pv,
      sysStatus: rt.sysStatus,
      energy: rt.energy,
      cells: rt.cells,
      onlineStatus: rt.onlineStatus,
      deviceInfo: rt.deviceInfo,
      updatedAt: DateTime.now(),
    );
    _latestData[sn] = updated;
    _realtimeController.add(updated);
  }

  void _handleSysStatusMessage(String sn, Map<String, dynamic> data) {
    final sysStatus = SystemStatus.fromJson(data);
    final rt = _getOrCreate(sn);
    final updated = InverterRealtime(
      deviceSN: sn,
      ac: rt.ac,
      battery: rt.battery,
      pv: rt.pv,
      sysStatus: sysStatus,
      energy: rt.energy,
      cells: rt.cells,
      onlineStatus: rt.onlineStatus,
      deviceInfo: rt.deviceInfo,
      updatedAt: DateTime.now(),
    );
    _latestData[sn] = updated;
    _realtimeController.add(updated);
  }

  void _handleEnergyMessage(String sn, Map<String, dynamic> data) {
    final energy = EnergyData.fromJson(data);
    final rt = _getOrCreate(sn);
    final updated = InverterRealtime(
      deviceSN: sn,
      ac: rt.ac,
      battery: rt.battery,
      pv: rt.pv,
      sysStatus: rt.sysStatus,
      energy: energy,
      cells: rt.cells,
      onlineStatus: rt.onlineStatus,
      deviceInfo: rt.deviceInfo,
      updatedAt: DateTime.now(),
    );
    _latestData[sn] = updated;
    _realtimeController.add(updated);
  }

  void _handleCellsMessage(String sn, Map<String, dynamic> data) {
    final cells = CellsData.fromJson(data);
    final rt = _getOrCreate(sn);
    final updated = InverterRealtime(
      deviceSN: sn,
      ac: rt.ac,
      battery: rt.battery,
      pv: rt.pv,
      sysStatus: rt.sysStatus,
      energy: rt.energy,
      cells: cells,
      onlineStatus: rt.onlineStatus,
      deviceInfo: rt.deviceInfo,
      updatedAt: DateTime.now(),
    );
    _latestData[sn] = updated;
    _realtimeController.add(updated);
  }

  void _handleAlarmMessage(String sn, Map<String, dynamic> data) {
    final alarm = AlarmData.fromJson(data);
    _alarmController.add(alarm);
  }

  void _handleInfoMessage(String sn, Map<String, dynamic> data) {
    final info = DeviceInfo.fromJson(data);
    final rt = _getOrCreate(sn);
    final updated = InverterRealtime(
      deviceSN: sn,
      ac: rt.ac,
      battery: rt.battery,
      pv: rt.pv,
      sysStatus: rt.sysStatus,
      energy: rt.energy,
      cells: rt.cells,
      onlineStatus: rt.onlineStatus,
      deviceInfo: info,
      updatedAt: DateTime.now(),
    );
    _latestData[sn] = updated;
    _realtimeController.add(updated);
  }

  void _handleOTANotifyMessage(String sn, Map<String, dynamic> data) {
    final notification = OTANotification.fromJson(data, sn);
    _otaNotificationController.add(notification);
  }

  @override
  void subscribeDeviceTopics(String deviceSN) {
    final topic = 'cs_inv/$deviceSN/#';
    _client?.subscribe(topic, MqttQos.atLeastOnce);
    _subscribedTopics.add(topic);
  }

  @override
  void unsubscribeDeviceTopics(String deviceSN) {
    if (_client == null || !isConnected) return;
    final topic = 'cs_inv/$deviceSN/#';
    _client?.unsubscribe(topic);
    _subscribedTopics.remove(topic);
  }

  @override
  Stream<InverterRealtime> get realtimeDataStream => _realtimeController.stream;

  @override
  Stream<OnlineStatus> get statusStream => _statusController.stream;

  @override
  Stream<AlarmData> get alarmStream => _alarmController.stream;

  @override
  Stream<OTANotification> get otaNotificationStream => _otaNotificationController.stream;

  @override
  Future<void> sendCommand(String deviceSN, String cmdType, {Map<String, dynamic>? value}) async {
    final topic = 'cs_inv/$deviceSN/cmd';

    final payloadJson = <String, dynamic>{
      'topic': cmdType,
    };

    if (value != null) {
      payloadJson['payload'] = json.encode(value);
    } else {
      payloadJson['payload'] = '';
    }

    final payload = json.encode(payloadJson);

    final builder = MqttClientPayloadBuilder();
    builder.addString(payload);
    _client?.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  InverterRealtime? getLatestData(String sn) => _latestData[sn];

  void dispose() {
    _realtimeController.close();
    _statusController.close();
    _alarmController.close();
    _otaNotificationController.close();
  }
}

class OTANotification {
  final String deviceSN;
  final String version;
  final String description;
  final int firmwareId;
  final int timestamp;

  const OTANotification({
    required this.deviceSN,
    this.version = '',
    this.description = '',
    this.firmwareId = 0,
    this.timestamp = 0,
  });

  factory OTANotification.fromJson(Map<String, dynamic> json, String sn) {
    return OTANotification(
      deviceSN: sn,
      version: json['version'] as String? ?? '',
      description: json['description'] as String? ?? '',
      firmwareId: (json['firmware_id'] as num?)?.toInt() ?? 0,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    );
  }
}
