import 'package:equatable/equatable.dart';

/// Decoded ARM CMD08 layout 0. Engineering values are already scaled upstream.
class BmsSummary extends Equatable {
  final int? layout;
  final int? bmsOnline;
  final int? batteryCount;
  final double? voltage, current, soc, soh;
  final double? capacityRemain, capacityFull, capacityDesign;
  final int? warningFlag, protectionFlag, statusFaultFlag, balanceStatus;
  final List<double?> cellVoltages, cellTemperatures;
  final int? cycleCount;
  final double? maxCellVoltage, minCellVoltage, maxCellTemp, minCellTemp;
  final double? mosTemp, pcbTemp, envTemp;
  final int? batteryMode, batteryStatus, systemMode;
  final int? totalChgCapacityRaw, totalDsgCapacityRaw;
  final int? chgRequestCurrentRaw, chgRequestVoltageRaw;
  final double? chargingVoltage;
  final int? socRaw, sohRaw, ageMs;
  final List<int>? rawBytes;
  final DateTime? updatedAt, reportedAt, expiresAt;

  BmsSummary.fromJson(Map<String, dynamic> json)
      : layout = _int(json['layout']),
        bmsOnline = _int(json['bms_online']),
        batteryCount = _int(json['battery_count']),
        voltage = _double(json['voltage']),
        current = _double(json['current']),
        soc = _double(json['soc']),
        soh = _double(json['soh']),
        capacityRemain = _double(json['capacity_remain']),
        capacityFull = _double(json['capacity_full']),
        capacityDesign = _double(json['capacity_design']),
        warningFlag = _int(json['warning_flag']),
        protectionFlag = _int(json['protection_flag']),
        statusFaultFlag = _int(json['status_fault_flag']),
        balanceStatus = _int(json['balance_status']),
        cellVoltages = _slots(json['cell_voltages'], 16, zeroMissing: true),
        // ARM does not populate these slots in layout 0.
        cellTemperatures = _int(json['layout']) == 0
            ? List<double?>.unmodifiable(List<double?>.filled(4, null))
            : _slots(json['cell_temperatures'], 4),
        cycleCount = _int(json['cycle_count']),
        maxCellVoltage = _positive(json['max_cell_voltage']),
        minCellVoltage = _positive(json['min_cell_voltage']),
        maxCellTemp =
            _int(json['layout']) == 0 ? null : _double(json['max_cell_temp']),
        minCellTemp =
            _int(json['layout']) == 0 ? null : _double(json['min_cell_temp']),
        mosTemp = _double(json['mos_temp']),
        pcbTemp = _double(json['pcb_temp']),
        envTemp = _double(json['env_temp']),
        batteryMode = _int(json['battery_mode']),
        batteryStatus = _int(json['battery_status']),
        systemMode = _int(json['system_mode']),
        totalChgCapacityRaw = _int(json['total_chg_capacity_raw']),
        totalDsgCapacityRaw = _int(json['total_dsg_capacity_raw']),
        chgRequestCurrentRaw = _int(json['chg_request_current_raw']),
        chgRequestVoltageRaw = _int(json['chg_request_voltage_raw']),
        chargingVoltage = _int(json['layout']) == 0
            ? null
            : _double(json['charging_voltage']),
        socRaw = _int(json['soc_raw']),
        sohRaw = _int(json['soh_raw']),
        rawBytes = _bytes(json['raw_bytes']),
        ageMs = _int(json['age_ms']),
        updatedAt = _utc(json['updated_at']),
        reportedAt = _utc(json['reported_at']),
        expiresAt = _utc(json['expires_at']);

  static DateTime? _utc(dynamic value) {
    if (value is! String) return null;
    final parsed = DateTime.tryParse(value);
    return parsed != null && parsed.isUtc ? parsed.toUtc() : null;
  }

  static double? _double(dynamic value) =>
      value is num && value.isFinite ? value.toDouble() : null;
  static int? _int(dynamic value) =>
      value is num && value.isFinite && value == value.toInt()
          ? value.toInt()
          : null;
  static double? _positive(dynamic value) {
    final number = _double(value);
    return number != null && number > 0 ? number : null;
  }

  static List<double?> _slots(
    dynamic value,
    int count, {
    bool zeroMissing = false,
  }) =>
      List<double?>.unmodifiable(
        List<double?>.generate(count, (i) {
          if (value is! List || i >= value.length) return null;
          return zeroMissing ? _positive(value[i]) : _double(value[i]);
        }),
      );

  static List<int>? _bytes(dynamic value) {
    if (value is! List || value.length != 100) return null;
    final result = <int>[];
    for (final item in value) {
      final byte = _int(item);
      if (byte == null || byte < 0 || byte > 255) return null;
      result.add(byte);
    }
    return List<int>.unmodifiable(result);
  }

  /// Null distinguishes an unknown link state from an explicit offline sample.
  bool? get online {
    if (bmsOnline == 0 ||
        batteryCount == 0 ||
        socRaw == 255 ||
        (ageMs != null && ageMs! > 120000)) {
      return false;
    }
    if (layout != 0 ||
        batteryCount == null ||
        batteryCount! < 1 ||
        batteryCount! > 255 ||
        socRaw == null ||
        socRaw! < 0 ||
        socRaw! > 65535 ||
        ageMs == null ||
        ageMs! < 0) {
      return null;
    }
    return bmsOnline == 1 ? true : null;
  }

