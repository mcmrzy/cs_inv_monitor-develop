import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/mqtt_service.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/entities/device_model_field.dart';
import 'package:inv_app/features/device/data/datasources/device_remote_data_source.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';

class DeviceRealtimePage extends StatefulWidget {
  final String sn;
  final String type;

  const DeviceRealtimePage({super.key, required this.sn, required this.type});

  @override
  State<DeviceRealtimePage> createState() => _DeviceRealtimePageState();
}

class _DeviceRealtimePageState extends State<DeviceRealtimePage> with TickerProviderStateMixin {
  InverterRealtime? _realtime;
  bool _loading = true;
  late AnimationController _pulseAnim;
  StreamSubscription<InverterRealtime>? _mqttSub;
  late MQTTService _mqttService;

  List<DeviceModelField>? _modelFields;
  bool _modelFieldsLoaded = false;
  List<Map<String, dynamic>> _dynamicGroups = [];

  static const _sectionDefs = [
    {
      'title': '交流输出',
      'icon': Icons.bolt_rounded,
      'color': Color(0xFF8B5CF6),
      'prefix': 'ac_',
    },
    {
      'title': '电池状态',
      'icon': Icons.battery_charging_full,
      'color': Color(0xFF10B981),
      'prefix': 'batt_',
    },
    {
      'title': '光伏 MPPT',
      'icon': Icons.wb_sunny_outlined,
      'color': Color(0xFFF59E0B),
      'prefix': 'pv_',
    },
    {
      'title': '负载',
      'icon': Icons.home_outlined,
      'color': Color(0xFF3B82F6),
      'prefix': 'load_',
    },
    {
      'title': '电表',
      'icon': Icons.electric_meter,
      'color': Color(0xFFEF4444),
      'prefix': 'meter_',
    },
    {
      'title': '系统状态',
      'icon': Icons.info_outline_rounded,
      'color': Color(0xFF06B6D4),
      'prefix': 'sys_',
    },
    {
      'title': '能量统计',
      'icon': Icons.show_chart_rounded,
      'color': AppColors.primary,
      'prefix': 'energy_',
    },
  ];

  static const _fallbackGroups = [
    {
      'title': '交流输出',
      'icon': Icons.bolt_rounded,
      'color': Color(0xFF8B5CF6),
      'keys': {
        '电压 (V)': 'ac_voltage',
        '电流 (A)': 'ac_current',
        '功率 (W)': 'ac_power',
        '频率 (Hz)': 'ac_frequency',
        '负载率 (%)': 'ac_load_percent',
        '功率因数': 'ac_pf',
      },
    },
    {
      'title': '电池状态',
      'icon': Icons.battery_charging_full,
      'color': Color(0xFF10B981),
      'keys': {
        'SOC (%)': 'batt_soc',
        'SOH (%)': 'batt_soh',
        '电压 (V)': 'batt_voltage',
        '电流 (A)': 'batt_current',
        '充电状态': 'batt_charge_state',
      },
    },
    {
      'title': '光伏 MPPT',
      'icon': Icons.wb_sunny_outlined,
      'color': Color(0xFFF59E0B),
      'keys': {
        'PV 电压 (V)': 'pv_voltage',
        'PV 电流 (A)': 'pv_current',
        'PV 功率 (W)': 'pv_power',
        'MPPT 状态': 'mppt_state',
      },
    },
    {
      'title': '负载',
      'icon': Icons.home_outlined,
      'color': Color(0xFF3B82F6),
      'keys': {
        '负载功率 (W)': 'load_power',
      },
    },
    {
      'title': '电表',
      'icon': Icons.electric_meter,
      'color': Color(0xFFEF4444),
      'keys': {
        '电表总功率 (W)': 'meter_total_power',
        'A相功率 (W)': 'meter_phase_a_power',
        'B相功率 (W)': 'meter_phase_b_power',
        'C相功率 (W)': 'meter_phase_c_power',
      },
    },
    {
      'title': '系统状态',
      'icon': Icons.info_outline_rounded,
      'color': Color(0xFF06B6D4),
      'keys': {
        '工作状态': 'state',
        '故障码': 'fault_code',
        '告警码': 'alarm_code',
        '逆变器温度 (℃)': 'temp_inv',
        'MOS温度 (℃)': 'temp_mos',
        '效率 (%)': 'efficiency',
      },
    },
    {
      'title': '能量统计',
      'icon': Icons.show_chart_rounded,
      'color': AppColors.primary,
      'keys': {
        '当日发电量 (kWh)': 'daily_pv',
        '累计发电量 (kWh)': 'total_pv',
        '运行时间 (h)': 'runtime_hours',
        '当日馈网 (kWh)': 'daily_feed_energy',
        '累计馈网 (kWh)': 'total_feed_energy',
        '当日购电 (kWh)': 'daily_grid_import',
        '累计购电 (kWh)': 'total_grid_import',
      },
    },
    {
      'title': '设备信息',
      'icon': Icons.devices_rounded,
      'color': Color(0xFF8B5CF6),
      'keys': {
        'SN': 'sn',
        '型号': 'model',
        '厂商': 'manufacturer',
        'ARM固件': 'firmware_arm',
        'ESP固件': 'firmware_esp',
        '类型': 'type',
        '额定功率 (W)': 'rated_power',
        '额定电压 (V)': 'rated_voltage',
        '额定频率 (Hz)': 'rated_freq',
        '电池电压 (V)': 'battery_voltage',
        '电池类型': 'battery_type',
        '电池串数': 'cell_count',
      },
    },
  ];

