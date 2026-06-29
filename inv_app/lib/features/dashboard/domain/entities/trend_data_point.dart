/// 趋势图数据点 - 用于 7 日发电用电趋势折线图
class TrendDataPoint {
  final String date; // 日期标签 (MM/DD)
  final double energy; // 当日发电量 (kWh)
  final double load; // 当日用电量 (kWh)
  final double cumulative; // 累计发电量 (kWh)

  const TrendDataPoint({
    required this.date,
    required this.energy,
    this.load = 0,
    this.cumulative = 0,
  });

  factory TrendDataPoint.fromJson(Map<String, dynamic> json) {
    return TrendDataPoint(
      date: json['date'] as String? ?? '',
      energy: (json['energy'] as num?)?.toDouble() ?? 0,
      load: (json['load'] as num?)?.toDouble() ?? 0,
      cumulative: (json['cumulative'] as num?)?.toDouble() ?? 0,
    );
  }
}