  bool? onlineAt(DateTime now) {
    if (online != true) return online;
    // ARM age at publish and heartbeat expiry measure different time intervals.
    // Missing/invalid expiry cannot establish that a cached report is current.
    if (expiresAt == null) return null;
    final remaining = expiresAt!.difference(now.toUtc());
    if (remaining > const Duration(seconds: 215)) return null;
    return remaining > Duration.zero;
  }

  // Bit positions are from ARM source/BMS/BMS.h, not the legacy pack_info group.
  static const _warningBits = {
    0: 'storage_alarm_cell_ov',
    1: 'storage_alarm_cell_uv',
    2: 'storage_alarm_pack_ov',
    3: 'storage_alarm_pack_uv',
    4: 'storage_alarm_chg_oc',
    5: 'storage_alarm_dsg_oc',
    8: 'storage_alarm_chg_ot',
    9: 'storage_alarm_dsg_ot',
    10: 'storage_alarm_chg_ut',
    11: 'storage_alarm_dsg_ut',
    12: 'storage_alarm_env_ot',
    13: 'storage_alarm_env_ut',
    14: 'storage_alarm_mos_ot',
    15: 'storage_alarm_soc_low',
  };
  static const _protectionBits = {
    0: 'storage_alarm_cell_ov',
    1: 'storage_alarm_cell_uv',
    2: 'storage_alarm_pack_ov',
    3: 'storage_alarm_pack_uv',
    4: 'storage_alarm_chg_oc',
    5: 'storage_alarm_dsg_oc',
    6: 'storage_fault_sc',
    7: 'storage_summary_charger_ov',
    8: 'storage_alarm_chg_ot',
    9: 'storage_alarm_dsg_ot',
    10: 'storage_alarm_chg_ut',
    11: 'storage_alarm_dsg_ut',
    12: 'storage_alarm_mos_ot',
    13: 'storage_alarm_env_ot',
    14: 'storage_alarm_env_ut',
  };
  static const _statusFaultBits = {
    0: 'storage_fault_chg_mos_fault',
    1: 'storage_fault_dsg_mos_fault',
    2: 'storage_fault_ntc_break',
    4: 'storage_summary_cell_fault',
    5: 'storage_fault_afe_comm',
    8: 'storage_charging',
    9: 'storage_discharging',
    10: 'storage_summary_charge_mos_on',
    11: 'storage_summary_discharge_mos_on',
    12: 'storage_summary_charge_limiter',
    14: 'storage_summary_charge_reversed',
    15: 'storage_summary_heater',
  };
  static List<String> _keys(int? word, Map<int, String> definitions) => [
        if (word != null)
          for (var bit = 0; bit < 16; bit++)
            if ((word & (1 << bit)) != 0)
              definitions[bit] ?? 'storage_summary_reserved_bit:$bit',
      ];
  List<String> get warningKeys => _keys(warningFlag, _warningBits);
  List<String> get protectionKeys => _keys(protectionFlag, _protectionBits);
  List<String> get statusFaultKeys => _keys(statusFaultFlag, _statusFaultBits);

  Map<String, dynamic> toJson() => {
        'layout': layout,
        'bms_online': bmsOnline,
        'battery_count': batteryCount,
        'voltage': voltage,
        'current': current,
        'soc': soc,
        'soh': soh,
        'capacity_remain': capacityRemain,
        'capacity_full': capacityFull,
        'capacity_design': capacityDesign,
        'warning_flag': warningFlag,
        'protection_flag': protectionFlag,
        'status_fault_flag': statusFaultFlag,
        'balance_status': balanceStatus,
        'cell_voltages': cellVoltages,
        'cell_temperatures': cellTemperatures,
        'cycle_count': cycleCount,
        'max_cell_voltage': maxCellVoltage,
        'min_cell_voltage': minCellVoltage,
        'max_cell_temp': maxCellTemp,
        'min_cell_temp': minCellTemp,
        'mos_temp': mosTemp,
        'pcb_temp': pcbTemp,
        'env_temp': envTemp,
        'battery_mode': batteryMode,
        'battery_status': batteryStatus,
        'total_chg_capacity_raw': totalChgCapacityRaw,
        'total_dsg_capacity_raw': totalDsgCapacityRaw,
        'chg_request_current_raw': chgRequestCurrentRaw,
        'chg_request_voltage_raw': chgRequestVoltageRaw,
        'system_mode': systemMode,
        'charging_voltage': chargingVoltage,
        'soc_raw': socRaw,
        'soh_raw': sohRaw,
        'raw_bytes': rawBytes,
        'age_ms': ageMs,
        'updated_at': updatedAt?.toIso8601String(),
        'reported_at': reportedAt?.toIso8601String(),
        'expires_at': expiresAt?.toIso8601String(),
      };

  @override
  List<Object?> get props => [toJson()];
}
