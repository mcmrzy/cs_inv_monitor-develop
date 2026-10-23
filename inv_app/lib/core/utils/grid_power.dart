/// Measured net grid power: positive import, negative export; null if unreported.
double? measuredGridPower(Map<String, dynamic>? telemetry) {
  double? read(String key, [String? group]) {
    final raw = group == null ? null : telemetry?[group];
    final section =
        raw is Map ? (raw['data'] is Map ? raw['data'] as Map : raw) : null;
    final value = telemetry?[key] ?? section?[key];
    return value is num && value.isFinite ? value.toDouble() : null;
  }

  final meter = read('grid_power') ?? read('meter_power');
  if (meter != null) return meter;
  final input = read('ac_input_power', 'ac');
  final charge =
      read('ac_charge_power', 'chr') ?? read('ac_charge_power', 'ac');
  return input == null && charge == null ? null : (input ?? 0) + (charge ?? 0);
}
