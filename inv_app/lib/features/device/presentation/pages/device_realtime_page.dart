import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/mqtt_service.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/entities/device_model_field.dart';
import 'package:inv_app/core/utils/telemetry_quality.dart';
import 'package:inv_app/core/utils/api_response.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class DeviceRealtimePage extends StatefulWidget {
  final String sn;
  final String type;

  const DeviceRealtimePage({super.key, required this.sn, required this.type});

  @override
  State<DeviceRealtimePage> createState() => _DeviceRealtimePageState();
}

class _DeviceRealtimePageState extends State<DeviceRealtimePage> {
  Map<String, dynamic> _realtimeData = {};
  List<DeviceModelField> _modelFields = [];
  bool _online = false;
  bool _loading = true;
  String? _error;
  String? _modelName;
  StreamSubscription? _statusSub;
  StreamSubscription? _realtimeSub;
  bool _hasMqttData = false;
  bool _apiUnavailable = false;

  // 分组定义（颜色和图标）
  static const _groupStyles = {
    'ac_params': {'icon': Icons.bolt_rounded, 'color': Color(0xFF8B5CF6)},
    'pv_params': {'icon': Icons.wb_sunny_outlined, 'color': Color(0xFFF59E0B)},
    'battery_params': {
      'icon': Icons.battery_charging_full,
      'color': Color(0xFF10B981)
    },
    'system_status': {
      'icon': Icons.info_outline_rounded,
      'color': Color(0xFF06B6D4)
    },
    'energy_stats': {
      'icon': Icons.show_chart_rounded,
      'color': Color(0xFF3B82F6)
    },
    'device_info': {
      'icon': Icons.device_hub_rounded,
      'color': Color(0xFF6B7280)
    },
    'control_cmd': {'icon': Icons.tune_rounded, 'color': Color(0xFFEF4444)},
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
      'control_cmd'
    };
    if (internalKeys.contains(raw)) return raw;
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
    _subscribeMqttData();
    _listenOnlineStatus();
    _fetchDeviceDetail();
  }

  void _listenOnlineStatus() {
    try {
      final mqtt = getIt<MQTTService>();
      _statusSub = mqtt.statusStream
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
    _statusSub?.cancel();
    _realtimeSub?.cancel();
    try {
      getIt<MQTTService>().unsubscribeDeviceTopics(widget.sn);
    } catch (_) {}
    super.dispose();
  }

  Future<void> _fetchDeviceDetail() async {
    try {
      final dio = getIt<Dio>();
      final res = await dio
          .get('/devices/${widget.sn}')
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
          // 仅当 MQTT 尚未填充数据时才使用 API 数据（避免覆盖实时数据）
          if (!_hasMqttData) {
            _realtimeData = flatData;
          }
          // 始终使用 API 返回的字段配置（比默认更完整）
          if (fields.isNotEmpty) {
            _modelFields = fields;
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

  /// 订阅 MQTT 实时数据流，本地直连场景下替代云端 API 获取实时数据
  void _subscribeMqttData() {
    try {
      final mqtt = getIt<MQTTService>();
      mqtt.subscribeDeviceTopics(widget.sn);
      _realtimeSub = mqtt.realtimeDataStream
          .where((rt) => rt.deviceSN == widget.sn)
          .listen((rt) {
        if (mounted) {
          setState(() {
            // 合并 MQTT 新数据到现有数据，而非完全替换
            // 这样 API 返回的字段不会因 MQTT 数据缺失而丢失
            final newMqttData = _inverterToFlatMap(rt);
            _realtimeData.addAll(newMqttData);
            _hasMqttData = true;
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
    if (rt.protocolVersion != null) {
      map['protocol_version'] = rt.protocolVersion;
    }
    if (rt.qualityFlags != null) {
      map['quality_flags'] = rt.qualityFlags;
    }
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
      // 只展示当前有数据且非零值的字段
      final value = _realtimeData[key];
      if (value != null && value != 0 && value != '' && value != 0.0) {
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
  // 与 admin 前端 DEFAULT_FIELD_LABELS 保持一致（不含单位，单位由 field.unit 单独显示）
  static const _fieldNameMap = {
    // 交流参数
    'ac_voltage': '输出电压',
    'ac_current': '输出电流',
    'ac_power': '有功功率',
    'ac_frequency': '输出频率',
    'power_factor': '功率因数',
    'apparent_power': '视在功率',
    'load_rate': '负载率',
    'voltage_thd': '电压THD',
    'ac_load_percent': '负载率',
    'ac_pf': '功率因数',
    'load_power': '负载功率',
    // 电池参数
    'battery_soc': '电池SOC',
    'battery_voltage': '电池电压',
    'battery_current': '电池电流',
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
    'cell_voltage_diff': '电芯压差',
    'charge_status': '充放电状态',
    'battery_avg_temp': '电池平均温度',
    'bms_fault_code': 'BMS故障码',
    'protect_status': '保护状态',
    'max_chg_current': '最大充电电流',
    'max_dischg_current': '最大放电电流',
    'charge_volt_ref': '充电参考电压',
    'dischg_cut_volt': '放电截止电压',
    'batt_soc': '电池SOC',
    'batt_soh': '电池SOH',
    'batt_voltage': '电池电压',
    'batt_current': '电池电流',
    'batt_charge_state': '充放电状态',
    // 光伏参数
    'pv1_voltage': 'PV1电压',
    'pv2_voltage': 'PV2电压',
    'pv1_current': 'PV1电流',
    'pv2_current': 'PV2电流',
    'pv1_power': 'PV1功率',
    'pv2_power': 'PV2功率',
    'pv_total_power': 'PV总功率',
    'mppt_status': 'MPPT状态',
    'mppt_state': 'MPPT状态',
    'pv1_voltage_max': 'PV1历史最高电压',
    'pv1_power_max': 'PV1历史最高功率',
    'pv2_voltage_max': 'PV2历史最高电压',
    'pv2_power_max': 'PV2历史最高功率',
    'pv_voltage': '光伏电压',
    'pv_current': '光伏电流',
    'pv_power': '光伏功率',
    // 系统状态
    'run_status': '运行状态',
    'state': '工作状态',
    'fault_code': '故障码',
    'alarm_code': '告警码',
    'inverter_temp': '逆变器温度',
    'heatsink_temp': '散热器温度',
    'ambient_temp': '环境温度',
    'dc_bus_voltage': '直流母线电压',
    'vbus1': '母线电压1',
    'vbus2': '母线电压2',
    'efficiency': '转换效率',
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
    'runtime_hours': '运行时长',
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
    'max_charge_current': '最大充电电流',
    'max_discharge_current': '最大放电电流',
    // 设备信息
    'serial_number': '序列号',
    'total_active_power': '总有功功率',
  };

  /// 字段显示名称：优先使用 fieldName，若为空或与 fieldKey 相同则查中文映射
  String _displayName(DeviceModelField field) {
    if (field.fieldName.isNotEmpty && field.fieldName != field.fieldKey) {
      return field.fieldName;
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
    if (fieldKey.startsWith('batt_') || fieldKey.startsWith('battery_'))
      return 'battery_params';
    if (fieldKey.startsWith('energy_') ||
        fieldKey.startsWith('daily_') ||
        fieldKey.startsWith('total_')) return 'energy_stats';
    if (fieldKey.startsWith('sys_') ||
        fieldKey.startsWith('state') ||
        fieldKey.startsWith('work_') ||
        fieldKey.startsWith('fault_') ||
        fieldKey.startsWith('internal_') ||
        fieldKey.startsWith('temp_')) return 'system_status';
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(50.h),
        child: AppBar(
          title: Text(
            l10n.deviceDetail,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17.sp),
          ),
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
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
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildError() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 44.sp, color: AppColors.textHint),
          SizedBox(height: 12.h),
          Text(_error!,
              style:
                  TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
          SizedBox(height: 16.h),
          OutlinedButton(
            onPressed: () {
              setState(() {
                _loading = true;
                _error = null;
              });
              _fetchDeviceDetail();
            },
            child: Text(l10n.retry),
          ),
        ],
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
          // 顶部状态卡片
          _buildStatusCard(),
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
            child: Icon(Icons.solar_power_rounded,
                size: 28.w, color: Colors.white),
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sn,
                    style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                if (model.isNotEmpty)
                  Text(model,
                      style: TextStyle(fontSize: 12.sp, color: Colors.white70)),
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
                  color: Colors.white),
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
              child: Icon(Icons.tune_rounded,
                  size: 20.sp, color: AppColors.primary),
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
                        color: AppColors.textPrimary),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    l10n.settingsEntryDesc,
                    style:
                        TextStyle(fontSize: 12.sp, color: AppColors.textHint),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20.sp, color: AppColors.textHint),
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
        ? AppColors.textHint
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
            '${l10n.str('telemetry_unknown_quality')} 0x${quality.unknownMask.toRadixString(16).toUpperCase()}');
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
              Icon(Icons.verified_outlined,
                  size: 18.sp, color: AppColors.primary),
              SizedBox(width: 8.w),
              Text(
                l10n.str('telemetry_metadata'),
                style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
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
                    l10n.str('telemetry_sampling_interval'), '3 min'),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Text(l10n.str('telemetry_data_quality'),
              style: TextStyle(fontSize: 12.sp, color: AppColors.textHint)),
          SizedBox(height: 4.h),
          Text(
            qualityText,
            style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w500,
                color: qualityColor),
          ),
        ],
      ),
    );
  }

  Widget _metadataValue(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 12.sp, color: AppColors.textHint)),
        SizedBox(height: 3.h),
        Text(value,
            style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
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
              child: Icon(Icons.monitor_heart_outlined,
                  size: 20.sp, color: AppColors.blue),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '协议遥测',
                    style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    '告警生命周期、并机当前态与三相 3 分钟历史',
                    style:
                        TextStyle(fontSize: 12.sp, color: AppColors.textHint),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20.sp, color: AppColors.textHint),
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
                Text(displayName,
                    style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
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
          Text(_displayName(field),
              style:
                  TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayValue,
                style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
              ),
              if (field.unit.isNotEmpty) ...[
                SizedBox(width: 4.w),
                Text(field.unit,
                    style:
                        TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
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
