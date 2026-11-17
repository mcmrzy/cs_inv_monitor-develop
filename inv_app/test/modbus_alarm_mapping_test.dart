import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/data/alarm_code_mapping.dart';

void main() {
  test('Modbus cloud alarm names include standard, 3KU and link alarms', () {
    expect(AlarmCodeMapping.getNameZh(17924), '过温');
    expect(
        AlarmCodeMapping.getLocalizedName(18433, 'en'), 'Battery undervoltage');
    expect(AlarmCodeMapping.getEntry(22530), isNotNull);
    expect(AlarmCodeMapping.getNameZh(18944), '逆变器通信中断');
    expect(AlarmCodeMapping.getNameZh(1), '逆变器过温保护');
  });
}
