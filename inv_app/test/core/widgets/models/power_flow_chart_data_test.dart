import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/widgets/models/power_flow_chart_data.dart';

void main() {
  group('PowerFlowChartData.fromRows', () {
    test('maps the four power fields in chart order using local decimal hours',
        () {
      const rawTime = '2025-06-29T06:03:00Z';
      final localTime = DateTime.parse(rawTime).toLocal();
      final expectedX = localTime.hour + localTime.minute / 60.0;

      final data = PowerFlowChartData.fromRows([
        <String, dynamic>{
          'time': rawTime,
          'pvPower': 10,
          'batteryCharge': 20.5,
          'batteryDischarge': 30,
          'loadPower': 40,
        },
      ]);

      expect(data.hasSourceRows, isTrue);
      expect(data.series, hasLength(4));
      expect(data.series.map((spots) => spots.single.x), everyElement(expectedX));
      expect(
        data.series.map((spots) => spots.single.y).toList(),
        <double>[10, 20.5, 30, 40],
      );
      expect(data.yMax, 48);
    });

    test('skips rows without time and defaults missing power fields to zero',
        () {
      final data = PowerFlowChartData.fromRows([
        <String, dynamic>{'pvPower': 999},
        <String, dynamic>{'time': 123, 'pvPower': 999},
        <String, dynamic>{'time': '2025-06-29T00:00:00Z'},
      ]);

      expect(data.hasSourceRows, isTrue);
      expect(data.series.map((spots) => spots.length), everyElement(1));
      expect(
        data.series.map((spots) => spots.single.y),
        everyElement(0),
      );
      expect(data.yMax, 100);
    });

    test('uses the largest value across all four series for the y maximum', () {
      final data = PowerFlowChartData.fromRows([
        <String, dynamic>{
          'time': '2025-06-29T00:00:00Z',
          'pvPower': 250,
          'batteryCharge': 20,
          'batteryDischarge': 30,
          'loadPower': 400,
        },
      ]);

      expect(data.yMax, 480);
    });

    test('skips invalid times without surfacing an asynchronous error', () {
      final data = PowerFlowChartData.fromRows([
        <String, dynamic>{'time': 'not-a-time', 'pvPower': 999},
      ]);

      expect(data.hasSourceRows, isTrue);
      expect(data.series, everyElement(isEmpty));
      expect(data.yMax, 100);
    });

    test('maps non-numeric and non-finite power values to zero', () {
      final data = PowerFlowChartData.fromRows([
        <String, dynamic>{
          'time': '2025-06-29T00:00:00Z',
          'pvPower': 'invalid',
          'batteryCharge': double.nan,
          'batteryDischarge': double.infinity,
          'loadPower': 25,
        },
      ]);

      expect(
        data.series.map((spots) => spots.single.y).toList(),
        <double>[0, 0, 0, 25],
      );
      expect(data.yMax, 30);
    });

    test('empty rows have no source data and use the default y maximum', () {
      final data = PowerFlowChartData.fromRows(const []);

      expect(data.hasSourceRows, isFalse);
      expect(data.series, hasLength(4));
      expect(data.series, everyElement(isEmpty));
      expect(data.yMax, 100);
    });
  });
}
