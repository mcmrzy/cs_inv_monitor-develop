import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/heartbeat_v1_mapper.dart';

void main() {
  test('maps heartbeat v1 fixed arrays into named realtime data', () {
    final result = HeartbeatV1Mapper.parse('CS12345678', {
      'v': 1,
      't': 1783676930,
      'seq': 12,
      'ac': [221.5, 8.88, 1947.9, 1967.6, 50.08, 0.99, 31.4, 2.5],
      'bat': [
        75,
        96,
        51.2,
        25.5,
        1305.6,
        100,
        200,
        10,
        32,
        25,
        3.4,
        3.2,
        0.2,
        1,
        0,
        0,
        60,
        120,
        56.8,
        44,
        28
      ],
      'pv': [
        85.3,
        12.5,
        1066.3,
        90,
        1100,
        82.1,
        11.8,
        969.0,
        88,
        1000,
        2035.3,
        0
      ],
      'sys': [1, 0, 0, 48.5, 55.2, 32.6, 380, 8640, 40, 94.6],
      'eng': [12.3, 2400, 3.2, 500, 2.1, 420, 10.2, 2200],
      'cells': [List.filled(16, 3.2), List.filled(16, 26.0)],
    });

    expect(result.ac?.power, 1947.9);
    expect(result.battery?.soc, 75);
    expect(result.pv?.pvPower, 2035.3);
    expect(result.ac?.apparentPower, 1967.6);
    expect(result.battery?.power, 1305.6);
    expect(result.battery?.temperature, 28);
    expect(result.pv?.pv2Power, 969.0);
    expect(result.sysStatus?.state, 'inverting');
    expect(result.sysStatus?.dcBusVoltage, 380);
    expect(result.energy?.dailyPV, 12.3);
    expect(result.energy?.totalLoad, 2200);
    expect(result.cells?.cellCount, 16);
  });

  test('rejects an invalid fixed array length', () {
    expect(
      () => HeartbeatV1Mapper.parse('CS12345678', {'v': 1, 't': 1, 'ac': []}),
      throwsFormatException,
    );
  });
}
