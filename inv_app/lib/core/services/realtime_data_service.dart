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
    final isNested = realtime.containsKey('ac') || 
                     realtime.containsKey('battery') || 
                     realtime.containsKey('batt') ||
                     realtime.containsKey('pv');
    
    if (kDebugMode) {
      debugPrint('[RealtimeDataService] Data structure: ${isNested ? "nested" : "flat"}');
    }
    
    // 从 realtime map 中解析各个组件数据
    ACData? acData;
    BatteryData? batteryData;
    PVData? pvData;
    SystemStatus? sysStatusData;
    EnergyData? energyData;
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

      batteryData = realtime['battery'] != null || realtime['batt'] != null
          ? BatteryData.fromJson(
              extractNestedData(realtime['battery'] ?? realtime['batt'])!,
            )
          : null;

      pvData = realtime['pv'] != null
          ? PVData.fromJson(extractNestedData(realtime['pv'])!)
          : null;

      sysStatusData = realtime['sys_status'] != null || realtime['sys'] != null
          ? SystemStatus.fromJson(
              extractNestedData(realtime['sys_status'] ?? realtime['sys'])!,
            )
          : null;

      energyData = realtime['energy'] != null
          ? EnergyData.fromJson(extractNestedData(realtime['energy'])!)
          : null;

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
      // 扁平结构：从键值对中提取数据构建对象
      if (kDebugMode) {
        debugPrint('[RealtimeDataService] Building objects from flat data');
      }
      
      // AC 数据 - 支持多种字段名格式
      if (realtime.containsKey('ac_voltage') || 
          realtime.containsKey('ac_power') || 
          realtime.containsKey('ac_active_power')) {
        acData = ACData(
          voltage: (realtime['ac_voltage'] as num?)?.toDouble() ?? 0,
          current: (realtime['ac_current'] as num?)?.toDouble() ?? 0,
          power: (realtime['ac_power'] as num?)?.toDouble() ?? 
                 (realtime['ac_active_power'] as num?)?.toDouble() ?? 0,
          frequency: (realtime['ac_frequency'] as num?)?.toDouble() ?? 0,
          loadPercent: (realtime['ac_load_percent'] as num?)?.toDouble() ?? 
                      (realtime['load_percent'] as num?)?.toDouble() ?? 0,
          pf: (realtime['ac_pf'] as num?)?.toDouble() ?? 
              (realtime['ac_power_factor'] as num?)?.toDouble() ?? 0,
        );
      }
      
      // Battery 数据 - 支持多种字段名格式
      if (realtime.containsKey('batt_soc') || 
          realtime.containsKey('batt_voltage') || 
          realtime.containsKey('battery_soc') || 
          realtime.containsKey('battery_voltage')) {
        batteryData = BatteryData(
          soc: (realtime['batt_soc'] as num?)?.toDouble() ?? 
               (realtime['battery_soc'] as num?)?.toDouble() ?? 0,
          soh: (realtime['batt_soh'] as num?)?.toDouble() ?? 
               (realtime['battery_soh'] as num?)?.toDouble() ?? 0,
          voltage: (realtime['batt_voltage'] as num?)?.toDouble() ?? 
                   (realtime['battery_voltage'] as num?)?.toDouble() ?? 0,
          current: (realtime['batt_current'] as num?)?.toDouble() ?? 
                   (realtime['battery_current'] as num?)?.toDouble() ?? 0,
          chargeState: realtime['batt_charge_state']?.toString() ?? 
                       realtime['battery_state']?.toString() ?? '',
        );
      }
      
      // PV 数据 - 支持多种字段名格式
      if (realtime.containsKey('pv_voltage') || 
          realtime.containsKey('pv_power') || 
          realtime.containsKey('pv_total_power') || 
          realtime.containsKey('pv1_voltage')) {
        pvData = PVData(
          pvVoltage: (realtime['pv_voltage'] as num?)?.toDouble() ?? 
                     (realtime['pv1_voltage'] as num?)?.toDouble() ?? 0,
          pvCurrent: (realtime['pv_current'] as num?)?.toDouble() ?? 
                     (realtime['pv1_current'] as num?)?.toDouble() ?? 0,
          pvPower: (realtime['pv_power'] as num?)?.toDouble() ?? 
                   (realtime['pv_total_power'] as num?)?.toDouble() ?? 0,
          mpptState: realtime['mppt_state']?.toString() ?? '',
        );
      }
      
      // System Status 数据 - 支持多种字段名格式
      if (realtime.containsKey('state') || 
          realtime.containsKey('temp_inv') || 
          realtime.containsKey('inverter_temperature') || 
          realtime.containsKey('work_state')) {
        sysStatusData = SystemStatus(
          state: realtime['state']?.toString() ?? 
                 realtime['work_state']?.toString() ?? '',
          faultCode: (realtime['fault_code'] as num?)?.toInt() ?? 0,
          alarmCode: (realtime['alarm_code'] as num?)?.toInt() ?? 0,
          tempInv: (realtime['temp_inv'] as num?)?.toDouble() ?? 
                   (realtime['inverter_temperature'] as num?)?.toDouble() ?? 0,
          tempMos: (realtime['temp_mos'] as num?)?.toDouble() ?? 
                   (realtime['mos_temperature'] as num?)?.toDouble() ?? 0,
          efficiency: (realtime['efficiency'] as num?)?.toDouble() ?? 0,
        );
      }
      
      // Energy 数据 - 支持多种字段名格式
      if (realtime.containsKey('daily_pv') || 
          realtime.containsKey('total_pv') || 
          realtime.containsKey('daily_pv_energy') || 
          realtime.containsKey('total_pv_energy')) {
        energyData = EnergyData(
          dailyPV: (realtime['daily_pv'] as num?)?.toDouble() ?? 
                   (realtime['daily_pv_energy'] as num?)?.toDouble() ?? 0,
          totalPV: (realtime['total_pv'] as num?)?.toDouble() ?? 
                   (realtime['total_pv_energy'] as num?)?.toDouble() ?? 0,
          runtimeHours: (realtime['runtime_hours'] as num?)?.toInt() ?? 0,
          dailyFeedEnergy: (realtime['daily_feed_energy'] as num?)?.toDouble() ?? 0,
          totalFeedEnergy: (realtime['total_feed_energy'] as num?)?.toDouble() ?? 0,
          dailyGridImport: (realtime['daily_grid_import'] as num?)?.toDouble() ?? 0,
          totalGridImport: (realtime['total_grid_import'] as num?)?.toDouble() ?? 0,
        );
      }
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
      debugPrint('[RealtimeDataService] Parsed: ac=${acData != null}, battery=${batteryData != null}, pv=${pvData != null}, sysStatus=${sysStatusData != null}, energy=${energyData != null}');
    }

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
