import 'package:dio/dio.dart';
import 'package:inv_app/core/utils/api_response.dart';
import 'package:inv_app/core/utils/realtime_payload.dart';
import 'package:inv_app/core/utils/timezone_utils.dart';
import 'package:timezone/timezone.dart' as tz;

class DeviceTelemetryPage {
  const DeviceTelemetryPage({required this.items, required this.total});
  final List<Map<String, dynamic>> items;
  final int total;
}

class DeviceTelemetryApi {
  DeviceTelemetryApi(this.dio,
      {String timezone = TimezoneUtils.defaultTimezone})
      : timezone = _validatedTimezone(timezone);
  final Dio dio;
  final String timezone;

  static String _validatedTimezone(String value) {
    TimezoneUtils.initialize();
    try {
      return tz.getLocation(value.trim()).name;
    } catch (_) {
      return TimezoneUtils.defaultTimezone;
    }
  }

  tz.Location get location {
    TimezoneUtils.initialize();
    return tz.getLocation(timezone);
  }

  Future<DeviceTelemetryPage> getHistory(String sn, DateTime day,
      {int page = 1, int pageSize = 20, String granularity = 'raw'}) async {
    final start = tz.TZDateTime(location, day.year, day.month, day.day);
    final end = tz.TZDateTime(location, day.year, day.month, day.day + 1)
        .subtract(const Duration(microseconds: 1));
    final response = await dio.get<dynamic>(
      '/devices/by-sn/${Uri.encodeComponent(sn)}/telemetry',
      queryParameters: {
        'start_time': start.toUtc().toIso8601String(),
        'end_time': end.toUtc().toIso8601String(),
        'granularity': granularity,
        'tz': timezone,
        'page': page,
        'page_size': pageSize,
        'sort': 'desc',
      },
    );
    final data = unwrapApiResponse<Map<String, dynamic>>(response.data,
        validate: (value) => value is Map<String, dynamic>,
        expected: 'an object');
    if (data['items'] is! List || data['total'] is! num) {
      throw const FormatException('Invalid telemetry history page');
    }
    final rows = (data['items'] as List).map((row) {
      if (row is! Map) throw const FormatException('Invalid telemetry sample');
      return normalizeRealtimePayload(Map<String, dynamic>.from(row));
    }).toList(growable: false);
    return DeviceTelemetryPage(
        items: rows, total: (data['total'] as num).toInt());
  }
}
