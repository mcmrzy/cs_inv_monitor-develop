import 'package:fl_chart/fl_chart.dart';

/// Precomputed presentation data for the power-flow line chart.
///
/// Series order is PV, battery charge, battery discharge, then load power.
class PowerFlowChartData {
  const PowerFlowChartData._({
    required this.hasSourceRows,
    required this.series,
    required this.yMax,
  });

  factory PowerFlowChartData.fromRows(List<Map<String, dynamic>> rows) {
    final series = <List<FlSpot>>[
      <FlSpot>[],
      <FlSpot>[],
      <FlSpot>[],
      <FlSpot>[],
    ];
    var maxValue = 0.0;

    for (final row in rows) {
      final time = row['time'];
      if (time is! String) continue;

      final parsedTime = DateTime.tryParse(time);
      if (parsedTime == null) continue;
      final localTime = parsedTime.toLocal();
      final x = localTime.hour + localTime.minute / 60.0;
      final values = <double>[
        _finiteDouble(row['pvPower']),
        _finiteDouble(row['batteryCharge']),
        _finiteDouble(row['batteryDischarge']),
        _finiteDouble(row['loadPower']),
      ];

      for (var index = 0; index < values.length; index++) {
        final value = values[index];
        series[index].add(FlSpot(x, value));
        if (value > maxValue) maxValue = value;
      }
    }

    return PowerFlowChartData._(
      hasSourceRows: rows.isNotEmpty,
      series: series,
      yMax: maxValue > 0 ? maxValue * 1.2 : 100.0,
    );
  }

  final bool hasSourceRows;
  final List<List<FlSpot>> series;
  final double yMax;
}

double _finiteDouble(dynamic value) {
  final parsed = value is num ? value.toDouble() : null;
  return parsed != null && parsed.isFinite ? parsed : 0;
}
