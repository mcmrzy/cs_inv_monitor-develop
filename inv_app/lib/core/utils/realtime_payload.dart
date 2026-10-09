/// Canonical telemetry keys shared by detail, polling and historical samples.
bool canReplaceTelemetry(DateTime? current, DateTime? incoming) =>
    current == null || (incoming != null && !incoming.isBefore(current));

Map<String, dynamic> normalizeRealtimePayload(Map<String, dynamic> source) {
  final result = Map<String, dynamic>.from(source);
  const aliases = {
    'ac_output_voltage': ['ac_voltage'],
    'output_current': ['ac_current'],
    'output_power': ['ac_active_power', 'ac_power'],
    'output_apparent_power': ['ac_apparent_power'],
    'ac_output_frequency': ['ac_frequency'],
    'capacity_remain': ['battery_capacity_remain'],
    'capacity_total': ['battery_capacity_total'],
    'cycle_count': ['battery_cycle_count'],
    'protect_status': ['battery_protect_status'],
    'inv_fan_speed': ['fan_speed_percent'],
    'daily_pv_energy': ['daily_pv'],
    'total_pv_energy': ['total_pv'],
    'daily_charge_energy': ['daily_charge'],
    'total_charge_energy': ['total_charge'],
    'daily_discharge_energy': ['daily_discharge'],
    'total_discharge_energy': ['total_discharge'],
    'daily_load_energy': ['daily_load'],
    'total_load_energy': ['total_load'],
  };
  const groupAliases = {
    'ac': {
      'ac_output_voltage': ['voltage', 'ac_voltage'],
      'output_current': ['current', 'ac_current'],
      'output_power': ['active_power', 'power', 'ac_active_power'],
      'output_apparent_power': ['apparent_power', 'ac_apparent_power'],
      'ac_output_frequency': ['frequency', 'ac_frequency'],
      'ac_power_factor': ['power_factor', 'pf'],
    },
    'battery': {
      'battery_soc': ['soc'],
      'battery_soh': ['soh'],
      'battery_voltage': ['voltage'],
      'battery_current': ['current'],
      'battery_power': ['power'],
      'battery_charge_power': ['charge_power'],
      'battery_discharge_power': ['discharge_power'],
      'battery_temp_max': ['temp_max'],
      'battery_temp_min': ['temp_min'],
      'battery_temperature': ['temperature', 'temp', 'temp_battery'],
    },
    'pv': {
      'pv1_voltage': ['pv_voltage'],
      'pv1_current': ['pv_current'],
      'pv_total_power': ['total_power', 'pv_power'],
    },
    'sys': {
      'work_state': ['state'],
      'inverter_temperature': ['temp_inv'],
    },
    'energy': {
      'daily_pv_energy': ['daily_pv'],
      'total_pv_energy': ['total_pv'],
      'daily_load_energy': ['daily_load'],
      'total_load_energy': ['total_load'],
      'daily_charge_energy': ['daily_charge'],
      'total_charge_energy': ['total_charge'],
      'daily_discharge_energy': ['daily_discharge'],
      'total_discharge_energy': ['total_discharge'],
    },
  };
  void applyAliases(
      Map<String, dynamic> target, Map<String, List<String>> names) {
    for (final entry in names.entries) {
      if (target[entry.key] != null) continue;
      for (final alias in entry.value) {
        if (target[alias] != null) {
          target[entry.key] = target[alias];
          break;
        }
      }
    }
  }

  const groups = {
    'ac': ['ac'],
    'battery': ['bat', 'battery', 'batt'],
    'pv': ['pv'],
    'sys': ['sys', 'sys_status', 'system'],
    'energy': ['eng', 'energy'],
    'fan': ['fan'],
    'diag': ['diag'],
    'chr': ['chr'],
  };
  for (final entry in groups.entries) {
    final fields = <String, dynamic>{};
    for (final key in entry.value.reversed) {
      final raw = source[key];
      if (raw is! Map) continue;
      final inner = raw['data'] is Map ? raw['data'] as Map : raw;
      fields.addAll(Map<String, dynamic>.from(inner));
    }
    applyAliases(fields, groupAliases[entry.key] ?? const {});
    // Nested groups hold the canonical current readings; flat aliases may
    // coexist in Redis, while DB fallback is entirely flat.
    for (final field in fields.entries) {
      if (field.value != null) result[field.key] = field.value;
    }
  }
  applyAliases(result, aliases);
  final derived = source['derived'];
  if (derived is Map) {
    final values = derived['data'] is Map ? derived['data'] as Map : derived;
    for (final entry in values.entries) {
      result['derived_${entry.key}'] = entry.value;
    }
  }
  if (result['updated_at'] == null) {
    final timestamp = source['_timestamp'];
    result['updated_at'] = source['event_time'] ??
        (timestamp is num
            ? DateTime.fromMillisecondsSinceEpoch((timestamp * 1000).toInt(),
                    isUtc: true)
                .toIso8601String()
            : null) ??
        source['_updated_at'];
  }
  for (final key in const [
    'ac_output_voltage',
    'output_current',
    'output_power',
    'output_apparent_power',
    'ac_output_frequency',
    'ac_power_factor',
    'battery_soc',
    'battery_soh',
    'battery_voltage',
    'battery_current',
    'battery_power',
    'pv1_voltage',
    'pv1_current',
    'pv1_power',
    'pv2_voltage',
    'pv2_current',
    'pv2_power',
    'pv_total_power',
  ]) {
    if (result[key] is String) {
      result[key] = num.tryParse(result[key] as String);
    }
  }
  if (result['work_time_total'] == null && result['runtime_hours'] is num) {
    result['work_time_total'] = (result['runtime_hours'] as num) * 3600;
  }
  return result;
}

bool deviceCloudOnline(Map<String, dynamic> data) {
  final online = data['online_status'] is Map
      ? (data['online_status'] as Map)['online']
      : null;
  if (online is bool) return online;
  final status =
      data['device'] is Map ? (data['device'] as Map)['status'] : null;
  return status == 1 || status == 2;
}
