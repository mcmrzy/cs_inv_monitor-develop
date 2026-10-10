import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/entities/bms_summary.dart';
import 'package:inv_app/core/entities/inverter_data.dart';

Map<String, dynamic> summaryFixture() => {
      'layout': 0,
      'bms_online': 1,
      'battery_count': 2,
      'voltage': 51.24,
      'current': -12.34,
      'soc': 80.5,
      'soh': 98.5,
      'soc_raw': 805,
      'soh_raw': 985,
      'capacity_remain': 18.123,
      'capacity_full': 28.456,
      'capacity_design': 100.789,
      'warning_flag': 0x8001,
      'protection_flag': 0x1040,
      'status_fault_flag': 0x4401,
      'balance_status': 0x8001,
      'cell_voltages': List<num?>.generate(16, (i) => i == 3 ? null : 3300 + i),
      'cell_temperatures': [null, null, null, null],
      'cycle_count': 152,
      'max_cell_voltage': 3315,
      'min_cell_voltage': 3300,
      'max_cell_temp': null,
      'min_cell_temp': null,
      'mos_temp': -5.5,
      'pcb_temp': 0,
      'env_temp': -12.3,
      'battery_mode': 2,
      'battery_status': 7,
      'system_mode': 11,
      'total_chg_capacity_raw': 4294967295,
      'total_dsg_capacity_raw': 123456,
      'chg_request_current_raw': 500,
      'chg_request_voltage_raw': -32768,
      'charging_voltage': null,
      'raw_bytes': List<int>.generate(100, (i) => i),
      'age_ms': 120000,
      'updated_at': '2026-10-08T00:00:00.000Z',
      'reported_at': '2026-10-08T00:02:00.000Z',
      'expires_at': '2026-10-08T00:05:30.000Z',
    };

void main() {
  test('unsupported layout and missing essential live metadata are unknown',
      () {
    for (final override in [
      {'layout': null},
      {'layout': 1},
      {'battery_count': null},
      {'battery_count': -1},
      {'battery_count': 256},
      {'soc_raw': null},
      {'age_ms': null},
      {'age_ms': -1},
    ]) {
      final summary = BmsSummary.fromJson({...summaryFixture(), ...override});
      expect(summary.online, isNull);
      expect(summary.onlineAt(DateTime.utc(2026, 10, 8, 0, 4)), isNull);
    }
    expect(
      BmsSummary.fromJson({
        ...summaryFixture(),
        'layout': 1,
        'battery_count': 0,
      }).online,
      isFalse,
    );
  });
  test('decoded engineering units and signed/raw fields survive roundtrip', () {
    final input = summaryFixture();
    final summary = BmsSummary.fromJson(input);
    expect(summary.toJson(), input);
    expect(summary.current, -12.34);
    expect(summary.capacityRemain, 18.123);
    expect(summary.chgRequestVoltageRaw, -32768);
    expect(summary.chgRequestVoltage, -3276.8);
    expect(summary.chgRequestCurrent, 50);
    expect(summary.totalChgCapacity, 4294967295);
    expect(summary.mosTemp, -5.5);
    expect(summary.pcbTemp, 0);
    expect(summary.cellVoltages[3], isNull);
    expect(summary.updatedAt!.isUtc, isTrue);
  });

  test('online boundary, explicit offline, count and SOC sentinel', () {
    expect(BmsSummary.fromJson(summaryFixture()).online, isTrue);
    for (final override in [
      {'age_ms': 120001},
      {'battery_count': 0},
      {'soc_raw': 255},
      {'bms_online': 0},
    ]) {
      expect(
        BmsSummary.fromJson({...summaryFixture(), ...override}).online,
        isFalse,
      );
    }
    final summary = BmsSummary.fromJson(summaryFixture());
    expect(summary.onlineAt(DateTime.utc(2026, 10, 8, 0, 4, 30)), isTrue);
    expect(summary.onlineAt(DateTime.utc(2026, 10, 8, 0, 5, 30)), isFalse);
    expect(summary.onlineAt(DateTime.utc(2026, 10, 8, 0, 5, 31)), isFalse);
  });

  test('expiry missing, malformed or lacking timezone cannot prove freshness',
      () {
    for (final expiry in [null, 'bad', '2026-10-08T00:05:30']) {
      final summary =
          BmsSummary.fromJson({...summaryFixture(), 'expires_at': expiry});
      expect(summary.expiresAt, isNull);
      expect(summary.onlineAt(DateTime.utc(2026, 10, 8, 0, 4, 30)), isNull);
    }
  });

  test('expiry more than 215 seconds in the future is unknown', () {
    final now = DateTime.utc(2026, 10, 8);
    for (final seconds in [215, 216]) {
      final summary = BmsSummary.fromJson({
        ...summaryFixture(),
        'expires_at': now.add(Duration(seconds: seconds)).toIso8601String(),
      });
      expect(summary.onlineAt(now), seconds == 215 ? isTrue : isNull);
    }
  });

  test('missing values stay null but layout 0 preserves populated zero slots',
      () {
    final missing = BmsSummary.fromJson({});
    expect(missing.online, isNull);
    expect(missing.soc, isNull);
    expect(missing.warningFlag, isNull);
    expect(missing.cellVoltages, List<double?>.filled(16, null));
    expect(missing.cellTemperatures, List<double?>.filled(4, null));
    final zeroSlots = BmsSummary.fromJson({
      'layout': 0,
      'cell_voltages': [0, 3300],
      'cell_temperatures': [-5, 0, 25, 30],
      'max_cell_temp': 0,
      'min_cell_temp': 0,
      'charging_voltage': 0,
    });
    expect(zeroSlots.cellVoltages[0], isNull);
    expect(zeroSlots.cellVoltages[1], 3300);
    expect(zeroSlots.maxCellTemp, 0);
    expect(zeroSlots.minCellTemp, 0);
    expect(zeroSlots.chargingVoltage, 0);
    expect(zeroSlots.cellTemperatures, [-5, 0, 25, 30]);
  });

  test('summary and legacy groups coexist in both supported envelopes', () {
    for (final wrapped in [false, true]) {
      final rt = InverterRealtime.fromJson({
        'device_sn': 'SN',
        'bms_summary': wrapped ? {'data': summaryFixture()} : summaryFixture(),
        'bms': {
          'data': {'bms_online': 1, 'bms_soc': 55},
        },
      });
      expect(rt.bmsSummary!.current, -12.34);
      expect(rt.bms!.soc, 55);
      expect(rt.toJson()['bms_summary'], summaryFixture());
    }
  });

  test('summary flag bits follow ARM definitions rather than legacy bits', () {
    final bms = BmsSummary.fromJson(summaryFixture());
    expect(bms.warningKeys, ['storage_alarm_cell_ov', 'storage_alarm_soc_low']);
    expect(bms.protectionKeys, ['storage_fault_sc', 'storage_alarm_mos_ot']);
    expect(bms.statusFaultKeys, [
      'storage_fault_chg_mos_fault',
      'storage_summary_charge_mos_on',
      'storage_summary_charge_reversed',
    ]);
    expect(
      BmsSummary.fromJson({'warning_flag': 1 << 6}).warningKeys,
      ['storage_summary_reserved_bit:6'],
    );
  });
}
