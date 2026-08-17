import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/core/widgets/xiaoshuo_state_panel.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/realtime_data_service.dart';
import 'package:inv_app/core/services/connection_mode_service.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/entities/device_model_field.dart';
import 'package:inv_app/core/utils/telemetry_quality.dart';
import 'package:inv_app/core/utils/api_response.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class DeviceRealtimePage extends StatefulWidget {
  final String sn;
  final String type;

  const DeviceRealtimePage({super.key, required this.sn, required this.type});

  @override
  State<DeviceRealtimePage> createState() => _DeviceRealtimePageState();
}

class _DeviceRealtimePageState extends State<DeviceRealtimePage> {
  final Map<String, dynamic> _realtimeData = {};
  List<DeviceModelField> _modelFields = [];
  bool _online = false;
  bool _loading = true;
  String? _error;
  String? _modelName;
  StreamSubscription? _statusSub;
  StreamSubscription? _realtimeSub;
  bool _hasMqttData = false;
  bool _apiUnavailable = false;
  bool _isLocalMode = false;

  /// 遥测数据时间戳（用于滞后提示；null 表示未知）
  DateTime? _dataUpdatedAt;

  /// 周期性刷新滞后状态：设备离线后数据不再更新，
  /// 需要定时器驱动 UI 进入"数据滞后"态
  Timer? _staleRefreshTimer;

  /// 超过该时长未更新的遥测数据视为滞后
  static const Duration _staleThreshold = Duration(minutes: 5);

  // 分组定义（颜色和图标）
  static const _groupStyles = {
    'ac_params': {'icon': Icons.bolt_rounded, 'color': AppColors.purple},
    'pv_params': {'icon': Icons.wb_sunny_outlined, 'color': AppColors.orange},
    'battery_params': {
      'icon': Icons.battery_charging_full,
      'color': AppColors.successLight,
    },
    'system_status': {
      'icon': Icons.info_outline_rounded,
      'color': Color(0xFF06B6D4),
    },
    'energy_stats': {
      'icon': Icons.show_chart_rounded,
      'color': AppColors.blue,
    },
    'device_info': {
      'icon': Icons.device_hub_rounded,
      // 静态映射无 BuildContext，保留浅色固定值（主题色统一入口见 AppColor）
      'color': AppColors.textSecondary,
    },
    'control_cmd': {'icon': Icons.tune_rounded, 'color': AppColors.errorLight},
  };

  // 英文 key 到 l10n 显示名的映射（支持多种 group_name 格式）
  String _localizedGroupName(String groupName) {
    final l10n = AppLocalizations.of(context)!;
    // 将不同格式的 group_name 统一规范化为内部 key
    final normalized = _normalizeGroupName(groupName);
    switch (normalized) {
      case 'ac_params':
        return l10n.groupAcParams;
      case 'pv_params':
        return l10n.groupPvParams;
      case 'battery_params':
        return l10n.groupBatteryParams;
      case 'system_status':
        return l10n.groupSystemStatus;
      case 'energy_stats':
        return l10n.groupEnergyStats;
      case 'device_info':
        return l10n.groupDeviceInfo;
      case 'control_cmd':
        return l10n.groupControlCmd;
      default:
        return l10n.groupOther;
    }
  }

  /// 将后端返回的各种 group_name 格式统一规范化为内部 key
  /// 支持格式：
  ///   - 内部 key: ac_params, pv_params, ...
  ///   - 后端短格式: ac, pv, battery, energy, system, status
  ///   - Admin 前端格式: models.acParams, models.batteryParams, ...
  ///   - 中文显示名: 交流参数, 光伏参数, ...
  static String _normalizeGroupName(String raw) {
    // 已经是内部 key，直接返回
    const internalKeys = {
      'ac_params',
      'pv_params',
      'battery_params',
      'system_status',
      'energy_stats',
      'device_info',
      'control_cmd',
    };
    if (internalKeys.contains(raw)) return raw;
    // 后端数据库短格式 → 内部 key
    const shortKeyMap = {
      'ac': 'ac_params',
      'pv': 'pv_params',
      'battery': 'battery_params',
      'bms': 'battery_params',
      'energy': 'energy_stats',
      'system': 'system_status',
      'status': 'system_status',
      'info': 'device_info',
      'control': 'control_cmd',
    };
    if (shortKeyMap.containsKey(raw)) return shortKeyMap[raw]!;
    // Admin 前端格式 models.xxx → 内部 key
    const adminKeyMap = {
      'models.acParams': 'ac_params',
      'models.batteryParams': 'battery_params',
      'models.pvParams': 'pv_params',
      'models.systemStatus': 'system_status',
      'models.energyStats': 'energy_stats',
      'models.deviceInfo': 'device_info',
      'models.controlStatus': 'control_cmd',
      'models.inverterControl': 'control_cmd',
      'models.bmsControl': 'control_cmd',
      'models.mpptControl': 'control_cmd',
      'models.epsControl': 'control_cmd',
      'models.parallelControl': 'control_cmd',
    };
    if (adminKeyMap.containsKey(raw)) return adminKeyMap[raw]!;
    // 中文显示名 → 内部 key
    const chineseMap = {
      '交流参数': 'ac_params',
      '光伏参数': 'pv_params',
      '电池参数': 'battery_params',
      '系统状态': 'system_status',
      '能量统计': 'energy_stats',
      '设备信息': 'device_info',
      '控制参数': 'control_cmd',
      '控制指令': 'control_cmd',
    };
    if (chineseMap.containsKey(raw)) return chineseMap[raw]!;
    // 无法识别，原样返回
    return raw;
  }

