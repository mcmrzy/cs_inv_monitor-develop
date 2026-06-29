/// 电站排行项 - 用于电站发电排行列表
class StationRankItem {
  final int stationId;
  final String stationName;
  final double energy; // 发电量 (kWh)
  final int deviceCount;

  const StationRankItem({
    required this.stationId,
    required this.stationName,
    required this.energy,
    required this.deviceCount,
  });

  factory StationRankItem.fromJson(Map<String, dynamic> json) {
    return StationRankItem(
      stationId: (json['stationId'] ?? json['station_id'] ?? 0) as int,
      stationName: (json['stationName'] ?? json['station_name'] ?? '-') as String,
      energy: (json['energy'] as num?)?.toDouble() ?? 0,
      deviceCount: (json['deviceCount'] ?? json['device_count'] ?? 0) as int,
    );
  }
}
