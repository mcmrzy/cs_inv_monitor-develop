class ACData {
  final double voltage;
  final double current;
  final double power;
  final double apparent;
  final double reactive;
  final double frequency;
  final double pf;
  final double loadPercent;
  final double thdV;
  final double thdI;
  final double dcInjection;

  const ACData({
    this.voltage = 0,
    this.current = 0,
    this.power = 0,
    this.apparent = 0,
    this.reactive = 0,
    this.frequency = 0,
    this.pf = 0,
    this.loadPercent = 0,
    this.thdV = 0,
    this.thdI = 0,
    this.dcInjection = 0,
  });

  factory ACData.fromJson(Map<String, dynamic> json) {
    return ACData(
      voltage: (json['voltage'] as num?)?.toDouble() ?? 0,
      current: (json['current'] as num?)?.toDouble() ?? 0,
      power: (json['power'] as num?)?.toDouble() ?? 0,
      apparent: (json['apparent'] as num?)?.toDouble() ?? 0,
      reactive: (json['reactive'] as num?)?.toDouble() ?? 0,
      frequency: (json['frequency'] as num?)?.toDouble() ?? 0,
      pf: (json['pf'] as num?)?.toDouble() ?? 0,
      loadPercent: (json['load_percent'] as num?)?.toDouble() ?? 0,
      thdV: (json['thd_v'] as num?)?.toDouble() ?? 0,
      thdI: (json['thd_i'] as num?)?.toDouble() ?? 0,
      dcInjection: (json['dc_injection'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'voltage': voltage,
    'current': current,
    'power': power,
    'apparent': apparent,
    'reactive': reactive,
    'frequency': frequency,
    'pf': pf,
    'load_percent': loadPercent,
    'thd_v': thdV,
    'thd_i': thdI,
    'dc_injection': dcInjection,
  };

  String get formattedPower {
    final kw = power / 1000.0;
    return '${kw.toStringAsFixed(1)} kW';
  }
}

class BatteryData {
  final double soc;
  final double soh;
  final double voltage;
  final double current;
  final double power;
  final double capacityRemain;
  final double capacityTotal;
  final int cycleCount;
  final double tempMax;
  final double tempMin;
  final double cellVoltMax;
  final double cellVoltMin;
  final double cellVoltDiff;
  final String chargeState;
  final String batteryType;
  final int protectStatus1;
  final int protectStatus2;

  const BatteryData({
    this.soc = 0,
    this.soh = 0,
    this.voltage = 0,
    this.current = 0,
    this.power = 0,
    this.capacityRemain = 0,
    this.capacityTotal = 0,
    this.cycleCount = 0,
    this.tempMax = 0,
    this.tempMin = 0,
    this.cellVoltMax = 0,
    this.cellVoltMin = 0,
    this.cellVoltDiff = 0,
    this.chargeState = '',
    this.batteryType = '',
    this.protectStatus1 = 0,
    this.protectStatus2 = 0,
  });

  factory BatteryData.fromJson(Map<String, dynamic> json) {
    return BatteryData(
      soc: (json['soc'] as num?)?.toDouble() ?? 0,
      soh: (json['soh'] as num?)?.toDouble() ?? 0,
      voltage: (json['voltage'] as num?)?.toDouble() ?? 0,
      current: (json['current'] as num?)?.toDouble() ?? 0,
      power: (json['power'] as num?)?.toDouble() ?? 0,
      capacityRemain: (json['capacity_remain'] as num?)?.toDouble() ?? 0,
      capacityTotal: (json['capacity_total'] as num?)?.toDouble() ?? 0,
      cycleCount: (json['cycle_count'] as num?)?.toInt() ?? 0,
      tempMax: (json['temp_max'] as num?)?.toDouble() ?? 0,
      tempMin: (json['temp_min'] as num?)?.toDouble() ?? 0,
      cellVoltMax: (json['cell_volt_max'] as num?)?.toDouble() ?? 0,
      cellVoltMin: (json['cell_volt_min'] as num?)?.toDouble() ?? 0,
      cellVoltDiff: (json['cell_volt_diff'] as num?)?.toDouble() ?? 0,
      chargeState: json['charge_state'] as String? ?? '',
      batteryType: json['battery_type'] as String? ?? '',
      protectStatus1: (json['protect_status1'] as num?)?.toInt() ?? 0,
      protectStatus2: (json['protect_status2'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'soc': soc,
    'soh': soh,
    'voltage': voltage,
    'current': current,
    'power': power,
    'capacity_remain': capacityRemain,
    'capacity_total': capacityTotal,
    'cycle_count': cycleCount,
    'temp_max': tempMax,
    'temp_min': tempMin,
    'cell_volt_max': cellVoltMax,
    'cell_volt_min': cellVoltMin,
    'cell_volt_diff': cellVoltDiff,
    'charge_state': chargeState,
    'battery_type': batteryType,
    'protect_status1': protectStatus1,
    'protect_status2': protectStatus2,
  };

  String get formattedSoc => '${soc.toStringAsFixed(1)}%';
  String get formattedVoltage => '${voltage.toStringAsFixed(1)}V';
  String get formattedCurrent => '${current.toStringAsFixed(2)}A';
  String get formattedPower => '${(power / 1000).toStringAsFixed(2)}kW';
}

class PVData {
  final double pvVoltage;
  final double pvCurrent;
  final double pvPower;
  final String mpptState;

  const PVData({
    this.pvVoltage = 0,
    this.pvCurrent = 0,
    this.pvPower = 0,
    this.mpptState = '',
  });

  factory PVData.fromJson(Map<String, dynamic> json) {
    return PVData(
      pvVoltage: (json['pv_voltage'] as num?)?.toDouble() ?? 0,
      pvCurrent: (json['pv_current'] as num?)?.toDouble() ?? 0,
      pvPower: (json['pv_power'] as num?)?.toDouble() ?? 0,
      mpptState: json['mppt_state'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'pv_voltage': pvVoltage,
    'pv_current': pvCurrent,
    'pv_power': pvPower,
    'mppt_state': mpptState,
  };

  String get formattedPvPower => '${pvPower.toStringAsFixed(0)}W';
}

class SystemStatus {
  final String state;
  final int faultCode;
  final int alarmCode;
  final double tempInv;
  final double tempMos;
  final double tempAmbient;
  final double dcBusVoltage;
  final int fanSpeed;
  final double efficiency;

  const SystemStatus({
    this.state = '',
    this.faultCode = 0,
    this.alarmCode = 0,
    this.tempInv = 0,
    this.tempMos = 0,
    this.tempAmbient = 0,
    this.dcBusVoltage = 0,
    this.fanSpeed = 0,
    this.efficiency = 0,
  });

  factory SystemStatus.fromJson(Map<String, dynamic> json) {
    return SystemStatus(
      state: json['state'] as String? ?? '',
      faultCode: (json['fault_code'] as num?)?.toInt() ?? 0,
      alarmCode: (json['alarm_code'] as num?)?.toInt() ?? 0,
      tempInv: (json['temp_inv'] as num?)?.toDouble() ?? 0,
      tempMos: (json['temp_mos'] as num?)?.toDouble() ?? 0,
      tempAmbient: (json['temp_ambient'] as num?)?.toDouble() ?? 0,
      dcBusVoltage: (json['dc_bus_voltage'] as num?)?.toDouble() ?? 0,
      fanSpeed: (json['fan_speed'] as num?)?.toInt() ?? 0,
      efficiency: (json['efficiency'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'state': state,
    'fault_code': faultCode,
    'alarm_code': alarmCode,
    'temp_inv': tempInv,
    'temp_mos': tempMos,
    'temp_ambient': tempAmbient,
    'dc_bus_voltage': dcBusVoltage,
    'fan_speed': fanSpeed,
    'efficiency': efficiency,
  };

  bool get hasFault => faultCode != 0;
  String get formattedEfficiency => '${efficiency.toStringAsFixed(1)}%';
  String get formattedTemp => '${tempInv.toStringAsFixed(1)}°C';
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
  final int runtimeHours;

  const EnergyData({
    this.dailyPV = 0,
    this.totalPV = 0,
    this.dailyCharge = 0,
    this.totalCharge = 0,
    this.dailyDischarge = 0,
    this.totalDischarge = 0,
    this.dailyLoad = 0,
    this.totalLoad = 0,
    this.runtimeHours = 0,
  });

  factory EnergyData.fromJson(Map<String, dynamic> json) {
    return EnergyData(
      dailyPV: (json['daily_pv'] as num?)?.toDouble() ?? 0,
      totalPV: (json['total_pv'] as num?)?.toDouble() ?? 0,
      dailyCharge: (json['daily_charge'] as num?)?.toDouble() ?? 0,
      totalCharge: (json['total_charge'] as num?)?.toDouble() ?? 0,
      dailyDischarge: (json['daily_discharge'] as num?)?.toDouble() ?? 0,
      totalDischarge: (json['total_discharge'] as num?)?.toDouble() ?? 0,
      dailyLoad: (json['daily_load'] as num?)?.toDouble() ?? 0,
      totalLoad: (json['total_load'] as num?)?.toDouble() ?? 0,
      runtimeHours: (json['runtime_hours'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'daily_pv': dailyPV,
    'total_pv': totalPV,
    'daily_charge': dailyCharge,
    'total_charge': totalCharge,
    'daily_discharge': dailyDischarge,
    'total_discharge': totalDischarge,
    'daily_load': dailyLoad,
    'total_load': totalLoad,
    'runtime_hours': runtimeHours,
  };

  String get formattedDailyPv => '${dailyPV.toStringAsFixed(2)} kWh';
  String get formattedTotalPv => '${totalPV.toStringAsFixed(1)} kWh';
}

class CellsData {
  final int cellCount;
  final List<double> voltages;
  final List<double> temps;
  final double chargeAhTotal;
  final double dischargeAhTotal;

  const CellsData({
    this.cellCount = 0,
    this.voltages = const [],
    this.temps = const [],
    this.chargeAhTotal = 0,
    this.dischargeAhTotal = 0,
  });

  factory CellsData.fromJson(Map<String, dynamic> json) {
    return CellsData(
      cellCount: (json['cell_count'] as num?)?.toInt() ?? 0,
      voltages: (json['voltages'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ?? [],
      temps: (json['temps'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ?? [],
      chargeAhTotal: (json['charge_ah_total'] as num?)?.toDouble() ?? 0,
      dischargeAhTotal: (json['discharge_ah_total'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'cell_count': cellCount,
    'voltages': voltages,
    'temps': temps,
    'charge_ah_total': chargeAhTotal,
    'discharge_ah_total': dischargeAhTotal,
  };
}

class OnlineStatus {
  final bool online;
  final int rssi;
  final String? ip;
  final String? city;

  const OnlineStatus({
    this.online = false,
    this.rssi = 0,
    this.ip,
    this.city,
  });

  factory OnlineStatus.fromJson(Map<String, dynamic> json) {
    final location = json['location'] as Map<String, dynamic>?;
    return OnlineStatus(
      online: json['online'] as bool? ?? false,
      rssi: (json['rssi'] as num?)?.toInt() ?? 0,
      ip: location?['ip'] as String?,
      city: location?['city'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'online': online,
    'rssi': rssi,
    'location': ip != null || city != null ? {
      'ip': ip,
      'city': city,
    } : null,
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

class InverterRealtime {
  final String deviceSN;
  final ACData? ac;
  final BatteryData? battery;
  final PVData? pv;
  final SystemStatus? sysStatus;
  final EnergyData? energy;
  final CellsData? cells;
  final OnlineStatus? onlineStatus;
  final DateTime updatedAt;

  const InverterRealtime({
    required this.deviceSN,
    this.ac,
    this.battery,
    this.pv,
    this.sysStatus,
    this.energy,
    this.cells,
    this.onlineStatus,
    required this.updatedAt,
  });

  factory InverterRealtime.fromJson(Map<String, dynamic> json) {
    return InverterRealtime(
      deviceSN: json['device_sn'] as String? ?? '',
      ac: json['ac'] != null ? ACData.fromJson(json['ac'] as Map<String, dynamic>) : null,
      battery: json['battery'] != null ? BatteryData.fromJson(json['battery'] as Map<String, dynamic>) : null,
      pv: json['pv'] != null ? PVData.fromJson(json['pv'] as Map<String, dynamic>) : null,
      sysStatus: json['sys_status'] != null ? SystemStatus.fromJson(json['sys_status'] as Map<String, dynamic>) : null,
      energy: json['energy'] != null ? EnergyData.fromJson(json['energy'] as Map<String, dynamic>) : null,
      cells: json['cells'] != null ? CellsData.fromJson(json['cells'] as Map<String, dynamic>) : null,
      onlineStatus: json['online_status'] != null ? OnlineStatus.fromJson(json['online_status'] as Map<String, dynamic>) : null,
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'device_sn': deviceSN,
    'ac': ac?.toJson(),
    'battery': battery?.toJson(),
    'pv': pv?.toJson(),
    'sys_status': sysStatus?.toJson(),
    'energy': energy?.toJson(),
    'cells': cells?.toJson(),
    'online_status': onlineStatus?.toJson(),
    'updated_at': updatedAt.toIso8601String(),
  };
}