  @override
  void initState() {
    super.initState();
    _initLocalMode();
    _subscribeMqttData();
    _listenOnlineStatus();
    _fetchDeviceDetail();
    // 每 30 秒刷新一次，保证数据停更后滞后提示能及时出现
    _staleRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _dataUpdatedAt != null) {
        setState(() {});
      }
    });
  }

  /// 检测本地模式并启动 bloc 本地轮询（含逆变器连接监控）
  Future<void> _initLocalMode() async {
    try {
      final modeService = getIt<ConnectionModeService>();
      await modeService.init();
      if (modeService.isLocal && mounted) {
        setState(() => _isLocalMode = true);
        // 启动 bloc 本地轮询：每 3 秒拉取逆变器实时数据并喂给连接监控
        context.read<DeviceBloc>().add(
              const DeviceStartLocalPoll(deviceIP: '192.168.4.1'),
            );
      }
    } catch (_) {
      // ConnectionModeService 不可用时忽略
    }
  }

  void _listenOnlineStatus() {
    try {
      final realtimeService = getIt<RealtimeDataService>();
      _statusSub = realtimeService.statusStream
          .where((status) => true) // 接收所有状态更新
          .listen((status) {
        if (mounted) {
          setState(() {
            _online = status.online;
          });
        }
      });
    } catch (_) {
      // MQTT 服务未初始化时忽略
    }
  }

  @override
  void dispose() {
    // 本地模式下停止 bloc 本地轮询和连接监控
    if (_isLocalMode) {
      try {
        // 使用全局 bloc 访问，避免 context 已失效
        final bloc =
            getIt.isRegistered<DeviceBloc>() ? getIt<DeviceBloc>() : null;
        bloc?.add(const DeviceStopLocalPoll());
      } catch (_) {}
    }
    _statusSub?.cancel();
    _realtimeSub?.cancel();
    _staleRefreshTimer?.cancel();
    try {
      getIt<RealtimeDataService>().stopPolling(widget.sn);
    } catch (_) {}
    super.dispose();
  }

  Future<void> _fetchDeviceDetail() async {
    try {
      final dio = getIt<Dio>();
      // API 路径: /devices/by-sn/:sn
      final res = await dio
          .get('/devices/by-sn/${widget.sn}')
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200 && mounted) {
        final data = unwrapApiResponse<Map<String, dynamic>>(
          res.data,
          validate: (value) => value is Map<String, dynamic>,
          expected: 'an object',
        );

        // 解析 realtime_data
        final realtimeRaw =
            data['realtime_data'] as Map<String, dynamic>? ?? {};
        Map<String, dynamic> flatData = {};

        // realtime_data 可能是嵌套结构（ac/pv/energy 对象），展平它
        // 数据结构可能是 {"ac": {"power": 2319}} 或 {"ac": {"data": {...}, "timestamp": ...}}
        realtimeRaw.forEach((key, value) {
          if (value is Map<String, dynamic>) {
            // 检查是否有 data 子字段（新格式）
            if (value.containsKey('data') &&
                value['data'] is Map<String, dynamic>) {
              final innerData = value['data'] as Map<String, dynamic>;
              innerData.forEach((subKey, subValue) {
                final flatKey = '${key}_$subKey';
                flatData[flatKey] = subValue;
              });
            } else {
              // 旧格式：直接嵌套
              value.forEach((subKey, subValue) {
                final flatKey = '${key}_$subKey';
                flatData[flatKey] = subValue;
              });
            }
          } else {
            flatData[key] = value;
          }
        });

        // 解析 model_fields
        final fieldsRaw = data['model_fields'] as List<dynamic>? ?? [];
        final fields = fieldsRaw
            .map((e) => DeviceModelField.fromJson(e as Map<String, dynamic>))
            .where((f) => f.isShow)
            .toList();

        setState(() {
          // 合并 API 数据到现有数据（MQTT 实时数据优先）
          _realtimeData.addAll(flatData);
          // 提取遥测时间戳（后端字段兼容 updated_at / data_time）
          final updatedAtStr = (data['updated_at'] ??
                  data['data_time'] ??
                  realtimeRaw['updated_at'])
              as String?;
          final parsed =
              updatedAtStr == null ? null : DateTime.tryParse(updatedAtStr);
          if (parsed != null) {
            _dataUpdatedAt = parsed;
          }
          // 始终使用 API 返回的字段配置（比默认更完整）
          if (fields.isNotEmpty) {
            _modelFields = fields;
          } else if (_modelFields.isEmpty) {
            // API 未返回 model_fields（型号字段未配置），
            // 用已有的 realtime 数据兜底生成默认字段
            _modelFields = _buildDefaultModelFields();
          }
          _online = data['online_status']?['online'] == true ||
              data['device']?['status'] == 1;
          _modelName = data['device']?['model'] as String?;
          _loading = false;
          _error = null;
          _apiUnavailable = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _apiUnavailable = true;
          // 只有已经实际收到 MQTT 数据时才允许降级展示。
          if (_hasMqttData && _modelFields.isEmpty) {
            _modelFields = _buildDefaultModelFields();
          }
          _loading = false;
          _error = _hasMqttData
              ? null
              : AppLocalizations.of(context)!.str('realtime_load_failed');
        });
      }
    }
  }

  /// 订阅实时数据流，通过 API 轮询获取实时数据
  void _subscribeMqttData() {
    try {
      final realtimeService = getIt<RealtimeDataService>();
      // 页面打开时先读取已缓存的实时数据（避免数据未变化导致流不触发）
      final cached = realtimeService.getLatestData(widget.sn);
      if (cached != null && mounted) {
        setState(() {
          final newMqttData = _inverterToFlatMap(cached);
          _realtimeData.addAll(newMqttData);
          _hasMqttData = true;
          if (cached.updatedAt != null) {
            _dataUpdatedAt = cached.updatedAt;
          }
          if (_modelFields.isEmpty) {
            _modelFields = _buildDefaultModelFields();
          }
          if (cached.onlineStatus != null) {
            _online = cached.onlineStatus!.online;
          }
          if (_loading) {
            _loading = false;
            _error = null;
          }
        });
      }
      realtimeService.startPolling(widget.sn);
      _realtimeSub = realtimeService.realtimeDataStream
          .where((rt) => rt.deviceSN == widget.sn)
          .listen((rt) {
        if (mounted) {
          setState(() {
            // 合并 MQTT 新数据到现有数据，而非完全替换
            // 这样 API 返回的字段不会因 MQTT 数据缺失而丢失
            final newMqttData = _inverterToFlatMap(rt);
            _realtimeData.addAll(newMqttData);
            _hasMqttData = true;
            if (rt.updatedAt != null) {
              _dataUpdatedAt = rt.updatedAt;
            }
            if (_apiUnavailable) {
              _error = null;
            }
            if (rt.onlineStatus != null) {
              _online = rt.onlineStatus!.online;
            }
            if (rt.deviceInfo?.model != null &&
                rt.deviceInfo!.model.isNotEmpty) {
              _modelName = rt.deviceInfo!.model;
            }
            // API 未成功获取字段配置时，使用默认配置
            if (_modelFields.isEmpty) {
              _modelFields = _buildDefaultModelFields();
            }
            // 首次收到 MQTT 数据时取消 loading 状态
            if (_loading) {
              _loading = false;
              _error = null;
            }
          });
        }
      });
    } catch (_) {
      // MQTT 服务不可用时忽略
    }
  }

  /// 将 InverterRealtime 转为与云端 API 一致的扁平 Map，
  /// key 与 _fieldNameMap 中的键保持一致
  Map<String, dynamic> _inverterToFlatMap(InverterRealtime rt) {
    final map = <String, dynamic>{};
    // AC
    if (rt.ac != null) {
      map['ac_voltage'] = rt.ac!.voltage;
      map['ac_current'] = rt.ac!.current;
      map['ac_power'] = rt.ac!.power;
      map['ac_frequency'] = rt.ac!.frequency;
      map['ac_load_percent'] = rt.ac!.loadPercent;
      map['ac_pf'] = rt.ac!.pf;
    }
    // Battery
    if (rt.battery != null) {
      map['batt_soc'] = rt.battery!.soc;
      map['batt_soh'] = rt.battery!.soh;
      map['batt_voltage'] = rt.battery!.voltage;
      map['batt_current'] = rt.battery!.current;
      map['batt_charge_state'] = rt.battery!.chargeState;
    }
    // PV
    if (rt.pv != null) {
      map['pv_voltage'] = rt.pv!.pvVoltage;
      map['pv_current'] = rt.pv!.pvCurrent;
      map['pv_power'] = rt.pv!.pvPower;
      map['mppt_state'] = rt.pv!.mpptState;
    }
    // System Status
    if (rt.sysStatus != null) {
      map['state'] = rt.sysStatus!.state;
      map['fault_code'] = rt.sysStatus!.faultCode;
      map['alarm_code'] = rt.sysStatus!.alarmCode;
      map['temp_inv'] = rt.sysStatus!.tempInv;
      map['temp_mos'] = rt.sysStatus!.tempMos;
      map['efficiency'] = rt.sysStatus!.efficiency;
    }
    // Energy
    if (rt.energy != null) {
      map['daily_pv'] = rt.energy!.dailyPV;
      map['total_pv'] = rt.energy!.totalPV;
      map['runtime_hours'] = rt.energy!.runtimeHours;
      map['daily_feed_energy'] = rt.energy!.dailyFeedEnergy;
      map['total_feed_energy'] = rt.energy!.totalFeedEnergy;
      map['daily_grid_import'] = rt.energy!.dailyGridImport;
      map['total_grid_import'] = rt.energy!.totalGridImport;
    }
    // Cells
    if (rt.cells != null && rt.cells!.voltages.isNotEmpty) {
      map['cell_count'] = rt.cells!.cellCount;
    }
    // Device Info
    if (rt.deviceInfo != null) {
      map['model'] = rt.deviceInfo!.model;
    }
    if (rt.loadPower != 0) {
      map['load_power'] = rt.loadPower;
    }
    return map;
  }

  /// 构建默认字段配置（API 不可用时的兜底），
  /// 仅包含 _fieldNameMap 中有对应数据且值非零的字段
  List<DeviceModelField> _buildDefaultModelFields() {
    final fields = <DeviceModelField>[];
    int sortIdx = 0;
    _fieldNameMap.forEach((key, _) {
      // 只展示当前有数据的字段
      final value = _realtimeData[key];
      if (value != null) {
        final idx = sortIdx++;
        final fType =
            value is int ? 'int' : (value is num ? 'float' : 'string');
        fields.add(
          DeviceModelField(
            id: idx,
            modelId: 0,
            fieldKey: key,
            fieldName: '',
            fieldType: fType,
            sort: idx,
          ),
        );
      }
    });
    return fields;
  }

  // field_key → 中文名称映射（后端 field_name 缺失时的兜底）
  // 包含所有 device_model_fields 表中 model_id=2 的 field_key
  static const _fieldNameMap = {
    // 交流参数
    'ac_voltage': '输出电压',
    'ac_current': '输出电流',
    'ac_active_power': '有功功率',
    'ac_power': '有功功率',
    'ac_apparent_power': '视在功率',
    'ac_frequency': '输出频率',
    'ac_power_factor': '功率因数',
    'ac_voltage_thd': '电压THD',
    'load_percent': '负载率',
    'power_factor': '功率因数',
    'apparent_power': '视在功率',
    'load_rate': '负载率',
    'voltage_thd': '电压THD',
    'ac_load_percent': '负载率',
    'ac_pf': '功率因数',
    'load_power': '负载功率',
    // 电池参数
    'battery_soc': '电池SOC',
    'battery_soh': '电池SOH',
    'battery_voltage': '电池电压',
    'battery_current': '电池电流',
    'battery_temperature': '电池温度',
    'battery_power': '充放电功率',
    'battery_state': '充放电状态',
    'battery_capacity_remain': '剩余容量',
    'battery_capacity_total': '额定容量',
    'battery_cycle_count': '循环次数',
    'battery_protect_status': '保护状态',
    'battery_temp_min': '电池最低温度',
    'battery_temp_max': '电池最高温度',
    'cell_voltage_min': '单体最低电压',
    'cell_voltage_max': '单体最高电压',
    'cell_voltage_diff': '电芯压差',
    'charge_voltage_ref': '充电参考电压',
    'discharge_cutoff_voltage': '放电截止电压',
    'max_charge_current': '最大充电电流',
    'max_discharge_current': '最大放电电流',
    'charge_request_current_x10': '充电请求电流',
    'charge_request_voltage_x10': '充电请求电压',
    'bms_fault_code': 'BMS故障码',
    'batt_soc': '电池SOC',
    'batt_soh': '电池SOH',
    'batt_voltage': '电池电压',
    'batt_current': '电池电流',
    'charge_status': '充放电状态',
    'battery_capacity': '电池容量',
    'battery_health': '电池健康度',
    'charge_discharge_power': '充放电功率',
    'remaining_capacity': '剩余容量',
    'rated_capacity': '额定容量',
    'cycle_count': '循环次数',
    'cell_max_temp': '电芯最高温度',
    'cell_min_temp': '电芯最低温度',
    'cell_max_voltage': '单体最高电压',
    'cell_min_voltage': '单体最低电压',
    'battery_avg_temp': '电池平均温度',
    'protect_status': '保护状态',
    'max_chg_current': '最大充电电流',
    'max_dischg_current': '最大放电电流',
    'charge_volt_ref': '充电参考电压',
    'dischg_cut_volt': '放电截止电压',
    'batt_charge_state': '充放电状态',
    // 光伏参数
    'pv1_voltage': 'PV1电压',
    'pv2_voltage': 'PV2电压',
    'pv1_current': 'PV1电流',
    'pv2_current': 'PV2电流',
    'pv1_power': 'PV1功率',
    'pv2_power': 'PV2功率',
    'pv_total_power': 'PV总功率',
    'pv1_voltage_max': 'PV1历史最高电压',
    'pv1_power_max': 'PV1历史最高功率',
    'pv2_voltage_max': 'PV2历史最高电压',
    'pv2_power_max': 'PV2历史最高功率',
    'mppt_state': 'MPPT状态',
    'mppt_status': 'MPPT状态',
    'pv_voltage': '光伏电压',
    'pv_current': '光伏电流',
    'pv_power': '光伏功率',
    // 系统状态
    'work_state': '工作状态',
    'fault_code': '故障码',
    'alarm_code': '告警码',
    'inverter_temperature': '逆变器温度',
    'mos_temperature': 'MOS温度',
    'ambient_temperature': '环境温度',
    'fan_speed_percent': '风扇转速',
    'dc_bus_voltage': '直流母线电压',
    'efficiency': '转换效率',
    'runtime_hours': '运行时长',
    'system_mode': '系统模式',
    'run_status': '运行状态',
    'state': '工作状态',
    'inverter_temp': '逆变器温度',
    'heatsink_temp': '散热器温度',
    'ambient_temp': '环境温度',
    'vbus1': '母线电压1',
    'vbus2': '母线电压2',
    'total_run_time': '累计运行时长',
    'fan_speed': '风扇转速',
    'temp_inv': '逆变器温度',
    'temp_mos': 'MOS温度',
    'internal_temperature': '内部温度',
    'bus_voltage': '母线电压',
    'work_state_1': '工作状态',
    'work_state_1_code': '状态码',
    'output_type': '输出类型',
    'nominal_active_power': '额定有功功率',
    // 能量统计
    'daily_pv_energy': '日发电量',
    'daily_charge_energy': '日充电量',
    'daily_discharge_energy': '日放电量',
    'daily_load_energy': '日用电量',
    'total_charge_energy': '累计充电量',
    'total_discharge_energy': '累计放电量',
    'total_load_energy': '累计用电量',
    'total_pv_energy': '累计发电量',
    'total_charge_capacity': '累计充电容量',
    'total_discharge_capacity': '累计放电容量',
    'total_charge_time': '累计充电时间',
    'total_discharge_time': '累计放电时间',
    'energy': '当日发电量',
    'total_energy': '累计发电量',
    'daily_charge': '当日充电量',
    'total_charge': '累计充电量',
    'discharge': '当日放电量',
    'total_discharge': '累计放电量',
    'daily_consumption': '当日用电量',
    'total_consumption': '累计用电量',
    'run_time': '运行时间',
    'daily_pv': '日发电量',
    'total_pv': '累计发电量',
    'daily_feed_energy': '日馈网电量',
    'total_feed_energy': '累计馈网电量',
    'daily_grid_import': '日购电量',
    'total_grid_import': '累计购电量',
    'daily_power_yields': '日发电量',
    'total_power_yields': '累计发电量',
    'grid_frequency': '电网频率',
    // 电表参数
    'meter_total_power': '电表总功率',
    'meter_phase_a_power': 'A相功率',
    'meter_phase_b_power': 'B相功率',
    'meter_phase_c_power': 'C相功率',
    // 控制参数
    'power_limit': '功率上限',
    'charge_enable': '充电使能',
    'discharge_enable': '放电使能',
    'grid_charge_enable': '电网充电使能',
    // 设备信息
    'serial_number': '序列号',
    'total_active_power': '总有功功率',
  };

  /// 字段显示名称：优先使用 fieldName，若为空、与 fieldKey 相同、或是 i18n key 则查中文映射
  String _displayName(DeviceModelField field) {
    // fieldName 如果是 i18n key（如 "fields.battery_voltage"），不直接显示
    final fn = field.fieldName;
    final isI18nKey = fn.startsWith('fields.') || fn.startsWith('models.');
    if (fn.isNotEmpty && fn != field.fieldKey && !isI18nKey) {
      return fn;
    }
    // 查静态中文映射
    final mapped = _fieldNameMap[field.fieldKey];
    if (mapped != null) return mapped;
    // 最终兜底：格式化 field_key 为可读文本
    final key = field.fieldKey;
    if (key.isEmpty) return '--';
    return key[0].toUpperCase() + key.substring(1).replaceAll('_', ' ');
  }

  /// 根据 field_key 前缀推断分组名（当数据库 group_name 为空时使用）
  String _inferGroupFromFieldKey(String fieldKey) {
    if (fieldKey.startsWith('ac_')) return 'ac_params';
    if (fieldKey.startsWith('pv_')) return 'pv_params';
    if (fieldKey.startsWith('batt_') || fieldKey.startsWith('battery_')) {
      return 'battery_params';
    }
    if (fieldKey.startsWith('energy_') ||
        fieldKey.startsWith('daily_') ||
        fieldKey.startsWith('total_')) {
      return 'energy_stats';
    }
    if (fieldKey.startsWith('sys_') ||
        fieldKey.startsWith('state') ||
        fieldKey.startsWith('work_') ||
        fieldKey.startsWith('fault_') ||
        fieldKey.startsWith('internal_') ||
        fieldKey.startsWith('temp_')) {
      return 'system_status';
    }
    if (fieldKey.startsWith('load_')) return 'ac_params';
    if (fieldKey.startsWith('meter_')) return 'ac_params';
    return 'device_info';
  }

  /// 按 group_name 分组字段（group_name 为空时根据 field_key 前缀推断）
  Map<String, List<DeviceModelField>> _groupByField() {
    final groups = <String, List<DeviceModelField>>{};
    for (final field in _modelFields) {
      // 先规范化 group_name，再用于分组
      final rawGroup = field.groupName.isNotEmpty ? field.groupName : '';
      final group = rawGroup.isNotEmpty
          ? _normalizeGroupName(rawGroup)
          : _inferGroupFromFieldKey(field.fieldKey);
      groups.putIfAbsent(group, () => []).add(field);
    }
    // 按 sort 排序每个组内的字段
    for (final list in groups.values) {
      list.sort((a, b) => a.sort.compareTo(b.sort));
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocListener<DeviceBloc, DeviceState>(
      listener: (context, state) {
        if (state is DeviceLocalDisconnected) {
          // 逆变器无响应，已自动断开设备热点并切回家用 WiFi
          final l10n = AppLocalizations.of(context)!;
          AppToast.show(context, l10n.inverterNoResponse, type: ToastType.error);
          context.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColor.surfaceHover(context),
        appBar: AppBar(
          title: Text(
            l10n.deviceDetail,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17.sp),
          ),
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          backgroundColor: AppColor.surfaceContainer(context),
          foregroundColor: AppColor.textPrimary(context),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                setState(() => _loading = true);
                _fetchDeviceDetail();
              },
            ),
          ],
        ),
        body: _loading
            ? const PageSkeleton(cardCount: 4)
            : _error != null
                ? _buildError()
                : _buildContent(),
      ),
    );
  }

  Widget _buildError() {
    final l10n = AppLocalizations.of(context)!;
    // 小烁离线动作插画：设备详情加载失败/断网态（美术路由 C4/offline）
    return XiaoshuoStatePanel(
      asset: CsergyAssets.xiaoshuoOffline,
      title: _error!,
      message: l10n.loadFailed,
      size: 176,
      action: OutlinedButton(
        onPressed: () {
          setState(() {
            _loading = true;
            _error = null;
          });
          _fetchDeviceDetail();
        },
        child: Text(l10n.retry),
      ),
    );
  }

  Widget _buildContent() {
    final groups = _groupByField();

    return RefreshIndicator(
      onRefresh: _fetchDeviceDetail,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 40.h),
        children: [
          if (_apiUnavailable && _hasMqttData) _buildMqttFallbackBanner(),
          // 数据滞后提示：设备离线时陈旧数据不再被误当实时值
          _buildStaleDataBanner(),
          // 顶部状态卡片
          _buildStatusCard(),
          SizedBox(height: 12.h),
          // V2.1 健康卡片（服务器 derived 组；MQTT 直连时无数据则不渲染）
          _buildHealthCard(),
          SizedBox(height: 12.h),
          _buildTelemetryMetadataCard(),
          SizedBox(height: 12.h),
          // 参数设置入口
          _buildSettingsEntry(),
          SizedBox(height: 12.h),
          _buildProtocolEntry(),
          SizedBox(height: 16.h),
          // 动态分组
          ...groups.entries
              .map((entry) => _buildGroupCard(entry.key, entry.value)),
        ],
      ),
    );
  }

  /// 数据滞后提示：遥测时间戳超过阈值时展示，
  /// 避免设备离线时用户把陈旧功率/SOC 等数值当实时值
  Widget _buildStaleDataBanner() {
    final updatedAt = _dataUpdatedAt;
    if (updatedAt == null) return const SizedBox.shrink();
    final stale = DateTime.now().difference(updatedAt.toLocal()) >
        _staleThreshold;
    if (!stale) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final timeStr = DateFormat('HH:mm:ss').format(updatedAt.toLocal());
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.hourglass_bottom_rounded,
            size: 18.sp,
            color: AppColors.warning,
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              l10n.str('realtime_data_stale', {'time': timeStr}),
              style: TextStyle(fontSize: 12.sp, color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMqttFallbackBanner() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 18.w, color: AppColors.warning),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              l10n.str('realtime_mqtt_fallback'),
              style: TextStyle(fontSize: 12.sp, color: AppColors.warning),
            ),
          ),
          TextButton(
            onPressed: _fetchDeviceDetail,
            child: Text(l10n.retry),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    final l10n = AppLocalizations.of(context)!;
    final sn = widget.sn;
    final model = _modelName ?? '';

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: AppColor.heroCard(context),
      child: Row(
        children: [
          Container(
            width: 48.w,
            height: 48.w,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(
              Icons.solar_power_rounded,
              size: 28.w,
              color: Colors.white,
            ),
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sn,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                if (model.isNotEmpty)
                  Text(
                    model,
                    style: TextStyle(fontSize: 12.sp, color: Colors.white70),
                  ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
            decoration: BoxDecoration(
              color: _online ? AppColors.online : AppColors.offline,
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Text(
              _online ? l10n.online : l10n.offline,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// V2.1 健康卡片：健康度评分 + 散热状态 + 并机角色 + 维护提醒
  /// 数据源为服务器 realtime 的 derived 组（展平键 derived_*）；MQTT 直连时无此数据 → 不渲染。
  Widget _buildHealthCard() {
    final l10n = AppLocalizations.of(context)!;
    final score = _realtimeData['derived_health_score'];
    if (score == null) return const SizedBox.shrink();
    final level = (_realtimeData['derived_health_level'] as String?) ?? 'good';
    final thermal =
        (_realtimeData['derived_thermal_status'] as String?) ?? 'normal';
    final role =
        (_realtimeData['derived_parallel_role'] as String?) ?? 'n/a';
    final workTimeTotal = _realtimeData['diag_work_time_total']; // 秒

    final levelColor = switch (level) {
      'healthy' => AppColors.success,
      'attention' => AppColors.warning,
      'maintenance' => AppColors.error,
      _ => AppColors.blue,
    };
    final thermalColor = switch (thermal) {
      'fault' => AppColors.error,
      'warning' => AppColors.warning,
      _ => AppColors.success,
    };
    final thermalText = switch (thermal) {
      'fault' => l10n.str('health_thermal_fault'),
      'warning' => l10n.str('health_thermal_warning'),
      'normal' => l10n.str('health_thermal_normal'),
      _ => l10n.str('unknown'),
    };
    final roleText = switch (role) {
      'master' => l10n.str('health_role_master'),
      'slave' => l10n.str('health_role_slave'),
      'standalone' => l10n.str('health_role_standalone'),
      _ => l10n.str('unknown'),
    };
    final maintenanceDue =
        workTimeTotal is num && workTimeTotal >= 5000 * 3600;
    final workHours =
        workTimeTotal is num ? (workTimeTotal / 3600).toStringAsFixed(0) : null;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      decoration: AppColor.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.favorite_rounded,
                size: 18.sp,
                color: levelColor,
              ),
              SizedBox(width: 8.w),
              Text(
                l10n.str('health_score'),
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColor.textPrimary(context),
                ),
              ),
              const Spacer(),
              Text(
                '${score.round()}',
                style: TextStyle(
                  fontSize: 22.sp,
                  fontWeight: FontWeight.w700,
                  color: levelColor,
                ),
              ),
              SizedBox(width: 4.w),
              Text(
                '/100',
                style: TextStyle(fontSize: 12.sp, color: AppColor.textHint(context)),
              ),
              SizedBox(width: 8.w),
              _healthChip(
                l10n.str('health_level_$level'),
                levelColor,
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(
                child: _healthChip(
                  '${l10n.str('health_thermal')}: $thermalText',
                  thermalColor,
                  icon: Icons.thermostat_rounded,
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: _healthChip(
                  '${l10n.str('health_parallel_role')}: $roleText',
                  AppColors.blue,
                  icon: Icons.account_tree_outlined,
                ),
              ),
              if (workHours != null) ...[
                SizedBox(width: 8.w),
                Expanded(
                  child: _healthChip(
                    '${l10n.str('health_work_time')}: $workHours${l10n.str('health_hours')}',
                    AppColor.textSecondary(context),
                    icon: Icons.schedule_rounded,
                  ),
                ),
              ],
            ],
          ),
          if (maintenanceDue) ...[
            SizedBox(height: 10.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.build_circle_outlined,
                    size: 16.sp,
                    color: AppColors.warning,
                  ),
                  SizedBox(width: 6.w),
                  Expanded(
                    child: Text(
                      l10n.str('health_maintenance_due_hint'),
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 健康卡片内的状态小胶囊（标签 + 可选图标）
  Widget _healthChip(String text, Color color, {IconData? icon}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14.sp, color: color),
            SizedBox(width: 4.w),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.sp,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsEntry() {
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: () => context.push('/device/${widget.sn}/settings'),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        decoration: AppColor.card(context),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(
                Icons.tune_rounded,
                size: 20.sp,
                color: AppColors.primary,
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.paramSettings,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColor.textPrimary(context),
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    l10n.settingsEntryDesc,
                    style:
                        TextStyle(fontSize: 12.sp, color: AppColor.textHint(context)),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20.sp,
              color: AppColor.textHint(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryMetadataCard() {
    final l10n = AppLocalizations.of(context)!;
    final protocolVersion = _realtimeData['protocol_version'];
    final quality = decodeTelemetryQuality(_realtimeData['quality_flags']);
    final qualityColor = quality.isNormal == null
        ? AppColor.textHint(context)
        : quality.isNormal!
            ? AppColors.success
            : AppColors.warning;

    String qualityText;
    if (quality.isNormal == null) {
      qualityText = l10n.str('telemetry_not_reported');
    } else if (quality.isNormal!) {
      qualityText = '${l10n.str('telemetry_quality_normal')} (0)';
    } else {
      final parts = quality.flags.map((flag) => flag.label).toList();
      if (quality.unknownMask != 0) {
        parts.add(
          '${l10n.str('telemetry_unknown_quality')} 0x${quality.unknownMask.toRadixString(16).toUpperCase()}',
        );
      }
      qualityText = parts.join(' · ');
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      decoration: AppColor.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.verified_outlined,
                size: 18.sp,
                color: AppColors.primary,
              ),
              SizedBox(width: 8.w),
              Text(
                l10n.str('telemetry_metadata'),
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColor.textPrimary(context),
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(
                child: _metadataValue(
                  l10n.str('telemetry_protocol_version'),
                  protocolVersion == null
                      ? l10n.str('telemetry_not_reported')
                      : 'V$protocolVersion',
                ),
              ),
              Expanded(
                child: _metadataValue(
                  l10n.str('telemetry_sampling_interval'),
                  '3 min',
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Text(
            l10n.str('telemetry_data_quality'),
            style: TextStyle(fontSize: 12.sp, color: AppColor.textHint(context)),
          ),
          SizedBox(height: 4.h),
          Text(
            qualityText,
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w500,
              color: qualityColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metadataValue(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12.sp, color: AppColor.textHint(context)),
        ),
        SizedBox(height: 3.h),
        Text(
          value,
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
            color: AppColor.textPrimary(context),
          ),
        ),
      ],
    );
  }

  Widget _buildProtocolEntry() {
    return GestureDetector(
      onTap: () => context.push('/device/${widget.sn}/protocol'),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        decoration: AppColor.card(context),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(
                Icons.monitor_heart_outlined,
                size: 20.sp,
                color: AppColors.blue,
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.protocolTelemetryTitle,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColor.textPrimary(context),
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    AppLocalizations.of(context)!.protocolTelemetryDesc,
                    style:
                        TextStyle(fontSize: 12.sp, color: AppColor.textHint(context)),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20.sp,
              color: AppColor.textHint(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCard(String groupName, List<DeviceModelField> fields) {
    final style = _groupStyles[groupName] ??
        {'icon': Icons.device_hub, 'color': AppColors.primary};
    final icon = style['icon'] as IconData;
    final color = style['color'] as Color;
    final displayName = _localizedGroupName(groupName);

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: AppColor.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 组标题
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 14.w, 16.w, 8.w),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(6.w),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Icon(icon, size: 16.sp, color: color),
                ),
                SizedBox(width: 10.w),
                Text(
                  displayName,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColor.textPrimary(context),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColor.divider(context)),
          // 字段列表
          ...fields.map((field) => _buildFieldRow(field)),
        ],
      ),
    );
  }

  Widget _buildFieldRow(DeviceModelField field) {
    final value = _realtimeData[field.fieldKey];
    final displayValue = _formatFieldValue(value, field);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _displayName(field),
            style: TextStyle(fontSize: 13.sp, color: AppColor.textSecondary(context)),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayValue,
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColor.textPrimary(context),
                ),
              ),
              if (field.unit.isNotEmpty) ...[
                SizedBox(width: 4.w),
                Text(
                  field.unit,
                  style: TextStyle(fontSize: 11.sp, color: AppColor.textHint(context)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatFieldValue(dynamic value, DeviceModelField field) {
    if (value == null) return '--';

    switch (field.fieldType) {
      case 'float':
        if (value is num) return value.toStringAsFixed(1);
        return value.toString();
      case 'int':
        if (value is num) return value.toInt().toString();
        return value.toString();
      case 'bool':
        final l10n = AppLocalizations.of(context)!;
        return value == true || value == 1 || value == 'true'
            ? l10n.yesLabel
            : l10n.noLabel;
      default:
        return value.toString();
    }
  }
}
