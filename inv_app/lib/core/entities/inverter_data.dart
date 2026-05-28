class ACData {
  final double voltage;
  final double current;
  final double power;
  final double frequency;
  final double loadPercent;

  const ACData({
    this.voltage = 0,
    this.current = 0,
    this.power = 0,
    this.frequency = 0,
    this.loadPercent = 0,
  });

  factory ACData.fromJson(Map<String, dynamic> json) {
    return ACData(
      voltage: (json['voltage'] as num?)?.toDouble() ?? 0,
      current: (json['current'] as num?)?.toDouble() ?? 0,
      power: (json['power'] as num?)?.toDouble() ?? 0,
      frequency: (json['frequency'] as num?)?.toDouble() ?? 0,
      loadPercent: (json['load_percent'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'voltage': voltage,
    'current': current,
    'power': power,
    'frequency': frequency,
    'load_percent': loadPercent,
  };
}

class BatteryData {
  final double soc;
  final double soh;
  final double voltage;
  final double current;
  final String chargeState;

  const BatteryData({
    this.soc = 0,
    this.soh = 0,
    this.voltage = 0,
    this.current = 0,
    this.chargeState = '',
  });

  factory BatteryData.fromJson(Map<String, dynamic> json) {
    return BatteryData(
      soc: (json['soc'] as num?)?.toDouble() ?? 0,
      soh: (json['soh'] as num?)?.toDouble() ?? 0,
      voltage: (json['voltage'] as num?)?.toDouble() ?? 0,
      current: (json['current'] as num?)?.toDouble() ?? 0,
      chargeState: json['charge_state'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'soc': soc,
    'soh': soh,
    'voltage': voltage,
    'current': current,
    'charge_state': chargeState,
  };
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
}

class SystemStatus {
  final String state;
  final int faultCode;
  final int alarmCode;
  final double tempInv;
  final double tempMos;
  final double efficiency;

  const SystemStatus({
    this.state = '',
    this.faultCode = 0,
    this.alarmCode = 0,
    this.tempInv = 0,
    this.tempMos = 0,
    this.efficiency = 0,
  });

  factory SystemStatus.fromJson(Map<String, dynamic> json) {
    return SystemStatus(
      state: json['state'] as String? ?? '',
      faultCode: (json['fault_code'] as num?)?.toInt() ?? 0,
      alarmCode: (json['alarm_code'] as num?)?.toInt() ?? 0,
      tempInv: (json['temp_inv'] as num?)?.toDouble() ?? 0,
      tempMos: (json['temp_mos'] as num?)?.toDouble() ?? 0,
      efficiency: (json['efficiency'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'state': state,
    'fault_code': faultCode,
    'alarm_code': alarmCode,
    'temp_inv': tempInv,
    'temp_mos': tempMos,
    'efficiency': efficiency,
  };

  bool get hasFault => faultCode != 0;
}

class EnergyData {
  final double dailyPV;
  final double totalPV;
  final int runtimeHours;

  const EnergyData({
    this.dailyPV = 0,
    this.totalPV = 0,
    this.runtimeHours = 0,
  });

  factory EnergyData.fromJson(Map<String, dynamic> json) {
    return EnergyData(
      dailyPV: (json['daily_pv'] as num?)?.toDouble() ?? 0,
      totalPV: (json['total_pv'] as num?)?.toDouble() ?? 0,
      runtimeHours: (json['runtime_hours'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'daily_pv': dailyPV,
    'total_pv': totalPV,
    'runtime_hours': runtimeHours,
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
              .toList() ?? [],
      temps: (json['temps'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
    'cell_count': cellCount,
    'voltages': voltages,
    'temps': temps,
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
  final CellsData? cells;
  final OnlineStatus? onlineStatus;
  final DeviceInfo? deviceInfo;
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
    this.deviceInfo,
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
      deviceInfo: json['device_info'] != null ? DeviceInfo.fromJson(json['device_info'] as Map<String, dynamic>) : null,
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
    'device_info': deviceInfo?.toJson(),
    'updated_at': updatedAt.toIso8601String(),
  };
}
