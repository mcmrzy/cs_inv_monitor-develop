import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/device/data/device_telemetry_api.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  tz_data.initializeTimeZones();
  test(
      'invalid legacy timezone falls back consistently for display and queries',
      () {
    for (final value in ['', 'not-a-timezone']) {
      final api = DeviceTelemetryApi(Dio(), timezone: value);
      expect(api.timezone, 'Asia/Shanghai');
      expect(api.location.name, api.timezone);
    }
  });
  for (final entry in [
    ('Asia/Kolkata', 2026, 10, 9, 24),
    ('Asia/Kathmandu', 2026, 10, 9, 24),
    ('America/New_York', 2026, 3, 8, 23),
    ('America/New_York', 2026, 11, 1, 25),
  ]) {
    test(
        '${entry.$1} local calendar day retains timezone and ${entry.$5} hours',
        () async {
      final dio = Dio();
      late Map<String, dynamic> query;
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        query = options.queryParameters;
        handler.resolve(Response(requestOptions: options, data: {
          'code': 0,
          'data': {'items': [], 'total': 0}
        }));
      }));
      final location = tz.getLocation(entry.$1);
      final day = tz.TZDateTime(location, entry.$2, entry.$3, entry.$4);
      final next = tz.TZDateTime(location, entry.$2, entry.$3, entry.$4 + 1);
      await DeviceTelemetryApi(dio, timezone: entry.$1)
          .getHistory('SN', day, page: 2, pageSize: 20, granularity: 'hour');
      expect(query['tz'], entry.$1);
      expect(query['start_time'], day.toUtc().toIso8601String());
      expect(
          query['end_time'],
          next
              .toUtc()
              .subtract(const Duration(microseconds: 1))
              .toIso8601String());
      expect(next.difference(day).inHours, entry.$5);
      expect(query['page'], 2);
      expect(query['page_size'], 20);
      expect(query['sort'], 'desc');
      expect(query['granularity'], 'hour');
    });
  }
  test('native calendar day uses explicitly selected device timezone',
      () async {
    final dio = Dio();
    late Map<String, dynamic> query;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      query = options.queryParameters;
      handler.resolve(Response(requestOptions: options, data: {
        'code': 0,
        'data': {'items': [], 'total': 0}
      }));
    }));
    final day = DateTime(2026, 10, 9);
    await DeviceTelemetryApi(dio, timezone: 'Asia/Kathmandu')
        .getHistory('SN', day);
    final location = tz.getLocation(query['tz'] as String);
    expect(query['tz'], 'Asia/Kathmandu');
    expect(
        query['start_time'],
        tz.TZDateTime(location, day.year, day.month, day.day)
            .toUtc()
            .toIso8601String());
  });
}
