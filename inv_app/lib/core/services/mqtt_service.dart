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

  void subscribeDeviceTopics(String deviceSN);
  void unsubscribeDeviceTopics(String deviceSN);

  Stream<InverterRealtime> get realtimeDataStream;
  Stream<OnlineStatus> get statusStream;
  Stream<AlarmData> get alarmStream;

  Future<void> sendCommand(String deviceSN, String cmdType, {Map<String, dynamic>? value});
}

class MQTTServiceImpl implements MQTTService {
  MqttServerClient? _client;
  Completer<void>? _connectionCompleter;

  final StreamController<InverterRealtime> _realtimeController = StreamController.broadcast();
  final StreamController<OnlineStatus> _statusController = StreamController.broadcast();
  final StreamController<AlarmData> _alarmController = StreamController.broadcast();

  final Map<String, InverterRealtime> _latestData = {};

  @override
  bool get isConnected => _client?.connectionStatus?.state == MqttConnectionState.connected;

  @override
  Future<void> connect(String clientId, {String? username, String? password}) async {
    _connectionCompleter = Completer<void>();
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

    _client!.logging(on: true);

    print('[MQTT] Connecting to ${AppConfig.mqttBrokerHost}:${AppConfig.mqttBrokerPort} as $clientId');

    try {
      await _client!.connect(username, password);
      print('[MQTT] Connected to broker');
      _client!.updates!.listen(_onMessage);
      if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
        _connectionCompleter!.complete();
      }
    } catch (e) {
      print('[MQTT] Connection failed: $e');
      _client!.disconnect();
      if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
        _connectionCompleter!.completeError(e);
      }
      rethrow;
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
  Future<void> disconnect() async {
    _client?.disconnect();
    _client = null;
  }

  void _onConnected() {
    print('MQTT Connected');
    if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
      _connectionCompleter!.complete();
    } else {
      _connectionCompleter = Completer<void>()..complete();
    }
  }

  void _onDisconnected() {
    print('MQTT Disconnected');
    if (_connectionCompleter != null && _connectionCompleter!.isCompleted) {
      _connectionCompleter = Completer<void>();
    }
  }

  void _onSubscribed(String topic) {
    print('MQTT Subscribed: $topic');
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage?>>? messages) {
    if (messages == null) return;

    for (final message in messages) {
      final topic = message.topic;
      final payload = message.payload as MqttPublishMessage;
      final jsonString = MqttPublishPayload.bytesToStringAsString(payload.payload.message);

      print('[MQTT] Received on $topic: $jsonString');

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
        }
      } catch (e) {
        print('Failed to parse MQTT message: $e');
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
      updatedAt: DateTime.now(),
    );
    _latestData[sn] = updated;
    _realtimeController.add(updated);
  }

  void _handleAlarmMessage(String sn, Map<String, dynamic> data) {
    final alarm = AlarmData.fromJson(data);
    _alarmController.add(alarm);
  }

  @override
  void subscribeDeviceTopics(String deviceSN) {
    _client?.subscribe('cs_inv/$deviceSN/status', MqttQos.atLeastOnce);
    _client?.subscribe('cs_inv/$deviceSN/data/ac', MqttQos.atMostOnce);
    _client?.subscribe('cs_inv/$deviceSN/data/battery', MqttQos.atMostOnce);
    _client?.subscribe('cs_inv/$deviceSN/data/pv', MqttQos.atMostOnce);
    _client?.subscribe('cs_inv/$deviceSN/data/status', MqttQos.atMostOnce);
    _client?.subscribe('cs_inv/$deviceSN/data/energy', MqttQos.atMostOnce);
    _client?.subscribe('cs_inv/$deviceSN/data/cells', MqttQos.atMostOnce);
    _client?.subscribe('cs_inv/$deviceSN/data/alarm', MqttQos.atLeastOnce);
  }

  @override
  void unsubscribeDeviceTopics(String deviceSN) {
    if (_client == null || !isConnected) return;
    _client?.unsubscribe('cs_inv/$deviceSN/status');
    _client?.unsubscribe('cs_inv/$deviceSN/data/ac');
    _client?.unsubscribe('cs_inv/$deviceSN/data/battery');
    _client?.unsubscribe('cs_inv/$deviceSN/data/pv');
    _client?.unsubscribe('cs_inv/$deviceSN/data/status');
    _client?.unsubscribe('cs_inv/$deviceSN/data/energy');
    _client?.unsubscribe('cs_inv/$deviceSN/data/cells');
    _client?.unsubscribe('cs_inv/$deviceSN/data/alarm');
  }

  @override
  Stream<InverterRealtime> get realtimeDataStream => _realtimeController.stream;

  @override
  Stream<OnlineStatus> get statusStream => _statusController.stream;

  @override
  Stream<AlarmData> get alarmStream => _alarmController.stream;

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
  }
}
