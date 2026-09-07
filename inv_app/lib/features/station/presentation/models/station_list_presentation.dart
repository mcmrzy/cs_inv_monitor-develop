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
