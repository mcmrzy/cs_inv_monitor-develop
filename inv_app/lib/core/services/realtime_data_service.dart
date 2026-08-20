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
  void startPolling(String deviceSN, {Duration interval = const Duration(seconds: 60)});

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
  void startPolling(String deviceSN, {Duration interval = const Duration(seconds: 60)}) {
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
      debugPrint('[RealtimeDataService] Started polling for $deviceSN (delay: ${staggerDelay.inSeconds}s)');
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
        debugPrint('[RealtimeDataService] Response status: ${response.statusCode} for $deviceSN');
      }
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        
        if (json['code'] == 0 && json['data'] != null) {
          final data = json['data'] as Map<String, dynamic>;
          
          // realtime 字段包含完整的设备数据
          final realtime = data['realtime'] as Map<String, dynamic>?;
          
          if (kDebugMode) {
            debugPrint('[RealtimeDataService] Realtime data: ${realtime != null ? "found (${realtime.keys.length} keys)" : "null"}');
          }

          if (realtime != null) {
            // 构建 InverterRealtime 对象
            final inverterRealtime = _parseRealtimeData(deviceSN, realtime, data);
            
            // 数据变化检测：只在数据变化时更新UI
            final previousData = _latestData[deviceSN];
            if (previousData != null && _isDataEqual(previousData, inverterRealtime)) {
              // 数据未变化，跳过更新
              if (kDebugMode) {
                debugPrint('[RealtimeDataService] Data unchanged for $deviceSN, skipping update');
              }
              return;
            }
            
            _latestData[deviceSN] = inverterRealtime;
            _realtimeController.add(inverterRealtime);

            // 更新在线状态 - 从 realtime 或 data 中获取
            final online = realtime['online'] as bool? ?? 
                          data['online'] as bool? ?? false;
            final status = OnlineStatus(online: online);
            _statusController.add(status);
            
            if (kDebugMode) {
              debugPrint('[RealtimeDataService] Successfully parsed data for $deviceSN, online: $online');
            }
          } else {
            if (kDebugMode) {
              debugPrint('[RealtimeDataService] No realtime data in response for $deviceSN');
            }
          }
        } else {
          if (kDebugMode) {
            debugPrint('[RealtimeDataService] Invalid response: code=${json['code']}, message=${json['message']}');
          }
        }
      } else {
        if (kDebugMode) {
          debugPrint('[RealtimeDataService] HTTP error ${response.statusCode} for $deviceSN');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RealtimeDataService] Error fetching data for $deviceSN: $e');
      }
    }
  }

  InverterRealtime _parseRealtimeData(
    String deviceSN,
    Map<String, dynamic> realtime,
    Map<String, dynamic> responseData,
  ) {
    if (kDebugMode) {
      debugPrint('[RealtimeDataService] Parsing realtime data, keys: ${realtime.keys.toList()}');
    }
    
    // 检查是否是嵌套结构（ac, battery, pv等）还是扁平结构
    // V2: ac/pv/bat/sys/eng/chr/fan/diag/sock, V1: ac/battery/batt/pv/sys_status/energy
    final isNested = realtime.containsKey('ac') || 
                     realtime.containsKey('battery') || 
                     realtime.containsKey('batt') ||
                     realtime.containsKey('bat') ||
                     realtime.containsKey('pv') ||
                     realtime.containsKey('eng') ||
                     realtime.containsKey('chr');
    
    if (kDebugMode) {
      debugPrint('[RealtimeDataService] Data structure: ${isNested ? "nested" : "flat"}');
    }
    
    // 从 realtime map 中解析各个组件数据
    ACData? acData;
    BatteryData? batteryData;
    PVData? pvData;
    SystemStatus? sysStatusData;
    EnergyData? energyData;
    FanData? fanData;
    int workTimeTotalSec = 0;
    CellsData? cellsData;
    DeviceInfo? deviceInfoData;
    MeterData? meterData;
    
    if (isNested) {
      // 嵌套结构：直接解析
      // 辅助函数：提取嵌套对象中的数据（支持 {"data": {...}} 格式）
      Map<String, dynamic>? extractNestedData(dynamic value) {
        if (value == null) return null;
        if (value is Map<String, dynamic>) {
          // 检查是否有 data 子字段（新格式：{"data": {...}, "timestamp": ...}）
          if (value.containsKey('data') && value['data'] is Map<String, dynamic>) {
            return value['data'] as Map<String, dynamic>;
          }
          // 旧格式：直接是字段值
          return value;
        }
        return null;
      }

      acData = realtime['ac'] != null
          ? ACData.fromJson(extractNestedData(realtime['ac'])!)
          : null;

      // V2: bat, V1: battery
      final batGroup = realtime['bat'] is Map ? realtime['bat']
          : realtime['battery'] is Map ? realtime['battery']
          : realtime['batt'] is Map ? realtime['batt'] : null;
      batteryData = batGroup != null
          ? BatteryData.fromJson(extractNestedData(batGroup)!)
          : null;

      pvData = realtime['pv'] is Map
          ? PVData.fromJson(extractNestedData(realtime['pv'])!)
          : null;

      // V2: sys, V1: sys_status
      // 注意：V2 中 sys_status 是 int（位掩码），不是 Map，需要用 sys 组
      final sysGroup = realtime['sys'] is Map ? realtime['sys'] : (realtime['sys_status'] is Map ? realtime['sys_status'] : null);
      sysStatusData = sysGroup != null
          ? SystemStatus.fromJson(extractNestedData(sysGroup)!)
          : null;

      // V2: eng, V1: energy
      final engGroup = realtime['eng'] is Map ? realtime['eng']
          : realtime['energy'] is Map ? realtime['energy'] : null;
      energyData = engGroup != null
          ? EnergyData.fromJson(extractNestedData(engGroup)!)
          : null;

      // V2.1 新增组：fan（双风扇转速）/ diag（诊断量）
      if (realtime['fan'] is Map) {
        fanData = FanData.fromJson(extractNestedData(realtime['fan'])!);
      }
      final diagGroup = realtime['diag'] is Map
          ? extractNestedData(realtime['diag'])
          : null;
      workTimeTotalSec =
          (diagGroup?['work_time_total'] as num?)?.toInt() ?? 0;

      cellsData = realtime['cells'] != null
          ? CellsData.fromJson(extractNestedData(realtime['cells'])!)
          : null;

      deviceInfoData = realtime['device_info'] != null
          ? DeviceInfo.fromJson(extractNestedData(realtime['device_info'])!)
          : null;

      meterData = realtime['meter'] != null
          ? MeterData.fromJson(extractNestedData(realtime['meter'])!)
          : null;
    } else {
      // 扁平结构：顶层键即 V2.1 协议键（服务端 normalizeRealtimeData 展平后），
      // 直接用实体 fromJson 解析，按代表性键做存在性守卫避免全 0 假数据
      if (kDebugMode) {
        debugPrint('[RealtimeDataService] Building objects from flat data');
      }

      if (realtime.containsKey('ac_output_voltage') ||
          realtime.containsKey('output_power')) {
        acData = ACData.fromJson(realtime);
      }

      if (realtime.containsKey('battery_soc') ||
          realtime.containsKey('battery_voltage')) {
        batteryData = BatteryData.fromJson(realtime);
      }

      if (realtime.containsKey('pv1_voltage') ||
          realtime.containsKey('pv_total_power')) {
        pvData = PVData.fromJson(realtime);
      }

      if (realtime.containsKey('work_state') ||
          realtime.containsKey('inverter_temperature')) {
        sysStatusData = SystemStatus.fromJson(realtime);
      }

      if (realtime.containsKey('daily_pv_energy') ||
          realtime.containsKey('total_pv_energy')) {
        energyData = EnergyData.fromJson(realtime);
      }

      if (realtime.containsKey('mppt_fan_speed') ||
          realtime.containsKey('inv_fan_speed')) {
        fanData = FanData.fromJson(realtime);
      }

      workTimeTotalSec =
          (realtime['work_time_total'] as num?)?.toInt() ?? 0;
    }

    final loadPower = (realtime['load_power'] as num?)?.toDouble() ?? 0;

    final updatedAtStr = realtime['updated_at'] as String? ??
        responseData['data_time'] as String? ??
        '';
    // 时间戳缺失时保持 null（视为未知），不用 DateTime.now() 兜底，
    // 避免把陈旧数据误当实时值展示
    final updatedAt = DateTime.tryParse(updatedAtStr);

    final onlineValue = realtime['online'] ?? responseData['online'];
    final onlineStatus = onlineValue != null
        ? OnlineStatus(online: onlineValue == true || onlineValue == 1)
        : null;

    if (kDebugMode) {
      debugPrint('[RealtimeDataService] Parsed: ac=${acData != null}, battery=${batteryData != null}, pv=${pvData != null}, sysStatus=${sysStatusData != null}, energy=${energyData != null}, fan=${fanData != null}, workTimeTotalSec=$workTimeTotalSec');
    }

    return InverterRealtime(
      deviceSN: deviceSN,
      ac: acData,
      battery: batteryData,
      pv: pvData,
      sysStatus: sysStatusData,
      energy: energyData,
      fan: fanData,
      workTimeTotalSec: workTimeTotalSec,
      cells: cellsData,
      onlineStatus: onlineStatus,
      deviceInfo: deviceInfoData,
      meter: meterData,
      loadPower: loadPower,
      updatedAt: updatedAt,
    );
  }

  /// 比较两个 InverterRealtime 对象是否相等
  /// 用于数据变化检测，避免重复更新UI
  bool _isDataEqual(InverterRealtime a, InverterRealtime b) {
    // 比较关键字段
    if (a.ac?.power != b.ac?.power) return false;
    if (a.battery?.soc != b.battery?.soc) return false;
    if (a.pv?.pvPower != b.pv?.pvPower) return false;
    if (a.sysStatus?.state != b.sysStatus?.state) return false;
    if (a.energy?.dailyPV != b.energy?.dailyPV) return false;
    if (a.onlineStatus?.online != b.onlineStatus?.online) return false;
    return true;
  }
}
