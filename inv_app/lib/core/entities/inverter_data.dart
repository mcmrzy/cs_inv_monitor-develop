class ACData {
  final double voltage;
  final double current;
  final double power;
  final double frequency;
  final double pf;
  final double apparentPower;

  const ACData({
    this.voltage = 0,
    this.current = 0,
    this.power = 0,
    this.frequency = 0,
    this.pf = 0,
    this.apparentPower = 0,
  });

  factory ACData.fromJson(Map<String, dynamic> json) {
    final power = (json['output_power'] as num?)?.toDouble() ?? 0;
    final apparent = (json['output_apparent_power'] as num?)?.toDouble() ?? 0;
    return ACData(
      voltage: (json['ac_output_voltage'] as num?)?.toDouble() ?? 0,
      current: (json['output_current'] as num?)?.toDouble() ?? 0,
      power: power,
      frequency: (json['ac_output_frequency'] as num?)?.toDouble() ?? 0,
      // V2.1 无独立功率因数字段，由有功/视在功率派生
      pf: apparent > 0 ? (power / apparent).clamp(0.0, 1.0) : 0,
      apparentPower: apparent,
    );
  }

  Map<String, dynamic> toJson() => {
        'ac_output_voltage': voltage,
        'output_current': current,
        'output_power': power,
        'ac_output_frequency': frequency,
        'output_apparent_power': apparentPower,
      };
}

class BatteryData {
  final double soc;
  final double soh;
  final double voltage;
  final double current;
  final String chargeState;
  final double power;
  /// V2: 充电功率（正值）
  final double chargePower;
  /// V2: 放电功率（正值）
  final double dischargePower;
  final double capacityRemain;
  final double capacityTotal;
  final int cycleCount;
  final double tempMax;
  final double tempMin;
  final double cellVoltageMax;
  final double cellVoltageMin;
  final double cellVoltageDiff;
  final int protectStatus;
  final int bmsFaultCode;
  final double maxChargeCurrent;
  final double maxDischargeCurrent;
  final double chargeVoltageRef;
  final double dischargeCutoffVoltage;
  final double temperature;

  const BatteryData({
    this.soc = 0,
    this.soh = 0,
    this.voltage = 0,
    this.current = 0,
    this.chargeState = '',
    this.power = 0,
    this.chargePower = 0,
    this.dischargePower = 0,
    this.capacityRemain = 0,
    this.capacityTotal = 0,
    this.cycleCount = 0,
    this.tempMax = 0,
    this.tempMin = 0,
    this.cellVoltageMax = 0,
    this.cellVoltageMin = 0,
    this.cellVoltageDiff = 0,
    this.protectStatus = 0,
    this.bmsFaultCode = 0,
    this.maxChargeCurrent = 0,
    this.maxDischargeCurrent = 0,
    this.chargeVoltageRef = 0,
    this.dischargeCutoffVoltage = 0,
    this.temperature = 0,
  });

