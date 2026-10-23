import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/utils/grid_power.dart';

void main() {
  test('grid includes AC load supply and battery charging', () {
    expect(measuredGridPower({'ac_input_power': 1200, 'ac_charge_power': 600}),
        1800,);
    expect(
        measuredGridPower(
          {
            'ac': {
              'data': {'ac_input_power': 1200},
            },
            'chr': {
              'data': {
                'ac_charge_power': 600,
              },
            },
          },
        ),
        1800,);
  });
  test('measured zero and signed export override fallback', () {
    expect(measuredGridPower({'grid_power': 0, 'ac_input_power': 900}), 0);
    expect(measuredGridPower({'meter_power': -500}), -500);
  });
  test('missing and non-finite power remain unknown', () {
    expect(
        measuredGridPower({'ac_power': 2000, 'ac_input_apparent_power': 2200}),
        isNull,);
    expect(
        measuredGridPower({'grid_power': double.nan, 'ac_charge_power': 300}),
        300,);
  });
}
