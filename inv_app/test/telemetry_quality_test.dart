import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/utils/telemetry_quality.dart';

void main() {
  test('quality mask zero is normal', () {
    final decoded = decodeTelemetryQuality(0);

    expect(decoded.isNormal, isTrue);
    expect(decoded.flags, isEmpty);
    expect(decoded.unknownMask, 0);
  });

  test('quality mask follows the storage contract and keeps unknown bits', () {
    final decoded = decodeTelemetryQuality(0x8b);

    expect(decoded.flags.map((flag) => flag.key), [
      'missing',
      'out_of_range',
      'out_of_order/backfill',
    ]);
    expect(decoded.unknownMask, 0x80);
    expect(decoded.isNormal, isFalse);
  });

  test('API decimal and hexadecimal strings are parsed strictly', () {
    expect(parseTelemetryQualityFlags('8'), 8);
    expect(parseTelemetryQualityFlags('0x20'), 32);
    expect(parseTelemetryQualityFlags('-1'), isNull);
    expect(parseTelemetryQualityFlags('invalid'), isNull);
  });

  test('realtime entity roundtrips device_sn and updated_at through JSON', () {
    final realtime = InverterRealtime.fromJson({
      'device_sn': 'INV001',
      'updated_at': '2026-07-15T00:00:00Z',
    });

    expect(realtime.deviceSN, 'INV001');
    expect(realtime.toJson()['device_sn'], 'INV001');
    expect(realtime.toJson()['updated_at'], '2026-07-15T00:00:00.000Z');
  });
}