  @override
  void initState() {
    super.initState();
    _pulseAnim = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _initMQTT();
  }

  @override
  void dispose() {
    _mqttSub?.cancel();
    _pulseAnim.dispose();
    super.dispose();
  }

  void _initMQTT() async {
    _mqttService = getIt<MQTTService>();

    _mqttSub = _mqttService.realtimeDataStream.listen((rt) {
      if (rt.deviceSN == widget.sn && mounted) {
        setState(() {
          _realtime = rt;
          _loading = false;
        });
      }
    });

    _fetchFromAPI();

    _mqttService.waitForConnection(timeout: const Duration(seconds: 10)).then((_) {
      _mqttService.subscribeDeviceTopics(widget.sn);
      final latestData = _mqttService.getLatestData(widget.sn);
      if (latestData != null && mounted) {
        setState(() {
          _realtime = latestData;
          _loading = false;
        });
      }
    });
  }

  Future<void> _fetchFromAPI() async {
    try {
      final dio = getIt<Dio>();
      final res = await dio.get('/devices/${widget.sn}/realtime');

      if (res.statusCode == 200 && mounted) {
        final resData = res.data;
        if (resData is Map) {
          Map<String, dynamic> realtime;

          if (resData['data'] is Map && (resData['data'] as Map)['realtime'] is Map) {
            realtime = (resData['data'] as Map)['realtime'] as Map<String, dynamic>;
          } else if (resData['realtime'] is Map) {
            realtime = resData['realtime'] as Map<String, dynamic>;
          } else {
            realtime = resData['data'] is Map
                ? resData['data'] as Map<String, dynamic>
                : resData as Map<String, dynamic>;
          }

          if (!realtime.containsKey('device_sn')) {
            realtime['device_sn'] = widget.sn;
          }

          realtime = _normalizeToNested(realtime);

          final rtData = InverterRealtime.fromJson(realtime);
          setState(() {
            _realtime = rtData;
            _loading = false;
          });

          _fetchModelFields(rtData.deviceInfo?.model);
        }
      }
    } catch (e) {
      debugPrint('Error fetching realtime data: $e');
    }
  }

