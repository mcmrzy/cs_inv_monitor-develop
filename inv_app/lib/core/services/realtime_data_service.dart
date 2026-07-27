import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/entities/inverter_data.dart';

/// 通过 HTTP API 轮询获取设备实时数据，替代 MQTT 直连方案
///
/// 优势：
/// - 无需维护 MQTT 长连接，节省电量和流量
/// - 无需在 App 端解析 MQTT 消息格式
/// - 后端统一处理数据，App 只需解析 JSON
abstract class RealtimeDataService {
  /// 设备实时数据流
  Stream<InverterRealtime> get realtimeDataStream;

  /// 设备在线状态流
  Stream<OnlineStatus> get statusStream;

  /// 告警数据流（通过 API 轮询或推送通知触发）
  Stream<AlarmData> get alarmStream;

  /// 开始轮询指定设备的实时数据
  void startPolling(String deviceSN, {Duration interval = const Duration(seconds: 3)});

  /// 停止轮询指定设备
  void stopPolling(String deviceSN);

  /// 停止所有轮询
  void stopAllPolling();

  /// 手动触发一次数据刷新
  Future<void> refresh(String deviceSN);

  /// 获取设备最新数据（从缓存）
  InverterRealtime? getLatestData(String deviceSN);

  /// 释放资源
  void dispose();
}

class RealtimeDataServiceImpl implements RealtimeDataService {
  final String _baseUrl;
  final String? _token;

  final Map<String, Timer> _pollingTimers = {};
  final Map<String, InverterRealtime> _latestData = {};

  final StreamController<InverterRealtime> _realtimeController =
      StreamController<InverterRealtime>.broadcast();
  final StreamController<OnlineStatus> _statusController =
      StreamController<OnlineStatus>.broadcast();
  final StreamController<AlarmData> _alarmController =
      StreamController<AlarmData>.broadcast();

  RealtimeDataServiceImpl({
    String? baseUrl,
    String? token,
  })  : _baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
        _token = token;

  @override
  Stream<InverterRealtime> get realtimeDataStream => _realtimeController.stream;

  @override
  Stream<OnlineStatus> get statusStream => _statusController.stream;

  @override
  Stream<AlarmData> get alarmStream => _alarmController.stream;

  @override
  void startPolling(String deviceSN, {Duration interval = const Duration(seconds: 3)}) {
    // 停止已有的轮询
    stopPolling(deviceSN);

    // 立即获取一次数据
    _fetchRealtimeData(deviceSN);

    // 启动定时轮询
    _pollingTimers[deviceSN] = Timer.periodic(interval, (_) {
      _fetchRealtimeData(deviceSN);
    });

    debugPrint('[RealtimeDataService] Started polling for $deviceSN');
  }

  @override
  void stopPolling(String deviceSN) {
    _pollingTimers[deviceSN]?.cancel();
    _pollingTimers.remove(deviceSN);
    debugPrint('[RealtimeDataService] Stopped polling for $deviceSN');
  }

  @override
  void stopAllPolling() {
    for (final timer in _pollingTimers.values) {
      timer.cancel();
    }
    _pollingTimers.clear();
    debugPrint('[RealtimeDataService] Stopped all polling');
  }

  @override
  Future<void> refresh(String deviceSN) async {
    await _fetchRealtimeData(deviceSN);
  }

  @override
  InverterRealtime? getLatestData(String deviceSN) {
    return _latestData[deviceSN];
  }

  @override
  void dispose() {
    stopAllPolling();
    _realtimeController.close();
    _statusController.close();
    _alarmController.close();
  }

  Future<void> _fetchRealtimeData(String deviceSN) async {
    try {
      final uri = Uri.parse('$_baseUrl/devices/$deviceSN/realtime');
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (_token != null) {
        headers['Authorization'] = 'Bearer $_token';
      }

      final response = await http.get(uri, headers: headers).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['code'] == 0 && json['data'] != null) {
          final data = json['data'] as Map<String, dynamic>;
          final realtime = data['realtime'] as Map<String, dynamic>?;

          if (realtime != null) {
            // 构建 InverterRealtime 对象
            final inverterRealtime = _parseRealtimeData(deviceSN, realtime, data);
            _latestData[deviceSN] = inverterRealtime;
            _realtimeController.add(inverterRealtime);

            // 更新在线状态
            final online = data['online'] as bool? ?? false;
            final status = OnlineStatus(online: online);
            _statusController.add(status);
          }
        }
      }
    } catch (e) {
      debugPrint('[RealtimeDataService] Error fetching data for $deviceSN: $e');
    }
  }

  InverterRealtime _parseRealtimeData(
    String deviceSN,
    Map<String, dynamic> realtime,
    Map<String, dynamic> responseData,
  ) {
    // 从 realtime map 中解析各个组件数据
    final acData = realtime['ac'] != null
        ? ACData.fromJson(realtime['ac'] as Map<String, dynamic>)
        : null;

    final batteryData = realtime['battery'] != null || realtime['batt'] != null
        ? BatteryData.fromJson(
            (realtime['battery'] ?? realtime['batt']) as Map<String, dynamic>)
        : null;

    final pvData = realtime['pv'] != null
        ? PVData.fromJson(realtime['pv'] as Map<String, dynamic>)
        : null;

    final sysStatusData = realtime['sys_status'] != null || realtime['sys'] != null
        ? SystemStatus.fromJson(
            (realtime['sys_status'] ?? realtime['sys']) as Map<String, dynamic>)
        : null;

    final energyData = realtime['energy'] != null
        ? EnergyData.fromJson(realtime['energy'] as Map<String, dynamic>)
        : null;

    final cellsData = realtime['cells'] != null
        ? CellsData.fromJson(realtime['cells'] as Map<String, dynamic>)
        : null;

    final deviceInfoData = realtime['device_info'] != null
        ? DeviceInfo.fromJson(realtime['device_info'] as Map<String, dynamic>)
        : null;

    final meterData = realtime['meter'] != null
        ? MeterData.fromJson(realtime['meter'] as Map<String, dynamic>)
        : null;

    final loadPower = (realtime['load_power'] as num?)?.toDouble() ?? 0;

    final updatedAtStr = realtime['updated_at'] as String? ??
        responseData['data_time'] as String? ??
        '';
    final updatedAt = DateTime.tryParse(updatedAtStr) ?? DateTime.now();

    final onlineStatus = responseData['online'] != null
        ? OnlineStatus(online: responseData['online'] as bool)
        : null;

    return InverterRealtime(
      deviceSN: deviceSN,
      ac: acData,
      battery: batteryData,
      pv: pvData,
      sysStatus: sysStatusData,
      energy: energyData,
      cells: cellsData,
      onlineStatus: onlineStatus,
      deviceInfo: deviceInfoData,
      meter: meterData,
      loadPower: loadPower,
      updatedAt: updatedAt,
    );
  }
}
