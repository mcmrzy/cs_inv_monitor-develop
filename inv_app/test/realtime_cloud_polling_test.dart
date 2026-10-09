import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/services/realtime_data_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:mocktail/mocktail.dart';

class _Storage extends Mock implements StorageService {}

void main() {
  test('cloud polling emits voltage-only changes with the same power and SOC',
      () async {
    final storage = _Storage();
    when(storage.getToken).thenAnswer((_) async => 'test-token');
    getIt.registerSingleton<StorageService>(storage);
    final service = RealtimeDataServiceImpl(baseUrl: 'https://example.test');
    final values = <InverterRealtime>[];
    final subscription = service.realtimeDataStream.listen(values.add);
    var voltage = 230;
    final client = MockClient((request) async => http.Response(
        jsonEncode({
          'code': 0,
          'data': {
            'online': true,
            'data_time': '2026-10-09T02:00:00Z',
            'realtime': {
              'ac_voltage': voltage,
              'ac_active_power': 510,
              'battery_soc': 80,
              'mppt_state': 2
            }
          },
        }),
        200));
    try {
      await http.runWithClient(() async {
        await service.refresh('H1ZZX0013900002H');
        await service.refresh('H1ZZX0013900002H');
        voltage = 235;
        await service.refresh('H1ZZX0013900002H');
        await Future<void>.delayed(Duration.zero);
      }, () => client);
      expect(values, hasLength(2));
      expect(values.first.ac?.voltage, 230);
      expect(values.last.ac?.voltage, 235);
      expect(values.last.ac?.power, 510);
      expect(values.last.onlineStatus?.online, true);
    } finally {
      await subscription.cancel();
      service.dispose();
      client.close();
      await getIt.reset();
    }
  });
}