  Future<void> _fetchModelFields(String? modelCode) async {
    if (_modelFieldsLoaded || modelCode == null || modelCode.isEmpty) return;

    try {
      final dio = getIt<Dio>();
      final res = await dio.get('/models/by-code/$modelCode/fields');
      if (res.statusCode == 200 && mounted) {
        final data = res.data;
        List? list;
        if (data is Map) {
          list = data['data'] ?? data['items'];
        }
        if (list is List && list.isNotEmpty) {
          final fields = list.map((e) => DeviceModelField.fromJson(e as Map<String, dynamic>)).toList();
          setState(() {
            _modelFields = fields;
            _modelFieldsLoaded = true;
            _dynamicGroups = _buildDynamicGroups(fields);
          });
        }
      }
    } catch (_) {}
  }

  List<Map<String, dynamic>> _buildDynamicGroups(List<DeviceModelField> fields) {
    final groups = <Map<String, dynamic>>[];

    for (final section in _sectionDefs) {
      final prefix = section['prefix'] as String;
      final sectionFields = fields
          .where((f) => f.isShow && f.fieldKey.startsWith(prefix))
          .toList()
        ..sort((a, b) => a.sort.compareTo(b.sort));

      if (sectionFields.isNotEmpty) {
        final keys = <String, String>{};
        for (final f in sectionFields) {
          final label = f.unit.isNotEmpty ? '${f.fieldName} (${f.unit})' : f.fieldName;
          keys[label] = f.fieldKey;
        }
        groups.add({
          'title': section['title'],
          'icon': section['icon'],
          'color': section['color'],
          'keys': keys,
        });
      }
    }

    final infoFields = fields
        .where((f) => f.isShow && !_sectionDefs.any((s) => f.fieldKey.startsWith(s['prefix'] as String)))
        .toList()
      ..sort((a, b) => a.sort.compareTo(b.sort));

    if (infoFields.isNotEmpty) {
      final keys = <String, String>{};
      for (final f in infoFields) {
        keys[f.fieldName] = f.fieldKey;
      }
      groups.add({
        'title': '设备信息',
        'icon': Icons.devices_rounded,
        'color': Color(0xFF8B5CF6),
        'keys': keys,
      });
    }

    return groups;
  }

