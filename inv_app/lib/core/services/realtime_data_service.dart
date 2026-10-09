import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';

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
  /// 默认60秒间隔，设备每180秒上报一次heartbeat
  void startPolling(String deviceSN,
      {Duration interval = const Duration(seconds: 60)});

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
  }) : _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  @override
  Stream<InverterRealtime> get realtimeDataStream => _realtimeController.stream;

  @override
  Stream<OnlineStatus> get statusStream => _statusController.stream;

  @override
  Stream<AlarmData> get alarmStream => _alarmController.stream;

  @override
  void startPolling(String deviceSN,
      {Duration interval = const Duration(seconds: 60)}) {
    // 停止已有的轮询
    stopPolling(deviceSN);

    // 计算错开延迟，避免多个设备同时请求
    final deviceIndex = _pollingTimers.length;
    final staggerDelay = Duration(seconds: deviceIndex * 2); // 每个设备错开2秒

    // 延迟获取第一次数据
    Future.delayed(staggerDelay, () {
      if (_pollingTimers.containsKey(deviceSN)) {
        _fetchRealtimeData(deviceSN);
      }
    });

    // 启动定时轮询
    _pollingTimers[deviceSN] = Timer.periodic(interval, (_) {
      _fetchRealtimeData(deviceSN);
    });

    if (kDebugMode) {
      debugPrint(
          '[RealtimeDataService] Started polling for $deviceSN (delay: ${staggerDelay.inSeconds}s)');
    }
  }

  @override
  void stopPolling(String deviceSN) {
    _pollingTimers[deviceSN]?.cancel();
    _pollingTimers.remove(deviceSN);
    if (kDebugMode) {
      debugPrint('[RealtimeDataService] Stopped polling for $deviceSN');
    }
  }

  @override
  void stopAllPolling() {
    for (final timer in _pollingTimers.values) {
      timer.cancel();
    }
    _pollingTimers.clear();
    if (kDebugMode) {
      debugPrint('[RealtimeDataService] Stopped all polling');
    }
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
      // 动态获取最新的 token
      final token = await getIt<StorageService>().getToken();

      // API 路径: /devices/by-sn/:sn/realtime
      final uri = Uri.parse('$_baseUrl/devices/by-sn/$deviceSN/realtime');
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      if (kDebugMode) {
        debugPrint('[RealtimeDataService] Fetching data for $deviceSN');
      }

      final response = await http.get(uri, headers: headers).timeout(
            const Duration(seconds: 10),
          );

      if (kDebugMode) {
        debugPrint(
            '[RealtimeDataService] Response status: ${response.statusCode} for $deviceSN');
      }

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;

        if (json['code'] == 0 && json['data'] != null) {
          final data = json['data'] as Map<String, dynamic>;

          // realtime 字段包含完整的设备数据
          final realtime = data['realtime'] as Map<String, dynamic>?;

          if (kDebugMode) {
            debugPrint(
                '[RealtimeDataService] Realtime data: ${realtime != null ? "found (${realtime.keys.length} keys)" : "null"}');
          }

          if (realtime != null) {
            // 构建 InverterRealtime 对象
            final inverterRealtime =
                _parseRealtimeData(deviceSN, realtime, data);

            // 数据变化检测：只在数据变化时更新UI
            final previousData = _latestData[deviceSN];
            if (previousData != null &&
                _isDataEqual(previousData, inverterRealtime)) {
              // 数据未变化，跳过更新
              if (kDebugMode) {
                debugPrint(
                    '[RealtimeDataService] Data unchanged for $deviceSN, skipping update');
              }
              return;
            }

            _latestData[deviceSN] = inverterRealtime;
            _realtimeController.add(inverterRealtime);

            // 更新在线状态 - 从 realtime 或 data 中获取
            final online = inverterRealtime.onlineStatus?.online ?? false;
            final status = OnlineStatus(online: online);
            _statusController.add(status);

            if (kDebugMode) {
              debugPrint(
                  '[RealtimeDataService] Successfully parsed data for $deviceSN, online: $online');
            }
          } else {
            if (kDebugMode) {
              debugPrint(
                  '[RealtimeDataService] No realtime data in response for $deviceSN');
            }
          }
        } else {
          if (kDebugMode) {
            debugPrint(
                '[RealtimeDataService] Invalid response: code=${json['code']}, message=${json['message']}');
          }
        }
      } else {
        if (kDebugMode) {
          debugPrint(
              '[RealtimeDataService] HTTP error ${response.statusCode} for $deviceSN');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[RealtimeDataService] Error fetching data for $deviceSN: $e');
      }
    }
  }

  InverterRealtime _parseRealtimeData(
    String deviceSN,
    Map<String, dynamic> realtime,
    Map<String, dynamic> responseData,
  ) {
    return InverterRealtime.fromJson({
      ...realtime,
      'device_sn': deviceSN,
      'updated_at': realtime['updated_at'] ?? responseData['data_time'],
      'online': realtime['online'] ?? responseData['online'],
    });
  }

  /// 比较两个 InverterRealtime 对象是否相等
  /// 用于数据变化检测，避免重复更新UI
  bool _isDataEqual(InverterRealtime a, InverterRealtime b) {
    return jsonEncode(a.telemetryFields) == jsonEncode(b.telemetryFields);
  }
}
