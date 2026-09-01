import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/station/presentation/models/station_list_presentation.dart';

void main() {
  group('StationListPresentation', () {
    final stations = <dynamic>[
      {
        'station_name': 'Alpha Solar',
        'status': 1,
        'fault_count': 0,
        'online_count': 2,
      },
      {
        'name': 'Beta Plant',
        'status': 1,
        'fault_count': 3,
        'online_count': 1,
      },
      {
        'station_name': 'Gamma',
        'status': 0,
        'fault_count': 0,
        'online_count': 0,
      },
      {
        'station_name': 'Delta',
        'status': 0,
        'fault_count': 1,
        'online_count': 0,
      },
    ];

    test('classifies station status using the existing business rules', () {
      expect(StationListPresentation.isNormal(stations[0]), isTrue);
      expect(StationListPresentation.hasFault(stations[1]), isTrue);
      expect(StationListPresentation.isOffline(stations[2]), isTrue);

      // Fault and offline are intentionally not mutually exclusive in the
      // existing summary counters.
      expect(StationListPresentation.hasFault(stations[3]), isTrue);
      expect(StationListPresentation.isOffline(stations[3]), isTrue);
    });

    test('counts keep fault and offline overlap', () {
      final counts = StationListPresentation.counts(stations);

      expect(counts.total, 4);
      expect(counts.normal, 1);
      expect(counts.fault, 2);
      expect(counts.offline, 2);
      expect(counts.asList, [4, 1, 2, 2]);
    });

    test('filters by case-insensitive station name before status', () {
      final result = StationListPresentation.filter(
        stations,
        query: 'BETA',
        filterIndex: StationListPresentation.faultFilter,
      );

      expect(result, [stations[1]]);
    });

    test('supports station_name and name aliases', () {
      expect(
        StationListPresentation.filter(stations, query: 'solar'),
        [stations[0]],
      );
      expect(
        StationListPresentation.filter(stations, query: 'plant'),
        [stations[1]],
      );
    });

    test('all filter without a query preserves the source list identity', () {
      final result = StationListPresentation.filter(stations);

      expect(identical(result, stations), isTrue);
    });

    test('unknown filter index preserves the searched list', () {
      final result = StationListPresentation.filter(
        stations,
        query: 'a',
        filterIndex: 99,
      );

      expect(result, stations);
    });
  });
}