  Map<String, dynamic> _normalizeToNested(Map<String, dynamic> flat) {
    if (flat.containsKey('ac') || flat.containsKey('pv') || flat.containsKey('battery') ||
        flat.containsKey('batt') || flat.containsKey('sys_status') || flat.containsKey('sys') ||
        flat.containsKey('energy') || flat.containsKey('device_info')) {
      // 统一 Redis 缓存中的 key 别名
      if (flat.containsKey('batt') && !flat.containsKey('battery')) {
        flat['battery'] = flat.remove('batt');
      }
      if (flat.containsKey('sys') && !flat.containsKey('sys_status')) {
        flat['sys_status'] = flat.remove('sys');
      }
      return flat;
    }

    final nested = <String, dynamic>{
      'device_sn': flat['_sn'] ?? flat['device_sn'] ?? widget.sn,
      'updated_at': (flat['_updated_at'] ?? flat['updated_at'] ?? flat['data_time'] ?? DateTime.now().toIso8601String()).toString(),
      'load_power': _toDouble(flat['load_power']),
    };

    // 处理带前缀的字段（如 ac_voltage, batt_soc 等）
    nested['ac'] = {
      'voltage': _toDouble(flat['ac_voltage'] ?? flat['voltage'] ?? flat['phase_a_voltage']),
      'current': _toDouble(flat['ac_current'] ?? flat['current'] ?? flat['phase_a_current']),
      'power': _toDouble(flat['ac_power'] ?? flat['power'] ?? flat['total_active_power']),
      'frequency': _toDouble(flat['ac_frequency'] ?? flat['frequency'] ?? flat['grid_frequency']),
      'load_percent': _toDouble(flat['ac_load_percent'] ?? flat['load_percent']),
      'pf': _toDouble(flat['ac_pf'] ?? flat['pf'] ?? flat['power_factor']),
    };

    nested['energy'] = {
      'daily_pv': _toDouble(flat['energy_daily_pv'] ?? flat['daily_pv'] ?? flat['daily_power_yields']),
      'total_pv': _toDouble(flat['energy_total_pv'] ?? flat['total_pv'] ?? flat['total_power_yields']),
      'runtime_hours': _toInt(flat['energy_runtime_hours'] ?? flat['runtime_hours'] ?? flat['total_running_time']),
      'daily_feed_energy': _toDouble(flat['energy_daily_feed_energy'] ?? flat['daily_feed_energy']),
      'total_feed_energy': _toDouble(flat['energy_total_feed_energy'] ?? flat['total_feed_energy']),
      'daily_grid_import': _toDouble(flat['energy_daily_grid_import'] ?? flat['daily_grid_import']),
      'total_grid_import': _toDouble(flat['energy_total_grid_import'] ?? flat['total_grid_import']),
    };

    nested['sys_status'] = {
      'state': (flat['sys_state'] ?? flat['state'] ?? flat['work_state_1'] ?? '').toString(),
      'fault_code': _toInt(flat['sys_fault_code'] ?? flat['fault_code']),
      'alarm_code': _toInt(flat['sys_alarm_code'] ?? flat['alarm_code']),
      'temp_inv': _toDouble(flat['sys_temp_inv'] ?? flat['temp_inv'] ?? flat['internal_temperature']),
      'temp_mos': _toDouble(flat['sys_temp_mos'] ?? flat['temp_mos']),
      'efficiency': _toDouble(flat['sys_efficiency'] ?? flat['efficiency']),
    };

    if (flat['pv_voltage'] != null || flat['pv_current'] != null || flat['pv_power'] != null ||
        flat['mppt_voltage'] != null || flat['mppt_current'] != null || flat['total_dc_power'] != null) {
      final mpptV = flat['pv_voltage'] ?? flat['mppt_voltage'];
      final mpptC = flat['pv_current'] ?? flat['mppt_current'];
      nested['pv'] = {
        'pv_voltage': mpptV is List && mpptV.isNotEmpty ? _toDouble(mpptV.first) : _toDouble(mpptV),
        'pv_current': mpptC is List && mpptC.isNotEmpty ? _toDouble(mpptC.first) : _toDouble(mpptC),
        'pv_power': _toDouble(flat['pv_power'] ?? flat['total_dc_power']),
        'mppt_state': (flat['mppt_state'] ?? '').toString(),
      };
    }

    if (flat['batt_soc'] != null || flat['soc'] != null || flat['battery_soc'] != null || flat['charge_state'] != null) {
      nested['battery'] = {
        'soc': _toDouble(flat['batt_soc'] ?? flat['soc'] ?? flat['battery_soc']),
        'soh': _toDouble(flat['batt_soh'] ?? flat['soh'] ?? flat['battery_soh']),
        'voltage': _toDouble(flat['batt_voltage'] ?? flat['voltage'] ?? flat['battery_voltage']),
        'current': _toDouble(flat['batt_current'] ?? flat['current'] ?? flat['battery_current']),
        'charge_state': (flat['batt_charge_state'] ?? flat['charge_state'] ?? '').toString(),
      };
    }

    if (flat['meter_total_power'] != null) {
      nested['meter'] = {
        'total_power': _toDouble(flat['meter_total_power']),
        'phase_a_power': _toDouble(flat['meter_phase_a_power']),
        'phase_b_power': _toDouble(flat['meter_phase_b_power']),
        'phase_c_power': _toDouble(flat['meter_phase_c_power']),
      };
    }

    nested['device_info'] = {
      'model': (flat['model'] ?? '').toString(),
      'manufacturer': (flat['manufacturer'] ?? '').toString(),
      'firmware_arm': (flat['firmware_arm'] ?? flat['arm_version'] ?? '').toString(),
      'firmware_esp': (flat['firmware_esp'] ?? flat['dsp_version'] ?? '').toString(),
      'rated_power': _toDouble(flat['rated_power'] ?? flat['nominal_active_power']),
      'rated_voltage': _toDouble(flat['rated_voltage']),
      'rated_freq': _toDouble(flat['rated_freq']),
      'battery_voltage': _toDouble(flat['battery_voltage']),
      'battery_type': (flat['battery_type'] ?? '').toString(),
      'cell_count': _toInt(flat['cell_count']),
    };

    return nested;
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  Future<void> _fetchRealtime() async {
    await _fetchFromAPI();
  }

  Map<String, dynamic> _buildRealtimeMap(InverterRealtime rt) {
    final merged = <String, dynamic>{};

    merged['sn'] = widget.sn;
    merged['load_power'] = rt.loadPower;

    if (rt.deviceInfo != null) {
      final info = rt.deviceInfo!;
      merged.addAll({
        'model': info.model,
        'manufacturer': info.manufacturer,
        'firmware_arm': info.firmwareArm,
        'firmware_esp': info.firmwareEsp,
        'rated_power': info.ratedPower,
        'rated_voltage': info.ratedVoltage,
        'rated_freq': info.ratedFreq,
        'battery_voltage': info.batteryVoltage,
        'battery_type': info.batteryType,
        'cell_count': info.cellCount,
        'type': 'inv',
      });
    }

    if (rt.ac != null) {
      final ac = rt.ac!;
      merged.addAll({
        'ac_voltage': ac.voltage,
        'ac_current': ac.current,
        'ac_power': ac.power,
        'ac_frequency': ac.frequency,
        'ac_load_percent': ac.loadPercent,
        'ac_pf': ac.pf,
      });
    }

    if (rt.battery != null) {
      final batt = rt.battery!;
      merged.addAll({
        'batt_soc': batt.soc,
        'batt_soh': batt.soh,
        'batt_voltage': batt.voltage,
        'batt_current': batt.current,
        'batt_charge_state': batt.chargeState,
      });
    }

    if (rt.pv != null) {
      final pv = rt.pv!;
      merged.addAll({
        'pv_voltage': pv.pvVoltage,
        'pv_current': pv.pvCurrent,
        'pv_power': pv.pvPower,
        'mppt_state': pv.mpptState,
      });
    }

    if (rt.sysStatus != null) {
      final status = rt.sysStatus!;
      merged.addAll({
        'state': status.state,
        'fault_code': status.faultCode,
        'alarm_code': status.alarmCode,
        'temp_inv': status.tempInv,
        'temp_mos': status.tempMos,
        'efficiency': status.efficiency,
      });
    }

    if (rt.energy != null) {
      final energy = rt.energy!;
      merged.addAll({
        'daily_pv': energy.dailyPV,
        'total_pv': energy.totalPV,
        'runtime_hours': energy.runtimeHours,
        'daily_feed_energy': energy.dailyFeedEnergy,
        'total_feed_energy': energy.totalFeedEnergy,
        'daily_grid_import': energy.dailyGridImport,
        'total_grid_import': energy.totalGridImport,
      });
    }

    if (rt.meter != null) {
      final meter = rt.meter!;
      merged.addAll({
        'meter_total_power': meter.totalPower,
        'meter_phase_a_power': meter.phaseAPower,
        'meter_phase_b_power': meter.phaseBPower,
        'meter_phase_c_power': meter.phaseCPower,
      });
    }

    return merged;
  }

  String _fmt(dynamic val, [String unit = '']) {
    if (val == null) return '--';
    if (val is List) {
      if (val.isEmpty) return '--';
      final n = val.first;
      if (n is num) return n.toStringAsFixed(1);
      return n.toString();
    }
    if (val is double) {
      final s = val % 1 == 0 ? val.toStringAsFixed(0) : val.toStringAsFixed(1);
      return unit.isEmpty ? s : '$s $unit';
    }
    if (val is int) return unit.isEmpty ? '$val' : '$val $unit';
    return unit.isEmpty ? '$val' : '$val $unit';
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        body: Column(
          children: [
            Container(
              color: Colors.white,
              padding: EdgeInsets.fromLTRB(20.w, MediaQuery.of(context).padding.top + 10.h, 20.w, 10.h),
              child: Row(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => context.pop(),
                      borderRadius: BorderRadius.circular(8.r),
                      child: Padding(
                        padding: EdgeInsets.all(8.w),
                        child: Icon(Icons.arrow_back_ios_rounded, size: 18, color: AppColors.textPrimary),
                      ),
                    ),
                  ),
                  Text('设备详细数据', style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const Spacer(),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(6.r),
                    ),
                    child: Text(widget.sn, style: TextStyle(fontSize: 11.sp, color: AppColors.primary, fontWeight: FontWeight.w600)),
                  ),
                  SizedBox(width: 8.w),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, size: 22, color: AppColors.textSecondary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                    onSelected: _onMenuAction,
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'ota',
                        child: Row(
                          children: [
                            Icon(Icons.system_update_alt_rounded, size: 20, color: AppColors.primary),
                            SizedBox(width: 12.w),
                            Text('OTA升级', style: TextStyle(fontSize: 14.sp, color: AppColors.primary)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'change_station',
                        child: Row(
                          children: [
                            Icon(Icons.swap_horiz, size: 20, color: AppColors.primary),
                            SizedBox(width: 12.w),
                            Text('修改绑定电站', style: TextStyle(fontSize: 14.sp)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'unbind',
                        child: Row(
                          children: [
                            Icon(Icons.link_off, size: 20, color: const Color(0xFFF59E0B)),
                            SizedBox(width: 12.w),
                            Text('解绑设备', style: TextStyle(fontSize: 14.sp)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 20, color: AppColors.errorLight),
                            SizedBox(width: 12.w),
                            Text('删除设备', style: TextStyle(fontSize: 14.sp, color: AppColors.errorLight)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const SkeletonDeviceRealtime()
                  : _realtime == null
                      ? Center(child: Text('暂无实时数据', style: TextStyle(fontSize: 14.sp, color: AppColors.textHint)))
                      : RefreshIndicator(
                          color: AppColors.primary,
                          onRefresh: _fetchRealtime,
                          child: _buildContent(),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  void _onMenuAction(String action) {
    switch (action) {
      case 'ota':
        context.push('/ota/${widget.sn}');
        break;
      case 'change_station':
        _showChangeStationDialog();
        break;
      case 'unbind':
        _showUnbindDialog();
        break;
      case 'delete':
        _showDeleteDialog();
        break;
    }
  }

  void _showChangeStationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _StationSelectDialog(
        onSelected: (stationId) async {
          Navigator.pop(ctx);
          await _changeStation(stationId);
        },
      ),
    );
  }

  Future<void> _changeStation(int newStationId) async {
    try {
      final dataSource = getIt<DeviceRemoteDataSource>();
      await dataSource.unbind(widget.sn);
      await dataSource.bind(widget.sn, newStationId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ 已成功修改绑定电站'),
          backgroundColor: AppColors.successLight,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('修改失败: $e'),
          backgroundColor: AppColors.errorLight,
        ));
      }
    }
  }

  void _showUnbindDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解绑设备'),
        content: Text('确定要解绑设备 ${widget.sn} 吗？\n解绑后设备将不再属于当前用户。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _unbindDevice();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
            child: const Text('解绑'),
          ),
        ],
      ),
    );
  }

  Future<void> _unbindDevice() async {
    try {
      final dataSource = getIt<DeviceRemoteDataSource>();
      await dataSource.unbind(widget.sn);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ 设备已解绑'),
          backgroundColor: AppColors.successLight,
        ));
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('解绑失败: $e'),
          backgroundColor: AppColors.errorLight,
        ));
      }
    }
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除设备'),
        content: Text('确定要删除设备 ${widget.sn} 吗？\n此操作不可恢复！'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _deleteDevice();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.errorLight),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteDevice() async {
    try {
      final dataSource = getIt<DeviceRemoteDataSource>();
      await dataSource.unbind(widget.sn);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ 设备已删除'),
          backgroundColor: AppColors.successLight,
        ));
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('删除失败: $e'),
          backgroundColor: AppColors.errorLight,
        ));
      }
    }
  }

  Widget _buildContent() {
    final groups = _dynamicGroups.isNotEmpty ? _dynamicGroups : _fallbackGroups;
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 40.h),
      itemCount: groups.length,
      itemBuilder: (_, i) => _buildTopicCard(groups[i], _realtime!),
    );
  }

  Widget _buildTopicCard(Map<String, dynamic> group, InverterRealtime realtime) {
    final title = group['title'] as String;
    final icon = group['icon'] as IconData;
    final color = group['color'] as Color;
    final keysRaw = group['keys'] as Map;
    final keys = keysRaw.map((k, v) => MapEntry(k.toString(), v.toString()));

    final realtimeMap = _buildRealtimeMap(realtime);

    final items = <Widget>[];
    var first = true;
    keys.forEach((label, key) {
      if (!first) {
        items.add(const Divider(height: 1, color: AppColors.surfaceHover));
      }
      first = false;
      items.add(_dataItem(label, realtimeMap[key]));
    });

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCardHeader(title, icon, color),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
            child: Column(children: items),
          ),
        ],
      ),
    );
  }

  Widget _buildCardHeader(String title, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.vertical(top: Radius.circular(14.r)),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, child) => Container(
              width: 6.w, height: 6.w,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.3 + _pulseAnim.value * 0.5),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 4)],
              ),
            ),
          ),
          SizedBox(width: 8.w),
          Icon(icon, size: 18.sp, color: color),
          SizedBox(width: 6.w),
          Text(title, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _dataItem(String label, dynamic value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
          ),
          Text(
            _fmt(value),
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: value != null ? AppColors.textPrimary : AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }
}