  factory BatteryData.fromJson(Map<String, dynamic> json) {
    final chargePower = (json['battery_charge_power'] as num?)?.toDouble() ?? 0;
    final dischargePower = (json['battery_discharge_power'] as num?)?.toDouble() ?? 0;
    final power = (chargePower != 0 || dischargePower != 0)
        ? chargePower - dischargePower
        : (json['power'] as num?)?.toDouble() ?? 0;

    return BatteryData(
      soc: (json['battery_soc'] as num?)?.toDouble() ?? 0,
      soh: (json['battery_soh'] as num?)?.toDouble() ?? 0,
      voltage: (json['battery_voltage'] as num?)?.toDouble() ?? 0,
      current: (json['battery_current'] as num?)?.toDouble() ?? 0,
      chargeState: json['charge_state'] as String? ?? '',
      power: power,
      chargePower: chargePower,
      dischargePower: dischargePower,
      capacityRemain: (json['capacity_remain'] as num?)?.toDouble() ?? 0,
      capacityTotal: (json['capacity_total'] as num?)?.toDouble() ?? 0,
      cycleCount: (json['cycle_count'] as num?)?.toInt() ?? 0,
      tempMax: (json['battery_temp_max'] as num?)?.toDouble() ?? 0,
      tempMin: (json['battery_temp_min'] as num?)?.toDouble() ?? 0,
      cellVoltageMax: (json['cell_voltage_max'] as num?)?.toDouble() ?? 0,
      cellVoltageMin: (json['cell_voltage_min'] as num?)?.toDouble() ?? 0,
      cellVoltageDiff: (json['cell_voltage_diff'] as num?)?.toDouble() ?? 0,
      protectStatus: (json['protect_status'] as num?)?.toInt() ?? 0,
      bmsFaultCode: (json['bms_fault_code'] as num?)?.toInt() ?? 0,
      maxChargeCurrent: (json['max_charge_current'] as num?)?.toDouble() ?? 0,
      maxDischargeCurrent:
          (json['max_discharge_current'] as num?)?.toDouble() ?? 0,
      chargeVoltageRef: (json['charge_voltage_ref'] as num?)?.toDouble() ?? 0,
      dischargeCutoffVoltage:
          (json['discharge_cutoff_voltage'] as num?)?.toDouble() ?? 0,
      temperature: (json['battery_temperature'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'soc': soc,
        'soh': soh,
        'voltage': voltage,
        'current': current,
        'charge_state': chargeState,
        'power': power,
        'capacity_remain': capacityRemain,
        'capacity_total': capacityTotal,
        'cycle_count': cycleCount,
        'temp_max': tempMax,
        'temp_min': tempMin,
        'cell_voltage_max': cellVoltageMax,
        'cell_voltage_min': cellVoltageMin,
        'cell_voltage_diff': cellVoltageDiff,
        'protect_status': protectStatus,
        'bms_fault_code': bmsFaultCode,
        'max_charge_current': maxChargeCurrent,
        'max_discharge_current': maxDischargeCurrent,
        'charge_voltage_ref': chargeVoltageRef,
        'discharge_cutoff_voltage': dischargeCutoffVoltage,
        'temperature': temperature,
      };
}

class PVData {
  final double pvVoltage;
  final double pvCurrent;
  final double pvPower;
  final String mpptState;
  final double pv1Power;
  final double pv1VoltageMax;
  final double pv1PowerMax;
  final double pv2Voltage;
  final double pv2Current;
  final double pv2Power;
  final double pv2VoltageMax;
  final double pv2PowerMax;

  const PVData({
    this.pvVoltage = 0,
    this.pvCurrent = 0,
    this.pvPower = 0,
    this.mpptState = '',
    this.pv1Power = 0,
    this.pv1VoltageMax = 0,
    this.pv1PowerMax = 0,
    this.pv2Voltage = 0,
    this.pv2Current = 0,
    this.pv2Power = 0,
    this.pv2VoltageMax = 0,
    this.pv2PowerMax = 0,
  });

  factory PVData.fromJson(Map<String, dynamic> json) {
    return PVData(
      pvVoltage: (json['pv1_voltage'] as num?)?.toDouble() ?? 0,
      pvCurrent: (json['pv1_current'] as num?)?.toDouble() ?? 0,
      pvPower: (json['pv_total_power'] as num?)?.toDouble() ?? 0,
      mpptState: json['mppt_state'] as String? ?? '',
      pv1Power: (json['pv1_power'] as num?)?.toDouble() ?? 0,
      pv1VoltageMax: (json['pv1_voltage_max'] as num?)?.toDouble() ?? 0,
      pv1PowerMax: (json['pv1_power_max'] as num?)?.toDouble() ?? 0,
      pv2Voltage: (json['pv2_voltage'] as num?)?.toDouble() ?? 0,
      pv2Current: (json['pv2_current'] as num?)?.toDouble() ?? 0,
      pv2Power: (json['pv2_power'] as num?)?.toDouble() ?? 0,
      pv2VoltageMax: (json['pv2_voltage_max'] as num?)?.toDouble() ?? 0,
      pv2PowerMax: (json['pv2_power_max'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'pv_voltage': pvVoltage,
        'pv_current': pvCurrent,
        'pv_power': pvPower,
        'mppt_state': mpptState,
        'pv1_power': pv1Power,
        'pv1_voltage_max': pv1VoltageMax,
        'pv1_power_max': pv1PowerMax,
        'pv2_voltage': pv2Voltage,
        'pv2_current': pv2Current,
        'pv2_power': pv2Power,
        'pv2_voltage_max': pv2VoltageMax,
        'pv2_power_max': pv2PowerMax,
      };
}

class SystemStatus {
  /// 运行状态（服务端由 sys_status 位推导：0 待机 1 逆变 2 旁路 4 故障）
  final String state;
  final int faultCode;
  final int alarmCode;
  /// 逆变器温度（℃）
  final double tempInv;
  /// 升压温度（℃）
  final double boostTemp;
  /// 变压器温度（℃）
  final double transformerTemp;
  /// PV 温度（℃）
  final double pvTemp;
  /// 母线电压（V）
  final double dcBusVoltage;
  /// 负载率（%）
  final double loadPercent;

  const SystemStatus({
    this.state = '',
    this.faultCode = 0,
    this.alarmCode = 0,
    this.tempInv = 0,
    this.boostTemp = 0,
    this.transformerTemp = 0,
    this.pvTemp = 0,
    this.dcBusVoltage = 0,
    this.loadPercent = 0,
  });

  factory SystemStatus.fromJson(Map<String, dynamic> json) {
    return SystemStatus(
      state: (json['work_state'] != null) ? json['work_state'].toString() : '',
      faultCode: (json['fault_code'] as num?)?.toInt() ?? 0,
      alarmCode: (json['alarm_code'] as num?)?.toInt() ?? 0,
      tempInv: (json['inverter_temperature'] as num?)?.toDouble() ?? 0,
      boostTemp: (json['boost_temperature'] as num?)?.toDouble() ?? 0,
      transformerTemp:
          (json['transformer_temperature'] as num?)?.toDouble() ?? 0,
      pvTemp: (json['pv_temperature'] as num?)?.toDouble() ?? 0,
      dcBusVoltage: (json['dc_bus_voltage'] as num?)?.toDouble() ?? 0,
      loadPercent: (json['load_percent'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'work_state': state,
        'fault_code': faultCode,
        'alarm_code': alarmCode,
        'inverter_temperature': tempInv,
        'boost_temperature': boostTemp,
        'transformer_temperature': transformerTemp,
        'pv_temperature': pvTemp,
        'dc_bus_voltage': dcBusVoltage,
        'load_percent': loadPercent,
      };

  bool get hasFault => faultCode != 0;
}

/// V2.1 fan 组：风扇转速（%，0=停转 100=全速）
/// MPPT 与逆变各一个独立风扇（散热诊断输入）
class FanData {
  /// MPPT 风扇转速（%）
  final double mpptSpeed;

  /// 逆变风扇转速（%）
  final double invSpeed;

  const FanData({this.mpptSpeed = 0, this.invSpeed = 0});

  factory FanData.fromJson(Map<String, dynamic> json) {
    return FanData(
      mpptSpeed: (json['mppt_fan_speed'] as num?)?.toDouble() ?? 0,
      invSpeed: (json['inv_fan_speed'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'mppt_fan_speed': mpptSpeed,
        'inv_fan_speed': invSpeed,
      };

  /// 两风扇中较高转速（健康度估算用）
  double get maxSpeed => mpptSpeed > invSpeed ? mpptSpeed : invSpeed;
}

class EnergyData {
  final double dailyPV;
  final double totalPV;
  final double dailyCharge;
  final double totalCharge;
  final double dailyDischarge;
  final double totalDischarge;
  final double dailyLoad;
  final double totalLoad;
  // V2 新增能量分项
  final double dailyGenEnergy;
  final double totalGenEnergy;
  final double dailyAcChargeEnergy;
  final double totalAcChargeEnergy;
  final double dailyAcBypassEnergy;
  final double totalAcBypassEnergy;
  final double dailyOutputEnergy;
  final double totalOutputEnergy;

  const EnergyData({
    this.dailyPV = 0,
    this.totalPV = 0,
    this.dailyCharge = 0,
    this.totalCharge = 0,
    this.dailyDischarge = 0,
    this.totalDischarge = 0,
    this.dailyLoad = 0,
    this.totalLoad = 0,
    this.dailyGenEnergy = 0,
    this.totalGenEnergy = 0,
    this.dailyAcChargeEnergy = 0,
    this.totalAcChargeEnergy = 0,
    this.dailyAcBypassEnergy = 0,
    this.totalAcBypassEnergy = 0,
    this.dailyOutputEnergy = 0,
    this.totalOutputEnergy = 0,
  });

  factory EnergyData.fromJson(Map<String, dynamic> json) {
    return EnergyData(
      dailyPV: (json['daily_pv_energy'] as num?)?.toDouble() ?? 0,
      totalPV: (json['total_pv_energy'] as num?)?.toDouble() ?? 0,
      dailyCharge: (json['daily_charge_energy'] as num?)?.toDouble() ?? 0,
      totalCharge: (json['total_charge_energy'] as num?)?.toDouble() ?? 0,
      dailyDischarge:
          (json['daily_discharge_energy'] as num?)?.toDouble() ?? 0,
      totalDischarge:
          (json['total_discharge_energy'] as num?)?.toDouble() ?? 0,
      // 负载用电：优先负载侧计量，回退输出电量分项（均为 V2 键）
      dailyLoad: (json['daily_load_energy'] as num?)?.toDouble() ??
                 (json['output_energy_daily'] as num?)?.toDouble() ?? 0,
      totalLoad: (json['total_load_energy'] as num?)?.toDouble() ??
                 (json['output_energy_total'] as num?)?.toDouble() ?? 0,
      // V2 新增
      dailyGenEnergy: (json['gen_energy_daily'] as num?)?.toDouble() ?? 0,
      totalGenEnergy: (json['gen_energy_total'] as num?)?.toDouble() ?? 0,
      dailyAcChargeEnergy: (json['ac_charge_energy_daily'] as num?)?.toDouble() ?? 0,
      totalAcChargeEnergy: (json['ac_charge_energy_total'] as num?)?.toDouble() ?? 0,
      dailyAcBypassEnergy: (json['ac_bypass_energy_daily'] as num?)?.toDouble() ?? 0,
      totalAcBypassEnergy: (json['ac_bypass_energy_total'] as num?)?.toDouble() ?? 0,
      dailyOutputEnergy: (json['output_energy_daily'] as num?)?.toDouble() ?? 0,
      totalOutputEnergy: (json['output_energy_total'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'daily_pv_energy': dailyPV,
        'total_pv_energy': totalPV,
        'daily_charge_energy': dailyCharge,
        'total_charge_energy': totalCharge,
        'daily_discharge_energy': dailyDischarge,
        'total_discharge_energy': totalDischarge,
        'output_energy_daily': dailyLoad,
        'output_energy_total': totalLoad,
        'gen_energy_daily': dailyGenEnergy,
        'gen_energy_total': totalGenEnergy,
        'ac_charge_energy_daily': dailyAcChargeEnergy,
        'ac_charge_energy_total': totalAcChargeEnergy,
        'ac_bypass_energy_daily': dailyAcBypassEnergy,
        'ac_bypass_energy_total': totalAcBypassEnergy,
      };
}

class CellsData {
  final int cellCount;
  final List<double> voltages;
  final List<double> temps;

  const CellsData({
    this.cellCount = 0,
    this.voltages = const [],
    this.temps = const [],
  });

  factory CellsData.fromJson(Map<String, dynamic> json) {
    return CellsData(
      cellCount: (json['cell_count'] as num?)?.toInt() ?? 0,
      voltages: (json['voltages'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [],
      temps: (json['temps'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'cell_count': cellCount,
        'voltages': voltages,
        'temps': temps,
      };
}

class MeterData {
  final double totalPower;
  final double phaseAPower;
  final double phaseBPower;
  final double phaseCPower;

  const MeterData({
    this.totalPower = 0,
    this.phaseAPower = 0,
    this.phaseBPower = 0,
    this.phaseCPower = 0,
  });

  factory MeterData.fromJson(Map<String, dynamic> json) {
    return MeterData(
      totalPower: (json['total_power'] as num?)?.toDouble() ?? 0,
      phaseAPower: (json['phase_a_power'] as num?)?.toDouble() ?? 0,
      phaseBPower: (json['phase_b_power'] as num?)?.toDouble() ?? 0,
      phaseCPower: (json['phase_c_power'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'total_power': totalPower,
        'phase_a_power': phaseAPower,
        'phase_b_power': phaseBPower,
        'phase_c_power': phaseCPower,
      };
}

class OnlineStatus {
  final bool online;
  final int rssi;
  final String? ip;

  const OnlineStatus({
    this.online = false,
    this.rssi = 0,
    this.ip,
  });

  factory OnlineStatus.fromJson(Map<String, dynamic> json) {
    return OnlineStatus(
      online: json['online'] as bool? ?? false,
      rssi: (json['rssi'] as num?)?.toInt() ?? 0,
      ip: json['ip'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'online': online,
        'rssi': rssi,
        'ip': ip,
      };
}

class AlarmData {
  final String event;
  final int timestamp;
  final String source;
  final int faultCode;
  final String faultDesc;
  final int alarmCode;
  final Map<String, dynamic>? trigger;

  const AlarmData({
    this.event = '',
    this.timestamp = 0,
    this.source = '',
    this.faultCode = 0,
    this.faultDesc = '',
    this.alarmCode = 0,
    this.trigger,
  });

  factory AlarmData.fromJson(Map<String, dynamic> json) {
    return AlarmData(
      event: json['event'] as String? ?? '',
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      source: json['source'] as String? ?? '',
      faultCode: (json['fault_code'] as num?)?.toInt() ?? 0,
      faultDesc: json['fault_desc'] as String? ?? '',
      alarmCode: (json['alarm_code'] as num?)?.toInt() ?? 0,
      trigger: json['trigger'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
        'event': event,
        'timestamp': timestamp,
        'source': source,
        'fault_code': faultCode,
        'fault_desc': faultDesc,
        'alarm_code': alarmCode,
        'trigger': trigger,
      };
}

class DeviceInfo {
  final String model;
  final String manufacturer;
  final String firmwareArm;
  final String firmwareEsp;
  final double ratedPower;
  final double ratedVoltage;
  final double ratedFreq;
  final double batteryVoltage;
  final String batteryType;
  final int cellCount;

  const DeviceInfo({
    this.model = '',
    this.manufacturer = '',
    this.firmwareArm = '',
    this.firmwareEsp = '',
    this.ratedPower = 0,
    this.ratedVoltage = 0,
    this.ratedFreq = 0,
    this.batteryVoltage = 0,
    this.batteryType = '',
    this.cellCount = 0,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      model: json['model'] as String? ?? '',
      manufacturer: json['manufacturer'] as String? ?? '',
      firmwareArm: json['firmware_arm'] as String? ?? '',
      firmwareEsp: json['firmware_esp'] as String? ?? '',
      ratedPower: (json['rated_power'] as num?)?.toDouble() ?? 0,
      ratedVoltage: (json['rated_voltage'] as num?)?.toDouble() ?? 0,
      ratedFreq: (json['rated_freq'] as num?)?.toDouble() ?? 0,
      batteryVoltage: (json['battery_voltage'] as num?)?.toDouble() ?? 0,
      batteryType: json['battery_type'] as String? ?? '',
      cellCount: (json['cell_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'model': model,
        'manufacturer': manufacturer,
        'firmware_arm': firmwareArm,
        'firmware_esp': firmwareEsp,
        'rated_power': ratedPower,
        'rated_voltage': ratedVoltage,
        'rated_freq': ratedFreq,
        'battery_voltage': batteryVoltage,
        'battery_type': batteryType,
        'cell_count': cellCount,
      };
}

class InverterRealtime {
  final String deviceSN;
  final ACData? ac;
  final BatteryData? battery;
  final PVData? pv;
  final SystemStatus? sysStatus;
  final EnergyData? energy;
  final FanData? fan;

  /// V2.1 diag 组累计运行时长（秒）
  final int workTimeTotalSec;

  final CellsData? cells;
  final OnlineStatus? onlineStatus;
  final DeviceInfo? deviceInfo;
  final MeterData? meter;
  final double loadPower;

  /// 遥测数据时间戳；缺失时为 null（视为未知，
  /// 不用 DateTime.now() 兜底，避免把陈旧数据误当实时值展示）
  final DateTime? updatedAt;

  const InverterRealtime({
    required this.deviceSN,
    this.ac,
    this.battery,
    this.pv,
    this.sysStatus,
    this.energy,
    this.fan,
    this.workTimeTotalSec = 0,
    this.cells,
    this.onlineStatus,
    this.deviceInfo,
    this.meter,
    this.loadPower = 0,
    this.updatedAt,
  });

  factory InverterRealtime.fromJson(Map<String, dynamic> json) {
    // 兼容 Redis 缓存中的 key 别名: batt → battery, sys → sys_status
    // V2 realtime_data 同时存在嵌套组（Map）和扁平字段（int/double），
    // 需要检查类型后再 cast，避免 "type 'int' is not a subtype of type 'Map'" 错误。
    // V2 嵌套组格式：{"data": {...}, "timestamp": ...}，需要提取 data 子字段。

    // 提取嵌套组数据（支持 {"data": {...}} 和直接字段两种格式）
    Map<String, dynamic>? extractGroupData(dynamic raw) {
      if (raw is! Map<String, dynamic>) return null;
      // V2 格式：{"data": {...}, "timestamp": ...}
      if (raw.containsKey('data') && raw['data'] is Map<String, dynamic>) {
        return raw['data'] as Map<String, dynamic>;
      }
      // V1 格式：直接是字段值
      return raw;
    }

    final batteryRaw = json['battery'] ?? json['batt'] ?? json['bat'];
    final batteryMap = extractGroupData(batteryRaw);

    final sysStatusRaw = json['sys_status'] is Map ? json['sys_status'] : json['sys'];
    final sysStatusMap = extractGroupData(sysStatusRaw);

    final acMap = extractGroupData(json['ac']);
    final pvMap = extractGroupData(json['pv']);
    final engRaw = json['eng'] ?? json['energy'];
    final engMap = extractGroupData(engRaw);

    // V2.1 新增组：fan（双风扇转速）/ diag（诊断量）
    final fanMap = extractGroupData(json['fan']);
    final diagMap = extractGroupData(json['diag']);

    return InverterRealtime(
      deviceSN: json['device_sn'] as String? ?? '',
      ac: acMap != null ? ACData.fromJson(acMap) : null,
      battery: batteryMap != null ? BatteryData.fromJson(batteryMap) : null,
      pv: pvMap != null ? PVData.fromJson(pvMap) : null,
      sysStatus: sysStatusMap != null ? SystemStatus.fromJson(sysStatusMap) : null,
      energy: engMap != null ? EnergyData.fromJson(engMap) : null,
      fan: fanMap != null ? FanData.fromJson(fanMap) : null,
      workTimeTotalSec:
          (diagMap?['work_time_total'] as num?)?.toInt() ?? 0,
      cells: json['cells'] is Map
          ? CellsData.fromJson(json['cells'] as Map<String, dynamic>)
          : null,
      onlineStatus: json['online_status'] is Map
          ? OnlineStatus.fromJson(json['online_status'] as Map<String, dynamic>)
          : null,
      deviceInfo: json['device_info'] is Map
          ? DeviceInfo.fromJson(json['device_info'] as Map<String, dynamic>)
          : null,
      meter: json['meter'] is Map
          ? MeterData.fromJson(json['meter'] as Map<String, dynamic>)
          : null,
      loadPower: (json['load_power'] as num?)?.toDouble() ?? 0,
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'device_sn': deviceSN,
        'ac': ac?.toJson(),
        'battery': battery?.toJson(),
        'pv': pv?.toJson(),
        'sys_status': sysStatus?.toJson(),
        'energy': energy?.toJson(),
        'fan': fan?.toJson(),
        'work_time_total': workTimeTotalSec,
        'cells': cells?.toJson(),
        'online_status': onlineStatus?.toJson(),
        'device_info': deviceInfo?.toJson(),
        'meter': meter?.toJson(),
        'load_power': loadPower,
        'updated_at': updatedAt?.toIso8601String(),
      };
}
