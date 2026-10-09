import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/utils/device_card_data.dart';

void main() {
  test('rated W takes precedence and legacy rated_power is kW', () {
    expect(deviceRatedWatts({'rated_power': 10}), 10000);
    expect(deviceRatedWatts({'rated_power': 10, 'rated_power_w': 6000}), 6000);
    expect(deviceRatedWatts({'rated_power': '6.5', 'rated_power_w': 0}), 6500);
    expect(deviceRatedWatts({}), isNull);
    expect(devicePowerLabel(-1200), '-1.20 kW');
  });
  test('declared category wins over a misleading model name', () {
    expect(
        deviceCategory({'model_category': 'inverter', 'model': 'BMS series'}),
        'inv');
  });
  test('legacy localized models retain their battery and collector categories', () {
    expect(deviceCategory({'model': '\u50a8\u80fd\u7535\u6c60'}), 'battery');
    expect(deviceCategory({'model': '\u6570\u636e\u91c7\u96c6\u5668'}), 'collector');
  });
  test('only actual CMD08 battery evidence creates a battery child', () {
    expect(
        deviceBattery({
          'bms_summary': {'layout': 0, 'battery_count': 0}
        }),
        isNull);
    expect(
        deviceBattery({
          'bms_summary': {'layout': 9, 'battery_count': 1}
        }),
        isNull);
    final offline = deviceBattery({
      'bms_summary': {'layout': 0, 'battery_count': 1, 'bms_online': 0}
    });
    expect(offline, isNotNull);
    expect(offline!.online, false);
  });
}