class _StationSelectDialog extends StatefulWidget {
  final void Function(int stationId) onSelected;

  const _StationSelectDialog({required this.onSelected});

  @override
  State<_StationSelectDialog> createState() => _StationSelectDialogState();
}

class _StationSelectDialogState extends State<_StationSelectDialog> {
  List<dynamic> _stations = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStations();
  }

  Future<void> _loadStations() async {
    try {
      final dio = getIt<Dio>();
      final res = await dio.get('/stations/summary');
      if (res.statusCode == 200 && mounted) {
        final body = res.data as Map<String, dynamic>;
        final data = (body['data'] ?? body) as Map<String, dynamic>;
        final stations = (data['stations'] as List?) ?? [];
        setState(() {
          _stations = stations;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '加载失败';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择电站'),
      content: SizedBox(
        width: double.maxFinite,
        height: 300.h,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : _stations.isEmpty
                    ? const Center(child: Text('暂无电站'))
                    : ListView.builder(
                        itemCount: _stations.length,
                        itemBuilder: (context, index) {
                          final station = _stations[index];
                          final id = (station['station_id'] ?? station['id']) as int;
                          final name = (station['station_name'] ?? station['name'] ?? '').toString();
                          final deviceCount = (station['device_count'] as num?)?.toInt() ?? 0;
                          return ListTile(
                            leading: const Icon(Icons.solar_power, color: AppColors.primary),
                            title: Text(name),
                            subtitle: Text('$deviceCount 台设备'),
                            onTap: () => widget.onSelected(id),
                          );
                        },
                      ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      ],
    );
  }
}
