import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/services/realtime_data_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:mocktail/mocktail.dart';

import 'bms_summary_test.dart' show summaryFixture;

class _Storage extends Mock implements StorageService {}

void main() {
  setUp(() {
    final storage = _Storage();
    when(() => storage.getToken()).thenAnswer((_) async => 'test-token');
    getIt.registerSingleton<StorageService>(storage);
  });
  tearDown(() async => getIt.reset());

  test('HTTP polling publishes BMS-only changes, nulls, removal and offline',
      () async {
    final service = RealtimeDataServiceImpl(baseUrl: 'https://example.test');
    final emitted = <InverterRealtime>[];
    final subscription = service.realtimeDataStream.listen(emitted.add);
    Map<String, dynamic>? summary = summaryFixture();
    final client = MockClient((request) async {
      expect(request.url.path, '/devices/by-sn/SN/realtime');
      expect(request.headers['Authorization'], 'Bearer test-token');
      return http.Response(
        jsonEncode({
          'code': 0,
          'data': {
            'online': true,
            'realtime': {
              // No ac/bat group: the summary must work by itself too.
              if (summary != null) 'bms_summary': summary,
            },
          },
        }),
        200,
      );
    });
    try {
      await http.runWithClient(
        () async {
          await service.refresh('SN');
          await service
              .refresh('SN'); // Identical maps must not duplicate updates.
          summary = {...summary!, 'current': -25.5};
          await service.refresh('SN');
          summary = {...summary!, 'cell_voltages': List<num?>.filled(16, null)};
          await service.refresh('SN');
          summary = {
            ...summary!,
            'bms_online': 0,
            'soc': null,
            'voltage': null,
          };
          await service.refresh('SN');
          summary = null;
          await service.refresh('SN');
          await Future<void>.delayed(Duration.zero);
        },
        () => client,
      );
      expect(emitted, hasLength(5));
      expect(emitted[0].bmsSummary!.soc, 80.5);
      expect(emitted[1].bmsSummary!.current, -25.5);
      expect(emitted[2].bmsSummary!.cellVoltages, everyElement(isNull));
      expect(emitted[3].bmsSummary!.online, isFalse);
      expect(emitted[3].bmsSummary!.soc, isNull);
      expect(emitted[4].bmsSummary, isNull);
      expect(service.getLatestData('SN')!.bmsSummary, isNull);
    } finally {
      await subscription.cancel();
      service.dispose();
      client.close();
    }
  });
}
