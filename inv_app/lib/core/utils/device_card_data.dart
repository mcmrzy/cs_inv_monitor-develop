import 'package:inv_app/core/entities/bms_summary.dart';

double? deviceNumber(dynamic value) {
  final number = value is num ? value.toDouble() : double.tryParse('$value');
  return number != null && number.isFinite ? number : null;
}

double? deviceRatedWatts(Map<String, dynamic> device) {
  final watts = deviceNumber(device['rated_power_w']);
  if (watts != null && watts > 0) return watts;
  final kw = deviceNumber(device['rated_power']);
  return kw != null && kw > 0 ? kw * 1000 : null;
}

String devicePowerLabel(double? watts) {
  if (watts == null) return '--';
  return watts.abs() >= 1000
      ? '${(watts / 1000).toStringAsFixed(2)} kW'
      : '${watts.toStringAsFixed(0)} W';
}

String deviceCategory(Map<String, dynamic> device) {
  final declared =
      '${device['model_category'] ?? ''} ${device['device_type'] ?? ''}'
          .toLowerCase();
  final source = declared.trim().isEmpty
      ? '${device['model'] ?? ''}'.toLowerCase()
      : declared;
  if (source.contains('battery') ||
      source.contains('bms') ||
      source.contains('\u50a8\u80fd') ||
      source.contains('\u7535\u6c60') ||
      source.contains('storage')) return 'battery';
  if (source.contains('collect') || source.contains('daq') ||
      source.contains('\u91c7\u96c6')) return 'collector';
  return 'inv';
}

BmsSummary? deviceBattery(Map<String, dynamic> device) {
  final raw = device['bms_summary'];
  if (raw is! Map) return null;
  final summary = BmsSummary.fromJson(
      Map<String, dynamic>.from(raw['data'] is Map ? raw['data'] as Map : raw));
  // A mere CMD08 placeholder is not evidence of an installed battery.
  return summary.layout == 0 && (summary.batteryCount ?? 0) > 0
      ? summary
      : null;
}
