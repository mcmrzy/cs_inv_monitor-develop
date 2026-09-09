/// Pure presentation rules shared by the station list, counters and cards.
///
/// Fault and offline are deliberately independent predicates: an offline
/// station with faults contributes to both existing summary counters.
abstract final class StationListPresentation {
  static const int allFilter = 0;
  static const int normalFilter = 1;
  static const int faultFilter = 2;
  static const int offlineFilter = 3;

  static bool isNormal(dynamic station) =>
      (station['status'] ?? 1) == 1 &&
      (station['fault_count'] ?? 0) == 0 &&
      (station['online_count'] ?? 0) > 0;

  static bool hasFault(dynamic station) =>
      (station['fault_count'] ?? 0) > 0;

  static bool isOffline(dynamic station) =>
      (station['status'] ?? 1) != 1 ||
      (station['online_count'] ?? 0) == 0;

  /// 电站地址文案：省/市/区非空段拼接，空段跳过。
  /// 不再硬编码"中国"前缀（海外电站/空地址时避免错误前缀）。
  static String addressText(dynamic station) {
    final parts = <String>[
      if ((station['province'] as String?)?.isNotEmpty == true)
        station['province'] as String,
      if ((station['city'] as String?)?.isNotEmpty == true)
        station['city'] as String,
      if ((station['district'] as String?)?.isNotEmpty == true)
        station['district'] as String,
    ];
    return parts.join(' ');
  }

  static StationListCounts counts(List<dynamic> stations) {
    return StationListCounts(
      total: stations.length,
      normal: stations.where(isNormal).length,
      fault: stations.where(hasFault).length,
      offline: stations.where(isOffline).length,
    );
  }

  static List<dynamic> filter(
    List<dynamic> stations, {
    String query = '',
    int filterIndex = allFilter,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    var result = normalizedQuery.isEmpty
        ? stations
        : stations.where((station) {
            final name = station['station_name'] ?? station['name'] ?? '';
            return name.toString().toLowerCase().contains(normalizedQuery);
          }).toList();

    result = switch (filterIndex) {
      normalFilter => result.where(isNormal).toList(),
      faultFilter => result.where(hasFault).toList(),
      offlineFilter => result.where(isOffline).toList(),
      _ => result,
    };
    return result;
  }
}

class StationListCounts {
  const StationListCounts({
    required this.total,
    required this.normal,
    required this.fault,
    required this.offline,
  });

  final int total;
  final int normal;
  final int fault;
  final int offline;

  List<int> get asList => [total, normal, fault, offline];
}
