import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:inv_app/core/services/data_cache_service.dart';

void main() {
  late DataCacheService cacheService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    cacheService = DataCacheService(prefs);
  });

  // ---------------------------------------------------------------------------
  // save & load
  // ---------------------------------------------------------------------------
  group('save & load', () {
    test('saves and loads data correctly', () async {
      final data = {'key': 'value', 'count': 42};
      await cacheService.save('test_key', data);

      final loaded = cacheService.load('test_key');
      expect(loaded, isNotNull);
      expect(loaded['key'], 'value');
      expect(loaded['count'], 42);
    });

    test('returns null for non-existent key', () {
      final loaded = cacheService.load('non_existent');
      expect(loaded, isNull);
    });

    test('returns null for expired data', () async {
      await cacheService.save('test_key', {'data': 'old'});

      // Load with zero TTL — data should be expired
      final loaded = cacheService.load(
        'test_key',
        ttl: Duration.zero,
      );
      expect(loaded, isNull);
    });

    test('handles nested data structures', () async {
      final data = {
        'stations': [
          {'id': 1, 'name': 'Station A'},
          {'id': 2, 'name': 'Station B'},
        ],
        'summary': {'total': 2},
      };
      await cacheService.save('nested_key', data);

      final loaded = cacheService.load('nested_key');
      expect(loaded, isNotNull);
      expect(loaded['stations'], isA<List>());
      expect(loaded['stations'].length, 2);
    });
  });

  // ---------------------------------------------------------------------------
  // loadOrNull
  // ---------------------------------------------------------------------------
  group('loadOrNull', () {
    test('returns data regardless of TTL', () async {
      await cacheService.save('test_key', {'data': 'value'});

      final loaded = cacheService.loadOrNull('test_key');
      expect(loaded, isNotNull);
      expect(loaded['data'], 'value');
    });

    test('returns null for non-existent key', () {
      final loaded = cacheService.loadOrNull('non_existent');
      expect(loaded, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // getTimestamp
  // ---------------------------------------------------------------------------
  group('getTimestamp', () {
    test('returns non-zero timestamp after save', () async {
      await cacheService.save('test_key', {'data': 'value'});

      final ts = cacheService.getTimestamp('test_key');
      expect(ts, greaterThan(0));
    });

    test('returns 0 for non-existent key', () {
      final ts = cacheService.getTimestamp('non_existent');
      expect(ts, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // remove
  // ---------------------------------------------------------------------------
  group('remove', () {
    test('removes cached data', () async {
      await cacheService.save('test_key', {'data': 'value'});
      expect(cacheService.load('test_key'), isNotNull);

      await cacheService.remove('test_key');
      expect(cacheService.load('test_key'), isNull);
      expect(cacheService.getTimestamp('test_key'), 0);
    });
  });

  // ---------------------------------------------------------------------------
  // clearAll
  // ---------------------------------------------------------------------------
  group('clearAll', () {
    test('removes all cached data', () async {
      await cacheService.save('key1', {'a': 1});
      await cacheService.save('key2', {'b': 2});

      await cacheService.clearAll();

      expect(cacheService.load('key1'), isNull);
      expect(cacheService.load('key2'), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Static cache keys
  // ---------------------------------------------------------------------------
  group('static cache keys', () {
    test('stationDetail generates correct key', () {
      expect(DataCacheService.stationDetail(1), 'station_detail_1');
      expect(DataCacheService.stationDetail(42), 'station_detail_42');
    });

    test('deviceDetail generates correct key', () {
      expect(DataCacheService.deviceDetail('SN001'), 'device_detail_SN001');
    });

    test('stationDevices generates correct key', () {
      expect(DataCacheService.stationDevices(5), 'station_devices_5');
    });
  });
}
